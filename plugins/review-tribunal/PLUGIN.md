# review-tribunal

Adversarial code review plugin. Parallel Skeptics attack the implementation, parallel
Advocates defend it, and a Judge rules on every finding by reading the code directly.
Configurable tribunal size (1–2 pairs) and full model diversity across roles.

## What it does

- Accepts a branch comparison or uncommitted diff as input
- Runs one or more debate rounds: Skeptics find defects, Advocates respond, Judge rules
- For large diffs (5000+ lines), uses LSP to scope review to changed symbols and their
  blast radius rather than passing the full diff to every subagent
- Emits fix prompts for every confirmed issue; surfaces flags requiring human judgment
- Persists all findings in a SQLite session store; writes a final report to `/memories/`

## Files

```
review-tribunal/
├── PLUGIN.md                               ← this file
├── agents/
│   ├── review-tribunal.agent.md            ← orchestrator (user-invocable)
│   ├── review-tribunal-skeptic.agent.md    ← finds defects (dispatched by orchestrator)
│   ├── review-tribunal-advocate.agent.md   ← defends implementation (dispatched by orchestrator)
│   └── review-tribunal-judge.agent.md      ← rules on all findings (dispatched by orchestrator)
└── scripts/
    ├── ReviewPatch.ps1                     ← generates the unified diff patch file
    └── ReviewIndex.ps1                     ← generates the per-file line-number index
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
@review-tribunal Compare branch feature/XYZ to develop -- verify auth middleware handles token expiry
@review-tribunal Compare the uncommitted changes to branch head -- add error handling to Login
```

Arguments parsed from the invocation string:

| Argument | Format | Example |
|---|---|---|
| Branch comparison | `branch:base..head` | `branch:develop..feature/XYZ` |
| Uncommitted diff | `uncommitted:branch` | `uncommitted:feature/XYZ` |
| Goal | free text after `--` | `verify auth middleware handles token expiry` |

Any arguments not supplied in the invocation string are collected interactively via
Step 0 of the orchestrator.

## Dependencies

| Dependency | Required for |
|---|---|
| `git` | Diff generation (all modes) |
| PowerShell 7+ | Running `ReviewPatch.ps1` and `ReviewIndex.ps1` |
| SQLite (via agent `sql` tool) | Session store — transcript, findings, checks |
| `lsp-config` + language servers | LSP scoping phase (diffs ≥ 5000 lines only) |

LSP coverage is optional. Diffs under 5000 lines skip LSP entirely and pass full file
context to every subagent.

## Supported models

| Provider | Models |
|---|---|
| Anthropic | `claude-sonnet-4.6`, `claude-haiku-4.5` |
| OpenAI | `gpt-5.4`, `gpt-5.3-codex` |

No two slots within the same role (Skeptics, Advocates) may share a provider.
Slots across roles may share a provider. The Judge has no provider restriction.

## Tribunal sizes

| Size | Slots |
|---|---|
| 1 | 1 Skeptic, 1 Advocate, 1 Judge |
| 2 | 2 Skeptics, 2 Advocates, 1 Judge |

Size 3 is defined in the schema but currently disabled.
