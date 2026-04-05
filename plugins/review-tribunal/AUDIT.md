# Audit Report — review-tribunal v1.1.1

Audited files: all agent definitions, schema, scripts, templates, and reference documents under `plugins/review-tribunal/`.

Findings are grouped by severity: **High** (correctness bugs), **Medium** (schema/data integrity and robustness), **Low** (platform limitations and specification gaps).

---

## HIGH — Correctness / Logic Bugs

### H1: Advocate SQL retrieves all-cluster skeptic findings instead of its own cluster's findings

**Location:** `agents/review-tribunal.agent.md:259–269`, `agents/review-tribunal-advocate.agent.md:33`

**Issue:** Each Advocate is dispatched with a specific `{cluster_id}` and queries code context only for that cluster. However, the skeptic-findings query the orchestrator specifies for Advocates retrieves findings from *all* clusters for the round:

```sql
SELECT id, agent, model, round, content FROM review_transcript_entries
WHERE review_id = ? AND agent LIKE 'skeptic_%' AND round = ? AND status = 'active'
ORDER BY id;
```

An Advocate assigned to `cluster_1` receives and must respond to findings from `cluster_2` files it has never read. This directly violates the Advocate rule "For multi-location findings, verify all of them. A partial read is not a defence." Responses on cross-cluster findings are structurally unverifiable.

The problem compounds in batched mode: with 4 clusters and `tribunal_size = 2`, batch 1 runs Skeptics on clusters 1 and 2, then Advocates on clusters 1 and 2 — but the Advocates' SQL still returns findings from clusters 3 and 4 (written in a prior batch), which have no corresponding Advocate reads.

**Recommendation:** Store `cluster_id` on transcript entries. Add a `cluster_id TEXT` column to `review_transcript_entries`. The orchestrator populates it when inserting Skeptic outputs. The Advocate query then becomes:

```sql
SELECT id, agent, model, round, content FROM review_transcript_entries
WHERE review_id = ? AND agent LIKE 'skeptic_%' AND round = ? AND cluster_id = ? AND status = 'active'
ORDER BY id;
-- bind: [review_id, round, cluster_id]
```

---

### H2: No constraint prevents re-raising Struck findings in subsequent rounds

**Location:** `agents/review-tribunal-skeptic.agent.md:33–36`, `agents/review-tribunal.agent.md:302`

**Issue:** The Skeptic spec prohibits re-raising `Defended` findings: "Do not escalate any finding that the Judge ruled Defended in a prior round unless the diff changed between rounds." No equivalent prohibition exists for `Struck` findings. A Struck finding was ruled *factually wrong at the cited location*. Because Struck entries are hidden from the transcript (`status = 'struck'`), a Skeptic re-reading the same files will see the same code and can independently arrive at the same (incorrect) conclusion again, re-raising a finding the Judge already disproved. This creates an infinite loop risk in multi-round sessions.

**Recommendation:** Add to the Skeptic's constraints:

> Do not raise a finding that a prior round's Judge ruled Struck. The Judge already verified the cited location and found it does not contain what was claimed.

Since Struck entries are hidden from the transcript, the Skeptic cannot consult prior Struck rulings directly. The orchestrator should pass a `{struck_findings_summary}` variable (a brief list of struck locations and claims) to each Skeptic dispatch so the Skeptic can avoid re-filing them.

---

### H3: Orchestrator does not short-circuit when all Skeptics return no findings

**Location:** `agents/review-tribunal.agent.md:218–293`

**Issue:** A Skeptic returns `{"findings": [], "no_changes": true}` when it finds nothing to raise (or when the diff is empty for its cluster). The orchestrator checks `{files_changed}` at Step 1 and stops if the file list is empty. However, if Skeptics return empty findings for other reasons (all changed files are unscoped, the diff is real but contains only deletions with no observable defects, etc.), the orchestrator has no logic to short-circuit. Advocates are dispatched against an empty findings list; the Judge receives an empty transcript. Both agents burn LLM calls producing vacuous output.

**Recommendation:** After collecting all Skeptic outputs, before dispatching Advocates, check:

```
if all(skeptic.findings == [] for skeptic in skeptic_outputs):
    skip Advocates and Judge
    persist review_checks row with all counts = 0, passed = 1
    surface "No findings this round" at checkpoint
```

---

### H4: LSP Phase C deduplication collapses distinct cross-file symbols when namespace is NULL

**Location:** `agents/review-tribunal.agent.md:188`, `PLUGIN.md` Phase C pseudocode (lines 269–275)

**Issue:** Phase C deduplicates symbols by `(symbol_name, symbol_type, namespace)` and stores the "primary file." When `namespace` is NULL — common in dynamically-typed languages (Python, JavaScript, Ruby) or when a language server does not report qualified names — two methods with the same name and type in different files collapse into a single `lsp_symbols` row. The secondary file's symbol is silently dropped from all downstream steps: blast radius analysis, clustering, and debate scope. Findings about that file's symbol will be missed entirely, with no warning to the user.

