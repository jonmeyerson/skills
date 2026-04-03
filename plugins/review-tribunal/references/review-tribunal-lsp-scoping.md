# LSP Scoping Workflow (Phases A–E)

Executed for all diffs (improved accuracy for all changes).

**Important:** Start Phase A immediately — LSP server startup can be slow. Beginning discovery now prevents it from blocking subagent dispatch later. Phases B–E depend on LSP being ready, so start the server in Phase A and wait for readiness before issuing any LSP requests.

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

Record errors as pre-confirmed issues — they skip the debate loop. Write:
```
{session_store}/files/review-{review_id}-diagnostics.json
```

Include diagnostic issues in the Final Verdict as a separate DIAGNOSTIC ISSUES section above CONFIRMED ISSUES.

---

## Phase C — Extract changed symbols

For each LSP-covered file, request all document symbols (`textDocument/documentSymbol`) and cross-reference with diff hunk headers to identify which symbols were actually changed.

**Pipelined parallel execution:**
- Maintain a pool of 5–10 concurrent `textDocument/documentSymbol` queries (configurable based on LSP server capacity)
- Load all changed files into a queue
- For each file in queue: Issue a `documentSymbol` request
- Store results in SQLite immediately when each query completes
- When a query slot opens (one query finishes): immediately start the next queued file (don't wait for batch completion)
- This pipelined approach maximizes throughput without idle time waiting for batch boundaries

**Symbol deduplication:** Not needed — each file's symbols are unique to that file (LSP returns symbols *defined* in each file, not all visible symbols)

---

## Phase D — Build blast radius

For each changed symbol, issue all four LSP traversals in parallel (no ordering dependency between them):

- `textDocument/incomingCalls` — callers, up to 2 hops
- `textDocument/outgoingCalls` — callees, up to 2 hops
- `typeHierarchy/supertypes` — base types / implemented interfaces, up to 2 hops
- `typeHierarchy/subtypes` — derived classes / implementors, up to 2 hops

**Pipelined parallel execution:**
- Maintain a pool of 10–20 concurrent symbol analyses (configurable based on LSP server capacity)
- Load all extracted symbols from Phase C into a queue
- For each symbol in queue: Issue all 4 LSP calls in parallel (these 4 calls are interdependent only within the symbol, not across symbols)
- Store results in SQLite immediately when a symbol's 4 calls complete
- When a pool slot opens (one symbol's analysis finishes): immediately start the next queued symbol (don't wait for batch completion)
- This pipelined approach maximizes throughput: continuous streaming of results with no idle time waiting for batch boundaries

**Exclude:** generated files (`*.generated.*`, `*.designer.*`, `*.g.cs`, `*_pb2.py`) and files outside the repository root. Deduplicate across all four traversals before clustering.

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
