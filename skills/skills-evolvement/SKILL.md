---
name: skills-evolvement
description: >
  (BN) Audit and improve all skills in the current skills repo: full context sweep, external
  research, multi-dimensional analysis, targeted fixes, review, and memory update. Use when skills feel slow,
  incomplete, or misaligned. Triggers: "improve my skills", "audit skills", "skills health
  check".
allowed-tools: Agent, Skill, Read, Write, Edit, Bash(git log *), Bash(git diff *), Bash(git rev-parse *), Bash(find *), Bash(grep *), Bash(wc *), Bash(cat *), Bash(stat *), Bash(sort *), Bash(cut *), Bash(jq *), Bash(ls *), Bash(trash *), Glob, Grep, ToolSearch, AskUserQuestion, TaskCreate, TaskUpdate, TaskList, mcp__plugin_retrospect_retrospect__memory_list, mcp__plugin_retrospect_retrospect__memory_read, mcp__plugin_retrospect_retrospect__reflect
hooks:
  Stop:
    - hooks:
        - type: command
          command: 'bash "${CLAUDE_PLUGIN_ROOT}/hooks/stop-completion-gate.sh" tasks.md "^- \[ \]" skills-evolvement'
---

# Skills Evolvement

You are performing a full audit and improvement cycle on this repo's skills. Your
primary obligation: **read every source completely before forming any opinion**. Never
skim, never rely on prior-context summaries, never stop mid-file. If a source is long,
paginate — but finish it.

## Cardinal Rule: Read Everything In Full

Before moving past any source in Phase 0:
1. Read the file completely (use `Read` with no limit, or paginate with `offset`/`limit` until done).
2. Write key findings as bullet points into `agent-spec/<slug>/plan.md` under a `## Phase 0 Findings` section.
3. Only then move to the next source.

Findings go to disk immediately. The conversation buffer is scratch; `plan.md` is memory.

