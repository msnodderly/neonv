## Overview

This document describes the issue grooming and project management process. Use this as a reference when performing PM duties or grooming the backlog.

Break down tasks into items suitable for execution by parallel coding agents.

## Issue Tracking System

This project uses **bd (beads)** for issue tracking. 

### Key Commands

```bash
bd ready              # Find issues ready to work (no blockers)
bd list --status=open # All open issues
bd blocked            # Show blocked issues
bd show <id>          # Detailed issue view
bd create --title="..." --type=task|bug|feature|epic --priority=0-4
bd update <id> --description="..." --status=...
bd close <id>         # Complete an issue
bd dep add <issue> <depends-on>  # Add dependency
bd stats              # Project statistics
```

## Grooming Process

### 1. Preparation

Start each grooming session by:

```bash
git checkout -b pm-grooming-YYYY-MM-DD
bd ready              # See what's unblocked
bd list               # Review all issues
bd blocked            # Check blocked issues
bd stats              # Get project health metrics
```

### 2. Review Criteria

For each issue, verify:

#### **Completeness Checklist**
- [ ] Has clear, specific title
- [ ] Has detailed description explaining WHAT and WHY
- [ ] Has acceptance criteria (checkbox list)
- [ ] Has appropriate type (task/bug/feature/epic)
- [ ] Has correct priority (P0-P4)
- [ ] Is small enough to implement in ~10 minutes OR broken into subtasks
- [ ] Dependencies are correctly set

#### **Task Sizing**
- **Good task**: Can be implemented in 5-15 minutes
- **Too large**: Needs breakdown into subtasks
- **Too small**: Consider combining with related work

#### **Priority Guidelines**
- **P0**: Critical blockers, production down
- **P1**: Important features, architectural decisions
- **P2**: Standard features and improvements (default)
- **P3**: Nice-to-haves, polish
- **P4**: Backlog, future considerations

### 3. Common Grooming Actions

#### Adding Descriptions

```bash
bd update <id> --description "Clear description of what needs to be done.

Requirements:
- Specific requirement 1
- Specific requirement 2

Acceptance Criteria:
- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

NOTES: Any architectural questions or concerns"
```

#### Breaking Down Large Tasks

For tasks too large to complete in ~10 minutes:

1. Create subtasks with descriptive titles
2. Add dependencies so subtasks block parent
3. Ensure subtasks are sequenced properly

Example:
```bash
# Create subtasks
bd create --title "Subtask 1: Foundation" --type task --priority 2 --description "..."
bd create --title "Subtask 2: Core logic" --type task --priority 2 --description "..."
bd create --title "Subtask 3: Integration" --type task --priority 2 --description "..."

# Add dependencies (parent depends on children)
bd dep add parent-id subtask1-id
bd dep add parent-id subtask2-id
bd dep add parent-id subtask3-id

# Sequential dependencies if needed
bd dep add subtask2-id subtask1-id
bd dep add subtask3-id subtask2-id
```

#### Marking Issues Not Ready

For issues requiring design decisions or more information:

1. Add note to description about what's unclear
2. Add to questions.md (see below)
3. Consider creating a "Design:" task to resolve questions
4. Dependencies will naturally block until design is done

### 4. Managing Epics

Epics are large features spanning multiple tasks.

**Epic Structure:**
- Epic issue (type=epic)
- Multiple task issues that block the epic
- Design tasks (priority P1) before implementation tasks
- Clear success criteria in epic description

**Epic Grooming:**
1. Ensure epic has clear vision and goals
2. Break down into implementable tasks
3. Identify design/architectural questions
4. Create blocking dependencies
5. Sequence tasks appropriately

Example dependency structure:
```
Epic: Multi-threading Support
  ← Design: Architecture decisions (P1, blocks everything)
  ← Implement: Basic threading (P2, depends on design)
  ← Implement: Tmux integration (P2, depends on basic)
  ← Implement: Thread management UI (P2, depends on basic)
```

### 5. Dependency Management

**Rules:**
- Design tasks block implementation tasks
- Foundation blocks features built on it
- Epics are blocked by their subtasks
- Avoid circular dependencies

**Check dependencies:**
```bash
bd blocked           # See what's blocked
bd show <id>         # See specific dependencies
```

