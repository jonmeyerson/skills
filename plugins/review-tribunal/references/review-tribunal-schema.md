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

Aggregated check results by round.

```sql
CREATE TABLE IF NOT EXISTS review_checks (
    id                 INTEGER PRIMARY KEY AUTOINCREMENT,
    review_id          TEXT    NOT NULL,
    check_name         TEXT    NOT NULL,
    round              INTEGER NOT NULL DEFAULT 1,
    confirmed_n        INTEGER,
    defended_n         INTEGER,
    flagged_n          INTEGER,
    confidence         TEXT,
    passed             INTEGER NOT NULL CHECK(passed IN (0, 1)),
    ts                 DATETIME DEFAULT CURRENT_TIMESTAMP
);
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

## Initialization

The orchestrator auto-creates these tables on first run if they don't exist. If tables already exist, no re-initialization occurs.
