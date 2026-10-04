---
name: handoff
description: >
  (BN) Compact the current session into a resume document at agent-spec/<slug>/handoff.md so a
  fresh session continues without re-deriving anything. Use when asked to hand off or wrap up,
  and automatically when the subscription budget nears its limit. Triggers: "write a handoff",
  "budget is nearly out".
allowed-tools: Skill, Read, Write, Edit, Glob, Grep, Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git branch *), Bash(git rev-parse *), Bash(cat *), Bash(jq *), Bash(ls *), Bash(stat *), Bash(date *), Bash(printf *), Bash(mkdir *), Bash(echo *)
---

# Handoff

Write a handoff document that lets a **fresh agent with none of this conversation's context**
pick the work up exactly where it stands. The document — not the conversation — becomes the
transfer medium, so everything load-bearing that exists only in this conversation must land in
the file.

## Hard constraint — document only, never implement

This skill **must not modify implementation files**. Create or update the handoff document and
nothing else. No source edits, no fixes "while you're in there", no commits, no stashes. If the
handoff surfaces work that still needs doing, it belongs in the document's **Exact next steps**,
not in a diff.

The single exception is the handoff document itself (and, if this skill created the session
folder, that folder).

## Step 1 — Session Bootstrap

Invoke the `session-slug` skill to resolve this session's `agent-spec/<slug>/` identity. Do not
re-derive slug logic here — `session-slug` owns it, including the rule that another concurrent
session's folder is **never** adopted.

The handoff is then always written to `agent-spec/<slug>/handoff.md`, alongside whatever other
state this session already has (`plan.md`, `tasks.md`, `code-review.md`, …). `agent-spec/` is
gitignored, so the handoff never pollutes a commit.

**Write it at most once per session.** If `agent-spec/<slug>/handoff.md` already exists,
*refresh it in place* (overwrite, preserving the `Created:` timestamp) — never append a second
handoff or create `handoff-2.md`.

## Step 2 — Inspect the working tree before writing

A handoff that misreports the working tree is worse than none. Read the real state:

```bash
git rev-parse --abbrev-ref HEAD          # current branch
git status --porcelain                    # uncommitted/untracked files
git diff --stat                           # unstaged shape
git diff --cached --stat                  # staged shape
git log --oneline -5                      # where HEAD sits
```

Then read the actual `git diff` for the files this session touched, so **Current implementation
status** reflects the tree rather than your recollection of what you intended.

Report paths and diff *shape* (files, hunks, line counts). Do not paste large diffs into the
document — the diff is already on disk; the next agent can run `git diff` itself.

Other sessions may be working in the same repo and branch: mention unrelated modified files as
"present in the tree, not from this session" rather than claiming them or reverting them.

## Step 3 — Write `agent-spec/<slug>/handoff.md`

Start the file with the standard `agent-spec/` timestamp header, then the sections below. Omit a
section only when it is genuinely empty — write "none" rather than deleting the heading, so the
next agent knows it was considered.

```markdown
---
Created: YYYY-MM-DD HH:MM
Last Updated: YYYY-MM-DD HH:MM
---

# Handoff: [short title]

> Reason for handoff: [manual request | daily budget ~X% used, resets <time> | weekly budget …]
> Session folder: agent-spec/<slug>/

## Original objective
[What the user actually asked for, in their framing — including any scope they explicitly
ruled in or out. If arguments were passed to this skill, state what the next session is meant
to focus on and tailor the rest of the doc to it.]

## Decisions already made (and why)
| # | Decision | Why | Where it lives |
|---|---|---|---|
[Every decision the next agent would otherwise re-litigate. "Why" is the important column.
Include decisions the *user* made — especially ones they chose over your recommendation.]

## Files inspected / modified
| Path | Inspected or modified | Note |
|---|---|---|
[Paths only, plus one-line relevance. Inspected-but-unchanged files matter: they record ground
already covered so the next agent doesn't re-explore it.]

## Current implementation status
[What works, what is half-done, what was never started — grounded in the git inspection from
Step 2. Name the branch, and whether changes are committed, staged, or loose in the tree.]

## Unresolved problems
[Open questions, blockers, things that didn't work and why. Include what you already tried and
ruled out — a failed approach is expensive knowledge.]

## Failing tests / commands
[Exact commands and their real current status. Quote the essential error lines, not whole logs.
If nothing was run, say so plainly — do not imply verification that didn't happen.]

## Exact next steps
1. [Concrete, ordered, actionable. First item should be something the next agent can do
   immediately without asking a question.]

## Constraints and assumptions
[Non-obvious rules in force: CLAUDE.md / org-policy constraints that shaped the work,
environment quirks, versions, "do not touch X", plus assumptions made that were never
confirmed — flag those explicitly as assumptions.]

## Relevant tool / MCP results
[Findings from tool or MCP calls that would be expensive or slow to re-run (tickets, log
queries, API shapes, external docs). Summarise the conclusion, cite the source, and note if
the result is time-sensitive.]

## Conversation-only knowledge
[The part that exists nowhere in the repo: user preferences expressed in passing, mid-course
corrections, things the user said not to do, rejected options and why, tone/priority signals.
This is the highest-value section of the handoff — if a fact isn't in the code, the commits,
plan.md, or a ticket, it belongs here or it is lost.]

## Corrections harvested
[Scan the session for correction language — "no, actually…", "don't do X", "I meant…",
a redone approach — and list each as: what was corrected → the rule it implies. Flag any that
should outlive this session as a candidate memory-file or skill fix (for /skills-evolvement to
pick up), so corrections compound instead of evaporating with the session.]

## Suggested skills
- `/<skill>` — [why the next agent should invoke it, and when]
[E.g. `/code-gen` to resume from the first unchecked task in tasks.md, `/cr` once the
implementation is complete, `/arch-verify` when a design doc exists, a PR-creation skill (if installed) when the
branch is ready.]

## Session state files
- `agent-spec/<slug>/plan.md` — [one line on what it holds, or "not created"]
- `agent-spec/<slug>/tasks.md` — status `🔄/✅`; first unchecked task: [quote it verbatim]
- `agent-spec/<slug>/code-review.<harness>-<model>.md` — [list each one found with its open findings count, or "not created"]
- [any design doc / RCA path this session produced]
```

