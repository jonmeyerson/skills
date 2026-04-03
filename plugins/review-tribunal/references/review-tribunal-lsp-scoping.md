# LSP Scoping Workflow (Phases A–E)

Execute for all diffs. Always use pipelined parallelization (maintain concurrent pool, start next task immediately when slot opens).

---

## Phase A — Discover and start LSP servers

Use `lsp-config` to identify language servers covering file extensions in `{files_changed}`. Start each server immediately.

Files without LSP coverage → `{unscoped_files}` (passed as full-file context to all dispatches).

**If unscoped files exist, ask user:**
```
The following files have no LSP coverage and will be passed as full-file context:
{unscoped_files}

Proceed, or install additional language servers now?
```

- "Proceed without installing" (default)
- "Install language servers now"

If installing: collect server names, run `lsp-config install {server}` per server, re-run Phase A. Any files still unscoped remain in `{unscoped_files}`.

---

## Phase B — Diagnostics pre-pass

Wait for all LSP servers to report ready.

Collect all diagnostics (errors, warnings, type mismatches, unresolved references) for each LSP-covered file. Use workspace-wide diagnostics if available; fall back to per-file `textDocument/diagnostic` for missing files.

**Store in SQLite:**
```sql
INSERT INTO lsp_diagnostics (review_id, file_path, line, column, severity, message, diagnostic_code)
VALUES (?, ?, ?, ?, ?, ?, ?);
-- bind: [review_id, file_path, line_num, column_num, 'error'|'warning'|'info', message_text, code]
```

Query for final report:
```sql
SELECT file_path, line, column, severity, message FROM lsp_diagnostics 
WHERE review_id = ? ORDER BY file_path, line;
```

Pre-confirmed issues (skip debate loop). Display in Final Verdict under DIAGNOSTIC ISSUES section above CONFIRMED ISSUES.

---

## Phase C — Extract changed symbols

Pool size: 5–10 concurrent `textDocument/documentSymbol` queries.

**Algorithm:**
1. For each LSP-covered file: Issue `documentSymbol` request
2. Parse response → extract (symbol_name, symbol_type, namespace, line_start, line_end, file_path)
3. Cross-reference line ranges with diff hunks; discard unchanged symbols
4. Deduplicate by `(symbol_name, symbol_type, namespace)` → pick first file as primary
5. Store in SQLite:
   ```sql
   INSERT INTO lsp_symbols (review_id, file_path, symbol_name, symbol_type, namespace, line_start, line_end)
   VALUES (?, ?, ?, ?, ?, ?, ?);
   -- For each deduplicated symbol: [review_id, primary_file, name, type, ns, start, end]
   ```

One row per unique symbol (dedup key: symbol_name, symbol_type, namespace). `file_path` = primary definition file.

---

## Phase D — Build blast radius

Pool size: 10–20 concurrent symbol analyses.

Read symbols:
```sql
SELECT id, file_path, symbol_name, symbol_type, namespace FROM lsp_symbols WHERE review_id = ?;
```

**For each symbol, parallel issue 4 LSP calls:**
- `textDocument/incomingCalls(symbol, up_to_2_hops)` → callers
- `textDocument/outgoingCalls(symbol, up_to_2_hops)` → callees
- `typeHierarchy/supertypes(symbol, up_to_2_hops)` → base types/interfaces
- `typeHierarchy/subtypes(symbol, up_to_2_hops)` → derived classes/implementors

**Algorithm:**
1. Collect all 4 call results
2. Extract (target_symbol, target_file, distance_hop, call_type) from each
3. Exclude: generated files (`*.generated.*`, `*.designer.*`, `*.g.cs`, `*_pb2.py`), files outside repo root
4. Deduplicate by `(target_symbol, target_file, call_type)` (keep one per call_type)
5. Store in SQLite:
   ```sql
   INSERT INTO lsp_blast_radius (review_id, symbol_id, call_type, target_symbol, target_file, distance, namespace)
   VALUES (?, ?, ?, ?, ?, ?, ?);
   -- For each dedup result: [review_id, symbol_id, 'incomingCall'|'outgoingCall'|'supertype'|'subtype',
   --                         target_name, target_file, distance_hops, target_namespace]
   ```

One row per unique `(call_type, target_symbol, target_file, distance)` per symbol.

---

## Phase E — Cluster and store in SQLite

Read symbols and blast radius:
```sql
SELECT id, symbol_name, symbol_type, namespace, file_path FROM lsp_symbols WHERE review_id = ?;
SELECT symbol_id, call_type, target_symbol, target_file, distance FROM lsp_blast_radius WHERE review_id = ?;
```

**Build clusters:**
1. For each symbol: compute "reach" = all files touched by symbol + its blast radius
2. Group symbols into clusters: target 6000-line budget per cluster (estimate from diff patch)
3. Split at file boundaries (don't split files across clusters)
4. Assign cluster_id ("cluster_1", "cluster_2", etc.)
5. For each symbol in each cluster: create one row in review_clusters

**Store cluster assignments:**
```sql
INSERT INTO review_clusters (review_id, cluster_id, symbol_id)
VALUES (?, ?, ?);
-- For each symbol in each cluster: [review_id, cluster_id, symbol_id]
```

**Query a cluster's symbols during dispatch:**
```sql
SELECT s.id, s.file_path, s.symbol_name, s.symbol_type, s.line_start, s.line_end, s.namespace
FROM lsp_symbols s
JOIN review_clusters c ON s.id = c.symbol_id
WHERE c.review_id = ? AND c.cluster_id = ?
ORDER BY s.file_path, s.line_start;
```

Subagents use this query to get all symbols in their assigned cluster with full file/line information.
