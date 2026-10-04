# Classification Heuristics

Read this before classifying any section of any `CLAUDE.md`, `AGENTS.md`, or `SKILL.md`
file. It expands on `SKILL.md`'s Step 3.

## What actually auto-loads, every session, in full

This is the fact the whole skill depends on — get it wrong and every recommendation
downstream is wrong too:

| Location | Loads |
|---|---|
| `CLAUDE.md` (any level: global, repo root, subdirectory) | Always, in full, every session |
| `AGENTS.md` (any level) | Always, in full, every session |
| `~/.claude/rules/*.md` | Always, in full, every session — **confirmed empirically, not documented as prominently as CLAUDE.md itself.** It looks like a secondary/optional location; it is not. Never propose it as an extraction destination. |
| `SKILL.md` frontmatter (`name` + `description`) | Always, as part of the skill listing |
| `SKILL.md` body (everything after frontmatter) | Only when the skill is judged relevant to the current task |
| `references/`, `scripts/`, `assets/` inside a skill folder | Only when the body explicitly points an agent at the file |

The practical consequence: extracting a section out of `CLAUDE.md`/`AGENTS.md`/
`rules/*.md` is a real context reduction. Extracting a section out of a `SKILL.md` body
only reduces cost on turns where that skill wasn't going to be invoked anyway — real, but
lower-severity, and never worth degrading the body's usefulness to chase.

## Keep inline

- Safety-critical or destructive-action rules (file deletion policy, force-push/reset
  restrictions, credential handling) — these must be visible unconditionally, not
  gated behind an agent's judgment call to go read something else first.
- Path-based or scope-based restrictions that change behavior for the whole session
  (e.g. "in this directory, skip step X").
- A condensed lookup table that is *itself* the fast-reference the file exists to
  provide (a summary table of steps, a runner-selection table) — even if it's short,
  it's the thing every other elaboration in the file points back to; extracting it
  would leave nothing for the pointers to reference.
- Anything genuinely consulted on a large fraction of sessions, regardless of length.

## Collapse (shorten, don't extract)

- Verbose step-by-step prose that re-explains a table or summary that already exists
  elsewhere in the *same file*. Keep the table as the always-loaded fast-reference;
  move the prose elaboration to a reference file, or delete it if the table alone is
  sufficient and the prose adds no information the table doesn't already carry
  (verify this before deleting anything — "adds no information" is a high bar).

## Extract wholesale

- Narrow or rare-trigger topics. A section explicitly labeled "(reference only)" by its
  own author is the strongest possible signal — someone already flagged it as
  low-frequency.
- Content specific to one occasional subsystem, investigation, or one-time setup
  procedure (e.g. a specific cloud login flow, a specific service's runner
  configuration) that most sessions never touch.
- Long enumerations/schemas that exist for lookup, not for every-session application
  (a full settings schema, a full list of runner names) where a short inline pointer
  plus the full list in a reference file serves the same purpose at a fraction of the
  always-loaded cost.

## Flag only — do not rewrite

- Content that duplicates a rule already enforced by an existing skill in the same
  repo. The fix here is not a reference file; it's replacing the duplicated prose with
  a pointer at the skill itself (e.g. "see the `coding-standards` skill"), and that
  requires understanding the skill dependency graph well enough not to break it — flag
  it for the user rather than resolving it unilaterally.
- Stale or broken references discovered along the way (a pointer to a file that no
  longer exists, a described behavior that no longer matches the code) — call these
  out in the report even if they're outside this run's stated scope.

## Red flags worth calling out in the report even when out of scope

- Duplicate information stated in more than one always-loaded file.
- A reference file that nothing points to (dead weight — no pointer means it never
  loads, so it isn't actually reducing anyone's context cost, it's just an orphan).
- A pointer whose target path doesn't exist (broken split from a previous edit).
