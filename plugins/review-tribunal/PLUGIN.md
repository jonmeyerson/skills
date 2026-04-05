# review-tribunal

Adversarial code review plugin. Parallel Skeptics attack the implementation, parallel Advocates defend it, and a Judge rules on every finding by reading the code directly.

**Key features:**
- Configurable tribunal size (1–3 pairs) with full model diversity
- Debate rounds: Skeptics find defects → Advocates respond → Judge rules
- LSP-powered scoping for all diffs (identifies changed symbols and blast radius)
- SQLite session store for full audit trail and reproducibility
- Fix prompts and flags for human judgment

---

## What it does

- Accepts a branch comparison or staged diff (git diff --staged) as input
- Runs one or more debate rounds: Skeptics find defects, Advocates respond, Judge rules
- Uses LSP to scope review to changed symbols and their blast radius, clustering for efficiency
- Emits fix prompts for every confirmed issue; surfaces flags requiring human judgment
- Persists all findings in a SQLite session store; writes a final report to `/memories/`

---

## High-Level Flow

```mermaid
graph TD
    User["👤 User invokes @review-tribunal"]
    Config["⚙️ Step 0: Collect config<br/>goal, diff mode, tribunal size, models"]
    Diff["📝 Step 1: Generate diff<br/>run ReviewPatch.ps1 & ReviewIndex.ps1"]
    LSP["🔍 LSP Scoping<br/>Phases A-E: discover LSP servers,<br/>extract symbols, build blast radius,<br/>cluster findings"]
    Store["💾 SQLite: lsp_diagnostics,<br/>lsp_symbols, lsp_blast_radius,<br/>review_clusters"]
    Debate["⚖️ Step 2: Debate Loop<br/>run N rounds until user satisfied"]
    Verdict["📊 Step 3: Verdicts<br/>confirmed, defended, flagged, gaps"]
    Report["📄 Step 4: Final Report<br/>write to /memories/, emit fixes"]
    
    User --> Config
    Config --> Diff
    Diff --> LSP
    LSP --> Store
    Store --> Debate
    Debate --> Verdict
    Verdict --> Report
```

---

## Orchestrator Pseudo-Code

```
FUNCTION orchestrate_review(goal, diff_source, diff_targets, tribunal_size, debate_rounds, models)
    
    // Step 0: Collect configuration
    review_id = generate_slug(goal)
    verify_unique_providers_per_role(models)
    
    // Step 1: Generate diff
    patch_file, changed_files = run_ReviewPatch(diff_source, diff_targets)
    index_file = run_ReviewIndex(patch_file)
    
    // LSP Scoping (Phases A-E)
    lsp_servers = discover_lsp_servers(changed_files)
    start_all_lsp_servers(lsp_servers)
    
    diagnostics = collect_diagnostics(lsp_servers, changed_files)      // Phase B
    symbols = extract_symbols(lsp_servers, changed_files)             // Phase C
    blast_radius = build_blast_radius(lsp_servers, symbols)           // Phase D
    clusters = cluster_symbols(symbols, blast_radius, line_budget=6000) // Phase E
    
    // Store in SQLite
    INSERT lsp_diagnostics, lsp_symbols, lsp_blast_radius, review_clusters
    
    // Step 2: Debate Loop
    FOR round = 1 TO debate_rounds DO
        // Phase 1: Skeptics (parallel)
        FOR each cluster IN parallel UP TO tribunal_size DO
            findings[round] += skeptic(review_id, cluster, patch_file, index_file)
        END FOR
        
        // Phase 2: Advocates (parallel)
        FOR each skeptic_findings IN parallel UP TO tribunal_size DO
            responses[round] += advocate(review_id, skeptic_findings, patch_file, index_file)
        END FOR
        
        // Phase 3: Judge (sequential)
        verdict[round] = judge(review_id, findings[round], responses[round], patch_file)
        
        // Step 3: Checkpoint
        persist_findings(verdict[round])
        display_verdict(verdict[round])
        
        IF user selects "Stop" THEN
            BREAK
        END IF
    END FOR
    
    // Step 4: Final Report
    final_status = "confirmed" IF any(confirmed_findings) ELSE "clean"
    write_final_report(review_id, final_status, all_findings, all_verdicts)
    emit_fix_prompts(confirmed_findings)
    
END FUNCTION
```

---

## Debate Round Sequence