### 6. Identifying Questions

Create `docs/questions.md` for issues needing clarification:

```markdown
# Architectural Questions

## Multi-Threading Architecture

**Issue:** agent-0wg, agent-2jm
**Question:** How should we handle thread state?

Options:
1. In-memory only (lost on restart)
2. File-based persistence
3. Separate database

**Needs decision from:** Matt

## Skill System Design

**Issue:** agent-3fj
**Question:** Should MMCA use same skill format as Claude Code?

Concerns:
- Compatibility vs. simplicity
- ...

**Needs decision from:** Matt
```

### 7. Final Steps

After grooming:

1. **Verify work:**
   ```bash
   bd ready          # Should see well-groomed, unblocked tasks
   bd blocked        # Review blockers make sense
   bd stats          # Sanity check numbers
   ```

2. **Document decisions:**
   - Update PM.md if process changed
   - Update questions.md with open items
   - Create design tasks for architectural decisions

3. **Commit and push:**
   ```bash
   git add .beads/ docs/
   git commit -m "PM grooming: <summary of changes> (pm-grooming)"
   git push -u origin HEAD
   gh pr create --title "PM Grooming: <date>" --body "..."
   ```

## Quality Indicators

### Good Backlog Health
- 60%+ issues have descriptions
- 80%+ tasks are small (<15 min)
- Clear path from "ready" to implementation
- Minimal blocked tasks without good reason
- Epics have clear breakdown

### Needs Grooming
- Many issues without descriptions
- Large tasks not broken down
- Unclear priorities
- Circular dependencies
- "Ready" tasks not actually implementable

## Common Patterns

### Pattern: Feature Epic

```
Epic: Feature Name
  ← Design: Architecture (P1)
  ← Task: Foundation (P2, depends on design)
  ← Task: Core Feature (P2, depends on foundation)
  ← Task: Polish/UX (P3, depends on core)
  ← Task: Documentation (P3, depends on core)
```

### Pattern: Bug Fix

Simple bugs don't need epics:

```
Bug: Specific error description
- Description with repro steps
- Acceptance: Error fixed, test added
- Priority: Based on severity
```

### Pattern: Research/Design

Before implementing complex features:

```
Design: Architecture for X
- Research existing approaches
- Document options and tradeoffs
- Get feedback/decision
- Blocks implementation tasks
```

## Tips for New PMs

1. **Start small**: Groom 5-10 issues first session
2. **Ask questions**: Add to questions.md when unsure
3. **Check "ready"**: Best metric for grooming quality
4. **Use bd prime**: Shows workflow context
5. **Trust the system**: Dependencies prevent premature work
6. **Document decisions**: Future you will thank you

## Lessons Learned: PM Session 2026-01-18

This section captures practical insights from real grooming sessions. Read this before your first grooming!

### Finding and Handling Duplicates

**What happened:** Found agent-on1 and agent-lbb.1 were both implementing the same `/edit` command feature.

**How to spot duplicates:**
```bash
# Search issue titles for similar keywords
bd list | grep -i "edit\|buffer"

# When reviewing an issue, check "RELATED" section in bd show output
bd show agent-on1  # Showed relationship to agent-lbb

# Look for closed issues on same topic
bd list --status=all | grep -i "skill"  # Found agent-d35 was closed, agent-3cd still open
```

**How to handle duplicates:**
1. Choose which issue to keep (usually the one with more detail or subtasks)
2. Remove dependencies: `bd dep remove <issue> <depends-on>`
3. Close with clear reason: `bd close <duplicate-id> --reason "Duplicate of agent-xyz. Consolidated under xyz."`
4. Update remaining issue to capture any unique info from duplicate

**Mistake to avoid:** Don't force-close blocked issues. Remove dependencies first, or you'll leave orphaned references.

### Understanding bd Dependencies (Direction Matters!)

**Critical concept:** `bd dep add A B` means "A depends on B" (B blocks A).

**This was confusing at first!**

```bash
# WRONG mental model:
bd dep add parent-task subtask  # "parent has child subtask"

# CORRECT mental model:
bd dep add parent-task subtask  # "parent DEPENDS ON subtask" (subtask must finish first)
```

