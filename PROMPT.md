# Autonomous Agent Workflow

We are working on the project in ./neonv
## Core Task
1.  **Context**: Read `docs/alt-nv-product-spec.md` and `docs/alt-nv-issues.md`.
2.  **Pick Task**: Select the highest priority item from `docs/alt-nv-issues.md`.
3.  **Plan**: Check `docs/implement_plan.md` and `docs/prototype-learnings.md` for context.
4.  **Implement**: Work on the task using Swift/SwiftUI conventions (macOS target).

## Workflow Rules

### 1. Preparation
- **Docs**: Read existing specs and plans before coding.
- **Git**: Use `git status` and `git diff` frequently. Commit often with clear messages.

### 2. Implementation (Swift/macOS)
- **PLANING**: Before implementing a complex chain, create a design doc in the docs/ folder
- **Style**: Follow Swift API Design Guidelines and existing project patterns.
- **Tests**: Run tests via `xcodebuild` or Xcode to ensure stability.
  - Test command: `xcodebuild test -scheme neonvPrototype -destination 'platform=macOS'`
- **Scope**: Focus strictly on the selected issue.

### 3. Documentation
- **Issues**: Update `docs/alt-nv-issues.md` with progress (In Progress -> Done).
- **Learnings**: Create/Update `docs/AGENTS.md` with:
  - **Patterns**: Reusable code patterns found.
  - **Gotchas**: Common pitfalls and solutions.
- **Spec**: Do NOT modify `docs/alt-nv-product-spec.md` unless explicitly instructed.

## Completion Checklist
- [ ] Code compiles and runs without errors.
- [ ] Tests passed.
- [ ] `@alt-nv-issues.md` updated.
- [ ] `@AGENTS.md` updated with learnings.
- [ ] Changes committed.