**Example:** `validate()` in `user_service.py` and `validate()` in `order_service.py`, both with `namespace = NULL`, deduplicate to one row. Only one file is reviewed.

**Recommendation:** Deduplication should be scoped to within a single file. The effective unique key is `(review_id, file_path, symbol_name, symbol_type, namespace)`. Cross-file deduplication should only apply when `namespace IS NOT NULL` (i.e., when the qualified name provably identifies the same symbol). Update the schema comment accordingly:

```sql
-- Unique per (review_id, file_path, symbol_name, symbol_type, namespace)
-- Cross-file deduplication applies only when namespace IS NOT NULL
```

---

## MEDIUM — Schema & Data Integrity

### M1: No FOREIGN KEY constraints on any table referencing `review_runs`

**Location:** `references/review-tribunal-schema.md` — all tables

**Issue:** All seven child tables (`review_transcript_entries`, `review_findings`, `review_checks`, `lsp_diagnostics`, `lsp_symbols`, `lsp_blast_radius`, `review_clusters`) carry `review_id TEXT NOT NULL` with no `FOREIGN KEY` referencing `review_runs.review_id`. Orphaned rows accumulate silently if a run row is absent or deleted. Additionally, SQLite disables FK enforcement by default; without `PRAGMA foreign_keys = ON` at connection start, the constraints have no effect even once added.

**Recommendation:** Add `FOREIGN KEY (review_id) REFERENCES review_runs(review_id) ON DELETE CASCADE` to each child table. Add a note to the schema initialization section:

```sql
-- Must be issued once per connection before any DML:
PRAGMA foreign_keys = ON;
```

---

### M2: No indexes on common high-frequency query patterns

**Location:** `references/review-tribunal-schema.md`

**Issue:** The schema defines no indexes. The following queries execute on every round and do full table scans:

| Query | Missing index |
|-------|---------------|
| `review_transcript_entries WHERE review_id=? AND agent LIKE 'skeptic_%' AND round=? AND status='active'` | `(review_id, round, status)` |
| `review_findings WHERE review_id=?` (judge cross-round aggregate) | `(review_id)` |
| `review_clusters WHERE review_id=? AND cluster_id=?` | `(review_id, cluster_id)` |
| `lsp_blast_radius JOIN lsp_symbols ON br.symbol_id = s.id` | `symbol_id` on `lsp_blast_radius` |
| `lsp_symbols WHERE review_id=?` | `(review_id)` |

On a large diff (100+ symbols, tribunal_size=3, 3 rounds), these full scans compound significantly.

**Recommendation:** Add to the schema initialization block:

```sql
CREATE INDEX IF NOT EXISTS idx_transcript_lookup  ON review_transcript_entries(review_id, round, status);
CREATE INDEX IF NOT EXISTS idx_findings_review    ON review_findings(review_id);
CREATE INDEX IF NOT EXISTS idx_clusters_lookup    ON review_clusters(review_id, cluster_id);
CREATE INDEX IF NOT EXISTS idx_blast_radius_sym   ON lsp_blast_radius(symbol_id);
CREATE INDEX IF NOT EXISTS idx_symbols_review     ON lsp_symbols(review_id);
```

---

### M3: Final `status` field conflates confirmed defects with flagged-for-human items

**Location:** `agents/review-tribunal.agent.md:421`, `references/review-tribunal-schema.md:24`

**Issue:** The orchestrator sets `status = 'confirmed'` when `total_confirmed_n > 0 OR total_flagged_n > 0`. A review with zero confirmed defects and three flagged items requiring human judgment is stored with `status = 'confirmed'` — indistinguishable from a review with actual code defects. The `review_runs.status` CHECK constraint allows only `('running', 'confirmed', 'clean')`.

**Recommendation:** Add `'flagged'` to the CHECK constraint and apply three-way logic:

```
status = 'confirmed'  if total_confirmed_n > 0
status = 'flagged'    if total_confirmed_n == 0 AND total_flagged_n > 0
status = 'clean'      if total_confirmed_n == 0 AND total_flagged_n == 0
```

Update the CHECK: `CHECK(status IN ('running', 'confirmed', 'flagged', 'clean'))`.

---

## MEDIUM — Robustness

### M4: Unreadable files are permanently excluded with no re-attempt mechanism

**Location:** `agents/review-tribunal.agent.md:244–255`

**Issue:** The spec states "Unreadable files persist across all rounds — once marked unreadable, they remain so." Round 1 stores the list via `UPDATE review_runs SET unreadable_files_json = ?`; subsequent rounds retrieve it verbatim. If unreadability was transient (network mount, file permission temporarily revoked, NFS timeout), the file remains excluded for the lifetime of the session. The user receives a warning in the checkpoint but has no mechanism to trigger a retry without starting a new review and losing all prior round findings.

**Recommendation:** Add a checkbox to the round checkpoint: "Retry unreadable files next round." If selected, clear `unreadable_files_json` before the next round's Skeptic dispatch. Skeptics that successfully read the previously-unreadable file treat it as newly in-scope; those that still cannot read it re-add it to `unreadable`.