```mermaid
sequenceDiagram
    participant O as Orchestrator
    participant S1 as Skeptic 1
    participant S2 as Skeptic 2
    participant A1 as Advocate 1
    participant A2 as Advocate 2
    participant J as Judge
    participant DB as SQLite
    
    Note over O: PHASE 1: Dispatch Skeptics (parallel)
    O->>S1: cluster_1, review_id, diff, index
    O->>S2: cluster_2, review_id, diff, index
    S1->>S1: read diff, query lsp_symbols, lsp_blast_radius
    S2->>S2: read diff, query lsp_symbols, lsp_blast_radius
    S1->>DB: INSERT findings (cluster_1)
    S2->>DB: INSERT findings (cluster_2)
    
    Note over O: PHASE 2: Dispatch Advocates (parallel)
    O->>A1: cluster_1, skeptic_findings, review_id, diff, index
    O->>A2: cluster_2, skeptic_findings, review_id, diff, index
    A1->>A1: read diff, query lsp_blast_radius
    A2->>A2: read diff, query lsp_blast_radius
    A1->>DB: INSERT responses (cluster_1)
    A2->>DB: INSERT responses (cluster_2)
    
    Note over O: PHASE 3: Dispatch Judge (sequential)
    O->>J: all_findings, all_responses, review_id, diff, index
    J->>DB: SELECT transcript_entries
    J->>J: read all files, verify every finding
    J->>J: query lsp_diagnostics, lsp_symbols, lsp_blast_radius
    J->>DB: INSERT verdict, check_results, strike_entries
    
    Note over O: CHECKPOINT
    O->>DB: SELECT findings for this round
    O->>O: display verdict to user
```

---

## LSP Scoping Workflow (Phases A–E)

```mermaid
graph LR
    A["📍 Phase A<br/>Discover LSP<br/>servers"]
    B["🔧 Phase B<br/>Collect<br/>diagnostics"]
    C["📌 Phase C<br/>Extract changed<br/>symbols"]
    D["🌀 Phase D<br/>Build blast<br/>radius"]
    E["📦 Phase E<br/>Cluster<br/>findings"]
    
    A -->|servers ready| B
    B -->|diagnostics| DB1["lsp_diagnostics"]
    B -->|servers ready| C
    C -->|symbols| DB2["lsp_symbols"]
    D -->|4-way traversals| DB3["lsp_blast_radius"]
    C -->|symbols| D
    B -->|servers ready| D
    D -->|symbols + impact| E
    E -->|cluster assignments| DB4["review_clusters"]
    
    style A fill:#e1f5ff
    style B fill:#fff3e0
    style C fill:#f3e5f5
    style D fill:#e8f5e9
    style E fill:#fce4ec
    style DB1 fill:#eceff1
    style DB2 fill:#eceff1
    style DB3 fill:#eceff1
    style DB4 fill:#eceff1
```

### Phase A — Discover and start LSP servers

```pseudocode
FUNCTION phase_a_discover_lsp(files_changed)
    lsp_servers = {}
    unscoped_files = []
    
    FOR each file IN files_changed DO
        extension = file.extension()
        server = lsp_config.find_server(extension)
        
        IF server THEN
            IF server NOT IN lsp_servers THEN
                lsp_config.start_server(server)
                lsp_servers[server] = ready=false
            END IF
        ELSE
            unscoped_files.append(file)
        END IF
    END FOR
    
    // Wait for all servers ready
    FOR each server IN lsp_servers DO
        WAIT server.ready()
    END FOR
    
    RETURN (lsp_servers, unscoped_files)
END FUNCTION
```

### Phase B — Diagnostics pre-pass

```pseudocode
FUNCTION phase_b_diagnostics(lsp_servers, files_changed)
    diagnostics = []
    
    FOR each file IN files_changed DO
        server = lsp_servers[file.extension()]
        results = server.textDocument/diagnostic(file)
        
        FOR each diagnostic IN results DO
            diagnostics.append({
                file: file,
                line: diagnostic.line,
                column: diagnostic.column,
                severity: diagnostic.severity,
                message: diagnostic.message,
                code: diagnostic.code
            })
        END FOR
    END FOR
    
    // Pre-confirmed issues (errors = skip debate)
    INSERT INTO lsp_diagnostics (review_id, file_path, line, column, severity, message, diagnostic_code)
    
    RETURN diagnostics
END FUNCTION
```

### Phase C — Extract changed symbols (Pipelined)

