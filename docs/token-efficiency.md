# Reducing context and token use

Measured on Claude Code over about 12,000 turns from long interactive sessions. Numbers come
from one machine, so treat them as ranges and re-measure on yours. Levers run from highest to
lowest impact. The official Claude Code docs (`env-vars`, `mcp`, `settings-reference`, `output-styles`
pages) confirm the env var and setting names here, except `CLAUDE_CODE_EFFORT_LEVEL`,
`alwaysThinkingEnabled`, `bashOutputMaxChars`, and `modelSettings`. Only summarized doc text
supports those four, so verify them on your version.

## For agents: rules to apply now

Read this section first. Each rule is an action you can take without further research.

1. Answer first. Do not restate the request. Do not close with a recap.
2. Read file ranges (`offset`/`limit`) or `grep` first. Read a whole file only when you need all of it.
3. Pipe noisy command output through `tail` or `grep`. Report 1 to 3 bullets, not raw output.
4. Send test runs and wide searches to a subagent that returns only failures or conclusions.
5. Send independent tool calls in one turn.
6. Do only what was asked. Add no extra features, docs, or comments.
7. Do not re-read a file you just edited. The edit tool reports failures.
8. At a task boundary, suggest `/compact` or `/clear`. Do not carry finished work forward.
9. When a session passes about 200k tokens of context, say so and offer a handoff.
10. Keep every hedge. Never present a suspicion as a verified fact.

To diagnose a large startup context, run in order:

1. `claude -p "Reply with exactly: ok" --output-format json` from an empty directory. Expect
   about 43k input tokens.
2. Repeat from the project directory. The difference is the project's always-on context.
3. Repeat with `--strict-mcp-config`. The difference is the MCP cost.
4. If MCP cost exceeds 5k tokens, check `ENABLE_TOOL_SEARCH` first, then `ANTHROPIC_BASE_URL`.

Paste this block into a project `CLAUDE.md` or `AGENTS.md` to apply rules 1 to 7 and 10:

```markdown
## Token efficiency
- Lead with the answer. No restating the request. No closing recap.
- Read ranges or grep first. Whole-file reads only when needed.
- Trim noisy command output to 1-3 bullets.
- Delegate test runs and wide searches to a subagent that returns only failures.
- Do only what was asked. No extra features, docs, or comments.
- Do not re-read files you just edited.
- Keep every hedge. State only verified facts as facts.
```

## Recommended settings

In `~/.claude/settings.json`:

```json
{
  "outputStyle": "Concise",
  "env": {
    "ENABLE_TOOL_SEARCH": "true"
  }
}
```

1. `ENABLE_TOOL_SEARCH=true` keeps MCP tool schemas deferred (section 3).
2. `outputStyle: "Concise"` shortens every answer (section 4).
3. Optional: `CLAUDE_CODE_DISABLE_1M_CONTEXT=1` to compact at about 200k (section 1).

## 1. Per-turn context size is the main cost

Every turn attends over the whole context before it emits a token. In the sample, 82% of turns
ran above 200k tokens and 23% above 600k. Plugin, skill, and MCP counts were not the cause.

- **Compact earlier.** A 1M-token window pushes auto-compaction from about 200k to about 930k.
  Several 700k+ sessions never compacted. Set `CLAUDE_CODE_DISABLE_1M_CONTEXT=1` to hold
  1M-default models to a 200K window. It applies to every model, including after `/model`.
  Lowering `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` (integer 1 to 100) also compacts earlier. It cannot
  raise the threshold. Keeping a large window is a valid choice. The trade is longer context
  against slower turns.
- **Split long sessions.** The longest sessions had 1,400 to 2,000 turns. Hand off to a fresh
  session at a task boundary. The `handoff` skill writes the resume document.
- **Run `/compact` at task boundaries**, not when the window is full. `/compact <instructions>`
  steers what the summary keeps. `/context` shows usage by source.

## 2. Startup context

A new session starts at roughly 43k tokens with no project files. That is the harness system
prompt and core tool schemas, which you cannot change. Everything above it is yours.

