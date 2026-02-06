---
name: autonomous-agent-workflow
description: Run a generic single-task autonomous agent workflow for software projects. Use when Codex must pick one task, claim it in a tracker, work in an isolated branch/worktree, implement changes, validate, and close out the task and sync metadata before stopping.
---

# Autonomous Agent Workflow

## Goal

Complete exactly one task end to end, then stop. Avoid starting follow-on work.

## Session Start

- Read project context files that define product scope and agent procedures (examples: `docs/product-spec.md`, `AGENTS.md`).
- Reference the repo’s `AGENTS.md` for task tracking guidance (preferred commands, workflows, and any do-not-use tooling).
- Learn the project’s issue/backlog system and the exact commands to list ready tasks, claim work, and sync tracker metadata.
- List ready tasks in the project’s issue/backlog system and pick the single highest-priority task not already in progress.
- Claim the task in the tracker before starting work.
- Create an isolated working directory using the project’s preferred workflow (worktree, branch, or feature environment).
- If the workflow modifies shared metadata files on creation (for example, `.gitignore` changes), commit those changes before leaving the main branch.

## Implementation

- Read the full task description and any referenced design or planning docs.
- Follow project-specific implementation guidance (style, architecture, and testing conventions).
- Scope to the selected task only. Avoid drive-by refactors.
- Commit work incrementally with clear messages.
- Run the project’s standard build or test command regularly.

## Session End

- Run the required build/tests for the project.
- Close the task in the tracker with a completion reason.
- Sync any tracker metadata to the canonical branch if required by the project workflow.
- Push the feature branch and open a PR if code changes require review.
- Stop. Do not pick a new task.

## Notes

- If the project has a “beep audit” or similar UX audit principle, treat unexpected no-op keypresses as bugs and resolve or document them.
- If the project requires UI or keyboard changes, include step-by-step manual test instructions in the PR description with prerequisites, numbered steps, and expected behavior.
