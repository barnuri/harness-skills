---
name: arch-verify
description: >
  (BN) Verify implemented code against an architecture design document, with incremental re-runs
  and regression detection. Use after implementation when a design doc exists. Triggers: "verify
  against the design", "arch verify", "did I implement everything?", "re-check the design".
allowed-tools: Skill, Read, Write, Edit, Bash(git rev-parse *), Bash(git diff *), Bash(git symbolic-ref *), Bash(git branch *), Bash(ghx repo view *), Bash(ghx pr view *), Bash(ghx api *), Bash(sed *), AskUserQuestion
hooks:
  Stop:
    - hooks:
        - type: command
          command: 'bash "${CLAUDE_PLUGIN_ROOT}/hooks/stop-completion-gate.sh" arch-design-diff.%HARNESS%.md "(❌ Missing|⚠️ Partial|🔄 Deviated)( ⚡ REGRESSION)? \|" arch-verify'
---

# Architecture Verification

You are checking whether the current code implementation addresses the requirements and approach
defined in an architecture design document. You maintain a persistent
`arch-design-diff.<harness>-<model>.md` file under `agent-spec/<slug>/` that tracks alignment
status — enabling fast, incremental re-runs after code changes.

## Slug Resolution

Invoke the `session-slug` skill to resolve which `agent-spec/<slug>/` folder this verification belongs to (reuses an in-context slug from a same-session code-gen run, or derives a fresh one from the design doc name), to ensure `agent-spec/` is gitignored, and to get the `agent_harness` token (its Step 5). Do not re-derive the slug or the gitignore check yourself — `session-slug` is the single source of truth, shared with code-gen, cr, and skills-evolvement.

**Output filename**: `agent-spec/<slug>/arch-design-diff.<harness>-<model>.md`, where `<harness>` is what `session-slug` returned and `<model>` is your own model id (e.g. `claude-sonnet-5`). This lets multiple harnesses/models verify the same slug in parallel without overwriting each other's file. Use this exact filename everywhere below that says `arch-design-diff.md`.

## Step 1: Locate the Arch Design File

The design file path should be referenced in the user's prompt (e.g., "check against `agents/soc_agent/design.md`" or "verify against the design doc I just wrote").

- If a full path is given: read it directly.
- If a relative path is given: resolve it relative to the project's architecture docs directory.
- If no path is given: check `agent-spec/<slug>/arch-design-diff.md` (if it exists) for the previously recorded
  design file path and reuse it. If that too is absent, ask the user to provide the path to the design doc.

## Step 2: Load Existing State (Re-run Support)

Before doing any analysis, check whether `agent-spec/<slug>/arch-design-diff.md` exists.

**If it exists (re-run):**
- Read it in full — it contains previously assessed items with their status and the git ref
  they were last checked against.
- Note which items were `✅ Covered` in the previous run; these are candidates for **regression
  checks** — code changes may have broken something that previously passed.
- Plan to re-check **all** items, not just previously-failing ones. A previously covered
  requirement can become broken after a refactor.
- If the design file path recorded in `agent-spec/<slug>/arch-design-diff.md` differs from
  the one the user provided, note the discrepancy and use the user-provided path.

**If it does not exist (first run):**
- Continue to Step 3 — you will create it fresh at the end.

## Step 3: Collect the Implementation

Get the code to verify:
- Default: all changes on the current branch vs. the default branch. Detect the base in the same
  command — never assume `main`:
  ```bash
  BASE=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|origin/||')
  [ -z "$BASE" ] && BASE=$(ghx repo view --json defaultBranchRef -q .defaultBranchRef.name)
  [ -n "$BASE" ] || { echo "cannot detect the base branch — ask for it" >&2; exit 1; }
  git branch --show-current
  git diff "$BASE"...HEAD
  ```
- If the current branch is the base branch or there are only uncommitted changes, use `git diff HEAD`.
- If the user specifies particular files or a commit range, use those instead.
- Also read any `agent-spec/<slug>/plan.md` or `agent-spec/<slug>/tasks.md` — they can clarify scope and
  confirm what was intentionally deferred.

Note the current git commit hash (`git rev-parse --short HEAD`) — you will record this in
`agent-spec/<slug>/arch-design-diff.md` so future re-runs know what was last checked.

## Step 4: Extract Design Requirements