**Visualization:**
```
bd dep add agent-lbb.1 agent-99b

Result:
  agent-lbb.1 (parent, BLOCKED)
     ↓ depends on
  agent-99b (child, must complete first)

bd show output:
  agent-lbb.1:
    DEPENDS ON → agent-99b (blocks are listed here)

  agent-99b:
    BLOCKS ← agent-lbb.1 (reverse relationship shown)
```

**Pro tip:** Use `bd show <id>` to verify dependency direction after adding. If you see "DEPENDS ON" pointing wrong way, fix it immediately.

### When to Create Design Tasks vs. Just Add Notes

**Question:** Should architectural questions be design tasks or just notes in questions.md?

**Answer:** Create a design task when:
1. Multiple implementation tasks are blocked waiting for the decision
2. The decision requires research/prototyping (not just a quick call)
3. You want to track that design work in bd stats/velocity
4. An agent could actually work on researching/documenting options

**Example from this session:**
- Created **agent-0wg** (Design: Multi-agent architecture) as P1 task
- It blocks **agent-ppw**, **agent-9m5**, and ultimately **agent-2jm** epic
- This shows up in `bd blocked` making the blocker visible
- Someone can claim agent-0wg and work on the design doc

**Just use questions.md when:**
- Quick decision needed from project owner (not research-intensive)
- Preference/style question rather than architecture
- Documentation of "things to think about" but not blocking work yet

### Subtask Naming Conventions

**Lesson:** Subtask titles should show sequence and scope at a glance.

**Good subtask titles:**
```
/edit: Parse REPL command and extract buffer           (step 1)
/edit: Open buffer in external editor                  (step 2)
/edit: Parse edited buffer and validate                (step 3)
/edit: Merge edited buffer back into conversation      (step 4)
```

**Why this works:**
- Common prefix (`/edit:`) groups them visually in `bd list`
- Verb starts each step (Parse, Open, Parse, Merge)
- Clear progression even without seeing dependencies
- Easy to tell which part you're working on

**Bad subtask titles:**
```
Implement editing                    (too vague)
Add buffer support                   (what aspect?)
Handle buffer changes                (which step?)
Finish edit feature                  (not a discrete task)
```

**Pro tip:** Use imperative mood (command form): "Add X", "Implement Y", not "Adding X" or "Should add X".

### Using Priority to Signal Sequencing

**Discovery:** Priority serves dual purpose - importance AND sequencing.

**Pattern observed:**
```
agent-0wg: Design task - P1 (do this first!)
agent-ppw: Basic implementation - P2 (depends on design)
agent-9m5: Advanced feature - P2 (depends on basic)
```

**Why P1 for design tasks:**
- They appear higher in `bd ready` list
- Signals "start here" to implementers
- Makes architectural decisions visible as critical path
- Even if the epic is P2, design blockers should be P1

**Pro tip:** After grooming, run `bd ready`. The P1 tasks should be the right starting points.

### Checking Related/Closed Issues Before Grooming

**Mistake I avoided:** Almost groomed agent-3cd without checking agent-d35 (closed).

**Always do this:**
```bash
# When grooming an issue, search for related closed issues
bd list --status=all | grep "keyword"

# Example: Grooming "add bd skill"
bd list --status=all | grep -i "skill"
# Found: agent-d35 (closed), agent-3cd (open, related), agent-3fj (different but related)

# Check the closed issue for context
bd show agent-d35
# Saw it was "related" to agent-3cd, gave context on why work was already attempted
```

**What you learn from closed issues:**
- Why was previous attempt closed? (completed, duplicate, blocked?)
- Any context/decisions made?
- Who worked on it? (can ask questions)
- Related issues that might need grooming too?

### The "10-Minute Rule" is a Guideline, Not a Law

**Initial interpretation:** Every task must be <10 minutes!

**Reality:** The rule means "implementable by an agent in one focused session."

**Good 10-minute tasks:**
- Add a config flag and document it
- Fix a specific error message
- Add acceptance criteria to 3 issues
- Create a skill definition file

**Good 15-20 minute tasks (still acceptable):**
- Implement a REPL command with simple logic
- Add a new provider integration following existing pattern
- Write tests for a single function
- Create documentation for a feature

