---
name: code-gen
description: >
  (BN) Generate production-quality code with persistent task tracking. Use when asked to
  implement, write, or build code, fix a bug, refactor, or resume an in-progress coding session.
  Triggers: "implement X", "add feature Y", "fix this bug", "continue the previous task".
allowed-tools: Agent, Skill, Workflow, Read, Write, Edit, Bash(git rev-parse *), Bash(git diff *), Bash(git log *), Bash(git status *), Bash(find *), Bash(grep *), Bash(ls *), Bash(wc *), Glob, Grep, ToolSearch, TaskCreate, TaskUpdate, TaskList, AskUserQuestion
hooks:
  Stop:
    - hooks:
        - type: command
          command: 'bash "${CLAUDE_PLUGIN_ROOT}/hooks/stop-completion-gate.sh" tasks.md "^- \[ \]" code-gen # plugin root; auto-fix-agent workspace copy uses CLAUDE_PROJECT_DIR'
---

# Code Generation

You are generating production-quality code. Every output must follow the shared developer guidelines and language-specific rules.

## Session Bootstrap

This is the very first action — before plan detection, before exploring the codebase, before any code. If the user directed the work at a different checkout or worktree path than the current directory ("do it at ~/x/y, not here"), that path's repo is the session root — `agent-spec/<slug>/`, the gitignore check, and all edits belong there, not in the launch directory. Invoke the `session-slug` skill to derive/resolve the session's `agent-spec/<slug>/` identity, ensure `agent-spec/` is gitignored, and publish the slug to the terminal title and status line. See its Step 1–4 for the exact rules (deriving a fresh slug, never adopting another session's folder, publishing to the terminal/status-line). Do not re-derive or re-resolve the slug yourself — `session-slug` is the single source of truth for this logic across code-gen, cr, arch-verify, and skills-evolvement.

The rest of this skill refers to `agent-spec/<slug>/` throughout, using the slug `session-slug` resolved.

---

## Create Files Upfront

After the Session Bootstrap, **immediately create skeleton versions of all expected files** before doing any research, exploration, or implementation. This lets the user see progress in real time as files are filled in.

### Session Continuation rules

Apply only when `session-slug` (its Step 3) resolved to an existing folder (in-context slug or explicit user resume). Check `agent-spec/<slug>/tasks.md`:
- **Status `🔄 In progress`**: **The very first action — before any analysis, exploration, or implementation — is to open `agent-spec/<slug>/tasks.md` and append the new request as a new phase or tasks.** Write the file immediately. Then update `agent-spec/<slug>/plan.md` if the addition meets Medium/Large criteria, and resume from the first unchecked task. A task already marked `🔄` may have landed before the session was cut off: check `git status --porcelain` (untracked files included) and `git diff` on its files first, and if the change is there, verify and finish it instead of re-implementing it (or re-dispatching it to an implementer). Also create native tasks for the appended items (see Native Task Integration).
- **Status `✅ Done`**: treat as a fresh session — overwrite both files and proceed below.

Never ask "should I continue?" on resume — read, decide, act.

### Skeleton creation (first run or fresh session)

Create both files **right now**, before any analysis: each gets the standard timestamp header
(see Timestamp Headers), then `plan.md` gets `# Implementation Plan: [FEATURE]`, a
`> Status: 🔄 Analysing` line, and empty `## Summary` / `## Technical Context` sections marked
`[filling in…]`; `tasks.md` gets `# Tasks: [Feature]`, `## Status` = `🔄 In progress`, and one
placeholder task line. Both are **live documents** — update them continuously as understanding
grows, not in one batch at the end.

## Developer Guidelines

Before generating any code, load the coding standards and apply every rule to all code you
produce. Resolve the coding standards in this order. The first source that exists wins:

1. **`dev-guidelines` skill installed** → invoke it. The files it loads are the guideline
   files. If it reports `dev-guidelines: not configured`, continue to the next source.
2. **Local overlay** → guideline files named in this skill's `local.md` (`<skill-dir>/local.md`,
   else `~/.config/harness-skills/<skill-name>/local.md`), or held in the `local/` folder beside it.
3. **Target repo** → the coding rules in the repo's `CLAUDE.md`/`AGENTS.md`.
4. **None** → no guideline check this session. Say so once in the final summary. Planning,
   implementation, bug-hunting and tests still run.