**Large corpora: delegate the full read, not a skim.** The memory directories alone run past
1 MB. When a source set is too big for this context, split it across parallel background
subagents (e.g. project memories; one agent's memory dir per subagent), each told to read every
file in full and write its findings to `agent-spec/<slug>/phase0-<source>.md`. Then summarise
those files into `plan.md`. Without a subagent tool, read sequentially and write findings after
each file.

## Unattended Run

If the invocation says it is unattended/scheduled/autonomous ("no user available", "don't ask"),
never call `AskUserQuestion` and never stop on a `⏸`. Use the same row format as `code-gen`'s
Autonomous Run (`⚙️ Assumed (autonomous) — <decision> · <rationale>`), with one difference: take
the most *conservative* option rather than the recommended one. Keep the task moving, and list every
assumption in the final summary. Unattended mode never authorizes a git commit, push, stash,
reset, or any other git mutation — leave every change in the working tree.

---

## Bootstrap

Invoke the `session-slug` skill to derive a fresh slug (`YYYY-MM-DD-skills-evolvement` pattern), ensure `agent-spec/` is gitignored, and publish it to the terminal title/status line. Do not re-derive the slug or the gitignore check yourself — `session-slug` is the single source of truth, shared with code-gen, cr, and arch-verify. Once resolved, create `agent-spec/<slug>/plan.md` and `agent-spec/<slug>/tasks.md` skeletons (`tasks.md`'s header carries `Owner: skills-evolvement`), then proceed.

**Repo rules come from the audited repo.** This skill holds no repo-specific conventions. The
audited repo's `CLAUDE.md`/`AGENTS.md` (read in Phase 0.2) define them: frontmatter rules, where
shared rules live, registration steps (e.g. a plugin manifest), naming prefixes. Every Phase 2
check below that says "repo convention" means what those files say. Where they are silent, fall
back to the harness's documented defaults.

---

## Phase 0 — Full Context Sweep

Run these sub-steps sequentially. After each sub-step, write findings to `plan.md`.

### 0.1 — Memory files (all projects)

Find every memory file across all project memory directories:

```bash
find ~/.claude/projects -name "*.md" -not -name "MEMORY.md" 2>/dev/null
find ~/.claude -maxdepth 2 -name "*.md" -path "*/memory/*" 2>/dev/null
```

Read each file found, in full. Note the `type:`, `description:`, and body content.
Synthesize: what patterns of friction has the user experienced? What preferences have
they stated? What rules have they asked to enforce?

Also sweep the plugin agents' own memories — every agent in `agents/` carrying `memory: user`
accumulates learnings across sessions there:

```bash
find ~/.claude/agent-memory -name "*.md" 2>/dev/null
```

Read each in full. Recurring false positives, codebase gotchas, and patterns the agents
keep re-learning are direct evidence of what their definitions (or the skills invoking
them) should encode permanently — an agent repeatedly noting the same trap in memory is
an improvement candidate for its `agents/*.md` file.

### 0.2 — CLAUDE.md files (all levels)

```bash
find ~/.claude -maxdepth 1 -name "CLAUDE.md" 2>/dev/null
find "$(git rev-parse --show-toplevel)" -name "CLAUDE.md" 2>/dev/null
```

Read each in full. Note: workflow rules, restricted paths, required skill invocations,
git/GitHub rules, runner configurations, and any per-path overrides.

### 0.3 — All skill files

```bash
find "$(git rev-parse --show-toplevel)/skills" -name "SKILL.md"
find "$(git rev-parse --show-toplevel)/agents" -name "*.md"
```

If the repo ships a mechanical skill checker (e.g. `scripts/check-skill-frontmatter.sh`, or
whatever its `CLAUDE.md` names), run it first, so the manual read focuses on what a grep can't
catch.

For each file: read in full. Record:
- `name`, `description`, `model`, `effort`, `hooks`, `allowed-tools` (frontmatter)
- Line count (`wc -l`)
- What it does, what it depends on, what other skills it calls
- Any patterns that look slow, redundant, or missing

### 0.4 — Settings and hooks

Read these files in full (skip if missing):
- `~/.claude/settings.json`
- `~/.claude/settings.local.json`
- `{repo-root}/.claude/settings.json`
- `{repo-root}/.claude/settings.local.json`

Note: all configured hooks (event, type, command), allowed/disallowed tools, model
overrides, any custom settings. Cross-reference hooks against skill Stop hooks to find
gaps where engine-level enforcement is missing.

### 0.5 — Git history on skills

```bash
git log --oneline -50 -- skills/ agents/ .claude-plugin/
git log --stat -10 -- skills/ agents/
```

Note: what has been changing recently, what kinds of fixes keep recurring (same files
edited repeatedly = systemic issue), when the last major improvement was made.

### 0.6 — Previous agent-spec sessions

```bash
find "$(git rev-parse --show-toplevel)/agent-spec" -name "tasks.md" 2>/dev/null
```

For each `tasks.md` with status `✅ Done` only (never adopt 🔄 in-progress sessions):
read in full. Note: what kinds of tasks dominated completed sessions — this reveals
which workflows the user runs most often and where gaps exist.

### 0.7 — Retrospect memories

If retrospect MCP tools are available, load their schemas via ToolSearch
(`select:mcp__plugin_retrospect_retrospect__memory_list,mcp__plugin_retrospect_retrospect__memory_read,mcp__plugin_retrospect_retrospect__reflect`),
then:

1. Call `memory_list` to enumerate all stored memories.
2. Read each memory that touches skills, coding workflow, or agent behaviour.
3. Call `reflect` to surface cross-session patterns not visible in individual memories.

If retrospect is unavailable, skip and note it in `plan.md`.

---

## Phase 1 — External Research (parallel)

Spawn both agents in the background simultaneously — do not wait for one before starting the other.

**Agent A — CandleKeep (spawn as `candlekeep-cloud:librarian` subagent in background):**
Prompt: "Find books about Claude Code skill architecture, agent best practices, writing
effective system prompts, performance optimization for sub-agents, and hook patterns.
List all available books and tell me which are relevant. Subscribe to marketplace books
that match."
When the librarian returns, immediately spawn `candlekeep-cloud:item-reader` with the
reading list it provides.

**Agent B — Official docs (spawn as `claude-code-guide` subagent in background):**
Prompt: "Fetch the latest official Claude Code documentation on: (1) SKILL.md frontmatter
fields (model, effort, hooks, context, allowed-tools, disable-model-invocation);
(2) Stop hook exit-code behavior for driving completion loops; (3) skill body size limits
and compaction budget; (4) sub-agent model resolution order; (5) known performance
pitfalls. Return actionable findings with citations."

If the `candlekeep-cloud:*` agent types are not in this session's agent list (the plugin is
not always enabled), skip Agent A and note it in `plan.md` — do not substitute a general agent.

Wait for both. Synthesize findings into `plan.md` under `## Phase 1 Findings`.

---

## Phase 2 — Analysis and Task Planning

Cross-reference Phase 0 and Phase 1 findings. Identify improvements across four dimensions:

### Speed
- Models: any skill or agent using a heavier model than the task requires?
- Agent count: any validation/confirmation step spawning N agents where 1 batch would do?
- Hidden round-trips: sub-agents invoking skills the parent already loaded?
- Body size: any SKILL.md over 500 lines (recurring token cost per turn)?
- Dynamic injection: expensive `!`command`` blocks that could be simplified?

### Reliability
- Missing Stop hooks: which skills lack engine-level enforcement for their completion condition?
- Weak completion gates: skills that say "re-read tasks.md" without a grep check?
- Instruction vs. enforcement: rules stated in prose but with no mechanism ensuring they run?
- Missing `allowed-tools`: skills that trigger permission prompts for obvious operations?

### Completeness
- Missing frontmatter: `allowed-tools` or `hooks` absent where they'd help? Any field the repo
  convention bans (e.g. pinned `model`/`effort`) that crept back in?
- Workflow gaps: patterns the user runs often (from Phase 0.6 + memories) with no skill?
- Reference files: skills that reference `references/*.md` files that don't exist?

### Alignment
- Memory vs. skill conflicts: something the user explicitly asked for in memory that no skill enforces?
- CLAUDE.md vs. skills: rules in CLAUDE.md that should be in a skill (or vice versa)?
- Duplicate rules: same rule stated in multiple skills — should live in one place (the skill or
  file the repo convention designates for shared rules)?

For each finding, write a specific task into `agent-spec/<slug>/tasks.md`:
```
- [ ] Task N: [exact change] — [file:line] (reason: [grounded in Phase 0/1 finding])
```

If a finding involves a genuine judgment call the user should make (e.g. remove vs. keep a skill, a tradeoff with no clear best practice, anything that changes user-facing workflow) — do not decide it yourself. Add a row to `agent-spec/<slug>/plan.md`'s `## 🚧 Open Questions — Blocking` table (same format as `code-gen`'s plan template: `| Q<N> | question | Task/Phase it blocks | 🔴 Open |`), mark the task `⏸` instead of `[ ]`, and ask the user with `AskUserQuestion` before proceeding on that task (plain text only when no ask tool exists; in an **Unattended Run**, follow that section instead). Resolve by flipping the row to `🟢 Resolved — <decision>` and unblocking the task.

