---
name: rca
description: >
  (BN) Create a root cause analysis / post-incident report as structured markdown, optionally
  enriched from an issue-tracker ticket, log query, or time window. Use when asked for an RCA, postmortem,
  incident report, or an outage/bug writeup. Triggers: "write an RCA", "do a postmortem",
  "document this incident".
allowed-tools: Write, Read, Bash(date *), Bash(mkdir *), Bash(ls *), Bash(pwd), ToolSearch
---

# RCA (Root Cause Analysis) Skill

You help engineers turn a messy incident into a clear, honest root cause analysis. The goal is a document a teammate could read cold and understand *what broke, why, what we did about it, and what we'll change so it doesn't happen again* — not a box-ticking exercise. Accuracy and specificity matter more than completeness; an RCA with three precise timeline entries beats one with ten vague ones.

The output is always a markdown file built from `references/template.md`. Read that template before writing.

**Local overlay.** Read this skill's local overlay first, if one exists: `<skill-dir>/local.md`, else
`~/.config/harness-skills/<skill-name>/local.md` (the plugin-install location, which survives
updates). Also read any file it points to in the `local/` folder beside it. It holds this install's site-specific setup: which issue tracker and
log/monitoring tools to use, the timezone to report in, naming conventions. Its rules override the
defaults below.

## Step 1: Decide the working mode

The skill has two modes that blend together — pick based on what the user gives you:

- **Template mode (default):** The user describes the incident, or the facts are already in this conversation. Take what's there and structure it. Don't invent details — if a field is unknown, mark it `TBD` and, if it matters, ask one focused question rather than guessing.
- **Investigation mode (when pointed at a source):** The user references a ticket key (e.g. `PROJ-123`), a log/error query, a service, or a time window. In that case, pull the real data to build the timeline and root cause instead of relying on memory, using whatever tools this session has (`local.md` names them when configured):
  - **Issue tracker** (if a tool for it is available): use the ticket's created/updated timestamps and comment thread to seed the timeline, and its description for the summary.
  - **Logs/errors** (if a log-search or monitoring tool is available): first-occurrence times, error volume curves, and stack traces are gold for the timeline and root cause.
  - Tools may be deferred. If a tool you need isn't directly callable, search for it first with `ToolSearch` (when the harness has it), then call it. If no such tool exists, stay in template mode and mark the gaps `TBD`.

You don't need every fact before writing. Gather what's cheaply available, then write — leave honest `TBD`s for the rest rather than blocking.

## Step 2: Resolve date and output path

**Date and time.** Work in **one timezone** throughout — for the filename date, the `**Date:**` field, and every timeline entry. Use the zone `local.md` names; otherwise the user's local time. Get the current date/time with `date '+%F %H:%M %Z'` (prefix `TZ='<zone>'` when `local.md` pins one). Use the *incident* date for the filename and the `**Date:**` field if it differs from today and the user told you when it happened; otherwise use today.

**Output path** — in priority order:
1. If the user named a path or folder, write there.
2. Otherwise write to the current working directory (the active folder). Run `pwd` if you're unsure where that is. Don't silently create a new docs tree the user didn't ask for.

**File name:** always `YYYY-MM-DD-rca-<slug>.md`, where `<slug>` is a short kebab-case description of the incident (e.g. `2026-06-24-rca-order-search-timeout.md`). Create the target directory with `mkdir -p` if it doesn't exist.

## Step 3: Write the RCA

Fill every section of the template with **real content**. Concrete beats vague everywhere: "p99 latency rose from 120ms to 9s at 14:32 UTC" is worth more than "the service got slow".

### Section guidance

**Title** — a one-line, specific name for the incident. `Order search 504s during EU peak` beats `Outage`.

**Header block (Date / Author / Severity / Status)** — keep it tight. Severity is the user's call; if they didn't say, infer a rough level from impact and mark it as your estimate.

**Goal** — what the team was *trying to do* — the objective of the work or the system's normal job that the incident interrupted. This frames everything else: a reader should understand what "working" looked like before reading what broke.

**Summary (what broke)** — 2-4 sentences a busy reader can absorb in ten seconds: what failed, who/what was impacted, how long, and how it ended. This is the TL;DR — no root cause detail here, just the shape of the incident.

**Root Cause** — the heart of the document. Explain the actual causal chain, not just the surface symptom. Push past the first answer: "the pod ran out of memory" is a symptom; "a missing pagination limit let a single query load the full orders table into memory" is a cause. If the root cause is still unconfirmed, say so plainly and list the leading hypotheses — a truthful "unknown" is more useful than a confident guess. Include contributing factors (what made it worse or slower to detect) where they exist.

**Timeline** — a chronological table of `When` / `Event`. Use real dates and times in the report's timezone (see Step 2), and label the zone so it's unambiguous. If a source gives you times in UTC (e.g. logs or traces), convert them before recording them. Cover detection → diagnosis → mitigation → resolution. Each row is one factual event; keep commentary out of the timeline and in Root Cause.

**Action Items** — always last, because this is what the RCA is *for*. Each item is concrete, assigned (owner or `TBD`), and where possible has a type (prevent / detect / mitigate) and a target date. Vague items like "improve monitoring" are weak — "add a p99 latency alert on order-search at >1s for 5m (owner: TBD)" is actionable. Distinguish what was already done during the incident from what's still outstanding.

## Step 4: Save and confirm

1. Write the file with the Write tool.
2. Tell the user the full file path.
3. Point out any `TBD`s you left and offer to fill them in or expand any section.

## Style notes

- `#` for the title, `##` for the main sections, `###` for subsections.
- Use a table for the Timeline and for Action Items — they scan far better than prose.
- Use `code` formatting for service names, ticket keys, error types, config keys, and metrics.
- Be direct and factual. An RCA is blameless: describe what systems and processes did, not who to blame. Avoid filler like "it's important to note that".
- Don't pad. If a section genuinely doesn't apply, say why in one line rather than inventing content.
- Keep certainty exact. State a cause the evidence proves flat. A suspected cause stays "likely" or "possible", with the evidence named. Never upgrade a hedge from the source data, and never add a cause or a frequency nobody observed.
- One claim per sentence, active voice, the system or process named as the actor. No semicolons.
