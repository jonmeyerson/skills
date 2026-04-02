---
name: review-tribunal-trigger
description: Quick-start prompts for triggering adversarial code review with argument hints
agent: review-tribunal
argument-hint: "<branch:base..head | uncommitted:branch> -- <goal>"
---

# Argument Hint Format

The Review Tribunal accepts argument hints to streamline initialization:

```
<branch:base..head | uncommitted:branch> -- <goal>
```

| Component | Format | Example |
|---|---|---|
| Diff source (uncommitted) | `uncommitted:branch` | `uncommitted:main` |
| Diff source (branch compare) | `branch:base..head` | `branch:develop..feature/XYZ` |
| Review goal | text after `--` | `verify error handling in the API client` |

The orchestrator parses these automatically and asks for remaining configuration (tribunal size, debate rounds, model assignments).

---

# Quick Tribunal Triggers

## Uncommitted Changes

Review your working directory changes against a branch:

```
@review-tribunal uncommitted:main -- verify error handling in the API client
```

```
@review-tribunal uncommitted:develop -- check for SQL injection vulnerabilities in new query builders
```

## Branch Comparisons

Review one branch against another:

```
@review-tribunal branch:develop..feature/XYZ -- verify the new auth middleware handles token expiry correctly
```

```
@review-tribunal branch:main..feature/database-migration -- ensure backwards compatibility with existing auth tokens
```

## Full Configuration

You can also provide all configuration in one prompt (tribunal size, rounds, models):

```
@review-tribunal Compare branch feature/XYZ to develop, tribunal size 2, 2 rounds. Goal: verify the new auth middleware handles token expiry correctly. Skeptic 1 = claude-sonnet-4.6, Skeptic 2 = gpt-5.4, Advocate 1 = gpt-5.4, Advocate 2 = claude-sonnet-4.6, Judge = claude-sonnet-4.6.
```

## After Triggering

The orchestrator will parse your argument hints and ask for any remaining configuration (tribunal size, debate rounds, model assignments if not provided).
