# LSP Scoping Workflow (Phases A–E)

Executed for all diffs (improved accuracy for all changes).

---

## Phase A — Discover LSPs and start servers

Use `lsp-config` to identify which installed language servers cover the file extensions in `{files_changed}`. Start each matched server now so it is warm before Phases B–D.

Files with no matching LSP go into `{unscoped_files}` and are passed as full-file context in every dispatch.

**If there are unscoped files:** Ask the user:

```
The following files have no LSP coverage and will be passed as full-file context:
{unscoped_files}

Proceed, or install additional language servers now?
```

**Radio — LSP install:**
- "Proceed without installing" (default)
- "Install language servers now"

If user selects "Install language servers now":
- Collect one server name per line
- Install each via `lsp-config install {server}`
- Re-run Phase A to check coverage
- Files still unscoped after installation remain in `{unscoped_files}`

---

## Phase B — Diagnostics pre-pass

Wait for each LSP server to report ready before issuing requests.

For each LSP-covered file, request all diagnostics (errors, warnings, type mismatches, unresolved references) in a single batch. Do not issue requests file-by-file if the LSP supports workspace-wide diagnostics — use the workspace pull first, then fall back to per-file `textDocument/diagnostic` only for files missing from the workspace result.

**Storing diagnostics in SQLite:**
For each diagnostic result (error, warning, or info), store in `lsp_diagnostics` table:
```sql
INSERT INTO lsp_diagnostics (
    review_id, file_path, line, column, severity, message, diagnostic_code
) VALUES (?, ?, ?, ?, ?, ?, ?);
-- bind: [review_id, file_path, line_number, column_number, 
--        'error'|'warning'|'info', message_text, code_or_null]
```

**Recording as pre-confirmed issues:**
Diagnostic issues (especially errors) are pre-confirmed and skip the debate loop. Include diagnostic issues in the Final Verdict as a separate DIAGNOSTIC ISSUES section above CONFIRMED ISSUES. Query all diagnostics for this review:
```sql
SELECT file_path, line, column, severity, message FROM lsp_diagnostics WHERE review_id = ? ORDER BY file_path, line;
```

---

## Phase C — Extract changed symbols

For each LSP-covered file, request all document symbols (`textDocument/documentSymbol`) and cross-reference with diff hunk headers to identify which symbols were actually changed.