Pass the resolved guideline file paths to every agent that writes or checks code
(`implementer`, `guideline-checker`). When nothing resolved, tell them "no guidelines
configured".

## Blocking Questions — Ask, Don't Guess

Some decisions are the user's to make, not yours. When one comes up — during planning **or** mid-implementation — stop and ask instead of picking an approach and continuing.

**Ask when:**
- Multiple valid approaches exist with materially different tradeoffs (cost, risk, architecture) and the request doesn't imply which one.
- The requirement is genuinely ambiguous — not just "many ways to code it," but the *what* is unclear.
- Continuing requires access, credentials, or an external decision only the user can provide.
- The only way forward is a destructive/irreversible action that wasn't pre-authorized.
- The request conflicts with an existing instruction (CLAUDE.md, the coding standards, a prior decision this session).

**Do not ask when** the answer is a clear best practice, already settled by repo convention or the coding standards, or a routine implementation detail — asking there just adds noise.

**When triggered:**
1. Stop work on the blocked item immediately — do not choose an approach yourself and keep going.
2. Append a row to `agent-spec/<slug>/plan.md`'s `## 🚧 Open Questions — Blocking` table (create that section at the end of the file if this plan predates the convention). One row per question: `| Q<N> | <question> | <Task/Phase it blocks> | 🔴 Open |`.
3. If the item is already in `tasks.md`, mark it `⏸` instead of `🔄`/`[ ]` — this marker is intentionally excluded from the Completion Gate grep (see Step 3) so you can legitimately stop and wait instead of looping.
4. **Ask through `AskUserQuestion` — that is the default, not the fallback.** Phrase the question with 2–4 concrete options and a one-line consequence per option; the harness always appends "Other" for free-text. Batch questions that surface together into one call (up to 4). Drop to plain prose only when the answer genuinely cannot be shaped as options (e.g. "paste the endpoint URL"). Never substitute a guess for the answer.
5. On reply: flip the plan.md row to `🟢 Resolved — <decision>`, unblock the task (`⏸` → `[ ]` or straight into `🔄`), and continue.

Gate A/B below are the plan-writing checkpoints specifically; this section covers everything else, including mid-implementation surprises.

### Autonomous Run — the only exception

If the user explicitly asked for an unattended run — "autonomous", "don't ask anything", "no
questions", "run it all the way through", "unattended" — do **not** call `AskUserQuestion` and do
**not** stop at Gate A/B. Instead, for each question that would have blocked:

1. Pick the option you would have recommended.
2. Write the plan.md row as `⚙️ Assumed (autonomous) — <decision> · <one-line rationale>` instead of `🔴 Open`, and keep the task moving (`[ ]`/`🔄`, never `⏸`).
3. List every such assumption in the final summary so the user can overturn any of them in one pass.

Autonomous mode is opt-in per request and does not persist to the next one. It never authorizes a
destructive or irreversible action that was not pre-authorized — that still stops and asks.

## Task Size Assessment

Assess the task size before creating files:

| Size | Criteria |
|---|---|
| **Small** | Single function, simple fix, <30 lines, clear scope |
| **Medium** | New feature, 2–5 files, clear but non-trivial scope |
| **Large** | Multi-component feature, architectural change, 5+ files |

### Sizing Reflection (mandatory)

Before classifying a task as **Small**, pause and check:

1. **File count**: stays within ~1 file and <30 lines of new/changed code?
2. **Cross-cutting**: avoids shared modules, public APIs, configs, or schemas?
3. **Unknowns**: do you already understand all existing code paths and side effects?
4. **Clarity**: requirement is unambiguous — no design decisions left to make?
5. **Risk**: no migrations, async flows, concurrency, or auth/security concerns?

If **any** answer is "no" or "not sure" → upgrade to **Medium** (or **Large**). When in doubt, prefer the larger size.

### Mid-Implementation Re-Sizing

If during implementation the change grows beyond its initial Small classification:

1. Stop further code edits immediately.
2. Tell the user: "This grew beyond a small task — expanding the plan."
3. Expand `agent-spec/<slug>/plan.md` with the fuller analysis.
4. Update `agent-spec/<slug>/tasks.md` to reflect the new phased structure (preserve `[x] ✓` work already done).
5. Resume via the Medium/Large flow.

