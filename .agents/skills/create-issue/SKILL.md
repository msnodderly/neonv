---
name: create-issue
description: "Creates issues using bd CLI and syncs to GitHub. Use when asked to create an issue, file a bug, add a task, or track new work."
---

# Creating Issues

Creates ONE issue using `bd`, syncs it, then stops. Does NOT implement the issue.

## Context

Read these files first if needed:
- `AGENTS.md` — Contains `bd` command reference and sync procedures
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
bd create \
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
bd show <id>
```

### 4. Sync to GitHub

Stash any uncommitted work first:

```bash
git stash --include-untracked
bd sync --full
git stash pop
```

`bd sync --full` exports, pulls, merges, commits, and pushes.

### 5. Verify Sync

```bash
git status
git log origin/main -1 --oneline
```

Expected:
- No uncommitted `.beads/` changes
- Recent commit with `bd sync: <timestamp>`

### 6. STOP

Do NOT implement the issue. Report:
- Issue ID created
- Sync succeeded
- Commit hash from `git log origin/main -1`

## Troubleshooting

If sync fails with "cannot pull with rebase: You have unstaged changes":

```bash
git stash --include-untracked
bd sync --full
git stash pop
```

## Checklist

- [ ] `bd show <id>` displays issue correctly
- [ ] `bd sync --full` completed
- [ ] `git status` shows no uncommitted `.beads/` changes
- [ ] `git log origin/main -1` shows sync commit
- [ ] NOT started implementing
