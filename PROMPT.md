# Autonomous Agent Workflow

**Project:** neonv (Swift/SwiftUI macOS app)

## Prime Directive

Select ONE task. Complete it. Stop.

Do not start additional tasks after completing your assigned work.

---

## Session Start

1. **Read context**:
   - `docs/neonv-product-spec.md` (product spec)
   - `AGENTS.md` (patterns, procedures, `bd` reference)

2. **Pick task**: Run `bd ready` and select the SINGLE highest priority item

3. **Claim task**: Run `bd update <id> --status in_progress`

4. **Create worktree**: Use `bd worktree` to create an isolated working directory
   ```bash
   bd worktree create <feature-name> --branch task/<id>-short-description
   cd <feature-name>
   ```

   **Why worktrees?** Multiple agents can work in parallel on different tasks. Each agent gets an isolated working directory without branch-switching conflicts. Using `bd worktree` (instead of `git worktree`) automatically configures beads to share the database across all worktrees.

---

## Implementation

### Before Coding
- Read the task description fully: `bd show <id>`
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
2. Close task: `bd close <id> --reason "Completed"`
3. **Sync beads to main**:
   ```bash
   git stash --include-untracked
   bd sync --full
   git stash pop
   ```
4. **Push code branch**: `git push -u origin <branch-name>` (your feature branch)
5. **Create PR**: `gh pr create --title "..." --body "..."` (for code changes only)
6. **STOP** — Do not pick another task

**Note:** Beads database changes go directly to `main` (no PR needed). Only code changes require a PR.

---

## Verification Checklist

Before creating the PR, confirm:

- [ ] `xcodebuild build` succeeds with no errors
- [ ] `bd show <id>` shows task closed
- [ ] `bd sync --full` completed successfully (beads pushed to `main`)
- [ ] `git status` shows no uncommitted `.beads/` changes
- [ ] `AGENTS.md` updated if patterns/gotchas discovered