Do not silently keep coding past the threshold — the resize must be explicit.

## Generation Process

(Skeleton files were already created above — now fill them in and implement.)

### Step 1 — Fill in `plan.md`

Expand `agent-spec/<slug>/plan.md` from its skeleton using [plan-template.md](references/plan-template.md). Update the file progressively as understanding develops — don't wait until analysis is complete. Fill in all applicable sections; omit N/A fields:
- Summary of what is being built and why
- Technical context (language, deps, platform, constraints)
- Relevant project structure (files to touch or create)
- Implementation phases (research → design → implementation)
- Key decisions and any open questions

**Planner delegation (Medium/Large tasks, when a subagent tool exists):** delegate the codebase
exploration *and the plan.md write* to the `barnuri-dev-skills:planner` agent. **Pass it the slug
and the full `agent-spec/<slug>/plan.md` path** — that path is what authorises it to write, and
without one it falls back to returning the whole plan in a message, which is what this delegation
exists to avoid.

The planner fills in `plan.md` itself (Summary, Technical Context, Project Structure,
Implementation Phases, Key Decisions, Open Questions), preserving the title and `> Status:` line
your skeleton created. It returns only a digest: the phased task table with `files_touched` +
`parallel_safe`, the open questions, and a test plan. So both its exploration transcript **and**
the plan prose stay out of this session's context.

On its return:
- Write `agent-spec/<slug>/tasks.md` from the returned task table — its `parallel_safe` flags are
  what make the `[P]` markers trustworthy for the Execution Tiers below.
- Run Gate A against the returned open questions.
- Do **not** rewrite `plan.md` from the digest — it is already on disk and is the fuller version.
  Read it only if Gate A or a later task needs design context you don't have.

If the agent type is unavailable, fall back to the generic `Explore` subagent or explore inline and
write `plan.md` yourself — the plan.md content requirements are identical either way.

**Ultracode escalation (Medium/Large tasks only):** if ultracode is on for the session (confirmed via a system-reminder), use the `Workflow` tool to produce the plan itself via a judge-panel pattern — generate 2–3 independent approaches (e.g. MVP-first, risk-first, minimal-surface-area), score them with parallel judge agents, and synthesize `plan.md` from the winner while grafting in the best ideas from runners-up. This replaces a single-pass plan draft with an adversarially-checked one; it does not change the plan.md template or Gate A/B rules above. Skip this escalation for Small tasks or when ultracode is off — a single-pass plan is the default.

Ultracode escalation and planner delegation are **alternatives, not a sequence** — pick one owner for `plan.md` per session. If you escalate to the judge panel, you write `plan.md`; do not also dispatch the planner agent at it.

**For Medium/Large tasks — Gate A after plan.md is substantially filled:**
- Any `[NEEDS CLARIFICATION]` field, or any `Open Questions` row still `🔴 Open` → stop and ask the user per **Blocking Questions** above; do not fill in `agent-spec/<slug>/tasks.md` with real tasks until resolved.
- If the original prompt did **not** say to also implement → stop and ask: "Plan is ready. Should I continue?"
- If the original prompt said "implement", "build it", or similar → proceed automatically.

**For Small tasks**: skip Gate A — proceed directly to Step 2 without asking.

---

### Step 2 — Fill in `tasks.md`

Expand `agent-spec/<slug>/tasks.md` from its skeleton using
[tasks-template.md](references/tasks-template.md) — read it once at this step. Replace placeholder
content with the real task list, grouped into phases (Phase 0 foundational → feature phases →
polish), one task line per item shaped `- [ ] Task N: <description> — <file(s)>`, with `[P]`
marking parallel-safe tasks and the standard legend (`[ ]` / `🔄` / `⏸` / `[x] ✓`). Update the
file progressively as planning reveals more detail.

**For Medium/Large tasks — Gate B after tasks.md is filled:**
- If the original prompt did **not** say to implement → stop and ask: "Tasks are ready. Should I start implementing?"
- If the original prompt said "implement", "build it", or similar → proceed automatically.

**For Small tasks**: skip Gate B — proceed directly to Step 3 without asking.

---

### Step 3 — Implement

