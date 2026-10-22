# Review Lenses

Use these lenses in the attack review. Each lens has a target and a set of attack questions. An
attack question is a prompt for you, not text for the report. A finding needs evidence: a quote
from the design, a repo fact, or the statement "the design is silent on X".

## Attack techniques

Use these techniques with every lens. Each technique changes one condition and asks what breaks.

| Technique | Ask |
|---|---|
| Pre-mortem | It is 6 months after release and this design failed. Name the most likely cause. |
| 10x | Traffic, data, or tenants grow 10 times. Which component fails first? |
| Dependency down | Each external system is unavailable for 1 hour. What does the user see? What data is lost? |
| On-call at 3 AM | A new engineer gets the first alert. Can they find the cause and the fix from this design? |
| Hostile caller | A malicious tenant or user calls every interface. What can they read, change, or exhaust? |
| Reversal cost | Which decision costs the most to undo in a year? Does the design say why it is safe? |
| Requirement change | The most likely product change arrives. How many components change? |

## Lenses

### L1 — Problem and scope

Target: Background, Goal in a Nutshell, Out of Scope.

- Is the problem stated before the solution?
- Are the success criteria observable and measurable?
- Does Out of Scope name the adjacent work that a reader expects to be in scope?
- Does the design solve the stated problem, or a different one?

### L2 — Requirements

Target: Detailed Requirements, Limitations.

- Is each requirement atomic, numbered, and testable?
- Do two requirements conflict?
- Does a component exist that no requirement needs?
- Does a requirement exist that no component covers?
- Are non-functional requirements stated with numbers: latency, throughput, availability, data
  size, cost?

### L3 — Decisions and alternatives

Target: Decisions, Design Alternatives.

- Does each decision have a reason?
- Are the alternatives real, or written to lose?
- Is there a "do nothing", "reuse existing", or "buy" option?
- Does a rejected alternative have a stronger case than the design admits?

### L4 — Failure modes

Target: Business Logic & Error Handling, Architecture & Flows.

- For each external call: what are the timeout, the retry policy, and the idempotency key?
- What happens on partial failure in the middle of a multi-step flow?
- How does the system handle a duplicate message, a poison message, or an out-of-order event?
- Is there backpressure, or does a slow consumer fill a queue without limit?

### L5 — Data and state

Target: Interfaces & Persistence, Life cycle & Maintenance.

- Which component owns each piece of data? Does any data have two writers?
- What consistency does each read need? Does the design give it?
- How does the schema change later? Is there a migration and a backfill plan?
- What are the retention and deletion rules? Who deletes tenant data on offboarding?

### L6 — Scale, performance, and cost

Target: Proposed Approach, Ops, Quality.

- Is each capacity or latency claim marked as measured or estimated?
- Where is the hot path? Is there a fan-out or an N+1 pattern in it?
- What does the design cost per month at today's load and at 10x?

### L7 — Security and privacy

Target: Security, Interfaces & Persistence.

- Does every new interface require authentication and authorization?
- How does the design isolate tenants? Can one tenant read another tenant's data by id?
- Where do secrets live? Who can read them?
- Does the design store personal or customer data? Is it encrypted at rest and in transit?
- Does the design validate every input before use? Does it write every sensitive action to an
  audit log?

### L8 — Operability

Target: Ops, Quality, Life cycle & Maintenance.

- Which metrics, logs, and alerts show that the feature works?
- What are the service level objectives (SLOs)?
- How does the rollout work: feature flag, canary, percentage?
- What is the rollback path? Does a rollback lose data?
- Which team owns the feature on-call?

### L9 — Interfaces and contracts

Target: Interfaces & Persistence, Architecture & Flows.

- Is each interface versioned? Is each change backward compatible with current callers?
- Are error shapes, pagination, and limits defined?
- Does each arrow in a diagram name the component that starts the call?
- Does passive voice hide which system performs a step? An unowned step is often a bug.

### L10 — Delivery and dependencies

Target: Implementation Plan, open `Q:` lines.

- Is the effort estimate realistic for the number of components and interfaces?
- Which other teams must deliver something? Does the design name each of them?
- Which open `Q:` lines block approval?
- Does the design contain a plan (tasks, phases, ordering) where it should state what and why?

### L11 — Coding-standards fit

Target: every section that names code structure, storage, or tools.

- Does a design choice force a violation of the resolved coding standards? Examples: a database
  enum type, local-timezone dates, a local copy of a shared package, logic in the transport layer.
- Cite only rules that exist in the resolved standards files. Quote the rule and name its file.
- When no coding standards resolved, skip this lens and say so in the report.

### L12 — Consistency

Target: the whole document.

- Do two sections state the same fact with different values?
- Does a diagram contradict the text?
- Does the design use more than one name for one concept?
- Does the design cite a repo path, field, or service that does not exist? Check the repo.

## Severity

| Severity | Meaning |
|---|---|
| 🔴 Blocker | The design cannot be approved: a requirement is not met, data can be lost or leaked, or the design contradicts itself. |
| 🟠 Major | A real risk or gap that needs an answer before implementation starts. |
| 🟡 Minor | A clarity or completeness issue. Implementation can start. |

Give each finding a confidence of high, medium, or low. Keep the hedge. A suspected gap is
"may", with the evidence. Report a low-confidence finding as a challenge question, not as a
finding.

## Strengths

Name what the design does well, with evidence. A strength tells the author what to keep when
the design changes. Examples: a decision with a measured reason, an explicit failure mode, an
honest rejected alternative. Do not list a strength to soften a finding.
