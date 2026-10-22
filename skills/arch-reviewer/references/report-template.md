# Report Template

Write the report to `agent-spec/<slug>/arch-review.<harness>-<model>.md`. Use this structure.
Delete a section that has no content and write one line that says why.

```markdown
---
Created: YYYY-MM-DD HH:MM
Last Updated: YYYY-MM-DD HH:MM
Owner: arch-reviewer
Branch: <branch>
---
# Architecture Review: <design title>

**Mode:** Attack review | Attack review + grill the author | User grills the design
**Coding standards:** <resolved files, or "none configured">

## Inputs

| File | Format | Role | Origin |
|---|---|---|---|
| `<path>` | md | source | arch-design |

## Verdict

<One paragraph. Lead with one of: "Ready for review", "Needs work before review", or
"Not reviewable yet". Then the 1–3 findings that decide it.>

## Strengths

- **S1** — <what the design does well> (<section or R/D code>)

## Findings

| # | Severity | Lens | Where | Finding | Status |
|---|---|---|---|---|---|
| F1 | 🔴 Blocker | L4 Failure modes | `R3`, Error Handling | <one line> | ❌ Open |

### F1 — <title>

- **Evidence:** "<quote>" (<section>), or "The design is silent on <topic>."
- **Why it matters:** <the concrete failure: input or state, then the wrong result>
- **Challenge:** <the question the author must answer>
- **Suggested fix:** <one or two lines>
- **Confidence:** high | medium | low

## Challenge questions

Low-confidence concerns and questions that are not yet findings.

- **C1** — <question> ➡️ <recommended answer>

## Grilling log

| Round | # | Question | Answer | Resolution |
|---|---|---|---|---|
| 1 | G1 | <question> | <answer> | Decision |

## Changes to apply to the design

<Only after the user confirmed. One line per change: the section, the change, and the
finding or G<n> it comes from. Never list an edit to approved text. List it as
"needs re-approval".>
```

## Finding status

| Status | Meaning |
|---|---|
| `❌ Open` | Not answered. |
| `💬 Answered` | The author answered it in the grilling log. The design text is not changed yet. |
| `✅ Resolved` | The design text now covers it. |
| `⏭️ Accepted risk` | The author accepts the risk. The log has the reason. |

## Re-run

When the report file already exists, read it first. Keep every `F<n>`, `S<n>`, `C<n>`, and `G<n>`
number. Re-check each `❌ Open` and `💬 Answered` finding against the current design. Append new
findings with the next free number. Never renumber.
