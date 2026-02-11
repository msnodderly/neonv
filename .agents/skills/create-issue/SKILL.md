---
name: create-issue
description: "Creates issues using br CLI and syncs to GitHub. Use when asked to create an issue, file a bug, add a task, or track new work."
---

# Creating Issues

Create ONE issue using `br`, sync it, then stop. Do NOT implement the issue.

## Context

Read these files first if needed:
- `AGENTS.md` — Contains `br` command reference and sync procedures
- `docs/neonv-product-spec.md` — Product guidance for issue scoping

## Workflow

### 1. Gather Details

| Field | Required | Values |
|-------|----------|--------|
| Title | Yes | Short, action-oriented (e.g., "Add retry logic to API client") |
| Type | Yes | `task`, `bug`, `feature`, or `epic` |
| Priority | Yes | `0` (critical) to `4` (backlog). Default: `2` |
| Description | Yes | What needs to be done and why |

### 2. Create Issue

```bash
br create \
  --title "Your specific title here" \
  --type task \
  --priority 2 \
  --description "What: Clear description of the work.

Why: Context and motivation.

Acceptance Criteria:
- [ ] First criterion
- [ ] Second criterion"
```

Save the issue ID from output (e.g., `neonv-abc`).

### 3. Verify

```bash
br show <id>
```

### 4. Sync to GitHub

Stash any uncommitted work first:

```bash
git stash --include-untracked
br sync --flush-only
git add .beads/issues.jsonl
git commit -m "br sync: Update issue database"
git push
git stash pop
```

`br sync --flush-only` exports database changes to JSONL. Git commit/push is explicit.

### 5. Verify Sync

```bash
git status
git log origin/main -1 --oneline
```

Expected:
- No uncommitted `.beads/` changes
- Recent commit with `br sync: ...`

### 6. STOP

Do NOT implement the issue. Report:
- Issue ID created
- Sync succeeded
- Commit hash from `git log origin/main -1`

## Troubleshooting

If sync fails with "cannot pull with rebase: You have unstaged changes":

```bash
git stash --include-untracked
br sync --flush-only
git add .beads/issues.jsonl
git commit -m "br sync: Update issue database"
git push
git stash pop
```

## Checklist

- [ ] `br show <id>` displays issue correctly
- [ ] `br sync --flush-only` completed
- [ ] `git status` shows no uncommitted `.beads/` changes
- [ ] `git log origin/main -1` shows sync commit
- [ ] NOT started implementing