---

## Phase 3 — Implementation

**Baseline first (RED → GREEN).** Before editing a skill to fix a *behavioral* gap (wrong
output, skipped step, bad triggering — anything claimed about how the model acts), capture the
baseline: reproduce the failing scenario without the fix (run it, or quote the verbatim
transcript evidence from Phase 0 that shows the failure and the model's rationalization), record
it in `plan.md` under `## Baselines`, and only then write the **minimum** guidance that closes
that specific gap. An improvement with no captured baseline is not falsifiable — don't ship it
as a behavioral fix, reclassify it as a structural change. For every merged behavioral fix, add
a regression eval to that skill's `evals/evals.json` reproducing the baseline scenario, so the
fix stays testable (correction-harvesting).

Work through the task list. For each task:
1. Mark it `🔄` in `tasks.md` before starting — or `⏸` if it's blocked on an open question (see Phase 2); skip blocked tasks until answered.
2. Apply the change (direct edit or via `code-gen` skill for larger changes). Skill text is
   instructions another agent executes. Write it with one instruction per sentence, one name
   per concept, and every hedge kept. If the loaded coding standards name a prose linter, run
   it on the changed lines.
3. Mark it `[x] ✓` immediately after.

Changes that touch more than 3 files or require structural redesign: invoke the
`code-gen` skill rather than editing inline.

---

## Phase 4 — Verification

Run the `cr` skill on all changed files. Apply fixes for any issues with
confidence ≥ 80. Re-run up to 3 passes following the code-gen review loop rules.

---

## Phase 5 — Memory Update

After all tasks are complete:

1. **Memory files**: For each new pattern discovered (a non-obvious finding, a recurring
   friction source, a rule that needed changing), write or update a memory file under
   the project's memory directory. Follow the memory file format with `type:`,
   `description:`, `name:`, and body with **Why:** and **How to apply:** lines.
   Update `MEMORY.md` index.

2. **LLM wiki**: If the auto-update manuscript is active in context, write an entry
   for the most significant finding from this session — the one insight a future
   instance of this skill should know about this repo's skill architecture.

3. **Post a brief summary** to the user: what was found, what was changed, what patterns
   to watch for next time.

4. **Sync status lines**: set `agent-spec/<slug>/tasks.md`'s `## Status` to `✅ Done` and
   `agent-spec/<slug>/plan.md`'s `> Status:` line to `✅ Done` in the same step — do not
   leave one updated and the other stale.

---

## Native Task Integration

Mirror `tasks.md` into Claude's native task system for real-time progress visibility, the same way `code-gen` does. Before using any Task tool, load its schema via `ToolSearch` with `select:TaskCreate,TaskUpdate,TaskList`.

| Event | Action |
|---|---|
| `tasks.md` populated with real tasks (end of Phase 2) | Create one native task per item via `TaskCreate` |
| Task marked `🔄` (starting) | Update the corresponding native task to in-progress via `TaskUpdate` |
| Task marked `[x] ✓` (done) | Mark the corresponding native task completed via `TaskUpdate` |
| Task marked `⏸` (blocked) | Leave the native task `in_progress` — native tasks have no blocked state; the block is tracked in `plan.md`'s Open Questions table instead |

Rules:
- Only create native tasks after the real task list is known — never from placeholder Phase 0/1 bootstrap text.
- Name each native task `[<slug>] Task N: <description>` to namespace them from other sessions.
- `tasks.md` remains the authoritative source of truth — native tasks are a display layer only.
- If a Task tool call is denied or unavailable, skip silently and continue with file-only tracking.

---

## Completion Gate

Before stopping, physically re-read `agent-spec/<slug>/tasks.md` and run:

```bash
grep -E '^\s*- \[ \]|^\s*- 🔄' agent-spec/<slug>/tasks.md
```

Read this skill's local overlay first, if one exists: `<skill-dir>/local.md`, else
`~/.config/harness-skills/<skill-name>/local.md` (the plugin-install location, which survives
updates). Also read any file it points to in the `local/` folder beside it. It holds this install's site-specific setup, and its rules override the
defaults below.

Any output means you are not done. Every task must be `[x] ✓` before declaring
this session complete. `⏸` (blocked) tasks are excluded from this grep by design —
it's legitimate to stop once you've logged the question in plan.md and asked, but
report any remaining `⏸` items to the user; the session isn't done while they're open.
