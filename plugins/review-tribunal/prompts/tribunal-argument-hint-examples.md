# Tribunal Argument Hint Examples

The Review Tribunal can be triggered with argument hints to streamline code review. The argument hint format is:

```
<branch:base..head | uncommitted:branch> -- <goal>
```

## Quick Trigger Examples

### Compare uncommitted changes to branch head
```
@review-tribunal uncommitted:main -- verify error handling in API client
```

### Compare specific branches
```
@review-tribunal branch:develop..feature/auth-refactor -- ensure auth middleware maintains backward compatibility
```

## Full Argument Breakdown

| Component | Format | Purpose | Example |
|---|---|---|---|
| Diff source | `uncommitted:branch` | Compare uncommitted changes against a branch | `uncommitted:main` |
| | `branch:base..head` | Compare two branches | `branch:develop..feature/XYZ` |
| Goal | text after `--` | Focus the tribunal's review | `verify error handling in API client` |

## Complete Examples

1. **Review uncommitted changes with specific goal:**
   ```
   @review-tribunal uncommitted:main -- add unit tests for User model
   ```

2. **Review feature branch against develop:**
   ```
   @review-tribunal branch:develop..feature/auth-refactor -- verify backwards compatibility with existing auth tokens
   ```

3. **Review branch with security focus:**
   ```
   @review-tribunal branch:main..feature/database-migration -- check for SQL injection vulnerabilities in new query builders
   ```

## What happens next

After triggering with argument hints, the orchestrator will:
1. Parse the diff source and goal from your prompt
2. Ask for remaining configuration (tribunal size, debate rounds, model assignments)
3. Generate the diff and begin the review
4. Run configured debate rounds with Skeptics, Advocates, and a Judge
5. Emit fix prompts for confirmed issues
