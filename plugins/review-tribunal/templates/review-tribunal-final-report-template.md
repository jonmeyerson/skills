# Final Report Template

Written to `/memories/session/review-{review_id}.md` after all rounds complete.

## Report Structure

```markdown
# Review Tribunal — {review_id}

Goal: {goal}
Diff: {diff_source}
Tribunal: {tribunal_size} Skeptic(s) × {tribunal_size} Advocate(s) × 1 Judge
Rounds: {total_rounds}
Confidence: {final_confidence}
Status: {status}

## Diagnostic Issues ({total_diagnostic_n})

{For each diagnostic error from diagnostics_path:
### {file}, line {line}
{message}
}

## Confirmed Issues ({total_confirmed_n})

{For each confirmed finding across all rounds:
### {n}. {issue} — round {round}
Location: {primary location}{if additional_locations: , {each additional location}}
Fix: {fix}

{fix_prompt tag for this issue — attribute: issue="round{round}-{n}"}
}

## Flagged for Human ({total_flagged_n})

{For each flagged finding across all rounds:
### {n}. {issue} — round {round}
Location: {primary location}{if additional_locations: , {each additional location}}
Reason: {flag_reason}
}

## Gaps ({total_gap_n})

{For each gap finding across all rounds:
### {n}. — round {round}
Question: {question}
Files: {files}
}

## Defended ({total_defended_n})

{For each defended finding: claim — one-line ruling}
```

## Template Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `{review_id}` | Unique tribunal session ID | `review_abc123def` |
| `{goal}` | User's specified review goal | `verify error handling in API client` |
| `{diff_source}` | Branch or uncommitted diff reference | `branch:develop..feature/auth` |
| `{tribunal_size}` | Number of skeptic/advocate pairs | `2` |
| `{total_rounds}` | Number of debate rounds executed | `3` |
| `{final_confidence}` | Overall confidence level | `high`, `medium`, `low` |
| `{status}` | Final review status | `confirmed`, `clean`, `running` |
| `{total_diagnostic_n}` | Count of diagnostic issues | `5` |
| `{total_confirmed_n}` | Count of confirmed issues | `3` |
| `{total_flagged_n}` | Count of flagged issues | `2` |
| `{total_gap_n}` | Count of identified gaps | `1` |
| `{total_defended_n}` | Count of defended issues | `4` |

## Sections

### Diagnostic Issues

Pre-confirmed issues from LSP diagnostics (if ≥5000 line diff). These skip the debate loop.

### Confirmed Issues

Issues that passed the debate gauntlet:
- Skeptics presented them
- Advocates could not adequately defend
- Judge ruled them confirmed

Each includes a `<fix_prompt>` tag for automated fixing.

### Flagged for Human

Issues requiring human judgment:
- Skeptics raised them
- Advocates partially defended
- Judge flagged for manual review

### Gaps

Questions or coverage gaps identified during review:
- Missing test coverage
- Undocumented behavior
- Unclear impact on related code

### Defended

Issues presented by Skeptics but successfully defended by Advocates:
- Implementation is sound
- Concern was mitigated
- No action needed