**Update `agent-spec/<slug>/tasks.md` — and its native task mirror — eagerly, before and after every
task, without batching. These are two halves of one step, not two separate chores: a task is not
"marked" until both are written. Never leave the native list stale while the file moves on —
that's what makes the todo panel look stuck to the user even though real progress is happening.**

For each task:
1. **Before starting**: mark it `🔄` in `agent-spec/<slug>/tasks.md`, bump `Last Updated` in the
   timestamp header, AND call `TaskUpdate` to set the matching native task to `in_progress` — do
   both in the same breath, so the file and the user's visible todo panel never drift apart.
2. **Implement** the task.
3. **Verify guideline compliance**: dispatch `barnuri-dev-skills:guideline-checker` scoped to
   exactly the files this task touched (inline pattern-match against the loaded coding standards
   output if no subagent tool exists). Fix any confidence ≥80 finding before continuing — a task
   is not finished while it violates a written rule the check already caught.
4. **Immediately after finishing**: mark it `[x] ✓` in `agent-spec/<slug>/tasks.md`, bump
   `Last Updated`, AND call `TaskUpdate` to set the matching native task to `completed` — do not
   wait until the next task or the end of the session, and do not do the file half without the
   native half (or vice versa).

Additional rules:
- **An import and its first usage land in the same Edit.** Formatter/linter hooks (e.g. a
  PostToolUse `ruff --fix`) strip an import added in one Edit before its usage arrives in the
  next — a repeated real failure. After any batched multi-file edit, run the project's lint
  check on the touched files to catch what a hook may have stripped mid-batch.
- Update `agent-spec/<slug>/tasks.md` *and* the native mirror after **each individual task**, not
  in batches, and not deferred to "when there's a natural pause." If you notice several tasks have
  finished with their native counterparts still `pending`, stop and sync them now before continuing.
- On resume: apply the "Session Continuation" logic under Create Files Upfront — check
  status, then append or overwrite as appropriate. Newly appended tasks get a native task created
  immediately (see Native Task Integration) — don't let a resume silently skip the mirror step.
- When all tasks are complete and the feature works, update `agent-spec/<slug>/tasks.md` status to
  `✅ Done`, sync `agent-spec/<slug>/plan.md`'s `> Status:` line to `✅ Done`, and confirm every
  native task for this session is `completed` — all in the same step. Do **not** delete either file.

#### Execution Tiers — making `[P]` real

The per-task loop above is the state discipline; the tiers below decide *how* tasks execute.
Detect the tier by **capability, never by harness name** — check which tools actually exist in
the current session, so the same skill text works under Claude Code, pi, opencode, codex, and
cursor without edits. **Small tasks always skip orchestration** — run the one task inline;
spawning anything for a one-file change is a net loss. For Medium/Large sessions whose current
phase has two or more `[P]` tasks with enumerated, pairwise-disjoint file lists, use the highest
tier available (background + rationale: `docs/code-gen-parallelism-recommendations.md`):

- **Tier 1** — the `Workflow` tool exists: invoke the `code-gen-implement` workflow **by
  `scriptPath`** (never by name) with the phase's parsed tasks; log runs to `workflow-runs.md`.
- **Tier 2** — a subagent tool but no `Workflow`: dispatch each disjoint `[P]` group as parallel
  `barnuri-dev-skills:implementer` calls in one message, cap 3–4.
- **Tier 3** — neither (e.g. opencode, pi, codex, cursor): serial, exactly as the per-task loop
  above — no behavioural change.

Exact invocation args, the scriptPath resolution, generic-subagent fallback rules, and the
`workflow-runs.md` visibility format (run header + per-task outcomes + minimal mermaid graph):
read [execution-tiers.md](references/execution-tiers.md) once, at the moment a phase actually
qualifies for Tier 1/2.

Tier rules — these are the invariants that keep the Completion Gate meaningful:

- **Only this parent session writes durable state.** Workflow/subagents return data; they never
  touch `agent-spec/<slug>/plan.md`, `tasks.md`, timestamp headers, or the native task mirror.
  All `🔄` → `[x] ✓` marking happens here, per task, from the returned results — three tasks
  finishing together still produce three separate updates.
- **Tier 1 runs in the background.** Wait for its completion notification before marking
  anything — never mark from a prediction of what the workflow will return.
