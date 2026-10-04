# Section Guidance

What belongs in each section of `template.md`, and — just as importantly — what must not.

## The design/plan contract

`design.md` answers **what and why**. `plan.md` / `tasks.md` answer **in what order and by whom**.
The design doc must be dense enough that an agent can derive the second from the first without
asking, and must never pre-empt it.

**The design doc owns:**

| Element | Why an agent needs it |
|---|---|
| YAML frontmatter (`title`, `status`, `owner`, `team`, `jira`, `area`, `date`) | Metadata, not a plan. Lets the doc be located, filtered, and routed without parsing prose |
| Numbered atomic requirements `R1…Rn` | Become acceptance criteria. `R<n>` is the **join key** — downstream tasks cite the requirement they satisfy, giving traceability without the design holding tasks |
| Explicit limitations and out-of-scope | Bounds the derived plan. Without these an agent widens scope |
| Target components with **real repo paths** in backticks | Says *where* work lands, not what order to do it in |
| Data models and interfaces with real field names | Directly buildable |
| Decisions marked `SELECTED`/`DECISION` with rationale | Stops an agent re-litigating settled choices |
| Cross-team and external dependencies | Surfaces what the plan cannot sequence freely |
| Open `Q:` lines | Feed `code-gen`'s Blocking Questions rule — the agent asks instead of guessing |
| Effort estimate per component (EE) | Sizing signal for Small / Medium / Large |

**The design doc must never contain:** task IDs, checkboxes, phases, ordering, `[P]` parallel
flags, per-file edit instructions, or per-item status.

```
design.md                        plan.md / tasks.md
──────────────────────────       ──────────────────────────
R3: exclusions on findings       Phase 1
`src/entity/HostConfig.cs`         [ ] Task 4 (R3) — src/entity/HostConfig.cs
EE ~1d                             [P] Task 5 (R3) — tests/…
DECISION: getResource
```

Everything left of the line is authored by a human and reviewed by product. Everything right of it
is generated and disposable.

---

## Per-section notes

**Document history / Approvals** — fill the history row on every revision. The three approval areas
are fixed; do not rename or add to them.

**Background, Motivation & Problem Statement** — state the problem before any solution. Name the
concrete demand: customer requests, issue-tracker references, support tickets. The scope boundary here is
what stops a derived plan from growing.

**Competitive Landscape** — how competitors solve this and where we differ. Omit the subsection
entirely if there is no external comparison; do not leave it empty.

**Goal in a Nutshell** — one paragraph a reader can repeat back. Name what is reused versus what is
new, because that ratio drives the effort estimate.

**Detailed Requirements** — atomic and testable. One behavior per `R<n>`. Never renumber after
review; append instead. "Compliance runs hourly and emits a finding per violation" is a
requirement; "make compliance better" is not.

**Limitations / Out of Scope** — the most load-bearing bounding in the document. Anything listed
here must not appear in the implementation.

**Mockups** *(optional)* — UI mocks, wireframes, or screenshots. Delete the subsection if there is
no UI change.

**Proposed Approach** — write it so a reader who was not in your conversation can follow it. Include
one concrete example (a sample rule, request, or record) so reviewers check understanding against
something real. Reference real paths in backticks. **No implementation code** — a design doc is a
blueprint, not a PR; schemas and interface shapes are fine, function bodies are not.

**Expected Limitations** *(optional)* — the limits the chosen approach imposes, judged against the
requirements. Keep it distinct from the **Limitations** subsection under Detailed Requirements:
that one is about what the product deliberately does not do, this one is about what the design
cannot do well. Delete the subsection if the approach has no notable limits.

**Design Alternatives** *(optional)* — delete the subsection if there was only ever one viable
approach. The shared Word template carries a note that this section *should move to the end once
decisions have been made*; that relocation is sanctioned, and it is the one exception to leaving
the section order alone. Otherwise, keep the rejected options. The record of what was rejected and why is the
most valuable part of the document, and it is what stops the same debate reopening in three months.
Mark the chosen one with the badge markup below. If a later revision reverses a decision, flip the
marker, rewrite the Decision and Rationale, and note that it reverses the earlier choice.

**Implementation Plan** — this section sits on the boundary and is the easiest to get wrong. Name
components, dependencies, and effort. **Never sequence them; never write task IDs or checkboxes.**
Tie each component back to the requirements it satisfies.

**Architecture & Flows** *(optional)* — affected components and the interactions between them,
both user-facing and internal. A `mermaid` diagram carries this far better than prose. Delete the
subsection if the change touches no component boundaries.

> **Every arrow must say who initiates and who is called.** This is the single most common gap in a
> review: a box-and-line diagram shows that two systems are connected but not which one picks up the
> phone. A reviewer cannot judge coupling, availability, auth direction, or blast radius without it.
>
> - Draw the arrow in the direction of the **call**, not the direction data happens to flow. Label
>   every edge `<initiator> → <target>` plus the trigger — `"Keystone → DCP · card approved"`, not
>   `"register"` — and number them (`1 ·`, `2 ·`) so prose and tables can cite an edge. State the
>   overall direction in one sentence above the diagram, and say plainly where it does not hold.
> - Show a response as a **dashed** edge back, or leave it out. A response is not a second call, and
>   drawing it solid makes a one-way integration look bidirectional. A callback or webhook *is* a
>   second call and gets its own solid arrow, initiator first.
> - **The rule applies to every diagram in the document, not just the top-level component one.** A
>   decision-path or state flowchart crosses a system boundary the moment one of its boxes is a remote
>   call. Put local steps and remote ones in separate labelled subgraphs and label the edge between
>   them. A box reading `register: env_id` names an action but hides who performs it — that is the
>   failure this rule exists to prevent.
> - Pair the component diagram with a `sequenceDiagram` whenever ordering or a failure branch matters.
>   It makes the initiator unambiguous by construction, and it is where retries, async gaps, and
>   "returns before the downstream call" belong.
> - Follow the diagram with an edge table — `# | initiator | target | trigger | in scope` — so the
>   direction survives into the Word export, which cannot render mermaid.

