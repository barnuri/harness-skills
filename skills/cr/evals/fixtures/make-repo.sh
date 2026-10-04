#!/usr/bin/env bash
# Shared fixture builder for the commit-anchoring eval cases.
# Builds a small git repo in the eval workspace:
#   commit A ("base")  — auth/login.py with a bare except that the prior review did NOT flag
#   commit B ("head")  — payments/refund.py with a real null-safety bug
# Callers pick which commits to create and whether to seed a prior tracker file.
set -euo pipefail

git init -q .
git config user.email eval@example.com
git config user.name "Eval Fixture"
printf 'agent-spec/\n' > .gitignore

mkdir -p auth payments
cat > auth/login.py <<'PY'
def login(user, password):
    try:
        return user.check(password)
    except:
        return False
PY
git add -A
git commit -qm "base: auth login"
BASE=$(git rev-parse --short HEAD)

if [ "${WITH_HEAD_COMMIT:-1}" = "1" ]; then
  cat > payments/refund.py <<'PY'
def refund_amount(order_id):
    order = db.find_order(order_id)  # documented as returning Optional[Order]
    return order.total * 0.9
PY
  git add -A
  git commit -qm "feat: refund helper"
fi
HEAD_HASH=$(git rev-parse --short HEAD)

# Seed a prior review tracker unless the case wants a virgin repo.
if [ -n "${SEED_ANCHOR:-}" ]; then
  case "$SEED_ANCHOR" in
    base) ANCHOR="$BASE" ;;
    head) ANCHOR="$HEAD_HASH" ;;
    *)    ANCHOR="$SEED_ANCHOR" ;;   # literal, e.g. a dangling hash
  esac
  mkdir -p "agent-spec/${SLUG:-refund-review}"
  cat > "agent-spec/${SLUG:-refund-review}/code-review.eval.md" <<MD
---
Created: 2026-09-01 10:00
Last Updated: 2026-09-01 10:00
Reviewed-Commit: ${ANCHOR}
Reviewed-Commit-Previous: none
Review-Scope: full
---

# Code Review

**Reviewed:** git diff
**Last checked:** 2026-09-01 at commit \`${ANCHOR}\`
**Scope this run:** full diff
**Overall:** Needs work

## Summary
Prior pass reviewed everything up to ${ANCHOR}.

## Issues Tracker

| ID | File:Line | Severity | Description | Status | Notes |
|----|-----------|----------|-------------|--------|-------|
| CR-1 | auth/login.py:4 | Important (82) | Bare \`except:\` swallows SystemExit/KeyboardInterrupt | ❌ Open | Catch \`Exception\` explicitly |
| CR-2 | auth/login.py:2 | Important (80) | \`login\` has no unit test | ❌ Open | Add tests/auth/test_login.py |
MD
fi

echo "BASE=$BASE HEAD=$HEAD_HASH"
