# SQL Bindings Reference

All SQL statements use `?` placeholders for safe parameter binding. Never interpolate strings directly into SQL.

## Binding Rules

1. **Placeholder syntax**: Use `?` for every parameter
2. **Parameter order**: Match the order of `?` placeholders exactly
3. **Array parameters**: When passing arrays (e.g., `skeptic_models`, `advocate_models`), serialize to JSON before binding
4. **Model array resolution**: When binding a specific model from an array slot (e.g., `skeptic_models[0]`), resolve the index to the actual model string before binding

## Examples

### Simple parameter binding
```sql
SELECT review_id FROM review_runs WHERE review_id = ?;
-- bind: [slug]
```

### JSON serialization (arrays)
```sql
INSERT INTO review_runs (
    review_id, goal, skeptic_models, advocate_models, ...
) VALUES (?, ?, ?, ?, ...);
-- bind: [review_id, goal, json_array(skeptic_models), json_array(advocate_models), ...]
-- skeptic_models and advocate_models are JavaScript arrays; serialize with json_array() before binding
```

### Model assignment from slot
```sql
INSERT INTO review_transcript_entries (review_id, round, agent, model, content)
VALUES (?, ?, ?, ?, ?);
-- For skeptic instance 1:
-- bind: [review_id, round, 'skeptic_1', skeptic_models[0], output_json]
-- Note: skeptic_models[0] is evaluated BEFORE binding to get the actual model string (e.g., "claude-sonnet-4.6")
```

### JSON column storage
```sql
UPDATE review_runs SET unreadable_files_json = ? WHERE review_id = ?;
-- bind: [JSON.stringify(unreadable_files), review_id]
```

### JSON column retrieval and parsing
```sql
SELECT unreadable_files_json FROM review_runs WHERE review_id = ?;
-- bind: [review_id]
-- Parse result: JSON.parse(unreadable_files_json)
```

## Common Patterns

### Status-based filtering
```sql
SELECT id, agent, model, round, content FROM review_transcript_entries
WHERE review_id = ? AND agent LIKE 'skeptic_%' AND round = ? AND status = 'active'
ORDER BY id;
-- bind: [review_id, round]
```

### Aggregation across rounds
```sql
SELECT 
  SUM(CASE WHEN verdict = 'Confirmed' THEN 1 ELSE 0 END) as total_confirmed_n,
  SUM(CASE WHEN verdict = 'Defended' THEN 1 ELSE 0 END) as total_defended_n,
  SUM(CASE WHEN verdict = 'Flagged' THEN 1 ELSE 0 END) as total_flagged_n,
  SUM(CASE WHEN verdict = 'Gap' THEN 1 ELSE 0 END) as total_gap_n
FROM review_findings WHERE review_id = ?;
-- bind: [review_id]
```

### Count aggregations
```sql
SELECT COUNT(*) as total_diagnostic_n FROM lsp_diagnostics WHERE review_id = ?;
-- bind: [review_id]

SELECT COUNT(*) as total_rounds FROM review_checks WHERE review_id = ?;
-- bind: [review_id]
```