```pseudocode
FUNCTION phase_c_extract_symbols(lsp_servers, files_changed, diff_hunks)
    symbol_pool = concurrent_pool(size=5..10)
    all_symbols = []
    
    FOR each file IN files_changed DO
        symbol_pool.add_task(() => {
            server = lsp_servers[file.extension()]
            symbols_in_file = server.textDocument/documentSymbol(file)
            
            FOR each symbol IN symbols_in_file DO
                // Keep only symbols overlapping with diff hunks
                IF symbol.line_range OVERLAPS diff_hunks[file] THEN
                    all_symbols.append({
                        file: file,
                        name: symbol.name,
                        type: symbol.type,
                        namespace: symbol.qualified_name,
                        line_start: symbol.start,
                        line_end: symbol.end
                    })
                END IF
            END FOR
        })
    END FOR
    
    symbol_pool.wait_all()
    
    // Deduplicate by (name, type, namespace)
    dedup_symbols = deduplicate_by_key(all_symbols, key=(name, type, namespace))
    
    // Insert unique symbols
    FOR each symbol IN dedup_symbols DO
        INSERT INTO lsp_symbols (review_id, file_path, symbol_name, symbol_type, namespace, line_start, line_end)
    END FOR
    
    RETURN dedup_symbols
END FUNCTION
```

### Phase D — Build blast radius (Pipelined)

```pseudocode
FUNCTION phase_d_blast_radius(lsp_servers, symbols)
    symbol_pool = concurrent_pool(size=10..20)
    
    FOR each symbol IN symbols DO
        symbol_pool.add_task(() => {
            server = lsp_servers[symbol.file.extension()]
            
            // Issue 4 LSP calls in parallel
            PARALLEL {
                incoming = server.textDocument/incomingCalls(symbol, 2_hops),
                outgoing = server.textDocument/outgoingCalls(symbol, 2_hops),
                supertypes = server.typeHierarchy/supertypes(symbol, 2_hops),
                subtypes = server.typeHierarchy/subtypes(symbol, 2_hops)
            }
            
            // Combine and deduplicate results
            all_results = incoming + outgoing + supertypes + subtypes
            dedup_results = deduplicate_by_key(all_results, 
                key=(call_type, target_symbol, target_file))
            
            // Filter exclusions
            filtered = filter_exclusions(dedup_results, 
                exclude_patterns=[*.generated.*, *.designer.*, *.g.cs, *_pb2.py],
                exclude_outside_repo_root=true)
            
            // Insert blast radius
            FOR each result IN filtered DO
                INSERT INTO lsp_blast_radius (
                    review_id, symbol_id, call_type, target_symbol, 
                    target_file, distance, namespace
                )
            END FOR
        })
    END FOR
    
    symbol_pool.wait_all()
END FUNCTION
```

### Phase E — Cluster findings

```pseudocode
FUNCTION phase_e_cluster(symbols, blast_radius, line_budget=6000)
    clusters = []
    cluster_id = 1
    current_cluster = []
    current_size = 0
    last_file = null
    
    FOR each symbol IN symbols SORTED BY file_path, line_start DO
        // Estimate size: symbol's code + blast radius reach
        symbol_size = estimate_lines(symbol)
        reach_files = blast_radius.get_target_files(symbol.id)
        reach_size = estimate_total_lines(reach_files)
        total_size = symbol_size + reach_size
        
        // Split at file boundary if adding symbol exceeds budget
        IF (current_size + total_size > line_budget) AND (symbol.file != last_file) THEN
            clusters.append({
                cluster_id: f"cluster_{cluster_id}",
                symbols: current_cluster
            })
            cluster_id += 1
            current_cluster = []
            current_size = 0
        END IF
        
        current_cluster.append(symbol.id)
        current_size += total_size
        last_file = symbol.file
    END FOR
    
    // Final cluster
    IF current_cluster.length() > 0 THEN
        clusters.append({
            cluster_id: f"cluster_{cluster_id}",
            symbols: current_cluster
        })
    END IF
    
    // Insert cluster assignments
    FOR each cluster IN clusters DO
        FOR each symbol_id IN cluster.symbols DO
            INSERT INTO review_clusters (review_id, cluster_id, symbol_id)
        END FOR
    END FOR
    
    RETURN clusters
END FUNCTION
```

---

## SQLite Schema & Data Flow

