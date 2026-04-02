# skills

AI agentic skills — reusable, self-contained plugins for agent runtimes.

## Plugin format

Each plugin lives in its own folder and contains a `PLUGIN.md` manifest plus any
combination of agent files, scripts, and supporting assets.

```
plugins/
└── <plugin-name>/
    ├── PLUGIN.md          ← manifest: description, file index, installation, dependencies
    ├── agents/            ← .agent.md files (orchestrators and subagents)
    └── scripts/           ← supporting scripts (PowerShell, bash, etc.)
```

### PLUGIN.md

Every plugin must include a `PLUGIN.md` at its root with:

- **What it does** — one paragraph description
- **Files** — annotated directory tree showing every file and its role
- **Installation** — steps to install into an agent runtime
- **Invocation** — how to call it, including argument format
- **Dependencies** — external tools, runtimes, or services required

### Agent files

Agent files use the `.agent.md` extension and include a YAML front matter block:

```yaml
---
name: <agent-name>
description: >
  One or two sentences. Used by the runtime to match agent invocations.
argument-hint: "<format hint shown to the user>"   # orchestrators only
user-invocable: true | false
tools: ['read', 'sql', ...]                        # tools this agent may use
agents: ['subagent-name', ...]                     # subagents this agent may dispatch
---
```

Only orchestrators set `user-invocable: true`. Subagents set it to `false` and are
dispatched exclusively by their orchestrator.

### Scripts

Scripts in `scripts/` are supporting tools invoked by agents — not agents themselves.
Name them after what they produce, not after the action (`ReviewPatch.ps1`, not
`Generate-Patch.ps1`). Each script must accept an `-OutputPath` parameter so the
caller controls where output lands.

## Plugins

| Plugin | Description |
|---|---|
| [review-tribunal](./review-tribunal/) | Adversarial code review — Skeptics attack, Advocates defend, Judge rules |