| Source | Typical cost | Lever |
|---|---|---|
| Project `CLAUDE.md` / `AGENTS.md` | 3k to 11k tokens each, plus nested ones | Split into on-demand references (`context-declutter`) |
| Global `CLAUDE.md` and `rules/*.md` | 3k+ tokens, loaded in every project | Same, with a separate confirmation |
| Skill and agent descriptions | about 3.5k for 30 skills and 7 agents | Short descriptions. Low priority |
| MCP tool names and instructions | about 4k for 300 tools | Keep tool search deferred (section 3) |
| `MEMORY.md` index | under 1k | One line per entry |

The worst project in the sample added 72k tokens over the empty-directory floor through a large
root `CLAUDE.md`, a nested `CLAUDE.md` tree, and 50 project skills.

Only `CLAUDE.md`, `AGENTS.md`, and `rules/*.md` always load in full. A `SKILL.md` loads only its
description until the agent uses the skill, and files under `references/` load only when the body
points at them. Never move content you want on-demand into `rules/`.

## 3. MCP tool schemas and tool search

Set `ENABLE_TOOL_SEARCH=true` explicitly. The value matters:

| Value | Behavior |
|---|---|
| unset | MCP tools deferred, loaded on demand |
| `true` | Always deferred. Also deferred behind a non-first-party `ANTHROPIC_BASE_URL`, if the proxy forwards `tool_reference` blocks |
| `auto` | Loads tools upfront while their definitions total under 10% of the context window |
| `auto:N` | Same, with a custom threshold of N percent (0 to 100) |
| `false` | Loads every tool upfront |

Measured impact, same empty directory, several MCP servers, 1M window: `auto` gave 98,326 startup
tokens and `true` gave 34,949. On a 1M window 10% is about 100k, so `auto` loads everything. "Tool search is on" does not mean "schemas are deferred".
Read the value.

- With a non-first-party `ANTHROPIC_BASE_URL` and the variable unset, tools load upfront. If
  startup context is far above 43k plus your project files, inspect that variable first.
- Measure with `claude -p "Reply with exactly: ok" --output-format json` and read the input
  token count. Run it once from an empty directory with `--strict-mcp-config` and once without.
  The difference is the MCP cost. Repeat after each Claude Code upgrade, because deferral
  regressed once between releases in this sample.
- `alwaysLoad: true` on a server forces its tools upfront regardless of tool search. Leave it
  unset. `MAX_MCP_OUTPUT_TOKENS` (default 25000) caps one tool response.
- Remove servers that need authentication and that you never use. Each adds two dead tool names.

## 4. Output tokens and thinking

| Lever | Setting | Effect |
|---|---|---|
| Output style | `"outputStyle": "Concise"` or `/output-style` | Shortens every answer. See below |
| Effort | `effortLevel` setting, `CLAUDE_CODE_EFFORT_LEVEL`, or `/effort` | Lower effort means fewer thinking and output tokens |
| Thinking budget | `MAX_THINKING_TOKENS` | Fixed budget. `0` disables thinking on models that allow it. Ignored on adaptive-reasoning models unless `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING=1` |
| Thinking off | `alwaysThinkingEnabled: false` | No effect on models that always think |
| Output cap | `CLAUDE_CODE_MAX_OUTPUT_TOKENS` | Per-request cap. Higher values shrink the room before auto-compaction |
| Shell output | `BASH_MAX_OUTPUT_LENGTH` (default 30000 chars) or `bashOutputMaxChars` | Caps Bash output read back. The setting wins |
| Subagent model | `CLAUDE_CODE_SUBAGENT_MODEL` | Cost lever: run subagents on a cheaper model |

`CLAUDE_EFFORT` is not a setting. Claude Code sets it read-only in Bash and hook subprocesses to
reflect the current level. Pinning it in an `env` block does nothing, and the level can drift
from what you pinned. Use `effortLevel` instead.

Thinking tokens generate sequentially, so they cost wall-clock time as well as tokens.

Delegate noisy work (test runs, large searches) to a subagent that returns only failures or
conclusions. The parent keeps the conclusion, not the output. Read file ranges, not whole files.
Ask for `file:line` references, not pasted code.

### Output style

Use the built-in `Concise` style (v2.1.237+). Select it with `/output-style` or set
`"outputStyle": "Concise"` in settings. It reduces output tokens. `Explanatory` and `Learning`
increase them. Any style adds instruction tokens, which prompt caching partly offsets.

If `Concise` is not terse enough, add a custom style: a markdown file in `output-styles/` with
frontmatter. This one cut answers to a finding, a fix, and a next step:

