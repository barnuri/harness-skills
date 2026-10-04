# tasks.md Template

Expand `agent-spec/<slug>/tasks.md` from its skeleton using this shape:

```markdown
---
Created: YYYY-MM-DD HH:MM
Last Updated: YYYY-MM-DD HH:MM
---

# Tasks: [Feature Name]

## Goal
[One paragraph description of what is being built and why]

## Status
🔄 In progress — last updated: [date]

## Plan
→ See agent-spec/<slug>/plan.md for full design

## Implementation Strategy
- **MVP-first**: deliver the smallest slice that is end-to-end functional before adding polish.
- **Incremental**: each task leaves the codebase in a working state.
- **Parallel** where possible: tasks marked `[P]` are independent and can run concurrently.

## Tasks

### Phase 0 — Foundational (blocking)
> Complete all foundational tasks before starting any feature work.
- [x] Task 0: agent-spec/<slug>/plan.md + agent-spec/<slug>/tasks.md created ✓
- [ ] Task F1: [shared infrastructure / setup that everything else depends on] — [file(s)]

### Phase 1 — [Feature / Story name]
- [ ] Task 1: [description] — [file(s)]
- [ ] [P] Task 2: [description — independent, can run in parallel with Task 3] — [file(s)]
- [ ] [P] Task 3: [description — independent, can run in parallel with Task 2] — [file(s)]

### Phase 2 — Polish / Cross-cutting
- [ ] Task N: [cleanup, error handling, docs if required] — [file(s)]

> Legend: `[ ]` not started · `🔄` in progress · `⏸` blocked — see plan.md Open Questions · `[x] ✓` done · `[P]` parallel-safe

## Notes
[Key decisions, constraints, dependencies discovered during implementation]
```
