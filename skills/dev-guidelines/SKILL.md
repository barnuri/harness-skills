---
name: dev-guidelines
description: >
  (BN) Load this install's coding standards from the skill's local configuration. Works only when
  configured: without a local.md it reports "not configured", loads nothing, and offers once to
  generate a configuration. Invoked by code-gen and cr. Also use it directly when asked about the
  coding standards.
allowed-tools: Read, Glob, Grep, Write, AskUserQuestion
---

# Developer Guidelines

This is a placeholder. It ships no rules of its own: every rule comes from the local
configuration that each install provides.

**Session guard.** If `dev-guidelines: loaded` or `dev-guidelines: not configured` already appears
in this conversation, repeat that line and stop. Do not read any files.

## Step 1 — Find the local configuration

Read the first `local.md` that exists:

1. `<skill-dir>/local.md` (a cloned or symlinked install).
2. `~/.config/harness-skills/dev-guidelines/local.md` (a marketplace plugin install, whose
   `<skill-dir>` is replaced on every update).

`local.md` lists the guideline files and the file types each one applies to. Its paths are
relative to the folder that holds that `local.md`.

If `local.md` contains the line `disabled: true`, output exactly `dev-guidelines: not configured`
and stop. Do not offer to generate a configuration.

If neither file exists, output exactly:

> dev-guidelines: not configured

Then go to **Offer to generate a configuration** below. Callers (`code-gen`, `cr`) treat
"not configured" as "no skill installed" and continue down their fallback chain.

## Step 2 — Load the guideline files

Read every file `local.md` marks as always-loaded, then every file whose file types match the
files in scope. Follow `local.md`'s routing exactly and do not borrow rules from a file it does
not route to.

## Step 3 — Confirm load

Output exactly:

> dev-guidelines: loaded

Then apply every loaded rule to all code you generate or review.

## Offer to generate a configuration

Offer this at most once per session. Skip the offer when this session is a subagent, an
autonomous run, or has no interactive ask tool.

Ask the user through the ask tool, with these options:

| Option | Action |
|---|---|
| Generate from this repo | Read the repo's lint and formatter configs, `CLAUDE.md`/`AGENTS.md`, and a sample of source files. Draft the guideline files from the conventions the code already follows |
| Write a starter set | Write a short, generic `coding-principles.md` plus one file per language found in the repo |
| Not now | Continue unconfigured. Ask again in a later session |
| Never ask | Write `local.md` with the single line `disabled: true` |

Write every generated file to `~/.config/harness-skills/dev-guidelines/`. Never write inside
`<skill-dir>`: a plugin update deletes it, and a cloned install may be a synced checkout. Show the
user the drafted files and get their approval before writing them. After writing, run Step 1 again.

A generated configuration contains:

- `local.md`: the routing list (see the example below). One "always load" file, then one line
  per file type with the file it adds.
- `local/coding-principles.md`: rules for every language. Naming, function size, error handling,
  comments, test expectations, and scope discipline (change only what the task needs).
- `local/<language>-guidelines.md`: one file per language in the repo. The formatter and linter
  with their configs, typing rules, the module layout, and the test framework and test layout.

Keep each rule to one checkable sentence. A reviewer must be able to answer "followed or not"
for every rule.

## Configuring it

Create `local.md` and put your guideline files in the `local/` folder beside it, in
`<skill-dir>/` or in `~/.config/harness-skills/dev-guidelines/`. Overlays are gitignored, so they
never reach the public repo. Example `local.md`:

```markdown
# Coding standards

- Always load: `local/coding-principles.md`
- `.py` files: also load `local/python-guidelines.md`
- `.ts` / `.tsx` files: also load `local/typescript-guidelines.md`
```

The paths are relative to the folder that holds `local.md`. `local/` may be a symlink to a
folder kept in another (private) repo.
