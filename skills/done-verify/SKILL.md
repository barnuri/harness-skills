---
name: done-verify
description: >
  (BN) Check that the current session is really finished before the agent says so: every user
  message was handled, every agent-spec task or review file the session wrote is closed, and no
  background command, monitor, or subagent is still running. Reports a checklist and a DONE or
  NOT DONE verdict. Use when the user asks whether everything is done, before a final summary of a
  long session, or before ending a session. Triggers: "done-verify", "did we handle everything",
  "is anything still running", "are we done".
allowed-tools: Read, Glob, Grep, Bash(python3 *), Bash(bash *), Bash(ps *), Bash(ls *), Bash(git status *), Bash(git log *), TaskStop, ListAgents
---

# Done Verify

Check the session against three conditions, and report the evidence for each one. The session is
done only when all three hold:

1. Every user message in the session is handled.
2. Every agent-spec state file that the session touched is closed.
3. No background work that the session started is still running.

Read this skill's local overlay first, if one exists: `<skill-dir>/local.md`, else
`~/.config/harness-skills/<skill-name>/local.md` (the plugin-install location, which survives
updates). Also read any file it points to in the `local/` folder beside it. It holds this install's site-specific setup, and its rules override the
defaults below.

This skill reports. It does not do the missing work. The one exception is Step 4: stop background
work that has already finished but is still listed.

## Step 1 — Collect the evidence

Find the session id and the harness:

```bash
. "<skill-dir>/../../hooks/agent-env.sh"
agent_harness
agent_session_id
```

`<skill-dir>` is this skill's own base directory, which the harness states when it loads the skill.

When the harness is `claude`, run the audit script on the session transcript:

```bash
python3 -I "<skill-dir>/scripts/session-audit.py" --session-id "<session-id>"
```

The script reads the transcript under `~/.claude/projects/*/<session-id>.jsonl`. It prints three
lists:

- **User requests** (`M1`, `M2`, …). These are the typed prompts, the messages sent mid-turn, and
  the slash-command invocations. Harness notifications and meta entries are left out.
- **Background work**: every background shell command, monitor, and subagent, with the state the
  transcript shows. `OPEN` means that the transcript shows no end notification and no stop.
- **agent-spec files**: each `.md` file in every `agent-spec/<slug>/` folder that the session
  wrote to, with its open and closed counts.

When the harness is not `claude`, or the script cannot find the transcript, build the same three
lists from the conversation context. Say in the report that the lists come from context and that
no transcript backs them. Context loses messages after a compaction, so mark that
report as less certain.

## Step 2 — Check each user request

Give each request one status:

| Status | Meaning |
|---|---|
| Handled | The work is done, or the question is answered. Name the evidence: a commit, a file path, a test count, a URL, or the answer. |
| Superseded | A later message replaced or cancelled it. Name that message (`M7`). |
| Partly handled | Some of the work is done. Name the part that is missing. |
| Not handled | Nothing addressed it. |

Rules:

- Judge each request from the work in the session, not from the summary text that the agent wrote.
  Check the evidence: run `git log` or `git status`, read the file, or open the URL.
- A request that names several things counts as handled only when each thing is handled. List
  the parts that are missing.
- A question counts as handled when the session gave a direct answer to it.
- A request that the user answered through an ask tool, or declined, counts as handled when the
  session acted on the answer.
- When a request is unclear, mark it `Partly handled` and quote the unclear words. Never guess
  that it is handled.

## Step 3 — Check the agent-spec files

For each file in the list:

- `tasks.md`: the status line must be `✅`, and the counts of open (`- [ ]`), in-progress (`- 🔄`),
  and blocked (`- ⏸`) tasks must all be 0.
- `code-review*.md`: the counts of `❌ Open` and `🆕 New` rows must be 0. A `📤 Reported` row is
  closed for this check, because the review delivered it. Still list each `📤 Reported` row, because
  it is a finding that nobody has fixed.
- Any other file: it must exist. Read it when it has a status line or a checklist, and apply the
  same rule.

A folder that belongs to another session is not this session's state. Leave it out when the
session only read a file in it and did not write to it.

## Step 4 — Check the background work

For each entry marked `OPEN`, check its live state with the harness's own task and agent listing
(for example `ListAgents`), or with `ps` for a shell process.

- **Finished but still listed:** stop it (`TaskStop` or the harness's equivalent), then mark it
  stopped.
- **Still working:** do not stop it. Report what it waits for. The verdict is NOT DONE until it
  ends.
- **Cannot be checked:** report it as unknown. The verdict is NOT DONE.

Also check for long-running processes that the session started outside the background tool: dev
servers, browser windows, port forwards, and watch loops. Report each one that is still running.
Stop one only when the session no longer needs it and the user did not ask to keep it.

## Step 5 — Report

Print one table per check, then the verdict.

```
## Requests
| ID | Request (short) | Status | Evidence |
|----|-----------------|--------|----------|
| M1 | ...             | Handled | commit abc1234, tests 120/120 |

## agent-spec files
| File | State | OK |

## Background work
| ID | Kind | What | State |

Verdict: DONE — N requests handled, 0 open task items, 0 background work running.
```

or

```
Verdict: NOT DONE — <count> item(s) open:
1. M4 partly handled: <missing part>
2. tasks.md: 2 open tasks
3. <task-id> still running: <what it waits for>
```

Rules:

- Print `DONE` only when every request is `Handled` or `Superseded`, every agent-spec file passes,
  and no background work is running or unknown.
- Number the open items in priority order. Put requests that are not handled first.
- End with one concrete next action when the verdict is NOT DONE.