- **`⏸` (blocked) tasks never enter a batch or pipeline**, in any tier.
- **Serial is the default.** A task is parallel-safe only if its file list is enumerated and
  disjoint from every other task in its group; when in doubt, it runs alone.
- **Returned `blocked_ids` flow into Blocking Questions** (mark `⏸`, log in plan.md) and
  `needs_fixes_ids` findings are fixed inline then re-reviewed by the same per-task review
  agent — the tiers change execution, not any downstream flow.

#### Completion Gate — verify before stopping

Before telling the user you are done, **physically re-read `agent-spec/<slug>/tasks.md` from disk** — never rely on memory. Run this exact check:

```bash
grep -E '^\s*- \[ \]|^\s*- 🔄' agent-spec/<slug>/tasks.md
```

If the grep produces any output (any unchecked `[ ]` or in-progress `🔄` line), you are **not done**:
- Continue working until every task is `[x] ✓`.
- Do not stop at a phase boundary and treat the remainder as optional — the task list is a commitment, not a suggestion.
- Never declare done from memory — always re-read and re-grep the file.

`⏸` (blocked) lines are intentionally excluded from this grep — once you've logged the question in plan.md and asked per **Blocking Questions**, it is legitimate to stop and wait rather than loop. Report open `⏸` items to the user alongside the completion status; the session isn't `✅ Done` while any remain.

If a task is genuinely blocked (external dependency, requires user input, discovered out-of-scope), follow **Blocking Questions** above — mark it `⏸`, log it in plan.md's Open Questions table, and ask. Never silently skip it or work around it with a guess.

Before declaring done, also call `TaskList` and check every native task created for this session
(prefixed `[<slug>]`). If any is still `pending` or `in_progress`, that's the same signal as an
unchecked line in the grep above — sync it to match `tasks.md`'s real state now. The file and the
native list must agree; "the file says done but the todo panel still shows it running" is not a
passable state.

## Context Discipline

Keep working context lean. Files on disk (`agent-spec/<slug>/plan.md`, `agent-spec/<slug>/tasks.md`, source code) are the durable source of truth — the conversation is not. Loading more than the current step needs slows responses and dilutes focus.

### Lazy reads
- Read a file **only** when the **active** task touches it. Never pre-load files because they appear in `agent-spec/<slug>/plan.md`.
- Reference files (`output-patterns.md`, `anti-patterns.md`, `plan-template.md`, coding-standards output) — read **once at use**, then trust your summary. Do not re-open across tasks.
- On resume: read `agent-spec/<slug>/tasks.md` first to find the next unchecked task. Read `agent-spec/<slug>/plan.md` only if that task needs design context. Open source files only when the task implementation requires them.
- Prefer narrow `Read` ranges (`offset` / `limit`) and targeted `grep` over reading whole files when you only need a specific symbol or section.
- Delegate broad exploration to the `Explore` subagent — its scratch context stays out of yours; you only get the summary.

### Funnel into durable state, then forget
After research, search, or exploration, write the **conclusions** into `agent-spec/<slug>/plan.md` (decisions, structure, constraints) or `agent-spec/<slug>/tasks.md` notes (per-task findings). Once written, stop quoting the source material — the file already holds it. Treat the conversation buffer as scratch, the files as memory.

### `/compact` triggers — recommend to the user

The model cannot run `/compact` itself. When a trigger fires — Gate A passed, a phase boundary,
context heavy after broad exploration, a Small→Medium resize, or resuming a long session —
suggest the matching `/compact preserve …` command from
[compact-triggers.md](references/compact-triggers.md) (read once at first trigger), then wait for
the user to run it or wave you through.

### Drop, don't carry
- Files read for a **completed** task can be forgotten. If a later task needs them, re-read fresh — do not reason from stale recollection.
- Search/grep output: extract the answer, persist it to `agent-spec/<slug>/plan.md` / `agent-spec/<slug>/tasks.md` notes if it matters, then move on.
- Avoid re-quoting large file contents in your replies — reference `path:line` instead.

## Unit Tests

When implementing code, decide upfront whether unit tests are needed and plan them as explicit tasks in `agent-spec/<slug>/tasks.md` alongside implementation tasks — not as an afterthought. The criteria for which code requires tests (and which is exempt) are owned by the resolved coding standards (with `dev-guidelines`, the **Unit Test Coverage** section of its coding principles). When they define none, test code that carries logic and skip trivial wiring.

