# SKILL.md-Specific Notes

Read this whenever `SKILL.md` files are in scope for a declutter pass. `SKILL.md` follows
a different loading model than `CLAUDE.md`/`AGENTS.md`, so the same size number means a
different thing.

## The three-level loading model

1. **Frontmatter (`name` + `description`)** — always loaded, for every skill, on every
   turn, as part of the skill listing. This is the only part of a `SKILL.md` that behaves
   like `CLAUDE.md` content (always-on cost). The `description` field:
   - Is capped at **1024 characters**.
   - Must state both *what the skill does* and *when to use it* — include the trigger
     phrases a user would actually type. A description that's accurate but generic
     ("Helps with projects") fails to trigger the skill when needed; a description with
     no triggers at all is a worse bug than a slightly-too-long body.
   - Must not contain literal `<`/`>` (XML angle brackets).
   - **Is a protected, separate budget from the body.** Shrinking a bloated body must
     never shrink or genericize the description in the process — if anything, an
     undertriggering skill needs *more* specific keywords in its description, not fewer.

2. **Body (everything after frontmatter)** — loaded in full, atomically, the moment an
   agent judges the skill relevant. There is no partial load of the body itself.
   Explicit ceiling: **keep the body under ~5,000 words.** Past that, the fix is the same
   one this skill applies everywhere else — move detail to `references/` and leave a
   pointer, don't just trim prose.

3. **`references/`, `scripts/`, `assets/`** — loaded only when the body explicitly
   points an agent at a specific path. Nothing in these directories is discovered on its
   own; an agent has no way to know a reference file exists unless the body names it.

## Why SKILL.md bloat is lower-severity than CLAUDE.md/AGENTS.md bloat

A large `SKILL.md` only costs tokens on turns where that specific skill was already
judged relevant — it doesn't tax every session the way `CLAUDE.md`/`AGENTS.md`/
`rules/*.md` do. Flag an oversized `SKILL.md` body in the report, but don't push as hard
to aggressively rewrite it as you would a `CLAUDE.md` of the same size — the ceiling
matters most when a skill is invoked often, since that's when its body cost compounds.

## Pointer quality — the difference between a split that works and one that doesn't

A reference split only reduces effective context if the agent invoking the skill
actually opens the reference file when needed. Two conventions make that reliable:

- **Name the exact file path and bullet what's inside it** in the body, e.g.:
  > Before writing queries, consult `references/api-patterns.md` for: rate limiting
  > guidance, pagination patterns, error codes and handling.

  A pointer that just gestures at "see references for more" without naming the file or
  its contents gives an agent nothing concrete to act on — it will neither open the file
  nor recall later that it existed. Treat a vague pointer as equivalent to having
  deleted the content, not moved it.

- **Prepend a `Load this file when: ...` annotation** to the top of every reference file
  you create. It gives both a human skimming the file and an agent deciding whether to
  open it the same disambiguating signal, and it should read as the same trigger
  condition named in the pointer left behind in the body.

## Structural invariants that must never move

These stay in the `SKILL.md` body's frontmatter block no matter how aggressively you
split the rest of the file — moving any of them into a reference file breaks the
always-loaded guarantee that the frontmatter tier exists to provide:

- `name`, `description`, `model`, `effort`, `allowed-tools`, `hooks`, and any
  `license`/`compatibility`/`metadata` fields present.
- The filename itself must remain exactly `SKILL.md` (case-sensitive) — never
  `skill.md` or `README.md` alongside it.

## Deterministic checks vs. reference prose

If a section under consideration for extraction is actually a validation procedure or
checklist a human/agent would otherwise run mentally, prefer converting it to a
`scripts/` file over a longer `references/` doc. Code is deterministic; language
interpretation of a checklist isn't — for anything correctness- or safety-critical, that
distinction matters more than where the words live.

## What doesn't need a size fix at all

A `SKILL.md` already under the ~5,000-word ceiling is not a splitting target regardless
of how it compares to sibling skills — the ceiling is the trigger, not relative size.
