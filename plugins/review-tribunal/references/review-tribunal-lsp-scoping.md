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

**Storing in SQLite:**
```sql
INSERT INTO lsp_symbols (
    review_id, file_path, symbol_name, symbol_type, namespace, line_start, line_end
) VALUES (?, ?, ?, ?, ?, ?, ?);
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

**Storing blast radius results in SQLite:**
For each of the 4 LSP call results (incomingCalls, outgoingCalls, supertypes, subtypes), deduplicate and store:
```sql
INSERT INTO lsp_blast_radius (
    review_id, symbol_id, call_type, target_symbol, target_file, distance, namespace
) VALUES (?, ?, ?, ?, ?, ?, ?);
-- bind: [review_id, symbol_id, 'incomingCall'|'outgoingCall'|'supertype'|'subtype', 
--        target_name, target_file, distance_hop_count, target_namespace]
```

For each call type (incomingCalls, outgoingCalls, supertypes, subtypes):
1. Collect all results from LSP
2. **Deduplicate** across all four traversals by `(target_symbol, target_file, call_type)` — avoid duplicate edges
3. **Exclude:** generated files (`*.generated.*`, `*.designer.*`, `*.g.cs`, `*_pb2.py`) and files outside the repository root
4. INSERT each unique result into `lsp_blast_radius` table with the symbol_id foreign key

---

## Phase E — Cluster and write scope file

Group changed symbols and their blast radius into clusters. Target: all content for a cluster fits within a 6000-line budget (diff hunks + file sections combined). Split large clusters at file boundaries.

Write `{session_store}/files/review-{review_id}-scope.json`:

```json
{
  "dispatch_mode": "scoped",
  "diagnostics_path": "{session_store}/files/review-{review_id}-diagnostics.json",
  "clusters": [
    {
      "cluster_id": "cluster_1",
      "changed_symbols": ["AuthService.Login"],
      "files": [
        { "file": "src/Services/AuthService.cs",      "lines": [28, 51] },
        { "file": "src/Controllers/AuthController.cs", "lines": [12, 40] },
        { "file": "tests/AuthServiceTests.cs",         "lines": [20, 45] }
      ],
      "diff_hunks": ["AuthService.cs:30-36"]
    }
  ],
  "unscoped_files": ["<files with no LSP coverage — passed as full-file context>"]
}
```

Set `{scope_path}` = `{session_store}/files/review-{review_id}-scope.json`.

---

## Dispatch with Scoped Context

In Step 2, when `{dispatch_mode}` = `scoped`:

- Each Skeptic instance is assigned one cluster from `{scope_path}` instead of the full `{files_changed}` and `{diff_path}`
- Pass `{cluster}` and `{scope_path}` as additional variables
- Files in `unscoped_files` are appended to every dispatch as full-file context