### Do not duplicate what other artifacts already hold

Reference by path or URL instead of copying: `plan.md`, `tasks.md`, `code-review.<harness>-<model>.md`, design
docs, RCAs, Jira tickets, commits, diffs. The handoff's job is to carry what is **not** written
down anywhere else, plus pointers to what is. A handoff that restates `plan.md` will drift out
of sync with it and mislead the next session.

The one thing worth quoting verbatim from another artifact: the first unchecked task in
`tasks.md` — it's the resume entry point.

### Redact

Never write secrets, API keys, tokens, credentials, connection strings, customer telemetry, or
PII into the handoff — organization policy, and the file outlives the session. Replace with a
description of the value and where it legitimately comes from (`[API key — from 1Password entry
X / env var Y]`).

## Step 4 — Auto-trigger: subscription budget nearly exhausted

Beyond manual invocation, the handoff should be written **before** the usage budget runs out, so
a session that gets cut off mid-task is resumable.

`api.type` and `rate_limits` reach only the status line's stdin — never a skill's context — so
read the snapshot that `hooks/usage-snapshot.sh` captures:

```bash
jq -r '
  "api=\(.api.type // "unknown") plan=\(.api.plan // "?") captured_at=\(.captured_at // "unknown")",
  (.rate_limits // {} | to_entries[]
    | "\(.key)=\(.value.used_percentage // .value.percentage // "?")% resets_at=\(.value.resets_at // .value.reset_at // "?")")
' ~/.claude/usage-snapshot.json 2>/dev/null
```

**Trigger when both hold:**
1. `api.type == "subscription"`, and
2. any of `five_hour`, `day`, `week`, `seven_day` is at **≥ 85%** used.

Record which window fired and its `resets_at` in the document's *Reason for handoff* line — that
tells the user when the next session can start.

**Best-effort, never blocking.** The snapshot is a convenience, not a dependency:

- File missing, empty, unparseable, or `jq` unavailable → **skip the auto-trigger silently** and
  behave as an ordinary manual invocation. Never error, never warn, never retry.
- `captured_at` (or the file's mtime) older than ~15 minutes → treat as **no signal**, not as a
  reading. A stale snapshot from yesterday's session would otherwise fire a spurious handoff.
- `api.type` anything other than `subscription` (API key, Bedrock, Vertex) → no budget windows
  apply; skip.

**Also treat as a trigger**, snapshot or not:
- A harness usage-limit warning appearing in the session ("approaching your usage limit", limit
  reached, or similar).
- The user saying the budget is nearly gone, or asking to wrap up before the limit.

On an auto-trigger: write the handoff **first**, before continuing or finishing other work — a
handoff written after the budget is gone is a handoff that never got written. Then tell the user
in one line where it is and which window fired, and carry on if budget remains.

## Step 5 — Report

If `<skill-dir>/local.md` exists, read it first (and any file it points to under
`<skill-dir>/local/`). It holds this install's site-specific setup, and its rules override the
defaults below.

One short message: the handoff path, why it was written (manual vs which budget window), and the
single most important next step. Do not paste the document back into the conversation — the
point of the handoff is that it lives on disk.
