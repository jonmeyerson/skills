# Review Tribunal Database Schema

Initialize on first run. Never drop existing tables.

## Tables

### review_runs

Tracks each tribunal review session.

```sql
CREATE TABLE IF NOT EXISTS review_runs (
    review_id          TEXT PRIMARY KEY,
    goal               TEXT NOT NULL,
    diff_source        TEXT NOT NULL,
    diff_path          TEXT NOT NULL,
    index_path         TEXT NOT NULL,
    files_changed      TEXT NOT NULL,
    tribunal_size      INTEGER NOT NULL CHECK(tribunal_size IN (1, 2, 3)),
    debate_rounds      INTEGER NOT NULL,
    skeptic_models     TEXT NOT NULL,   -- JSON array
    advocate_models    TEXT NOT NULL,   -- JSON array
    judge_model        TEXT NOT NULL,
    status             TEXT NOT NULL CHECK(status IN ('running', 'confirmed', 'clean')),
    unreadable_files_json TEXT,         -- JSON array of file paths that could not be read (consistent across rounds)
    ts                 DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

### review_transcript_entries

Records all agent outputs and interactions.

```sql
CREATE TABLE IF NOT EXISTS review_transcript_entries (
    id                 INTEGER PRIMARY KEY AUTOINCREMENT,
    review_id          TEXT    NOT NULL,
    round              INTEGER NOT NULL,   -- 0 = header
    agent              TEXT    NOT NULL,   -- 'orchestrator' | 'skeptic_1'..'skeptic_N' | 'advocate_1'..'advocate_N' | 'judge'
    model              TEXT    NOT NULL,
    status             TEXT    NOT NULL DEFAULT 'active' CHECK(status IN ('active', 'struck')),
    struck_reason      TEXT,              -- NULL unless status = 'struck'
    content            TEXT    NOT NULL,
    ts                 DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

### review_checks

Per-round aggregated verdict summary from Judge. One row per round per check. Used for:
- Computing final pass/fail status (passed=1 if no confirmed issues)
- Aggregating verdict counts across all rounds for final report
- Historical audit trail of verdict evolution across rounds

```sql
CREATE TABLE IF NOT EXISTS review_checks (
    id                 INTEGER PRIMARY KEY AUTOINCREMENT,
    review_id          TEXT    NOT NULL,
    check_name         TEXT    NOT NULL,     -- always 'judge-verdict' for review-tribunal
    round              INTEGER NOT NULL DEFAULT 1,
    confirmed_n        INTEGER,              -- count of confirmed findings this round
    defended_n         INTEGER,              -- count of defended findings this round
    flagged_n          INTEGER,              -- count of flagged findings this round
    confidence         TEXT,                 -- judge's confidence level this round
    passed             INTEGER NOT NULL CHECK(passed IN (0, 1)),  -- 1 if no confirmed, 0 otherwise
    ts                 DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

**Query for aggregates across all rounds:**
```sql
SELECT 
  COUNT(*) as total_rounds,
  SUM(confirmed_n) as total_confirmed,
  SUM(defended_n) as total_defended,
  SUM(flagged_n) as total_flagged,
  AVG(CAST(confidence AS FLOAT)) as avg_confidence
FROM review_checks WHERE review_id = ? AND check_name = 'judge-verdict';
```

### review_findings

Individual findings with verdicts.

```sql
CREATE TABLE IF NOT EXISTS review_findings (
    id                   INTEGER PRIMARY KEY AUTOINCREMENT,
    review_id            TEXT    NOT NULL,
    round                INTEGER NOT NULL,
    finding_n            INTEGER NOT NULL,
    verdict              TEXT    NOT NULL CHECK(verdict IN ('Confirmed', 'Defended', 'Flagged', 'Struck', 'Gap')),
    issue                TEXT    NOT NULL,
    fix                  TEXT,
    location             TEXT,
    additional_locations TEXT,              -- JSON array of strings; NULL if none
    ts                   DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

### lsp_diagnostics

Compiler/linter errors from Phase B (LSP diagnostics pre-pass). Pre-confirmed issues that skip the debate loop.

```sql
CREATE TABLE IF NOT EXISTS lsp_diagnostics (
    id                 INTEGER PRIMARY KEY AUTOINCREMENT,
    review_id          TEXT    NOT NULL,
    file_path          TEXT    NOT NULL,
    line               INTEGER NOT NULL,
    column             INTEGER NOT NULL,
    severity           TEXT    NOT NULL CHECK(severity IN ('error', 'warning', 'info')),
    message            TEXT    NOT NULL,
    diagnostic_code    TEXT,
    ts                 DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

### lsp_symbols

Changed symbols extracted in Phase C via `textDocument/documentSymbol`. Each symbol per file (no cross-file deduplication).

```sql
CREATE TABLE IF NOT EXISTS lsp_symbols (
    id                 INTEGER PRIMARY KEY AUTOINCREMENT,
    review_id          TEXT    NOT NULL,
    file_path          TEXT    NOT NULL,
    symbol_name        TEXT    NOT NULL,
    symbol_type        TEXT    NOT NULL,   -- 'function', 'class', 'method', 'variable', etc.
    namespace          TEXT,               -- qualified name if available (e.g., "com.example.Class" for Java)
    line_start         INTEGER NOT NULL,
    line_end           INTEGER,
    ts                 DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

### lsp_blast_radius

Results from Phase D (4-way LSP traversals). References symbols from `lsp_symbols`.

```sql
CREATE TABLE IF NOT EXISTS lsp_blast_radius (
    id                 INTEGER PRIMARY KEY AUTOINCREMENT,
    review_id          TEXT    NOT NULL,
    symbol_id          INTEGER NOT NULL,  -- foreign key: lsp_symbols.id
    call_type          TEXT    NOT NULL CHECK(call_type IN ('incomingCall', 'outgoingCall', 'supertype', 'subtype')),
    target_symbol      TEXT    NOT NULL,
    target_file        TEXT    NOT NULL,
    distance           INTEGER NOT NULL,  -- hop count (1 or 2)
    namespace          TEXT,               -- target symbol's namespace if available
    ts                 DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (symbol_id) REFERENCES lsp_symbols(id)
);
```

### review_clusters

Clustering information from Phase E. Maps each symbol to its cluster. Join with lsp_symbols to get file paths and line ranges.

```sql
CREATE TABLE IF NOT EXISTS review_clusters (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    review_id   TEXT    NOT NULL,
    cluster_id  TEXT    NOT NULL,
    symbol_id   INTEGER NOT NULL,  -- Foreign key: references lsp_symbols(id)
    ts          DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (symbol_id) REFERENCES lsp_symbols(id)
);
```

**Query a cluster's symbols with file/line info:**
```sql
SELECT s.id, s.file_path, s.symbol_name, s.symbol_type, s.line_start, s.line_end, s.namespace
FROM lsp_symbols s
JOIN review_clusters c ON s.id = c.symbol_id
WHERE c.review_id = ? AND c.cluster_id = ?
ORDER BY s.file_path, s.line_start;
```

## Initialization

The orchestrator auto-creates these tables on first run if they don't exist. If tables already exist, no re-initialization occurs.
