# Review Feedback Format

## Per-Issue Format

```
**[P1]** `path/to/file.py:line` — confidence: 92
> The trigger (inputs or state), then the problem.

Why it matters: [one sentence on the impact]
Fix: [concrete fix or alternative code snippet]
```

**Priority levels** (defined in the **Priority** section of `SKILL.md`): `P0` blocks the
release, `P1` fix before merge, `P2` should fix, `P3` minor. Priority is separate from the
confidence score.

## Full Review Format

```markdown
## Code Review

### Summary
[Overall assessment: what is good, what needs attention, merge readiness.]

### P1 — fix before merge
**[P1]** `auth/login.py:42` — confidence: 95
> Any login request: the password is compared with `==` instead of constant-time function.
Why it matters: Timing attacks can leak partial password matches.
Fix: Use `hmac.compare_digest(stored_hash, input_hash)`.

### P2 — should fix
**[P2]** `agents/runner.py:18` — confidence: 82
> A Ctrl-C during a run: the bare `except:` catches SystemExit and KeyboardInterrupt.
Why it matters: Hides unrelated crashes and prevents clean shutdown.
Fix: Replace with `except Exception as e:` or catch the specific type.
```

## Tone

- Be direct and specific — vague feedback is not actionable.
- Explain *why* something is a problem, not just *what* is wrong.
- Acknowledge good decisions in the Summary only — never in a per-issue finding.
- Ask a question if something is genuinely ambiguous — don't assume the worst.
- Never nitpick what is not in the developer guidelines.

## Wording

A developer and a fixing agent both act on each finding. Write it so neither has to guess.

- Match the words to the confidence score. State a failure you traced flat: "crashes when `user`
  is `None`". Below 90, write "can" or "likely", never "will".
- One claim per sentence. Name the code that acts: "`save()` drops the error", not "the error is
  dropped". No semicolons.
- Use one name for each function, file, and concept across the whole review. Two findings about
  one object must not use two names for it.
- Open each finding with its trigger: the inputs or environment that cause the failure.
- Write each finding's description as one paragraph.
- Keep each snippet that quotes the problem code to 3 lines or fewer. Suggestion blocks and fix
  snippets are exempt.
- Never state a priority or an impact higher than the evidence shows.