**Draw only what the document's own Scope boundary admits.** A diagram is held to the scope the
document already declared, and it is the easiest place to break it by accident: neighbours are cheap
to draw and each one invites a review conversation the document explicitly refused to have. Show a
system outside the scope **only** when an in-scope edge touches it. If the answer to "what happens
next" is another team's design, write that sentence instead of drawing their boxes:

> What DCP does with a claim once it has one — who reads it, what it notifies, where it gets its
> environment inventory — is DCP's design, not this one.

Solid for what this design builds, dashed for a sibling that reaches the same target another way,
and one line saying which is which. Never state another team's integration shape as fact because a
neighbouring design document describes it — that document is their plan, not their commitment.
Confirm it, or draw it as the shape you are building and say it is unconfirmed.

**Interfaces & Persistence** — real field names, real id formats. Say what deletes the data when its
parent goes away; that question is missed more often than any other.

**Business Logic & Error Handling** — failure modes first, then logging. Monitoring and alerting
live in **Ops**, not here.

**Life cycle & Maintenance** — deployment, versioning, rollback, and who carries the ongoing load.

**Security** — if the design genuinely introduces nothing new because it reuses the platform, say so
explicitly. An empty Security section reads as unconsidered, not as low-risk.

**Quality** *(optional)* — which parts get unit tests, automation, or manual QA. Delete the section
if the existing test strategy covers the change unchanged.

**Ops** *(optional)* — roll-out, monitoring, and operating the change. This is where the monitoring
and alerting table lives. At least one metric, one alert condition, and a named owner for the
response; write it for whoever gets paged at 2am. Delete the section if the change adds no
operational surface.

**Other** *(optional)* — documentation, training, migration comms. Delete it if nothing applies.

---

## Open questions

Write them inline as `Q:` lines in the section they affect, as `template.md` shows.
A `Q:` line is a signal to `code-gen` that the point is unresolved — it will ask rather than guess.

**Ask the user before writing a `Q:` line** — see *Open Questions — Ask, Don't Guess* in
`SKILL.md`. `AskUserQuestion` is the default; a `Q:` line survives only for questions the user
here cannot answer, or when the run is explicitly autonomous.

**A question about the requirements stays in the requirements.** Open `Q:` lines are what block
approval, so they belong in the section they block, written for whoever has to answer them. Only
questions the engineering team will settle by itself belong in a sibling working file.

**Closing a question produces a decision, not more prose.** Delete the `Q:` line and add one row
to the decisions table under Proposed Approach; put the reasoning in a Document history row. A
question that stays as a paragraph after it is answered is the main way a design document becomes
unreadable — see the decisions rule in `SKILL.md`.

**Number them yourself once a document has more than a couple.** `Q:` auto-numbers in document
order, which silently renumbers every later question the moment you insert one — and prose,
review comments and downstream tasks cite questions by name. Write `Q3:` instead and the renderer
keeps your number and anchors it at `#q-3`. Closing a question then means deleting its line and
recording the answer as a decision; the remaining numbers do not shift.
Resolve a question by replacing the `Q:` line with the answer, or by promoting it to a Design
Alternative with a Decision if the choice was substantive.

## Marking selected decisions (GitHub-compatible)

Use this exact triple-layer markup so it renders across GitHub, IDE previews, and HTML exports:

```
$\color{green}\textbf{SELECTED}$ <strong style="color: #27ae60"><ins>**…the selected text…**</ins></strong>
```

Use `SELECTED` for a chosen option in an options list and `DECISION` for a standalone Decision line.
`template.md` shows one of each.
Each layer is load-bearing:

- **Color on GitHub:** GitHub's sanitizer **strips the `style` attribute**, so `<strong style="color:…">`
  shows no color on github.com. The inline LaTeX badge `$\color{green}\textbf{…}$` is the only way to
  get real color there. Keep the `<strong style="color:…">` too — it *does* colorize in CSS-aware
  renderers, so the two layers cover both worlds.
- **Underline:** `<u>` is not on GitHub's allowed-tag list and gets stripped — use `<ins>`.
- **Bold:** `**…**` works everywhere, including inside the kept `<strong>`/`<ins>` tags.

Gotchas: do **not** put `\checkmark` or other math-only commands inside `\textbf{}` — KaTeX errors
with "`\checkmark` is only supported in math mode" and the badge renders as raw source. The LaTeX
badge also renders as raw text in the **GitHub mobile apps**; that is an accepted limitation, and the
`<ins>` + `**` still give underline and bold there.

Use this sparingly — for genuinely selected options and final Decisions only. Over-marking defeats
the purpose.

---

## Everything you produce is sent standalone

`design.md`, `design.html`, and `design.docx` are handed to people as files. Nothing in a design
document may point at a file in this skill — no link to `section-guidance.md` or
`review-process.md`, and no relative path that only resolves inside the repo. Those references are
author guidance and are dead paths for a recipient.

Open questions are also collected in the HTML review panel, alongside reviewer comments — the
launcher reads **Review** and its badge counts both, so a `0` means nothing is outstanding. A `Q:`
line that does not start at the beginning of a paragraph is not detected, so it appears neither as
a callout nor in the panel.

Mermaid diagrams and `Q:` callouts render in the **HTML artifact only**. Word gets the diagram
source as plain text and no callout styling, so send the HTML (or a PDF printed from it) whenever
the diagrams matter.