```markdown
---
name: Caveman
description: Few words, do trick
keep-coding-instructions: true
---

Respond with the minimum text needed.

Rules:
- Prefer action over explanation
- Use short sentences
- No motivational filler
- No step-by-step reasoning unless asked
- No long summaries
- When possible, return only: 1. finding 2. fix 3. next step
- For code tasks, keep prose under 5 lines unless I ask for detail
- If a command output is noisy, summarize it in 1-3 bullets
- If confidence is high, state the answer directly
- Do not restate my request
```

`keep-coding-instructions: true` keeps the coding behavior while the style trims the prose.
Style names are case-sensitive in the settings file.

### Write instructions in Simplified Technical English

Text another agent reads (skill steps, agent prompts, tool descriptions, error messages, handoff
documents) costs tokens on every read and causes rework when misread. Apply the structural rules
of ASD-STE100 Simplified Technical English:

1. One instruction per sentence, 20 words or fewer.
2. Active voice. Name the actor.
3. One name per thing. Do not rotate "check", "verify", and "confirm" for one action.
4. Plain verbs: "start", not "spin up". "Analyze", not "perform an analysis".
5. No marketing adjectives. Keep the number that earns the claim.
6. Keep every hedge. "May have failed" never becomes "failed". Never add a cause the source did
   not state.

The `dev-guidelines` placeholder skill can load a full writing guide from your local overlay.

## 5. More ways to save usage

Habits and instructions that cut tokens without changing settings:

1. **Clear between unrelated tasks.** `/clear` starts empty. A new task in an old session pays
   for the old context on every turn.
2. **Keep the prompt prefix stable.** Prompt caching works on an unchanged prefix. Editing
   `CLAUDE.md`, switching models, or toggling MCP servers mid-session can invalidate the cache.
   Change them between sessions.
3. **Pick the model per task.** Run routine edits on a smaller model and set
   `CLAUDE_CODE_SUBAGENT_MODEL` for subagents. Set a per-model effort level with `modelSettings`
   in settings, for example `{"claude-opus-5-5": {"effortLevel": "medium"}}`.
4. **Trim noisy command output.** Pipe long output through `tail` or `grep`, or send it to a test
   runner subagent that reports only failures. Cap shell output with `BASH_MAX_OUTPUT_LENGTH`.
5. **Batch independent tool calls** in one turn. Each extra round trip re-sends the context.

Settings used in the author's setup. The author did not check these against the docs, so verify
them on your version before relying on them:

- `disableClaudeAiConnectors: true`: skips claude.ai connectors you never use.
- `respondToBashCommands: false`: does not answer after `!` shell commands.
- `awaySummaryEnabled: false`: skips the summary when you return to an idle session.
- `cleanupPeriodDays`: old transcripts accumulate without a limit. This affects disk, not tokens.

### Instructions that save tokens

Put these in your `CLAUDE.md` or coding guidelines. Each stops work the user did not ask for:

- **Scope discipline.** Implement only what was asked. No extra features, helpers, or
  abstractions. No README or documentation unless requested. No comments unless the code is
  complex. Make the minimum change to existing code.
- **Answer first.** Lead with the result. Do not restate the request, and do not close with a
  recap.
- **Delete text that says nothing.** Polishing a hollow paragraph yields a clean, hollow
  paragraph.
- **Stop at unambiguous, not at shortest.** Keep a condition, scope, or number even when it costs
  words.
- **Cap lists at 5 items.** Rank them, or split them into do-now and later.
- **Confirm before costly or irreversible work**, not after.
- **Hand off at budget limits.** When a usage window passes about 85%, write a resume document
  first, then continue.

## 6. Things that did not help

Measured and ruled out as the cause of slow turns or large context:

- MCP server startup time. Connections are non-blocking unless a server sets `alwaysLoad: true`.
- The status line. It runs locally, uses no API tokens, and never blocks a turn.
- Plugin count. Going from 15 to 8 enabled plugins did not change startup context.
- Skill and agent description size. About 3% of startup.

## How to measure your own setup

1. Read the per-turn `usage` fields in your session transcripts. Bucket turns by total input
   tokens (under 100k, 100k to 200k, 200k to 400k, 400k to 600k, over 600k).
2. Measure startup with the `claude -p` probe above from an empty directory, then from your
   project. The difference is your project's always-on context.
3. Run the `context-declutter` skill on the project, then repeat step 2.