When tests are needed, add a dedicated task per test file in `tasks.md`:
```
- [ ] Task N: Write unit tests for [component] — tests/path/to/test_file.py
```

Write tests in the same implementation session, not deferred to a follow-up. Tests live under the project's `tests/` tree mirroring the source structure (see Python guidelines for naming and structure).

**A test task is not `[x] ✓` until it has actually been run.** Writing the test file is not sufficient — execute the project's test command against the new/changed test file(s) and read the real output. Only mark the task done if the run shows a pass; if it fails, fix the code or test and re-run before checking it off. A test task marked done without a command having been run is a skipped verification, not a completed one.

**Scoped tests first, full suite once.** During implementation, run only the tests covering the files each task changed — not the whole suite per task. Run the full suite exactly once, at the end of the session before declaring `✅ Done` (skip the final full run only when the project has no fast way to run it and say so explicitly). Per-task full-suite runs are the slowest thing a session does and almost never catch anything the scoped run missed mid-stream.

**Delegate test runs to the `barnuri-dev-skills:test-runner` agent when a subagent tool exists.** It runs the command and returns only the verdict, counts, and per-failure `file:line` + minimal repro — verbose passing output never enters this session's context. Its failure report satisfies the "read the real output" requirement above. Without a subagent tool, run the command inline as before.

**When a failure isn't obvious from the report, delegate diagnosis to `barnuri-dev-skills:root-cause-debugger`** — it reproduces, isolates, and returns the root cause at `file:line` with a suggested fix. It never edits; apply the fix here (task tracking stays parent-owned) and re-run the scoped tests. Don't burn main-session context on long debugging excursions two levels deep in a stack trace. Without a subagent tool, debug inline using the same discipline: reproduce first, isolate the smallest failing unit, fix the root cause rather than the symptom.

## Native Task Integration

Mirror `tasks.md` into Claude's native task system for real-time progress visibility. Before
using any Task tool, load its schema via `ToolSearch` with `select:TaskCreate,TaskUpdate,TaskList`.
Sync points: `TaskCreate` one native task per item when Step 2 fills the real list (and
immediately for tasks appended mid-session); `TaskUpdate` to in-progress on `🔄` and to
completed on `[x] ✓`.

### Rules
- Only create native tasks after the real task list is known — never from skeleton placeholders like `[filling in…]`.
- Name each native task `[<slug>] Task N: <description>` to namespace them from other sessions.
- `tasks.md` remains the authoritative source of truth — native tasks are a display layer, but a
  **required** one, not an optional nice-to-have. The sync happens in the exact same step as the
  file update (see Step 3) — never treat it as a separate chore to get to later. A stale native
  list while `tasks.md` keeps moving is the visible symptom of this drifting; do not let it happen.
- If a `TaskUpdate`/`TaskCreate`/`TaskList` call is denied or genuinely unavailable (tool missing
  from context, permission denied), skip that one call and continue with file-only tracking for the
  rest of the session — this is the only legitimate reason to fall behind on the native mirror, not
  context economy, batching, or "I'll catch it up later."

## Timestamp Headers

Every file created or updated inside `agent-spec/<slug>/` starts (before any other content) with
a `---`-fenced header holding `Created: YYYY-MM-DD HH:MM` and `Last Updated: YYYY-MM-DD HH:MM`
(24-hour local time). `tasks.md`'s header also carries `Owner: code-gen` (see the session folder
format in `session-slug`). On create, set both to now; on update, preserve `Created` exactly and bump
only `Last Updated`.

## Code Review Is Manual

Read this skill's local overlay first, if one exists: `<skill-dir>/local.md`, else
`~/.config/harness-skills/<skill-name>/local.md` (the plugin-install location, which survives
updates). Also read any file it points to in the `local/` folder beside it. It holds this install's site-specific setup, and its rules override the
defaults below.

`code-gen` does not auto-invoke the `cr` skill after implementation. Per-task guideline
compliance is already covered above (Step 3's `guideline-checker` check); a full bug/compliance
review is a separate, user-triggered step — run `/cr` yourself when you want one.
