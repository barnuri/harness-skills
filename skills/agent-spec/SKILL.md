---
name: agent-spec
description: >
  (BN) Manage agent-spec/ session folders: report unfinished sessions and offer to resume one
  (status), delete finished session folders (clean), or prune stale session-slug pointer files
  (prune). Use when asked for open sessions, to clean up agent-spec, or to prune session slugs.
  Triggers: "what's unfinished in agent-spec?", "clean up agent-spec", "prune session slugs
  older than a week".
allowed-tools: Read, Bash(for *), Bash(grep *), Bash(git rev-parse *), Bash(ls *), Bash(find *), Bash(stat *), Bash(cat *), Bash(date *), Bash(trash *), Skill, AskUserQuestion
disable-model-invocation: true
---

# agent-spec

Housekeeping for the session folders that state-keeping skills write under `agent-spec/<slug>/`.
The folder format (the `tasks.md` `## Status` emoji, task markers, `Owner:` line, orphans) is
defined once in the `session-slug` skill's **Session folder format** section. Read that section
before classifying anything, and never invent a status it does not define.

Read this skill's local overlay first, if one exists: `<skill-dir>/local.md`, else
`~/.config/harness-skills/<skill-name>/local.md` (the plugin-install location, which survives
updates). Also read any file it points to in the `local/` folder beside it. Its rules override the defaults below.

## Pick the mode

| Mode | Use when the user asks to… | Writes? |
|---|---|---|
| **status** | see open or unfinished sessions | Never, unless they pick one to resume |
| **clean** | delete finished `agent-spec/` folders | Trashes `✅ Done` folders after approval |
| **prune** | prune stale session-slug pointer files | Trashes files under `~/.claude/session-slugs/` after approval |

If the request does not make the mode clear, ask with `AskUserQuestion` (plain text only when no
ask tool exists). Run one mode per invocation.

## Shared: scan the session folders (status, clean)

1. Resolve `agent-spec/` under the git root (`git rev-parse --show-toplevel`). If it does not
   exist, say there are no sessions and stop.
2. For each immediate subfolder, read the first status line under `## Status` in `tasks.md`.
   Symlinked folders are listed as links and never followed:

   ```sh
   root="$(git rev-parse --show-toplevel)/agent-spec"
   for d in "$root"/*/; do
     d="${d%/}"
     if [ -L "$d" ]; then echo "$(basename "$d") -> LINK"; continue; fi
     s=$(awk '/^## Status/{f=1;next} f&&/^[✅🔄]/{print;exit}' "$d/tasks.md" 2>/dev/null)
     echo "$(basename "$d") -> ${s:-ORPHAN}"
   done
   ```

3. Classify each folder as **Done** (`✅`), **In progress** (`🔄`), **Orphan** (no `tasks.md`, or
   a status line that does not parse), or **Link** (a symlink: report it, never clean it).

## Mode: status

1. Run the shared scan.
2. For every In progress folder, read `tasks.md` and collect: the slug, the `Owner:` skill, the
   goal (first paragraph under `## Goal` or the title), `Last Updated`, a short list of open task
   lines (`- [ ]`, `- 🔄`, `- ⏸`), and blockers: `⏸` lines plus any `🔴 Open` row in `plan.md`'s
   `Open Questions — Blocking` table. Three to five bullets per session.
3. Report, in this order:
   1. **Unfinished sessions:** slug, owner, last updated, goal, open tasks, blockers.
   2. **Orphan folders:** slug list with a one-line note.
   3. **Done sessions:** the count only. Suggest clean mode if the user wants them removed.
4. If any session is unfinished, ask once with `AskUserQuestion` which one to resume (up to 4
   slugs, most recently updated first).
5. On a pick, invoke the skill named on its `Owner:` line and tell it to resume that slug. Older
   sessions may lack the line: a folder holding both `plan.md` and `tasks.md` was written by a
   code-generation skill, so offer `code-gen` when it is installed. Otherwise, or when the named
   skill is not installed, tell the user which slug they picked and that no owning skill was
   found, then stop. Do not pre-summarize the session for the owning skill.
6. If the user declines or nothing is unfinished, confirm in one line and stop.

## Mode: clean

1. Run the shared scan.
2. **Ignore list.** The user may name sessions to keep. Treat them as Keep whatever their status.
   If a description is ambiguous ("the payments session"), ask before matching it to a folder.
3. Show the plan: folders to **delete** (Done) and folders to **keep** (In progress, ignored,
   Orphan, Link). Unless the user already gave blanket approval in this request, confirm with
   `AskUserQuestion`.
4. Trash all approved folders in one `trash` command with absolute paths. Never `rm`.
5. Summarize: folders deleted, folders kept and why, folders that need the user's judgment.

## Mode: prune

`~/.claude/session-slugs/` holds one file per session (`session_id → slug`) that `session-slug`
writes at bootstrap. The files never self-clean. Pruning removes only the pointer, never the
`agent-spec/<slug>/` work.

1. **Ask for the age threshold first** unless the request already gave one. Default: 3 days.
   A file qualifies when its mtime is the threshold or older (an exactly 3-day-old file
   qualifies). Never start listing or deleting on an assumed threshold.
2. List candidates:

   ```sh
   now=$(date +%s); threshold_secs=$(( <days> * 86400 ))
   for f in ~/.claude/session-slugs/*; do
     [ -f "$f" ] || continue
     mtime=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null)
     age=$(( now - mtime ))
     [ "$age" -ge "$threshold_secs" ] && echo "$(basename "$f")  age=$(( age / 86400 ))d  slug=$(cat "$f" 2>/dev/null)"
   done
   ```

   `stat -f %m` is BSD/macOS. `stat -c %Y` is the GNU fallback.
3. Show every candidate (session id, age, slug) so the user can spot a session still active, and
   confirm with `AskUserQuestion`. Exclude any slugs the user names to keep. Zero candidates: say
   so and stop. Do not try to resolve which repo a slug belongs to.
4. Trash only the confirmed files, listed by explicit filename. Never a wildcard.
5. Summarize: files deleted, threshold used, slugs kept.

## Safety rules

- **Never delete an In progress folder**, even on "delete everything". The user must name it.
- **Never delete a folder on the ignore list**, even if it is Done.
- **Never delete an Orphan automatically.** Report it and let the user decide.
- **Never trash a Link or anything it points to.** A symlinked session folder may target content
  outside `agent-spec/`.
- **Status mode is read-only**, and it never resumes more than one session.
- **Prune mode never touches `agent-spec/`**, only files directly under `~/.claude/session-slugs/`.
- **Always use `trash` with absolute paths or explicit filenames.** Never `rm`, never wildcards.
- **Do not retry a denied `trash`.** Stop, name the blocked command, and give the user the exact
  one-liner to run themselves.

> Harness note: `disable-model-invocation` is Claude-Code-only. Other harnesses ignore it, so the
> description wording is the only guard.
