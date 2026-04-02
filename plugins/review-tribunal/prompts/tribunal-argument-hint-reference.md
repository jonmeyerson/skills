# Argument Hint Reference

The Review Tribunal accepts argument hints to streamline initialization. The orchestrator parses these automatically.

## Format

```
<branch:base..head | uncommitted:branch> -- <goal>
```

## Components

| Component | Format | Purpose | Example |
|---|---|---|---|
| Diff source | `uncommitted:branch` | Compare uncommitted changes against a branch | `uncommitted:main` |
| | `branch:base..head` | Compare two branches | `branch:develop..feature/XYZ` |
| Goal | text after `--` | Focus the tribunal's review | `verify error handling in API client` |

## How the Orchestrator Parses Arguments

The orchestrator's Step 0 (Tribunal Configuration) extracts:

1. **diff_mode** from the diff source specification
   - `uncommitted:branch` → diff_mode = "uncommitted", branch resolved via `git rev-parse`
   - `branch:base..head` → diff_mode = "branch", base and head extracted from range

2. **goal** from all text following the `--` separator

3. **Remaining configuration** (tribunal_size, debate_rounds, model assignments) is collected interactively if not provided

## Partial vs. Full Configuration

You can provide any combination:
- **Argument hint only**: Orchestrator asks for tribunal size, rounds, and model assignments
- **Partial config**: If you also specify tribunal size or rounds, those steps are skipped
- **Full config**: Provide all parameters in one prompt; orchestrator proceeds directly to review

See `review-tribunal-trigger.prompt.md` for invocation examples.