```mermaid
erDiagram
    review_runs ||--o{ review_transcript_entries : has
    review_runs ||--o{ review_checks : has
    review_runs ||--o{ review_findings : has
    review_runs ||--o{ lsp_diagnostics : has
    review_runs ||--o{ lsp_symbols : has
    review_runs ||--o{ lsp_blast_radius : has
    review_runs ||--o{ review_clusters : has
    
    lsp_symbols ||--o{ lsp_blast_radius : "symbol_id"
    lsp_symbols ||--o{ review_clusters : "symbol_id"
    
    review_runs {
        text review_id PK
        text goal
        text diff_source
        text diff_path
        text index_path
        text files_changed
        int tribunal_size
        int debate_rounds
        text skeptic_models
        text advocate_models
        text judge_model
        text status
    }
    
    lsp_diagnostics {
        int id PK
        text review_id FK
        text file_path
        int line
        int column
        text severity
        text message
        text diagnostic_code
    }
    
    lsp_symbols {
        int id PK
        text review_id FK
        text file_path
        text symbol_name
        text symbol_type
        text namespace
        int line_start
        int line_end
    }
    
    lsp_blast_radius {
        int id PK
        text review_id FK
        int symbol_id FK
        text call_type
        text target_symbol
        text target_file
        int distance
        text namespace
    }
    
    review_clusters {
        int id PK
        text review_id FK
        text cluster_id
        int symbol_id FK
    }
```

---

## Subagent Data Access Patterns

```mermaid
graph TB
    SK["🔍 SKEPTIC<br/>Analyze cluster"]
    AD["⚖️ ADVOCATE<br/>Defend cluster"]
    JG["📋 JUDGE<br/>Rule on all"]
    
    SK -->|Query cluster symbols| Q1["SELECT s.* FROM lsp_symbols s<br/>JOIN review_clusters c ON s.id=c.symbol_id<br/>WHERE c.review_id=? AND c.cluster_id=?"]
    SK -->|Query blast radius| Q2["SELECT br.* FROM lsp_blast_radius br<br/>JOIN review_clusters c ON br.symbol_id=c.symbol_id<br/>WHERE c.review_id=? AND c.cluster_id=?"]
    SK -->|Query diagnostics| Q3["SELECT * FROM lsp_diagnostics<br/>WHERE review_id=?"]
    
    AD -->|Query cluster symbols| Q1
    AD -->|Query blast radius| Q2
    
    JG -->|Query all clusters| Q4["SELECT DISTINCT c.cluster_id, s.* FROM lsp_symbols s<br/>JOIN review_clusters c ON s.id=c.symbol_id<br/>WHERE c.review_id=?"]
    JG -->|Query all blast radius| Q5["SELECT c.cluster_id, br.* FROM lsp_blast_radius br<br/>JOIN review_clusters c ON br.symbol_id=c.symbol_id<br/>WHERE c.review_id=?"]
    JG -->|Query diagnostics| Q3
    JG -->|Query transcript| Q6["SELECT * FROM review_transcript_entries<br/>WHERE review_id=? AND status='active'<br/>ORDER BY id"]
    
    Q1 --> DB[(SQLite)]
    Q2 --> DB
    Q3 --> DB
    Q4 --> DB
    Q5 --> DB
    Q6 --> DB
```

---

## Configuration & Model Assignment

```mermaid
graph TD
    TS["Tribunal Size"]
    TS -->|1| M1["1 Skeptic<br/>1 Advocate<br/>1 Judge"]
    TS -->|2| M2["2 Skeptics<br/>2 Advocates<br/>1 Judge"]
    TS -->|3| M3["3 Skeptics<br/>3 Advocates<br/>1 Judge"]
    
    M1 -->|Select models| SRC["Skeptic Role<br/>(all different providers)"]
    M1 -->|Select models| ARC["Advocate Role<br/>(all different providers)"]
    M1 -->|Select model| JMC["Judge Role<br/>(no constraint)"]
    
    SRC -->|"Example: Anthropic + OpenAI + Google"| CHECK["Provider Uniqueness Check"]
    ARC -->|"Example: OpenAI + Anthropic + Google"| CHECK
    JMC -->|"Can match any provider"| CHECK
    
    CHECK -->|Valid| READY["✅ Ready to dispatch"]
    CHECK -->|Invalid| RETRY["❌ Re-prompt conflicting slots"]
```

---

## Files

```
review-tribunal/
├── PLUGIN.md                                    ← this file
├── agents/
│   ├── review-tribunal.agent.md                 ← orchestrator (user-invocable)
│   ├── review-tribunal-skeptic.agent.md         ← finds defects (dispatched)
│   ├── review-tribunal-advocate.agent.md        ← defends implementation (dispatched)
│   └── review-tribunal-judge.agent.md           ← rules on all findings (dispatched)
├── references/
│   ├── review-tribunal-schema.md               ← SQLite schema
│   ├── review-tribunal-invocation-examples.md  ← usage examples
│   ├── review-tribunal-subagent-behavior.md    ← common subagent workflow (Steps 1–3)
│   └── sql-bindings-reference.md              ← SQL binding patterns and examples
├── scripts/
│   ├── ReviewPatch.ps1                         ← generate unified diff
│   └── ReviewIndex.ps1                         ← generate file→line index
├── templates/
│   └── review-tribunal-final-report-template.md ← report format
└── prompts/
    └── (system prompts for agents)
```

