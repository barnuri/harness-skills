# Review Feedback Format

## Per-Issue Format

```
**[SEVERITY]** `path/to/file.py:line` — confidence: 92
> Brief description of the problem.

Why it matters: [one sentence on the impact]
Fix: [concrete fix or alternative code snippet]
```

**Severity levels:**
- `BLOCKER` — must fix before merge (correctness, security, data loss)
- `IMPORTANT` — should fix (guideline violation, maintainability debt)

## Full Review Format

```markdown
## Code Review

### Summary
[Overall assessment: what is good, what needs attention, merge readiness.]

### Blockers
**[BLOCKER]** `auth/login.py:42` — confidence: 95
> Password compared with `==` instead of constant-time function.
Why it matters: Timing attacks can leak partial password matches.
Fix: Use `hmac.compare_digest(stored_hash, input_hash)`.

### Important Issues
**[IMPORTANT]** `agents/runner.py:18` — confidence: 82
> Bare `except:` catches SystemExit and KeyboardInterrupt.
Why it matters: Hides unrelated crashes and prevents clean shutdown.
Fix: Replace with `except Exception as e:` or catch the specific type.
```

## Tone

- Be direct and specific — vague feedback is not actionable.
- Explain *why* something is a problem, not just *what* is wrong.
- Acknowledge good decisions when present — a review is a conversation, not an audit.
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
