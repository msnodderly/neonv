# Autonomous Agent Workflow

We are working on the project "neonv"
## Core Task
1.  **Task Tracking** Use 'bd' for task tracking.
2.  **Specs**: Read `docs/alt-nv-product-spec.md` for context.
3.  **Pick Task**: Select the highest priority item using bd
4.  **Plan**: Check `docs/implement_plan.md` for guidance on creating and implementing plans.
5.  **Implement**: Work on the task using Swift/SwiftUI conventions (macOS target).

## Workflow Rules

### 1. Preparation
- **Docs**: Read existing specs and plans before coding.
- **Git**: Commit often with clear messages.

### 2. Implementation (Swift/macOS)
- **PLANING**: Before implementing a complex chain, create a design doc in the docs/plans folder
- **Style**: Follow Swift API Design Guidelines and existing project patterns.
- **Tests**: Run tests via `xcodebuild` or Xcode to ensure stability.
- **Scope**: Focus strictly on the selected issue.

### 3. Documentation
- **Learnings**: Create/Update `AGENTS.md` with:
  - **Patterns**: Reusable code patterns found.
  - **Gotchas**: Common pitfalls and solutions.
- **Spec**: Do NOT modify `docs/alt-nv-product-spec.md` unless explicitly instructed.

## Completion Checklist
- [ ] Code compiles and runs without errors.
- [ ] Tests passed.
- [ ] beads database updated
- [ ] `AGENTS.md` updated with learnings.
- [ ] Changes committed.