Read the design doc thoroughly. Extract every checkable commitment, organized by section:

| Section | What to extract |
|---------|----------------|
| **Motivation & Goals** | The stated "done" criteria and success metrics |
| **Functional Requirements** | Each bullet — what the system must do |
| **Non-Functional Requirements** | Performance targets, security, availability, scalability |
| **Proposal Approach** | Key components, data models, and interfaces described |
| **Implementation Steps** | Each numbered step — is it present in the code? |
| **Monitoring** | Metrics, alerts, SLOs that the code should set up or instrument |

For each extracted item, create a short identifier (e.g., `FR-1`, `NFR-perf`, `impl-step-3`,
`monitoring-alert`) that you will use consistently across re-runs to track the same requirement.

## Step 5: Analyze Alignment

For each requirement, check the code diff and assign one of these statuses:

| Status | Meaning |
|--------|---------|
| `✅ Covered` | Clear implementation present in the diff |
| `⚠️ Partial` | Implementation started but incomplete (scaffolding, TODOs, missing edge cases) |
| `❌ Missing` | No implementation found at all |
| `🔄 Deviated` | Implemented differently from the design — note whether this looks intentional |
| `⏭️ Deferred` | Explicitly out of scope for this implementation (e.g., noted in tasks.md or plan.md) |

**Re-run regression detection:** If an item was `✅ Covered` in the previous run but is now
`⚠️ Partial`, `❌ Missing`, or `🔄 Deviated`, write `⚡ REGRESSION` after its new status in the
same cell (`⚠️ Partial ⚡ REGRESSION`).

**`📤 Reported`** — the end state of an open item (`❌ Missing`, `⚠️ Partial`, `🔄 Deviated`)
once this run delivers it: Step 7 names it by ID, or Step 8 posts it on the PR. Before finishing a
run, append ` · 📤 Reported` to the status cell of every open item you delivered
(`⚠️ Partial · 📤 Reported`, `🔄 Deviated ⚡ REGRESSION · 📤 Reported`). The Stop hook gates only
on a status cell that ends without it, so a finished verification can stop with items still open
for someone else to fix, such as the PR author. `📤 Reported` never changes the alignment status
or the verdict. Re-runs re-check every item and write bare statuses, then mark again what this
run delivered.

**Scope guidance:**
- Don't flag items that are clearly infrastructure/deployment concerns and not expressible in code.
- Monitoring items are often implemented separately — flag as `❌ Missing` but note this may
  be addressed in a follow-up.
- Don't conflate code quality with design alignment — that's what `cr` is for.

## Step 6: Write / Update arch-design-diff.md

Always write or overwrite `agent-spec/<slug>/arch-design-diff.md` with the current results.
The file serves as the persistent state across re-runs, so keep it machine- and human-readable.

The file must begin with a timestamp header. On first write: set both `Created` and `Last Updated`
to now. On subsequent writes: preserve `Created`, bump `Last Updated`.

Use this exact structure:

```markdown
---
Created: YYYY-MM-DD HH:MM
Last Updated: YYYY-MM-DD HH:MM
---

# Architecture Design Alignment

**Design doc:** [full path to design file]
**Last checked:** [YYYY-MM-DD] at commit `[short-hash]`
**Overall:** [Fully aligned / Mostly aligned / Partially aligned / Not aligned]

---

## Summary
[One paragraph: overall alignment, regressions if any, and whether the implementation is
ready to call "design-complete".]

---

## Requirements Tracker

| ID | Requirement | Status | Notes |
|----|-------------|--------|-------|
| FR-1 | [requirement text] | ✅ Covered | [brief note] |
| FR-2 | [requirement text] | ❌ Missing | [what's absent] |
| NFR-perf | [requirement text] | ⚠️ Partial | [what's there, what's not] |
| impl-step-2 | [step text] | 🔄 Deviated | [what differs from design] |
| monitoring-alert | [metric/alert] | ⏭️ Deferred | [noted in tasks.md] |

---

## Regressions ⚡
[List items that were previously passing but are now failing, or "None detected." if clean]

---

## Next Steps
[Prioritized list of actions to reach full alignment, if any gaps remain. Empty if fully aligned.]

---

## Published
[One line per run that ran Step 8: date, publish choice, review URL. Omit when there is no PR.]
```