---

### M5: In-memory `{round}` counter is lost on orchestrator restart

**Location:** `agents/review-tribunal.agent.md:95`, Step 3 user checkpoint

**Issue:** `{round}` is an in-memory variable incremented at each "Run another round" selection. If the orchestrator's context is reset (session timeout, agent crash, user re-invokes the orchestrator with the same `review_id`), `{round}` restarts at 1. A fresh round 1 inserts new `review_checks` and `review_findings` rows alongside existing ones from prior rounds, corrupting aggregate counts in the Judge's cross-round totals and the final report.

**Recommendation:** On Step 0, after resolving `review_id`, check for an in-progress run:

```sql
SELECT MAX(round) FROM review_checks WHERE review_id = ?;
-- bind: [review_id]
```

If a result is returned, offer the user "Resume from round N" and initialize `{round} = N + 1`. If the user chooses to restart, delete prior findings and check rows before proceeding.

---

## LOW — Platform & Dependencies

### L1: PowerShell-only scripts with no cross-platform alternative

**Location:** `scripts/ReviewPatch.ps1`, `scripts/ReviewIndex.ps1`, `PLUGIN.md` Dependencies table

**Issue:** Both scripts require PowerShell 7+. On macOS and Linux developer machines without PowerShell, the plugin is entirely non-functional at Step 1. The `PLUGIN.md` Dependencies table lists PowerShell as a requirement but provides no fallback. The scripts perform operations trivially portable to bash (git diff, line-by-line text parsing).

**Recommendation:** Provide bash equivalents `scripts/review-patch.sh` and `scripts/review-index.sh` with identical parameters and output contracts. The orchestrator auto-selects based on the runtime OS or an explicit `--script-runner` configuration option.

---

### L2: `ReviewPatch.ps1` does not strip `\r` before joining patch lines on Windows

**Location:** `scripts/ReviewPatch.ps1:102`

**Issue:**

```powershell
[System.IO.File]::WriteAllText($OutputPath, ($patch -join "`n"), [System.Text.Encoding]::UTF8)
```

On Windows, PowerShell splits the `git diff` output into an array by line boundaries but retains trailing `\r` on each element when git outputs CRLF. Rejoining with `\n` produces `line\r\nline\r\n...` — an invalid patch format. Subagents reading this file will see `\r` at the end of every diff line, which breaks `verified` field comparisons in Skeptic output (the exact code quoted will carry a trailing carriage return that the source file does not).

**Recommendation:**

```powershell
$normalized = $patch | ForEach-Object { $_.TrimEnd("`r") }
[System.IO.File]::WriteAllText($OutputPath, ($normalized -join "`n"), [System.Text.Encoding]::UTF8)
```

---

### L3: LSP blast radius exclusion patterns are hardcoded with no user configuration

**Location:** `agents/review-tribunal.agent.md:196`, `PLUGIN.md` Phase D pseudocode

**Issue:** The exclusion list `[*.generated.*, *.designer.*, *.g.cs, *_pb2.py]` is embedded in the orchestrator prompt. Projects with different auto-generated file conventions (e.g., `*.auto.ts`, `vendor/**`, `__generated__/**`, auto-generated test mocks) cannot extend the list without editing the orchestrator agent file directly.

**Recommendation:** Add an optional `exclusion_patterns` field to Step 0 configuration, defaulting to the current hardcoded list. Allow it to be passed in the invocation argument string:

```
@review-tribunal branch:develop..feature -- goal --exclude "vendor/**,*.auto.ts"
```

---

## LOW — Specification Gaps

### L4: `review_id` slug generation algorithm is underspecified

**Location:** `agents/review-tribunal.agent.md:60`

**Issue:** "Generate a slug from `{goal}` (lowercase, hyphens, max 40 chars)" does not define: how punctuation is handled, whether consecutive hyphens are collapsed, whether leading/trailing hyphens are stripped, or whether non-ASCII characters are transliterated or dropped. Different agent implementations could produce different slugs for the same goal, causing collision detection to miss duplicates when two implementations are used against the same database.

**Recommendation:** Specify the algorithm exactly:

> Lowercase the goal. Replace any run of characters that are not `[a-z0-9]` with a single hyphen. Strip leading and trailing hyphens. Truncate to 40 characters. Strip any trailing hyphen introduced by truncation.

---

### L5: `{subtask_goals}` mapping silently applies default goal for unmatched file paths

**Location:** `agents/review-tribunal.agent.md:160–164`

**Issue:** "If caller mapping is invalid JSON or contains unknown file paths, report error and stop" — but the spec is silent on the case where a valid mapping omits some files from `{files_changed}`. Those files silently fall back to the default `{goal}`. If the omission was a typo in the caller's mapping (e.g., `"src/services/auth.ts"` when the actual path is `"src/service/auth.ts"`), the user receives no feedback that their per-file goal was never applied.

**Recommendation:** After applying the mapping, report which files in `{files_changed}` are using the default goal because no explicit mapping entry matched them. Give the user the option to correct the mapping or proceed with defaults.
