# Invocation Examples

**What these examples show:** Using the argument-hint format to pre-fill orchestrator configuration and skip asking for those fields.

---

## Pattern 1: Minimal (Diff Only)

Provide only diff source and goal. Orchestrator asks for: tribunal size, debate rounds, model assignments.

```
@review-tribunal uncommitted:main -- verify error handling in the API client
```

```
@review-tribunal uncommitted:develop -- check for SQL injection vulnerabilities in new query builders
```

---

## Pattern 2: Branch Comparison

Specify diff targets (branch + head). Orchestrator asks for: tribunal size, debate rounds, model assignments.

```
@review-tribunal branch:develop..feature/XYZ -- verify the new auth middleware handles token expiry correctly
```

```
@review-tribunal branch:main..feature/database-migration -- ensure backwards compatibility with existing auth tokens
```

---

## Pattern 3: Full Configuration

Pre-fill all parameters. Orchestrator skips configuration and proceeds directly to diff generation.

```
@review-tribunal Compare branch feature/XYZ to develop, tribunal size 2, 2 rounds. Goal: verify the new auth middleware handles token expiry correctly. Skeptic 1 = claude-sonnet-4.6, Skeptic 2 = gpt-5.4, Advocate 1 = gemini-2.5, Advocate 2 = gpt-5.3-codex, Judge = claude-sonnet-4.6.
```

---

## Argument-Hint Format

| Component | Format | Purpose |
|-----------|--------|---------|
| Diff source (uncommitted) | `uncommitted:branch` | Compare working changes to branch HEAD |
| Diff source (branch) | `branch:base..head` | Compare two branches |
| Goal | text after `--` | Focus the review on a specific objective |

After triggering, orchestrator asks for remaining configuration:
- **Tribunal size** (if not pre-filled)
- **Debate rounds** (if not pre-filled)
- **Model assignments** (always asked)