**Needs breakdown (>30 min):**
- "Add multi-threading support" (becomes epic)
- "Implement buffer editing" (becomes 4 subtasks)
- "Design architecture" (becomes research + document + decision)

**Red flags a task is too large:**
1. Description has >5 bullet points in requirements
2. Acceptance criteria has >8 checkboxes
3. You use words like "and also" multiple times
4. You're not sure where to start when reading it
5. It requires touching >5 files

**When to break down:**
- Can you identify discrete steps that could fail independently? → Break it down
- Does it have a "design" phase and "implement" phase? → Separate tasks
- Will the implementer need to make architectural decisions? → Add design task first

### Batch Operations Save Time

**Discovered:** Creating many issues one-by-one is slow. Batch them in terminal.

**Example from this session:**
```bash
# Creating 4 related subtasks - do in one command block
bd create --title "Subtask 1" --type task --priority 2 --description "..." && \
bd create --title "Subtask 2" --type task --priority 2 --description "..." && \
bd create --title "Subtask 3" --type task --priority 2 --description "..." && \
bd create --title "Subtask 4" --type task --priority 2 --description "..."

# Then copy all the IDs and batch the dependencies
bd dep add parent-id subtask1-id && \
bd dep add parent-id subtask2-id && \
bd dep add parent-id subtask3-id && \
bd dep add parent-id subtask4-id
```


Then write your dep commands referencing the file.

### Epics Can Overlap (And That's Okay)

**Initial confusion:** agent-2jm and agent-lbb seemed to overlap heavily.

**Both epics mention:**
- Multi-threaded conversations
- Context merging
- Tmux windows
- Buffer editing

**How I handled it:**
1. Identified **agent-2jm** is about the threading/spawning infrastructure
2. Identified **agent-lbb** is about buffer manipulation and UI commands
3. Created dependencies: agent-2jm → agent-7sc (thread management commands)
4. Both epics can progress in parallel with some shared tasks

**Key insight:** Epics are high-level vision statements. It's okay if they overlap. The task-level dependencies will sort out the actual work order.

**When epics overlap:**
- Create shared tasks that both epics depend on
- Or make one epic depend on the other (if clear sequencing)
- Update epic descriptions to clarify scope boundaries
- Link them in "Related" sections

**Don't:** Try to force epics into perfect non-overlapping boxes. Real features have fuzzy boundaries.

### Git + bd Workflow Quirks

**Challenge:** bd sync modifies `.beads/issues.jsonl` which causes git commit issues.

**The workflow that works:**
```bash
# 1. Make your changes (update issues, etc.)
# 2. Stage your non-beads files first
git add docs/PM.md docs/questions.md

# 3. Run bd sync (it will modify .beads/issues.jsonl)
bd sync

# 4. Stage beads changes
git add .beads/

# 5. Commit everything together
git commit -m "Your message"

# 6. Run bd sync AGAIN after commit
bd sync

# 7. If .beads/ changed again, commit again
git add .beads/
git commit -m "bd sync: Update issue database"

# 8. Push
git push
```

**Why this is annoying:** bd sync synchronizes with remote state, which can modify the JSONL file even after you've committed.

**Pro tip:** Expect 2-3 commits per grooming session:
1. Your actual grooming work
2. bd sync reconciliation
3. Maybe another bd sync after that

**Don't stress about it.** The bd tool is managing distributed state. Just follow the workflow above.

### Validating Your Grooming Work

**Before you PR:** Run these commands and sanity-check the output.

```bash
bd ready          # Should show well-defined, unblocked tasks
bd blocked        # Blocked tasks should have good reasons (design dependencies, etc.)
bd stats          # Check that "Ready to Work" increased
bd list | head -20  # Scan titles - do they make sense?
```

**Good signs after grooming:**
- `bd ready` shows 10-20 actionable tasks
- Tasks in `bd ready` have clear descriptions (spot-check with `bd show`)
- `bd blocked` shows tasks waiting on design or prerequisites (not random blocks)
- `bd stats` shows total issues increased (you broke things down) but ready work also increased

**Bad signs (need more grooming):**
- `bd ready` has <5 tasks
- Tasks in `bd ready` are actually blocked but dependencies weren't set
- `bd blocked` has weird circular dependencies
- You see tasks like "TBD" or "Figure out X"

