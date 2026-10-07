---
name: session-slug
description: >
  (BN) Internal shared skill — resolves the agent-spec/<slug>/ session identity and publishes it
  to the terminal title and status line, and defines the shared session-folder format. Invoked
  at bootstrap by skills that keep per-session state (arch-verify, skills-evolvement, and
  others); use directly only when debugging slug or terminal-title behavior.
allowed-tools: Bash(git rev-parse *), Bash(mkdir *), Bash(printf *), Bash(echo *), Bash(cat *), Read, Write, Edit
user-invocable: false
---

# Session Slug

Single source of truth for deriving, resolving, and publishing an `agent-spec/<slug>/`
session identity, and for the session-folder format every state-keeping skill shares.
Skills that keep per-session state (e.g. `arch-verify`, `skills-evolvement`, and any
code-generation or review skill installed alongside) invoke this skill instead of inlining
their own slug logic — if the resolution or publishing behavior needs to change, change it
here once.

## Step 1 — Derive a slug (new session only)

Generate a short kebab-case name for the task (2–4 words), then prefix it with today's
date in `YYYY-MM-DD-` form so the slug — and therefore the `agent-spec/` folder — sorts
chronologically. Examples: "add user authentication" → `2026-06-26-user-authentication`,
"fix login redirect bug" → `2026-06-26-fix-login-redirect`, "improve skills" →
`2026-06-26-skills-evolvement`. This date-prefixed slug is the session's identity
throughout — keep it stable across the entire conversation and reuse it for every later
step (review, verification, resumed sessions).

## Step 2 — Ensure `agent-spec/` is gitignored

Find the git root (`git rev-parse --show-toplevel`) and check the `.gitignore` there:
- **Contains `**/agent-spec` or `**/agent-spec/`**: nothing to do.
- **Exists but missing the entry**: append `**/agent-spec` on a new line.
- **Does not exist**: create `.gitignore` at the git root with a single line: `**/agent-spec`.

Idempotent — do this at most once per session, never duplicate an existing entry.

## Step 3 — Resolve or create the working folder

Multiple terminal sessions may run concurrently in the same repo, so `agent-spec/` may
contain folders that belong to **other** sessions. Never scan `agent-spec/` to find work
to resume — resume is context-bound:

- **Slug already in this conversation's context** (this session created it earlier, or a
  caller skill passed it explicitly): reuse that folder as-is. Do not re-derive or rename it.