**Pipelined parallel execution:**
- Maintain a pool of 5–10 concurrent `textDocument/documentSymbol` queries (configurable based on LSP server capacity)
- Load all changed files into a queue
- For each file in queue: Issue a `documentSymbol` request
- Collect results and deduplicate before storing in SQLite
- When a query slot opens (one query finishes): immediately start the next queued file (don't wait for batch completion)
- This pipelined approach maximizes throughput without idle time waiting for batch boundaries

**Symbol deduplication:**
LSP returns symbols *defined* in each file. If the same symbol (same name, type, and namespace) is defined in multiple changed files, deduplicate before Phase D:

1. Collect all symbols from all files
2. Group by `(symbol_name, symbol_type, namespace)` — this is the deduplication key
3. For each unique symbol group:
   - SELECT the PRIMARY definition file (pick first/canonical file if multiple definitions exist)
   - INSERT into `lsp_symbols` table with PRIMARY file as `file_path`
   - Note: The same symbol appearing in multiple files is a rare edge case (usually indicates copy-paste or multiple definitions). Pick the first occurrence as primary.

**Storing in SQLite — Detailed insertion process:**

1. **Extract symbols from LSP responses:**
   - For each file: Parse `textDocument/documentSymbol` response
   - For each symbol in response: Extract (symbol_name, symbol_type, namespace/qualified_name, line_start, line_end, file_path)
   - Cross-reference symbol line ranges with diff hunks to confirm symbol was actually changed (only store changed symbols)

2. **Deduplication in memory:**
   - Group extracted symbols by `(symbol_name, symbol_type, namespace)` 
   - For each group with multiple files: select the FIRST file as primary_file_path
   - Create deduplicated list: `[(symbol_name, symbol_type, namespace, primary_file_path, line_start, line_end), ...]`

3. **Insert deduplicated symbols:**
   ```sql
   INSERT INTO lsp_symbols (
       review_id, file_path, symbol_name, symbol_type, namespace, line_start, line_end
   ) VALUES (?, ?, ?, ?, ?, ?, ?);
   -- For each deduplicated symbol:
   -- bind: [review_id, primary_file_path, symbol_name, symbol_type, namespace, line_start, line_end]
   ```

Store one row per *unique* symbol (deduplicated by symbol_name, symbol_type, namespace). The `file_path` column contains the primary definition file.

---

## Phase D — Build blast radius

For each changed symbol, issue all four LSP traversals in parallel (no ordering dependency between them):

- `textDocument/incomingCalls` — callers, up to 2 hops
- `textDocument/outgoingCalls` — callees, up to 2 hops
- `typeHierarchy/supertypes` — base types / implemented interfaces, up to 2 hops
- `typeHierarchy/subtypes` — derived classes / implementors, up to 2 hops

**Pipelined parallel execution:**
- Read all symbols from `lsp_symbols` table for this review:
  ```sql
  SELECT id, file_path, symbol_name, symbol_type, namespace FROM lsp_symbols WHERE review_id = ?;
  ```
- Maintain a pool of 10–20 concurrent symbol analyses (configurable based on LSP server capacity)
- Load all symbols into a queue
- For each symbol in queue: Issue all 4 LSP calls in parallel (using symbol_name/namespace from DB)
- Store results in SQLite immediately when a symbol's 4 calls complete
- When a pool slot opens (one symbol's analysis finishes): immediately start the next queued symbol (don't wait for batch completion)
- This pipelined approach maximizes throughput: continuous streaming of results with no idle time waiting for batch boundaries

**Storing blast radius results in SQLite — Detailed insertion process:**

For each symbol from `lsp_symbols` (in pipelined parallel pool):

1. **Issue 4 LSP calls in parallel:**
   - Call 1: `textDocument/incomingCalls(symbol_name, symbol_file, up_to_2_hops)` → list of callers
   - Call 2: `textDocument/outgoingCalls(symbol_name, symbol_file, up_to_2_hops)` → list of callees
   - Call 3: `typeHierarchy/supertypes(symbol_name, symbol_file, up_to_2_hops)` → base types/interfaces
   - Call 4: `typeHierarchy/subtypes(symbol_name, symbol_file, up_to_2_hops)` → derived classes/implementors
   - Wait for all 4 to complete

2. **Process and deduplicate results:**
   - Collect all results from 4 calls
   - For each result: extract (target_symbol_name, target_file, distance_hop_count)
   - Apply exclusions: skip generated files (`*.generated.*`, `*.designer.*`, `*.g.cs`, `*_pb2.py`) and files outside repo root
   - Deduplicate by `(target_symbol, target_file, call_type)` — if same target appears in multiple traversals, keep only one row per call_type
   - Build in-memory list: `[(call_type, target_symbol, target_file, distance, namespace), ...]`

3. **Insert deduplicated blast radius results:**
   ```sql
   INSERT INTO lsp_blast_radius (
       review_id, symbol_id, call_type, target_symbol, target_file, distance, namespace
   ) VALUES (?, ?, ?, ?, ?, ?, ?);
   -- For each deduplicated result:
   -- bind: [review_id, symbol_id, 'incomingCall'|'outgoingCall'|'supertype'|'subtype',
   --        target_symbol_name, target_file_path, distance_hop_count, target_namespace]
   ```

Store one row per unique `(call_type, target_symbol, target_file, distance)` combination per symbol.

---

## Phase E — Cluster and store in SQLite

Group changed symbols and their blast radius into clusters. Target: all content for a cluster fits within a 6000-line budget (diff hunks + file sections combined). Split large clusters at file boundaries.

**Clustering algorithm:**

1. **Read all symbols and their blast radius from SQLite:**
   ```sql
   SELECT id, symbol_name, symbol_type, namespace, file_path 
   FROM lsp_symbols WHERE review_id = ?;
   
   SELECT symbol_id, call_type, target_symbol, target_file, distance
   FROM lsp_blast_radius WHERE review_id = ?;
   ```

2. **Build clusters:**
   - For each symbol: calculate its "reach" (all files touched by it and its blast radius)
   - Group symbols into clusters, targeting 6000-line budget per cluster (estimate from diff patch line counts)
   - Split large clusters at file boundaries (don't split a file across clusters)
   - Assign cluster_id (e.g., "cluster_1", "cluster_2", ...)

3. **Store cluster metadata in SQLite:**
   ```sql
   INSERT INTO review_scope (
       review_id, cluster_id, symbol_ids_json, affected_files_json, line_range
   ) VALUES (?, ?, ?, ?, ?);
   -- bind: [review_id, cluster_id, 
   --        json_array(symbol_id1, symbol_id2, ...), 
   --        json_array(file1, file2, ...), 
   --        "summary of line ranges or NULL"]
   ```
   
   For each cluster, store:
   - `cluster_id`: unique within review (e.g., "cluster_1")
   - `symbol_ids_json`: JSON array of symbol IDs in this cluster (from lsp_symbols.id)
   - `affected_files_json`: JSON array of all files touched by symbols + blast radius
   - `line_range`: optional summary of line ranges (can be NULL)

**Query clusters for Dispatch:**

When dispatching to Skeptics/Advocates/Judge, query each cluster:
```sql
SELECT symbol_ids_json, affected_files_json FROM review_scope 
WHERE review_id = ? AND cluster_id = ?;
```

Expand the JSON arrays and construct the dispatch context from lsp_symbols and lsp_blast_radius tables.
