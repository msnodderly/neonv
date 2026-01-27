# Autonomous Agent Workflow

**Project:** neonv (Swift/SwiftUI macOS app)

## Prime Directive

Select ONE task. Complete it. Stop.

Do not start additional tasks after completing your assigned work.

---

## Session Start

1. **Read context**:
   - `docs/alt-nv-product-spec.md` (product spec)
   - `AGENTS.md` (patterns, procedures, `bd` reference)

2. **Pick task**: Run `bd ready` and select the SINGLE highest priority item

3. **Claim task**: Run `bd update <id> --status in_progress`

4. **Create worktree**: Create a new git worktree with a feature branch
   ```bash
   git worktree add -b task/<id>-short-description ../neonv-<feature> main
   cd ../neonv-<feature>
   ```

   **Why worktrees?** Multiple agents can work in parallel on different tasks. Each agent gets an isolated working directory without branch-switching conflicts.

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
3. Sync beads: `bd sync`
4. Push branch: `git push -u origin <branch-name>`
5. Create PR: `gh pr create --title "..." --body "..."`
6. **STOP** — Do not pick another task

---

## Verification Checklist

Before creating the PR, confirm:

- [ ] `xcodebuild build` succeeds with no errors
- [ ] `bd show <id>` shows task closed
- [ ] `git status` shows clean working directory
- [ ] `AGENTS.md` updated if patterns/gotchas discovered
