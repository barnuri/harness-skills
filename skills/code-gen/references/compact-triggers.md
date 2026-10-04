# `/compact` Trigger Table

The model cannot run `/compact` itself. When a trigger fires, surface a one-line suggestion to
the user **before** continuing, then wait for them to run it or wave you through.

| Trigger | Suggested command |
|---|---|
| `plan.md` written and approved (Gate A passed) | `/compact preserve agent-spec/<slug>/plan.md contents and current task list; drop research transcripts and exploratory file reads` |
| Phase boundary in `tasks.md` (Phase 0 → 1, 1 → 2, etc.) | `/compact preserve agent-spec/<slug>/tasks.md state and active phase scope; drop completed-phase implementation details and source reads` |
| Context feels heavy after broad search/exploration | `/compact preserve agent-spec/<slug>/plan.md + agent-spec/<slug>/tasks.md + active task; drop search results and unrelated reads` |
| Mid-Implementation Re-Sizing (Small → Medium upgrade) | `/compact preserve what was learned during the small attempt; drop stale assumptions about scope` |
| Resume in a long-running session before starting next task | `/compact preserve agent-spec/<slug>/tasks.md + active task only` |

Format the suggestion as:
> Context is heavy after [reason]. Recommend: `/compact <focus from table above>` before I continue.