## Installation

1. Copy this folder into your agent skills directory (e.g. `/mnt/skills/user/review-tribunal/`).
2. Place `scripts/ReviewPatch.ps1` and `scripts/ReviewIndex.ps1` somewhere on your
   PowerShell `$PATH`, or set the orchestrator's script path variable to their location.
3. Register the four agent files with your agent runtime.

## Invocation

User-facing entry point is `review-tribunal.agent.md`. The three subagent files are
internal — they are dispatched by the orchestrator and should not be invoked directly.

```
@review-tribunal branch:develop..feature/XYZ -- verify auth middleware handles token expiry
@review-tribunal uncommitted:feature/XYZ -- add error handling to Login
```

Arguments parsed from the invocation string:

| Argument | Format | Example |
|---|---|---|
| Branch comparison | `branch:base..head` | `branch:develop..feature/XYZ` |
| Staged diff | `uncommitted:branch` | `uncommitted:feature/XYZ` |
| Goal | free text after `--` | `verify auth middleware handles token expiry` |

Any arguments not supplied in the invocation string are collected interactively via
Step 0 of the orchestrator.

## Dependencies

| Dependency | Required for |
|---|---|
| `git` | Diff generation (all modes) |
| PowerShell 7+ | Running `ReviewPatch.ps1` and `ReviewIndex.ps1` |
| SQLite (via agent `sql` tool) | Session store — transcript, findings, checks |
| `lsp-config` + language servers | LSP scoping phase (all diffs) |

## Supported models

| Provider | Models |
|---|---|
| Anthropic | `claude-sonnet-4.6`, `claude-haiku-4.5` |
| OpenAI | `gpt-5.4`, `gpt-5.3-codex` |
| Google | `gemini-2.5`, `gemini-3-flash` |

No two slots within the same role (Skeptics, Advocates) may share a provider.
Slots across roles may share a provider. The Judge has no provider restriction.

## Tribunal sizes

| Size | Slots |
|---|---|
| 1 | 1 Skeptic, 1 Advocate, 1 Judge |
| 2 | 2 Skeptics, 2 Advocates, 1 Judge |
| 3 | 3 Skeptics, 3 Advocates, 1 Judge |

## Verdict Types

| Verdict | Meaning | Debate? |
|---------|---------|---------|
| **Confirmed** | Defect found; fix included | ✅ Debate closed |
| **Defended** | No defect; goal met | ✅ Debate closed |
| **Flagged** | Requires human judgment | ✅ Debate closed |
| **Gap** | Insufficient evidence | ✅ Debate closed |
| **Struck** | Finding factually wrong | ✅ Debate closed |
| **Diagnostic** | Compiler/linter error | ❌ Skips debate |

---

## Key Concepts

**LSP Scoping:** For all diffs, identifies changed symbols and their blast radius (callers, callees, type hierarchies) via Language Server Protocol. Clusters findings to keep each subagent's context manageable (6000-line budget).

**Tribunal Size:** Number of Skeptic-Advocate pairs. Larger tribunals provide more diverse perspectives but increase review time.

**Model Diversity:** No two slots within the same role (Skeptics or Advocates) may share a provider. Forces different reasoning strategies.

**Pipelined Parallelization:** LSP queries stream results as they complete; next query starts immediately when a pool slot opens. No batching delays.

**Single Source of Truth:** All data persists in SQLite. Subagents query the database for symbols, blast radius, diagnostics. No file-based intermediate state.

## Roundtrip Workflow

```
Round 1: Skeptics → Advocates → Judge → Verdict → Checkpoint

User: "Continue review"

Round 2: Skeptics → Advocates → Judge → Verdict → Checkpoint

User: "Stop — surface final verdict"

Final Report: Confirmed + Flagged + Gaps + Fix Prompts
```

Once a finding is Confirmed, Defended, Flagged, or Struck, it cannot be re-raised in subsequent rounds unless **the diff itself changed** between rounds.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| LSP server fails to start | Check `lsp-config` installed; verify language server is on system |
| Provider uniqueness error | Select different providers for each Skeptic/Advocate slot |
| Subagent timeout | Increase context window; reduce tribunal size; smaller diff |
| SQLite lock error | Close other processes accessing session database |
