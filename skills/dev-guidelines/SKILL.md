---
name: dev-guidelines
description: >
  (BN) Load this install's coding standards from the skill's local configuration. Works only when
  configured: without a local.md it reports "not configured" and loads nothing. Invoked by
  code-gen and cr; also use directly when asked about the coding standards.
allowed-tools: Read, Glob
---

# Developer Guidelines

This is a placeholder. It ships no rules of its own: every rule comes from the local
configuration that each install provides.

**Session guard.** If `dev-guidelines: loaded` or `dev-guidelines: not configured` already appears
in this conversation, repeat that line and stop. Do not read any files.

## Step 1 — Find the local configuration

Read `<skill-dir>/local.md`. It lists the guideline files (usually under `<skill-dir>/local/`)
and which file types each one applies to.

If `local.md` does not exist, output exactly:

> dev-guidelines: not configured

Then stop. Callers (`code-gen`, `cr`) treat this as "no skill installed" and continue down their
fallback chain.

## Step 2 — Load the guideline files

Read every file `local.md` marks as always-loaded, then every file whose file types match the
files in scope. Follow `local.md`'s routing exactly and do not borrow rules from a file it does
not route to.

## Step 3 — Confirm load

Output exactly:

> dev-guidelines: loaded

Then apply every loaded rule to all code you generate or review.

## Configuring it

Create `<skill-dir>/local.md` and put your guideline files in `<skill-dir>/local/`. Both are
gitignored, so they never reach the public repo. Example `local.md`:

```markdown
# Coding standards

- Always load: `local/coding-principles.md`
- `.py` files: also load `local/python-guidelines.md`
- `.ts` / `.tsx` files: also load `local/typescript-guidelines.md`
```

The paths are relative to this skill's directory. `local/` may be a symlink to a folder kept in
another (private) repo.
