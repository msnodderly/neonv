# New Issue Creation Workflow

**Project:** neonv (Swift/SwiftUI macOS app)

## Prime Directive

Create ONE issue. Sync it. Stop.

Do NOT implement the issue. Do NOT start additional tasks.

---

## Step 1: Read Context

Read these files first:
- `AGENTS.md` — Contains `bd` command reference and sync procedures
- Reference `docs/neonv-product-spec.md` if additional product guidance is required.

---

## Step 2: Gather Issue Details

Collect from the user or determine from context:

| Field | Required | Values |
|-------|----------|--------|
| Title | Yes | Short, action-oriented (e.g., "Add retry logic to API client") |
| Type | Yes | `task`, `bug`, `feature`, or `epic` |
| Priority | Yes | `0` (critical) to `4` (backlog). Default: `2` |
| Description | Yes | What needs to be done and why |

---

## Step 3: Create the Issue

Run this command (replace values):

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

**Save the issue ID** from the output (e.g., `neonv-abc`).

---

## Step 4: Verify Issue Created

```bash
bd show <id>
```

Confirm title, description, and priority are correct.

---

## Step 5: Sync to GitHub

**Important:** `bd sync --full` requires a clean working directory. If you have uncommitted changes or untracked files, stash them first:

```bash
git stash --include-untracked
```

Then run the full sync:

```bash
bd sync --full
```

This command:
1. Exports to `.beads/issues.jsonl`
2. Pulls from remote
3. Merges changes
4. Commits to current branch
5. Pushes to `origin`

After sync completes, restore your stashed work:

```bash
git stash pop
```

**Note:** Plain `bd sync` (without `--full`) only exports to JSONL — it does NOT commit or push.

---

## Step 6: Verify Sync Succeeded

Run both commands:

```bash
git status
git log origin/main -1 --oneline
```

**Expected results:**
- `git status` — No uncommitted `.beads/` changes
- `git log` — Recent commit with message like `bd sync: <timestamp>`

---

## Step 7: STOP

You are done. Do NOT:
- Implement the issue
- Pick another task
- Make any code changes

Report to the user:
- Issue ID created
- Confirmation that `bd sync --full` succeeded
- The commit hash from `git log origin/main -1`

---

## If `bd sync --full` Fails

Common failure: "cannot pull with rebase: You have unstaged changes"

**Fix:**
```bash
git stash --include-untracked
bd sync --full
git stash pop
```

---

## Verification Checklist

Before reporting completion:

- [ ] `bd show <id>` displays the new issue correctly
- [ ] `bd sync --full` completed without errors
- [ ] `git status` shows no uncommitted `.beads/` changes
- [ ] `git log origin/main -1` shows recent `bd sync` commit
- [ ] You have NOT started implementing the issue
