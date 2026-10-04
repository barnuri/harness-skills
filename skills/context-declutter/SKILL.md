---
name: context-declutter
description: >
  (BN) Find every CLAUDE.md/AGENTS.md/SKILL.md in a repo (plus global ones), measure always-
  loaded context, and split bloated sections into on-demand references with confirmation before
  writing. Use when context files feel too big. Triggers: "my CLAUDE.md is too big", "reduce
  context bloat".
allowed-tools: Read, Write, Edit, Bash(find *), Bash(wc *), Bash(grep *), Bash(ls *), Bash(readlink *), Bash(git rev-parse *), Bash(mkdir *), Glob, Grep, AskUserQuestion
---

# Context Declutter

Find every file that is permanently injected into this agent's context on every turn,
and move whatever isn't needed on every turn into a file that loads on demand instead —
without losing a single word of it.

## The loading model this skill is built on

Only three things are ever guaranteed to load automatically, every session, in full:
`CLAUDE.md` (every level), `AGENTS.md` (every level), and `~/.claude/rules/*.md`. A
`SKILL.md` file is different — only its frontmatter `description` is always loaded (as
part of the skill listing); the body loads only when the skill is judged relevant, and
anything under `references/`, `scripts/`, or `assets/` loads only if the body explicitly
points an agent at it. This is why `SKILL.md` bloat is lower-severity than CLAUDE.md/
AGENTS.md bloat, and why `~/.claude/rules/` is never a valid destination for content
you're trying to make on-demand — it auto-loads exactly like CLAUDE.md does. Full
heuristics for classifying content under this model are in
[references/classification-heuristics.md](references/classification-heuristics.md) —
read it before classifying any file's sections. SKILL.md-specific sizing and frontmatter
rules are in [references/skill-md-notes.md](references/skill-md-notes.md) — read it
whenever `SKILL.md` files are in scope.

## Step 1 — Scope

Target repo = the current working directory's git root, or an explicit path if the user
gave one. **Always also include global scope**, regardless of what repo you're in:
`~/.claude/CLAUDE.md` and every file matching `~/.claude/rules/*.md`.

Treat global-scope files as a separate, higher-blast-radius category from repo-scope
files throughout this workflow — they affect every project and every future session, not
just this one repo. They get their own confirmation step later (Step 6), never bundled
into the same yes/no as repo-scope changes.

## Step 2 — Discover (recursive, symlink-aware)

```bash
find "<repo-root>" -type f \( -name "CLAUDE.md" -o -name "AGENTS.md" -o -name "SKILL.md" \) \
  -not -path "*/node_modules/*" -not -path "*/.git/*"
ls -la ~/.claude/rules/*.md 2>/dev/null
```

For every `CLAUDE.md`/`AGENTS.md` pair, check with `readlink` whether one is a symlink to
the other (this repo's own convention, and one you may find elsewhere). A linked pair is
one file with two names — count it once, and always edit the real file, never the
symlink; editing through a symlink works but reasoning about it as "two files" leads to
double-counting size and duplicate pointer text.

For every discovered file, record `wc -l` and `wc -c` (or word count) for a size ranking.
For `SKILL.md` files specifically, also record whether the body is already under the
~5,000-word ceiling from `references/skill-md-notes.md` — a `SKILL.md` under that ceiling
is not a target for splitting regardless of absolute size, since its body only loads when
already judged relevant.

## Step 3 — Classify sections per file

Work through each file's sections using the criteria in
[references/classification-heuristics.md](references/classification-heuristics.md).
Every section lands in exactly one bucket: **keep inline**, **collapse** (shorten prose
that duplicates a table/summary already in the file), **extract wholesale** (move to a
reference file), or **flag only** (point at an existing skill instead of rewriting
anything — don't touch it yet). Do not skip reading that file — the always-inline vs.
extract line is not obvious from section length alone (a short section can be
safety-critical; a long one can be pure lookup-table material).

## Step 4 — Reference file placement

- **Repo-scope extractions**: beside the source file, reusing an existing
  `references/`/`docs/`-style convention in that repo if one exists (this repo's own
  `skills/<name>/references/` layout is the model), otherwise creating one, e.g.
  `.claude/context/<topic>.md` next to the repo's `CLAUDE.md`.
- **Global-scope extractions**: `~/.claude/knowledge/<topic>.md`. **Never**
  `~/.claude/rules/` — that directory auto-loads in full every session, identically to
  `CLAUDE.md`, so "moving" content there is not a reduction, it's a relabeling.

Every new reference file starts with a one-line annotation naming exactly when to read
it, e.g. `> Load this file when: setting up AWS SSO or picking a profile.` This is the
same signal an agent needs on both ends of the split — mirror its wording in the pointer
text you leave behind in Step 5.

## Step 5 — Rewrite pointers

Replace each extracted section with 1–3 lines that name the **exact relative path** and
**bullet what's inside it** — not a vague "see references for more". A pointer that
doesn't name the file and its contents gives an agent nothing to act on; it will neither
open the file nor recall it was ever there. Example shape:

```
AWS SSO login and profile→environment mapping: see .claude/knowledge/aws-sso.md — read it
when setting up or debugging AWS SSO authentication.
```

Write pointers in imperative, harness-neutral phrasing (works for any agent reading the
file, not just Claude Code — see this repo's own Cross-Harness Portability rules if
`CLAUDE.md`/`AGENTS.md` in this repo are in scope).

## Step 6 — Report before writing

Produce a before/after size table (lines or words per file, estimated reduction) plus the
exact proposed pointer text and new file layout for every file in scope. Ask for
go-ahead via `AskUserQuestion`. **Ask again, separately**, before touching any
global-scope file (`~/.claude/CLAUDE.md`, `~/.claude/rules/*.md`) — a single approval
covering both scopes is not enough given the difference in blast radius.

## Step 7 — Apply only what's approved

`Write` the new reference files, `Edit` the sources to swap approved sections for their
pointers. Every moved paragraph must appear verbatim in its new home (condensed only
where it was genuinely redundant with a summary already left behind in the same file) —
this skill only relocates content, it never deletes it. If a section under
consideration is a deterministic checklist or validation procedure rather than
reference prose, prefer converting it to a `scripts/` file over a longer reference
doc — code is deterministic, prose instructions aren't, and that's a stronger
guarantee for anything safety- or correctness-critical.

## Verification

After applying changes:

```bash
wc -l <edited-file>              # confirm it shrank
grep -F "<extracted-heading>" <new-reference-file>   # confirm nothing was dropped
```

Re-read every edited file end-to-end once. Confirm nothing safety-critical, path-scoped,
or genuinely used-every-session was moved out — those stay inline by definition (see
`references/classification-heuristics.md`'s "keep inline" criteria).

## Report the result

If `<skill-dir>/local.md` exists, read it first (and any file it points to under
`<skill-dir>/local/`). It holds this install's site-specific setup, and its rules override the
defaults below.

When the run is done, report the reduction for every edited file — both as a raw count and as
a percentage — e.g. `~/.claude/CLAUDE.md: 220 → 198 lines (-22 lines, -10%)`. Compute this from
the actual before/after `wc -l` (or word count) numbers, never estimate it. Include a total
across all edited files if more than one was changed.
