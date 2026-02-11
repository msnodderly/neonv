# Autonomous Agent Workflow

**Project:** neonv (Swift/SwiftUI macOS app)

## Prime Directive

Select ONE task. Complete it. Stop.

Do not start additional tasks after completing your assigned work.

---

## Session Start

1. **Read context**:
   - `docs/neonv-product-spec.md` (product spec)
   - `AGENTS.md` (patterns, procedures, `br` reference)

2. **Pick task**: Run `br ready` and select the SINGLE highest priority item that is NOT already `in_progress`
   
   **IMPORTANT:** Tasks with status `in_progress` are being worked on by another agent. Skip them to avoid conflicts.

3. **Claim task**: Run `br update <id> --status in_progress` to reserve it before starting work

4. **Create worktree**: Use `git worktree` to create an isolated working directory
   ```bash
   git worktree add -b task/<id>-short-description <feature-name> main
   cd <feature-name>
   ```

   **Why worktrees?** Multiple agents can work in parallel on different tasks. Each agent gets an isolated working directory without branch-switching conflicts.

---

## Implementation

### Before Coding
- Read the task description fully: `br show <id>`
- Check `docs/implement_plan.md` for planning guidance
- For complex features: create a design doc in `docs/plans/` before writing code

### While Coding
- **Scope**: Only work on the selected task—no drive-by refactors
- **Style**: Follow Swift API Design Guidelines and existing project patterns
- **Commits**: Commit frequently with clear messages
- **Build**: Run `xcodebuild -scheme NeoNV -destination 'platform=macOS' build` regularly

### After Coding
- Update `AGENTS.md` with any new patterns or gotchas discovered
- Do NOT modify `docs/alt-nv-product-spec.md` unless explicitly instructed

---

## Session End

When the task is complete, follow the "Session Completion Procedure" in `AGENTS.md`:

1. Build passes: `xcodebuild -scheme NeoNV -destination 'platform=macOS' build`
2. Close task: `br close <id> --reason "Completed"`
3. **Sync beads to main**:
   ```bash
   git stash --include-untracked
   br sync --flush-only
   git add .beads/
   git commit -m "br sync: Update issues"
   git pull --rebase
   git push
   git stash pop
   ```
4. **Push code branch**: `git push -u origin <branch-name>` (your feature branch)
5. **Create PR**: `gh pr create --title "..." --body "..."` (for code changes only)
6. **STOP** — Do not pick another task

**Note:** Beads database changes go directly to `main` (no PR needed). Code changes require a PR.

---

## Verification Checklist

Before creating the PR, confirm:

- [ ] `xcodebuild build` succeeds with no errors
- [ ] `br show <id>` shows task closed
- [ ] `br sync --flush-only` completed and sync commit pushed to `main`
- [ ] `git status` shows no uncommitted `.beads/` changes
- [ ] `AGENTS.md` updated if patterns/gotchas discovered
