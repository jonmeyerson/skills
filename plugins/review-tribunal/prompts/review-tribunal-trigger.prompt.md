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
| Diff source (staged) | `uncommitted:branch` | `uncommitted:main` |
| Diff source (branch compare) | `branch:base..head` | `branch:develop..feature/XYZ` |
| Review goal | text after `--` | `verify error handling in the API client` |

The orchestrator parses these automatically and asks for remaining configuration (tribunal size, debate rounds, model assignments).

See [Invocation Examples](../references/review-tribunal-invocation-examples.md) for invocation patterns.
