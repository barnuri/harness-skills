---
title: <Feature / Project Name>
status: Draft            # Draft | In review | Approved
owner: <name>
team: <team>
jira: <PROJ-1234 — the bare key. Linked to the browse URL when jira_base_url (or DESIGN_JIRA_BASE_URL) is set.>
epic: <PROJ-1000 — optional, same treatment. Delete the line if there is no epic.>
area: <subsystem, used as the docs/architecture/<area>/ folder on promotion>
date: <YYYY-MM-DD>
---

# <Feature / Project Name>

---

## Document history

<Author, review meetings, approvals, major changes. One row per revision.>

| Date | Description of the document change | By whom | Comments |
|------|------------------------------------|---------|----------|
| <YYYY-MM-DD> | Initial draft | <name> | |
| | | | |

## Approvals

<Every area below must be signed off before implementation starts.>

| Area | Approver(s) | Approval date | Comments |
|------|-------------|---------------|----------|
| Product, Requirements | | | |
| Architecture, APIs, Security, Life cycle | | | |
| Implementation plan, quality, maintenance, ops | | | |

---

## Background, Motivation & Problem Statement

<What exists today and why it is not enough. State the problem before any solution.>

<Who asked for this: customer requests, issue-tracker references, support tickets, internal need.>

<Scope boundary: what this design explicitly does NOT cover.>

### Competitive Landscape

<How competitors solve this. What they do well, what they are missing, where we differentiate. Omit this subsection if the feature has no external comparison.>

### Goal in a Nutshell

<The solution in one paragraph a reader can repeat back. Name the infrastructure being reused and the pieces being built new.>

<Success criteria: what is observably true once this ships.>

---

## Detailed Requirements (Customer-Facing)

<Numbered, atomic, and testable. Each `R<n>` is a stable identifier that downstream tasks and tests cite — never renumber a requirement once the document has been reviewed; add `R<n+1>` instead.>

- **R1:** <requirement, phrased as observable customer behavior>
- **R2:** <requirement>
- **R3:** <requirement>

### Limitations

<What customers explicitly will NOT be able to do, and why that is acceptable.>

### Out of Scope

<Deferred items and future phases. Anything listed here must not appear in the implementation.>

---

## Proposed Approach in a Nutshell

<Step-by-step description of the chosen design: data flow, components, storage, entities. Name real repo paths in backticks so the approach is locatable, e.g. `src/services/host_config/`.>

<A concrete example — a sample rule, request, or record — so reviewers can check their understanding against something real.>

<Where the output lands: which entity, which UI surface, which downstream consumer.>

Q: <any question that must be answered before this approach is final. One per line, prefixed
`Q:` to auto-number, or `Q3:` to pin the number when other text cites it.>

### Mockups

<Optional — delete this subsection if there is no UI change.>

<UI mocks, wireframes, or screenshots.>

### Expected Limitations

<Optional — delete this subsection if the approach has no notable limits.>

<Main limitations of the proposed approach above, with regard to the requirements. These are limits the *chosen approach* imposes — distinct from the Limitations section above, which is about what the product deliberately does not do.>

### Decisions

<Settled decisions, one line each. Reasoning lives in Document history, not here. Delete this
subsection while every decision is still open.>

| # | Decision | Why |
|---|----------|-----|
| D1 | <the decision, one line> | <short phrase, not a paragraph> |
| D2 | ~~<superseded decision>~~ | Superseded by D<n> |

### Design Alternatives

<Optional — delete this subsection if there was only ever one viable approach.>

<Note: can be moved to the end of the document once decisions have been made.>

#### Alternative 1: <name>

<One-line description.>

- $\color{green}\textbf{SELECTED}$ <strong style="color: #27ae60"><ins>**Pro:** <the benefit that decided it></ins></strong>
- **Con:** <cost>

$\color{green}\textbf{DECISION}$ <strong style="color: #27ae60"><ins>**Decision:** <what was decided></ins></strong>

**Rationale:** <why this beat the alternatives.>

#### Alternative 2: <name>

<One-line description.>

- **Pro:** <benefit>
- **Con:** <cost>

**Decision:** Rejected — <the deciding reason.>

---

## Implementation Plan

> Name the components, their dependencies, and the effort. Do **not** sequence them, and do not
> write task IDs, checkboxes, phases, or per-item status — ordering is derived downstream, and a
> plan embedded here goes stale the moment the work starts.

**Components to build or change**

- `<repo/path/to/component>` — <what changes and why> — satisfies <R1, R2>
- `<repo/path/to/component>` — <what changes and why> — satisfies <R3>

**Infrastructure**

<New services, queues, IaC/Terraform, pipelines, deployment jobs.>

**UI changes**

<Yes — describe them. Or state "None" explicitly; silence reads as an oversight.>

**Cross-team dependencies**

<Which team owns which piece, and what is blocked on them.>

**Effort estimate (EE)**

| Component | Estimate |
|-----------|----------|
| <component> | <N days> |
| <component> | <N days> |

### Architecture & Flows

<Optional — delete this subsection if the change touches no component boundaries.>

<Affected architectural components, and interactions — user-facing and between components.>

<A fenced mermaid block carries this better than prose. Add one here when the design has a flow worth drawing; the diagram renders in the HTML artifact only, not in Word.>

---

## Interfaces & Persistence

<APIs, message contracts, and events: producer, consumer, payload shape.>

**Data model**

```json
{
  "_id": "<id format>",
  "<field>": "<type / example value>"
}
```

<Retention, indexing, and deletion: what removes this data when its parent object is deleted.>

Q: <uniqueness, region scoping, key format, migration of existing data — anything still undecided.>

---

## Business Logic & Error Handling

<Failure modes and what happens on each: retries, DLQ, dropped events, partial data.>

<Logging: what is logged, at what level, with which correlation id.>

---

## Life cycle & Maintenance

<Deployment: pipeline, job, rollout order, feature flag.>

<Versioning, backward compatibility, and rollback plan.>

<Ongoing maintenance: who owns it, and what routine work it creates.>

---

## Security

<Authentication and authorization for every new endpoint or consumer.>

<Data classification, encryption in transit and at rest, secret handling.>

<If the design introduces nothing new because it reuses the platform, state that explicitly — an empty Security section reads as unconsidered.>

---

## Quality

<Optional — delete this section if the existing test strategy covers the change unchanged.>

<Which parts should be covered by unit tests, automation, manual QA, etc.>

---

## Ops

<Optional — delete this section if the change adds no operational surface.>

<Plan to roll out, monitor (health, performance), and operate the new or modified capabilities.>

**Monitoring & alerting**

| Metric | What it measures | Target | Alert threshold |
|--------|------------------|--------|-----------------|
| <metric> | <description> | <goal> | <when to page> |

<Which team owns the alert response. SLI/SLO if the service has one, e.g. "99.9% success over 30 days".>

---

## Other

<Optional — delete this section if nothing else applies.>

<Whatever other considerations matter for this design — documentation, training, migration comms, etc.>