### The Value of questions.md

**Before I created it:** Grooming felt incomplete. Had nagging "but what about...?" thoughts.

**After creating it:** Felt confident marking issues as ready even though architectural questions existed.

**Why it helps:**
1. **Captures uncertainty** without blocking work
2. **Shows you did your due diligence** thinking through implications
3. **Creates agenda items** for technical discussions
4. **Prevents premature decisions** - documents that a choice needs to be made
5. **Helps future PMs** understand why certain tasks are structured as-is

**When to add to questions.md:**
- You encounter "this could go multiple ways" while grooming
- You're about to make an assumption that could be wrong
- You see two issues that seem to conflict
- You're unsure about project conventions/patterns
- Implementation would require choosing a library/framework/architecture

**Format that works:**
```markdown
## Feature Name

**Related Issues:** agent-xxx, agent-yyy
**Status:** 🔴 Blocking / 🟡 Needs decision / 🟢 Ready

### Question Title

Options:
1. Option A - pros/cons
2. Option B - pros/cons

Considerations:
- Important factor 1
- Important factor 2

Recommendation: [your suggestion] OR "Needs owner decision"
```

### Common Mistakes Junior PMs Make

**Learned these by almost making them:**

1. **Not checking bd show before adding dependencies**
   - Added a dep, then realized it was backwards
   - Fix: Always `bd show <id>` after `bd dep add` to verify

2. **Writing descriptions in questions.md instead of the issue**
   - Questions.md is for *questions*, not requirements
   - Fix: Requirements go in issue description, questions go in questions.md

3. **Making all subtasks the same priority as parent**
   - Actually, sequence matters more than uniform priority
   - Fix: Design subtasks get P1, implementation gets P2

4. **Not naming subtasks clearly**
   - Generic names like "Part 2" are useless
   - Fix: Descriptive names with context (see "Subtask Naming" above)

5. **Trying to groom everything in one session**
   - Got fatigued after ~15 issues, quality dropped
   - Fix: Groom 8-12 issues well, stop, PR it, repeat next session

6. **Not documenting "why" in issue descriptions**
   - Just wrote "what" to do
   - Fix: Add context - why is this needed? What problem does it solve?

7. **Forgetting to update epic descriptions after breaking them down**
   - Epic had 10 bullet points, but I created tasks for them
   - Fix: Update epic to reference the subtasks, remove duplicated detail

### Your First Grooming Session: A Checklist

Use this for your first time:

**Before you start:**
- [ ] Read this entire PM.md document
- [ ] Run `bd prime` to understand bd workflow
- [ ] Run `bd ready` and `bd stats` to see current state
- [ ] Create your grooming branch: `git checkout -b pm-grooming-YYYY-MM-DD`

**During grooming (repeat for each issue):**
- [ ] Run `bd show <id>` to see full details
- [ ] Check for duplicates: `bd list --status=all | grep <keyword>`
- [ ] Does it have a clear description? If not, add one
- [ ] Does it have acceptance criteria? If not, add them
- [ ] Is it <15 minutes of work? If not, break it down
- [ ] Are dependencies correct? Use `bd show` to verify
- [ ] Are there architectural questions? Add to questions.md

**After grooming 8-12 issues:**
- [ ] Run `bd ready` - do tasks look implementable?
- [ ] Run `bd blocked` - do blocks make sense?
- [ ] Run `bd stats` - did ready work increase?
- [ ] Update questions.md with any architectural decisions needed
- [ ] Commit: `git add .beads/ docs/`
- [ ] Commit: `git commit -m "PM grooming: <what you did>"`
- [ ] Run `bd sync` (might modify .beads again)
- [ ] Commit again if needed: `git add .beads/ && git commit -m "bd sync"`
- [ ] Push: `git push -u origin HEAD`
- [ ] PR: `gh pr create --title "PM Grooming: <date>"`

**After your first session:**
- [ ] Ask for feedback on your PR
- [ ] Update this document if you learned something new!

## References

- `bd prime` - Full bd workflow documentation
- `.claude/CLAUDE.md` - Project-specific instructions
- `docs/questions.md` - Open architectural questions
- `.beads/issues.jsonl` - Raw issue database