In `Notes`, cite the `file:line` that proves each status. If a status rests on inference rather
than code you read (for example, a requirement you assume a library covers), write "likely" and
name what would prove it. Never mark `✅ Covered` from inference alone. Use `⚠️ Partial` until
the code proves it.

Update the file incrementally as you work through each section — write it progressively rather
than waiting until the full analysis is complete. This way, if the session is interrupted, the
state is not lost.

## Step 7: Report to the User

After writing `agent-spec/<slug>/arch-design-diff.md`, output a concise summary in the conversation:

```
## Arch Verify — [YYYY-MM-DD] (commit: [hash])

**Design:** [full path to design file]
**Verdict:** [Fully aligned / Mostly aligned / Partially aligned / Not aligned]

| Status | Count |
|--------|-------|
| ✅ Covered | N |
| ⚠️ Partial | N |
| ❌ Missing | N |
| 🔄 Deviated | N |
| ⏭️ Deferred | N |
| ⚡ Regressions | N |

[Every open item (❌ Missing, ⚠️ Partial, 🔄 Deviated) by ID, one line each, regressions first]

Full details saved to `agent-spec/<slug>/arch-design-diff.md`.
```

If everything is covered: say so clearly — "Implementation fully addresses the design. No action needed."

## Step 8: Publish to the PR

Run this step only when the verified code is an open PR: the user named one, or
`ghx pr view --json number,author,state` finds one for the current branch with `state` `OPEN`.
Compare `ghx api user -q .login` with `ghx pr view <n> --json author -q .author.login`:

- **Current user is the PR author:** do not ask and do not publish. The Step 7 output is the
  delivery. Record `publish: none (author)` under `## Published`. An explicit `--comment` still
  publishes **Both**.
- **Current user is not the PR author:** as the last step of the run, ask with the ask tool which
  to publish: **Both** (recommended), **Inline comments**, **Summary comment**, or **None**.
  `--comment` in the arguments answers with **Both**.
- **The ask tool is unavailable, or the user declines:** publish nothing and say so.

Publish as one review (`ghx api repos/<o>/<r>/pulls/<n>/reviews`, `event: COMMENT`):

- **Inline comments:** one comment per open item whose Notes cite a `file:line` on a RIGHT-side
  line inside the current PR diff. Read the file lines before posting, and anchor on the exact
  line. State the requirement ID, the status, what the design says, what the code does, and the
  concrete change. Items with no line in the diff (most `❌ Missing` items) go in the summary.
- **Summary comment:** the review `body`: design doc path, commit checked, verdict, the status
  counts table, regressions, every open item that has no inline comment, and the Next Steps list.
  With **Summary comment** alone, post the body with no inline comments.

When `cr` also runs on this PR in this session, the skill that runs last asks once for both and
posts one combined review. The skill that runs first records its items and posts nothing. Record
the publish choice and the review URL in `arch-design-diff.md` under `## Published`.

## Re-run Behavior

When re-run after code changes:
1. Read `agent-spec/<slug>/arch-design-diff.md` to load previous state.
2. Re-check **all** items — even previously `✅ Covered` ones — because code changes can introduce regressions.
3. Highlight any items whose status changed since the last run (improved or regressed).
4. Overwrite `agent-spec/<slug>/arch-design-diff.md` with the fresh results, preserving the same requirement IDs and the original `Created` timestamp.

This means the file is always authoritative for the current state, not an append log.

## Guidelines

Read this skill's local overlay first, if one exists: `<skill-dir>/local.md`, else
`~/.config/harness-skills/<skill-name>/local.md` (the plugin-install location, which survives
updates). Also read any file it points to in the `local/` folder beside it. It holds this install's site-specific setup, and its rules override the
defaults below.

- **Stay focused on design alignment** — code quality belongs in `cr`, not here.
- **Be specific** — name the exact file, function, or class that covers (or fails to cover)
  each requirement.
- **Deferred is not missing** — if `plan.md` or `tasks.md` explicitly marks something as
  out-of-scope for this iteration, use `⏭️ Deferred`, not `❌ Missing`.
- **One requirement, one ID** — use consistent IDs across re-runs so the diff table stays
  coherent and comparable over time.
- **Write the file early** — start writing `agent-spec/<slug>/arch-design-diff.md` after Step 4 and update it
  row by row so partial results are persisted even if the session ends mid-analysis.