- **User explicitly asked to resume/continue a previous session** (e.g. "resume",
  "continue where we left off", or named a slug): scan `agent-spec/*/tasks.md` (or the
  caller's equivalent state file) for `🔄 In progress` folders, list them, and let the
  user pick (use the named one directly if it exists).
- **Anything else — a new request**: create a fresh `agent-spec/<slug>/`. If a folder
  with that slug already exists but was not created in this conversation, do **not**
  adopt it — append a numeric suffix (`<slug>-2`, `<slug>-3`, …) until the name is free.

**Never rename or move an existing slug folder once resolved** — later steps in this or
any calling skill assume the folder path is stable for the rest of the session.

## Step 4 — Publish the slug (terminal title + status line)

Once the slug is resolved (new or resumed), make it visible outside the conversation —
this is what lets the user glance at a terminal tab or the status line and know which
`agent-spec/<slug>/` a given window is working on, instead of having to ask.

**Terminal title** — set it via an ANSI OSC escape sequence, best-effort (never fail the
session bootstrap if this doesn't work, e.g. non-interactive/CI shells):
```bash
printf '\033]0;%s\007' "<slug>"
```

**Status line** — write the slug to a small per-session state file keyed by the
session's own id, so an external status-line renderer can pick it up without needing
any of this skill's context:
```bash
# <skill-dir> is this skill's own base directory, which the harness states when it loads
# the skill. Sourcing resolves through the symlink other harnesses see, so this works
# under Claude Code, Cursor, Codex, Gemini, Grok Build, DeepSeek Harness, opencode, and pi.
. "<skill-dir>/../../hooks/agent-env.sh"
mkdir -p ~/.claude/session-slugs
echo "<slug>" > ~/.claude/session-slugs/"$(agent_session_id)"
```
`agent_session_id` (from `hooks/agent-env.sh`) is the key. It returns the harness's own
session id **verbatim** when one exists — e.g. `CLAUDE_CODE_SESSION_ID`,
`CURSOR_CONVERSATION_ID`, `CODEX_THREAD_ID`, `GROK_SESSION_ID`, `GEMINI_SESSION_ID`,
`DSH_SESSION_ID` / `DEEPSEEK_SESSION_ID` — so status-line / Stop-hook readers that key
on the same env (or stdin `session_id`) find the matching file.

Do **not** substitute a bare `${CLAUDE_CODE_SESSION_ID:-unknown}` here. That variable is
unset outside Claude Code, so every session would write to one shared file named
`unknown` and concurrent sessions would clobber each other's slug. The resolver also handles
the nested case (an inner harness started from an outer one inherits the outer session
env, and must *not* adopt the outer session's id).

Overwrite (not append) on every publish — the file always reflects the current slug. If
sourcing the resolver fails for any reason, skip publishing rather than guessing a key;
publishing is cosmetic and a wrong key is worse than no key.

Do not block or retry either publish step — both are cosmetic. If the terminal doesn't
support OSC titles or the state directory can't be written, continue silently.

## Step 5 — Resolve the harness token (callers with a per-harness output filename)

Some callers (e.g. `arch-verify`, review skills) write an output file suffixed
`<harness>-<model>` so multiple harnesses/models can work the same slug concurrently
without clobbering each other's file. The harness half of that suffix is
`agent_harness` — already sourced in Step 4, so no extra step is needed beyond calling
it: `agent_harness` (from the same `hooks/agent-env.sh` source). Return its value
(`claude`, `opencode`, `pi`, `codex`, `cursor`, …) to the caller alongside the slug; the
caller supplies its own model id (it knows this about itself) to complete the suffix.
Callers that don't need a per-harness filename (e.g. `skills-evolvement`) can ignore this.

## Session folder format

Every skill that writes under `agent-spec/<slug>/` follows this format, so tools that list,
resume, or clean sessions (the `agent-spec` skill) work without knowing which skill wrote them.

- **`tasks.md`** is the session's state file. It has a `## Status` heading whose first emoji is
  the session status:

  | Emoji | Status |
  |---|---|
  | `🔄` | In progress |
  | `✅` | Done |

- **Task lines** in `tasks.md` use these markers:

  | Marker | Meaning |
  |---|---|
  | `- [ ]` | Not started |
  | `- 🔄` | In progress |
  | `- ⏸` | Blocked, waiting on a question |
  | `- [x] ✓` | Done |

- **`plan.md`** (optional) carries a `> Status:` line that mirrors the `tasks.md` status.
- **Owner.** `tasks.md` names the skill that created the session on an `Owner: <skill-name>`
  line in its header. A resume goes back through that skill.
- **Other state files** (e.g. `arch-design-diff.<harness>-<model>.md`) live beside `tasks.md` and
  keep their own vocabulary. A folder with no `tasks.md` is an orphan: report it, never classify
  or delete it automatically.

## Return contract

Callers should treat this skill's durable output as: the resolved `<slug>` string (now
stable for the session), the fact that `agent-spec/` is gitignored and the
title/status-line files are published, and — for callers that asked — the `agent_harness`
token from Step 5. Callers still own creating their own state files (`tasks.md`,
`code-review.<harness>-<model>.md`, `arch-design-diff.<harness>-<model>.md`, …) under
`agent-spec/<slug>/` — this skill only resolves *which* folder that is, plus the harness
token when needed.

Read this skill's local overlay first, if one exists: `<skill-dir>/local.md`, else
`~/.config/harness-skills/<skill-name>/local.md` (the plugin-install location, which survives
updates). Also read any file it points to in the `local/` folder beside it. It holds this install's site-specific setup, and its rules override the
defaults below.

> Harness note: the `user-invocable: false` frontmatter key is Claude-Code-only; opencode/pi ignore it. There, the description wording above is the only guard — no behavioral fallback needed.
