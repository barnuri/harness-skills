# Code Review Checklist

Use this as a quick reference during review. Full rules are in the coding standards resolved by `cr/SKILL.md`.

## Correctness

- [ ] Code does what it claims — logic is correct
- [ ] Edge cases and null/empty inputs handled
- [ ] No off-by-one errors or incorrect boolean logic
- [ ] Exceptions caught at the right level and handled meaningfully (not swallowed)

## Robustness

- [ ] Transient failures (timeouts, network errors, rate-limit responses) are retried with backoff — not propagated immediately to the caller
- [ ] Retry caps (max attempts) and delay strategies are explicit constants, not magic numbers
- [ ] Non-transient errors (auth failures, bad requests) exit immediately without retrying

## Security

- [ ] No hardcoded secrets or credentials
- [ ] User inputs validated before use
- [ ] No injection risks (SQL, shell, path traversal)
- [ ] No sensitive data logged or exposed

## Developer Guidelines, Python-Specific, TypeScript-Specific, Design & Maintainability

Owned by the resolved coding standards — do not restate here (with `dev-guidelines`
installed: `coding-principles.md` and its language files, including the **Unit Test
Coverage** section).
