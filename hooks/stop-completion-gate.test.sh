#!/usr/bin/env bash
# Regression tests for stop-completion-gate.sh — specifically the bug where the
# hook picked an active slug by grepping every "agent-spec/<slug>" string ever
# mentioned in the transcript and falling back to "most recently modified
# matching file" among those candidates. That let a stale, unrelated session's
# still-open code-review.md win by elimination whenever the CURRENT session's
# own state file hadn't been written yet — blocking Stop forever on someone
# else's work. The fix scopes strictly to the active slug published at
# ~/.claude/session-slugs/<session_id>; these tests pin that behavior down so
# it can't regress silently.
#
# Run: bash stop-completion-gate.test.sh
# Exits non-zero (and prints which case failed) if any assertion fails.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/stop-completion-gate.sh"

failures=0
pass_count=0

# Runs the hook in an isolated temp $HOME/cwd, feeding it stdin JSON.
# Args: workdir  session_id  state_filename  open_pattern  label
run_hook() {
  local workdir="$1" session_id="$2" state_filename="$3" open_pattern="$4" label="$5"
  local json
  if [ -n "$session_id" ]; then
    json=$(printf '{"session_id":"%s"}' "$session_id")
  else
    json='{}'
  fi
  ( cd "$workdir" && HOME="$workdir/home" printf '%s' "$json" | HOME="$workdir/home" bash "$HOOK" "$state_filename" "$open_pattern" "$label" )
}

assert_exit() {
  local description="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass_count=$((pass_count + 1))
    echo "PASS: $description"
  else
    failures=$((failures + 1))
    echo "FAIL: $description (expected exit $expected, got $actual)"
  fi
}

new_workdir() {
  local d
  d=$(mktemp -d)
  mkdir -p "$d/home/.claude/session-slugs"
  mkdir -p "$d/agent-spec"
  printf '%s' "$d"
}

publish_slug() {
  local workdir="$1" session_id="$2" slug="$3"
  printf '%s' "$slug" > "$workdir/home/.claude/session-slugs/$session_id"
}

write_state_file() {
  local workdir="$1" slug="$2" filename="$3" content="$4"
  mkdir -p "$workdir/agent-spec/$slug"
  printf '%s' "$content" > "$workdir/agent-spec/$slug/$filename"
}

# --- Case 1 (THE REGRESSION): active slug's own state file does not exist yet,
# but an unrelated slug — merely present under agent-spec/, standing in for
# "mentioned somewhere in the transcript" in the old buggy version — has an
# OPEN marker. The hook must NOT block: it has nothing to gate for the active
# slug, and must never fall through to a different slug's file.
w=$(new_workdir)
publish_slug "$w" "sess-1" "2026-07-29-active-slug"
write_state_file "$w" "2026-07-28-unrelated-slug" "code-review.md" "some finding
Status: ❌ Open"
run_hook "$w" "sess-1" "code-review.md" "❌ Open" "code-review" >/tmp/out.$$ 2>&1
code=$?
assert_exit "regression: unrelated slug's open marker must not block when active slug has no file" 0 "$code"
rm -rf "$w" /tmp/out.$$

# --- Case 2: active slug's OWN state file has an open marker — must block (exit 2).
w=$(new_workdir)
publish_slug "$w" "sess-2" "2026-07-29-active-slug"
write_state_file "$w" "2026-07-29-active-slug" "code-review.md" "some finding
Status: ❌ Open"
run_hook "$w" "sess-2" "code-review.md" "❌ Open" "code-review" >/tmp/out.$$ 2>&1
code=$?
assert_exit "active slug's own open marker must block" 2 "$code"
rm -rf "$w" /tmp/out.$$

# --- Case 3: active slug's own state file is fully resolved (no open marker) — must not block.
w=$(new_workdir)
publish_slug "$w" "sess-3" "2026-07-29-active-slug"
write_state_file "$w" "2026-07-29-active-slug" "code-review.md" "no open findings
Status: ✅ Clean"
run_hook "$w" "sess-3" "code-review.md" "❌ Open" "code-review" >/tmp/out.$$ 2>&1
code=$?
assert_exit "active slug's own resolved file must not block" 0 "$code"
rm -rf "$w" /tmp/out.$$

# --- Case 4: an unrelated slug is open AND the active slug is also open —
# must still block (exit 2), scoped to the active slug's own content, not
# because the unrelated one is open.
w=$(new_workdir)
publish_slug "$w" "sess-4" "2026-07-29-active-slug"
write_state_file "$w" "2026-07-28-unrelated-slug" "code-review.md" "Status: ❌ Open"
write_state_file "$w" "2026-07-29-active-slug" "code-review.md" "Status: ❌ Open"
run_hook "$w" "sess-4" "code-review.md" "❌ Open" "code-review" >/tmp/out.$$ 2>&1
code=$?
assert_exit "active slug open + unrelated slug open: still blocks on the active slug's own item" 2 "$code"
rm -rf "$w" /tmp/out.$$

# --- Case 5: no session_id at all and no agent-spec dirs — nothing to gate, exit 0.
w=$(new_workdir)
run_hook "$w" "" "code-review.md" "❌ Open" "code-review" >/tmp/out.$$ 2>&1
code=$?
assert_exit "no session_id, no agent-spec dirs: exit 0" 0 "$code"
rm -rf "$w" /tmp/out.$$

# --- Case 5b: no session_id at all, but an unrelated slug IS open — must not
# guess from it. "Can't resolve the active slug" always means "nothing to
# gate", never "fall back to whatever is on disk".
w=$(new_workdir)
write_state_file "$w" "2026-07-28-unrelated-slug" "code-review.md" "Status: ❌ Open"
run_hook "$w" "" "code-review.md" "❌ Open" "code-review" >/tmp/out.$$ 2>&1
code=$?
assert_exit "empty session_id must never guess from an unrelated open slug" 0 "$code"
rm -rf "$w" /tmp/out.$$

# --- Case 6: session_id given but unresolvable (no session-slugs file for it) —
# must NOT fall back to scanning agent-spec/* even if an unrelated slug is open;
# unresolvable means "don't guess", not "guess from anything available".
w=$(new_workdir)
write_state_file "$w" "2026-07-28-unrelated-slug" "code-review.md" "Status: ❌ Open"
run_hook "$w" "sess-unknown" "code-review.md" "❌ Open" "code-review" >/tmp/out.$$ 2>&1
code=$?
assert_exit "unresolvable session_id must not fall back to scanning other slugs" 0 "$code"
rm -rf "$w" /tmp/out.$$

# --- Scenario block: many OLD, no-longer-relevant slugs littering agent-spec/
# with genuinely unfinished/open work — the exact real-world shape of the bug
# (a repo accumulates dozens of past sessions' folders over weeks; several are
# old, abandoned, and were simply never marked done). The active slug must
# stay correctly scoped no matter how much stale open work is lying around, in
# what file, or under what naming pattern.

# --- Case 8: several old dated slugs, each genuinely unfinished (open
# tasks.md AND open code-review.md), sitting alongside a clean active slug —
# must not block, regardless of how many stale candidates exist.
w=$(new_workdir)
publish_slug "$w" "sess-8" "2026-07-29-active-slug"
write_state_file "$w" "2026-07-29-active-slug" "code-review.md" "Status: ✅ Clean"
write_state_file "$w" "2026-06-01-ancient-feature" "code-review.md" "Status: ❌ Open"
write_state_file "$w" "2026-06-01-ancient-feature" "tasks.md" "- [ ] never finished this"
write_state_file "$w" "2026-06-15-abandoned-spike" "code-review.md" "Status: ❌ Open"
write_state_file "$w" "2026-07-01-half-done-refactor" "tasks.md" "- [ ] still not done"
run_hook "$w" "sess-8" "code-review.md" "❌ Open" "code-review" >/tmp/out.$$ 2>&1
code=$?
assert_exit "many old unfinished slugs present: active slug's clean file still wins, exit 0" 0 "$code"
rm -rf "$w" /tmp/out.$$

# --- Case 9: same pile of old unfinished slugs, but the ACTIVE slug's own
# code-review.md doesn't exist yet — must exit 0 (nothing to gate for this
# session), never fall through to one of the old stale slugs just because
# they happen to have a matching, open file.
w=$(new_workdir)
publish_slug "$w" "sess-9" "2026-07-29-active-slug"
write_state_file "$w" "2026-06-01-ancient-feature" "code-review.md" "Status: ❌ Open"
write_state_file "$w" "2026-06-15-abandoned-spike" "code-review.md" "Status: ❌ Open"
run_hook "$w" "sess-9" "code-review.md" "❌ Open" "code-review" >/tmp/out.$$ 2>&1
code=$?
assert_exit "old unfinished slugs present, active slug has no file of its own: exit 0" 0 "$code"
rm -rf "$w" /tmp/out.$$

# --- Case 10: an old slug's UNFINISHED tasks.md (different state filename,
# different open-marker convention — "- [ ]" not "❌ Open") must never leak
# into a code-review.md gate check, even though both are "open work" in a
# loose sense. The state-filename parameter must stay a hard boundary.
w=$(new_workdir)
publish_slug "$w" "sess-10" "2026-07-29-active-slug"
write_state_file "$w" "2026-07-29-active-slug" "code-review.md" "Status: ✅ Clean"
write_state_file "$w" "2026-06-20-old-code-gen-run" "tasks.md" "- [ ] unfinished task from weeks ago
- 🔄 still in progress supposedly"
run_hook "$w" "sess-10" "code-review.md" "❌ Open" "code-review" >/tmp/out.$$ 2>&1
code=$?
assert_exit "old slug's unfinished tasks.md must not leak into a code-review.md gate check" 0 "$code"
rm -rf "$w" /tmp/out.$$

# --- Case 11: the SAME scenario as Case 10, but this time gating on tasks.md
# with the tasks.md open pattern (code-gen's own convention) — the old,
# irrelevant slug's unfinished tasks.md must still never be picked over the
# active slug having none of its own, in either direction.
w=$(new_workdir)
publish_slug "$w" "sess-11" "2026-07-29-active-slug"
write_state_file "$w" "2026-06-20-old-code-gen-run" "tasks.md" "- [ ] unfinished task from weeks ago"
run_hook "$w" "sess-11" "tasks.md" '^\s*- \[ \]|^\s*- 🔄' "code-gen" >/tmp/out.$$ 2>&1
code=$?
assert_exit "old slug's unfinished tasks.md never picked when active slug has no tasks.md" 0 "$code"
rm -rf "$w" /tmp/out.$$

# --- Case 12: active slug DOES have its own genuinely unfinished tasks.md —
# must correctly block on ITS OWN content even with old unrelated unfinished
# slugs also present, proving the fix didn't overcorrect into never blocking.
w=$(new_workdir)
publish_slug "$w" "sess-12" "2026-07-29-active-slug"
write_state_file "$w" "2026-07-29-active-slug" "tasks.md" "- [ ] this session's own unfinished task"
write_state_file "$w" "2026-06-20-old-code-gen-run" "tasks.md" "- [ ] ancient unrelated unfinished task"
run_hook "$w" "sess-12" "tasks.md" '^\s*- \[ \]|^\s*- 🔄' "code-gen" >/tmp/out.$$ 2>&1
code=$?
assert_exit "active slug's own genuinely unfinished tasks.md still blocks correctly" 2 "$code"
rm -rf "$w" /tmp/out.$$

# --- Case 7: retry cap releases the block on the 7th call and resets the counter.
# The hook increments its counter before checking (n starts at 1 on the first
# call), so calls 1-6 block and the 7th call is the one that hits n>=7 and
# releases — not an 8th call (Claude Code's own cap is 8 consecutive blocks).
w=$(new_workdir)
publish_slug "$w" "sess-7" "2026-07-29-active-slug"
write_state_file "$w" "2026-07-29-active-slug" "code-review.md" "Status: ❌ Open"
last_code=""
for _ in $(seq 1 6); do
  run_hook "$w" "sess-7" "code-review.md" "❌ Open" "code-review" >/tmp/out.$$ 2>&1
  last_code=$?
done
assert_exit "6th retry still blocks" 2 "$last_code"
run_hook "$w" "sess-7" "code-review.md" "❌ Open" "code-review" >/tmp/out.$$ 2>&1
code=$?
assert_exit "7th retry releases the block (cap reached)" 0 "$code"
retry_file="$w/agent-spec/2026-07-29-active-slug/.stop-hook-retries"
if [ -f "$retry_file" ]; then
  failures=$((failures + 1))
  echo "FAIL: retry counter file should be removed once the cap releases the block"
else
  pass_count=$((pass_count + 1))
  echo "PASS: retry counter file removed once the cap releases the block"
fi

# --- Case 7b: evidence-grounded regression, found in this hook's own dev-testing
# transcript (session e22f668c, simulated slug-a/slug-b interference) — after the
# cap releases (a one-time reprieve so the model can self-diagnose), if the file
# is STILL open on the very next call, the hook must re-block starting from
# retry 1/7 again — not stay permanently released, and not skip straight back
# to a high retry count from stale state.
run_hook "$w" "sess-7" "code-review.md" "❌ Open" "code-review" >/tmp/out.$$ 2>&1
code=$?
assert_exit "still-open file re-blocks immediately after the cap released once" 2 "$code"
if grep -q "retry 1/7" /tmp/out.$$; then
  pass_count=$((pass_count + 1))
  echo "PASS: retry counter restarted at 1/7 after the cap-release reset it"
else
  failures=$((failures + 1))
  echo "FAIL: expected retry counter to restart at 1/7 after the cap-release reset it"
  cat /tmp/out.$$
fi
rm -rf "$w" /tmp/out.$$

# --- Further edge cases: malformed/adversarial inputs the mechanism must
# survive without misbehaving, even though none of these caused the original
# bug directly — worth locking in given how easily "which slug am I" logic can
# regress again.

# --- Case 13: two DIFFERENT sessions each have their own published slug and
# their own state file in the SAME repo at the SAME time (the normal
# concurrent-sessions case this repo's CLAUDE.md explicitly calls out) — each
# session's hook invocation must see only its own slug's file, never the
# other's, regardless of which one is open/closed.
w=$(new_workdir)
publish_slug "$w" "sess-13a" "2026-07-29-session-a"
publish_slug "$w" "sess-13b" "2026-07-29-session-b"
write_state_file "$w" "2026-07-29-session-a" "code-review.md" "Status: ❌ Open"
write_state_file "$w" "2026-07-29-session-b" "code-review.md" "Status: ✅ Clean"
run_hook "$w" "sess-13a" "code-review.md" "❌ Open" "code-review" >/tmp/out.$$ 2>&1
assert_exit "session A sees only its own open file, blocks" 2 "$?"
run_hook "$w" "sess-13b" "code-review.md" "❌ Open" "code-review" >/tmp/out.$$ 2>&1
assert_exit "session B sees only its own clean file, does not block" 0 "$?"
rm -rf "$w" /tmp/out.$$

# --- Case 14: the retry counter file is corrupted (non-numeric content) —
# e.g. from an interrupted write or a manually-edited file. The hook must not
# crash (bash arithmetic on a non-numeric string errors under `set -u`/strict
# contexts); it should behave sanely rather than exiting with an uncaught
# error that would look like a silent, unexplained pass-through.
w=$(new_workdir)
publish_slug "$w" "sess-14" "2026-07-29-active-slug"
write_state_file "$w" "2026-07-29-active-slug" "code-review.md" "Status: ❌ Open"
mkdir -p "$w/agent-spec/2026-07-29-active-slug"
printf 'not-a-number' > "$w/agent-spec/2026-07-29-active-slug/.stop-hook-retries"
run_hook "$w" "sess-14" "code-review.md" "❌ Open" "code-review" >/tmp/out.$$ 2>&1
code=$?
if [ "$code" = "2" ] || [ "$code" = "0" ]; then
  pass_count=$((pass_count + 1))
  echo "PASS: corrupted retry counter does not crash the hook (exit $code, not an uncaught error)"
else
  failures=$((failures + 1))
  echo "FAIL: corrupted retry counter produced an unexpected exit code: $code"
  cat /tmp/out.$$
fi
rm -rf "$w" /tmp/out.$$

# --- Case 15: the published slug file is empty (published but blank — e.g. a
# torn write) — must be treated as unresolved (same as no file at all), never
# as an active slug named "" that happens to path-join into "agent-spec//<file>".
w=$(new_workdir)
: > "$w/home/.claude/session-slugs/sess-15"
write_state_file "$w" "2026-07-28-unrelated-slug" "code-review.md" "Status: ❌ Open"
run_hook "$w" "sess-15" "code-review.md" "❌ Open" "code-review" >/tmp/out.$$ 2>&1
code=$?
assert_exit "empty published slug file is treated as unresolved, not as slug \"\"" 0 "$code"
rm -rf "$w" /tmp/out.$$

# --- Case 16: the active slug's state file exists but is completely empty
# (e.g. a freshly-`touch`ed placeholder before the skill has written real
# content yet) — grep against an empty file finds no match, so this must not
# block, the same as "no open marker" rather than erroring on an empty file.
w=$(new_workdir)
publish_slug "$w" "sess-16" "2026-07-29-active-slug"
mkdir -p "$w/agent-spec/2026-07-29-active-slug"
: > "$w/agent-spec/2026-07-29-active-slug/code-review.md"
run_hook "$w" "sess-16" "code-review.md" "❌ Open" "code-review" >/tmp/out.$$ 2>&1
code=$?
assert_exit "completely empty state file: no match, does not block" 0 "$code"
rm -rf "$w" /tmp/out.$$

# --- Case 17: the active slug string itself contains a slash (e.g. a
# corrupted/adversarial publish, or a future slug format change gone wrong) —
# must not silently escape agent-spec/ into an arbitrary path. Document
# current behavior explicitly rather than leaving it unspecified: the hook
# does no path sanitization, so this is a real (currently low-risk, since only
# the trusted session-slug skill ever writes this file) latent gap — this test
# exists so a future change to how slugs are generated doesn't introduce path
# traversal without anyone noticing the hook has no defense here.
w=$(new_workdir)
publish_slug "$w" "sess-17" "../../../../etc/passwd"
run_hook "$w" "sess-17" "code-review.md" "❌ Open" "code-review" >/tmp/out.$$ 2>&1
code=$?
assert_exit "path-like slug with no matching file still resolves to exit 0 (no crash, no false block)" 0 "$code"
rm -rf "$w" /tmp/out.$$

# --- %HARNESS% token tests --------------------------------------------------
# Added alongside guideline-checker / multi-harness-parallel code-review and
# arch-verify: a state_filename containing the literal token %HARNESS% resolves
# against files named <base>.<harness>-<model>.md, scoped to THIS session's own
# harness (never a guess across harnesses or models). These discover the REAL
# harness token via the same agent-env.sh the hook sources, so they assert
# behavior without hardcoding a token that would only be correct in one harness.
REAL_HARNESS="$(. "$SCRIPT_DIR/agent-env.sh" && agent_harness)"

# --- Case 18: %HARNESS%, no matching file yet — exit 0 (nothing written yet,
# same semantics as the literal-filename "no file" case).
w=$(new_workdir)
publish_slug "$w" "sess-18" "2026-08-24-active-slug"
run_hook "$w" "sess-18" "code-review.%HARNESS%.md" "❌ Open" "code-review" >/tmp/out.$$ 2>&1
code=$?
assert_exit "%HARNESS%: no file yet, exit 0" 0 "$code"
rm -rf "$w" /tmp/out.$$

# --- Case 19: %HARNESS%, exactly one matching file, open — blocks (exit 2).
w=$(new_workdir)
publish_slug "$w" "sess-19" "2026-08-24-active-slug"
write_state_file "$w" "2026-08-24-active-slug" "code-review.$REAL_HARNESS-sonnet-5.md" "Status: ❌ Open"
run_hook "$w" "sess-19" "code-review.%HARNESS%.md" "❌ Open" "code-review" >/tmp/out.$$ 2>&1
code=$?
assert_exit "%HARNESS%: one matching harness file, open, blocks" 2 "$code"
rm -rf "$w" /tmp/out.$$

# --- Case 20: %HARNESS%, exactly one matching file, resolved — exit 0.
w=$(new_workdir)
publish_slug "$w" "sess-20" "2026-08-24-active-slug"
write_state_file "$w" "2026-08-24-active-slug" "code-review.$REAL_HARNESS-sonnet-5.md" "Status: ✅ Clean"
run_hook "$w" "sess-20" "code-review.%HARNESS%.md" "❌ Open" "code-review" >/tmp/out.$$ 2>&1
code=$?
assert_exit "%HARNESS%: one matching harness file, resolved, exit 0" 0 "$code"
rm -rf "$w" /tmp/out.$$

# --- Case 21: %HARNESS%, two files for the SAME harness but different models —
# genuine ambiguity (e.g. two models under one harness reviewing the same slug
# at once). NEVER GUESS which one is "this" session's; exit 0 even though both
# are open.
w=$(new_workdir)
publish_slug "$w" "sess-21" "2026-08-24-active-slug"
write_state_file "$w" "2026-08-24-active-slug" "code-review.$REAL_HARNESS-sonnet-5.md" "Status: ❌ Open"
write_state_file "$w" "2026-08-24-active-slug" "code-review.$REAL_HARNESS-opus-5.md" "Status: ❌ Open"
run_hook "$w" "sess-21" "code-review.%HARNESS%.md" "❌ Open" "code-review" >/tmp/out.$$ 2>&1
code=$?
assert_exit "%HARNESS%: two files, same harness, different models — ambiguous, never guesses, exit 0" 0 "$code"
rm -rf "$w" /tmp/out.$$

# --- Case 22: a DIFFERENT harness's open file exists and is the only
# code-review.*.md present — must not be picked up as this session's file just
# because nothing else matches by filename alone.
w=$(new_workdir)
publish_slug "$w" "sess-22" "2026-08-24-active-slug"
write_state_file "$w" "2026-08-24-active-slug" "code-review.other-harness-gpt-5.md" "Status: ❌ Open"
run_hook "$w" "sess-22" "code-review.%HARNESS%.md" "❌ Open" "code-review" >/tmp/out.$$ 2>&1
code=$?
assert_exit "%HARNESS%: a different harness's open file is not picked up, exit 0" 0 "$code"
rm -rf "$w" /tmp/out.$$

# --- Case 23: literal-filename behavior (no %HARNESS% token) must remain
# completely unaffected — the existing code-gen/tasks.md path.
w=$(new_workdir)
publish_slug "$w" "sess-23" "2026-08-24-active-slug"
write_state_file "$w" "2026-08-24-active-slug" "tasks.md" "- [ ] still open"
run_hook "$w" "sess-23" "tasks.md" '^\s*- \[ \]' "code-gen" >/tmp/out.$$ 2>&1
code=$?
assert_exit "literal filename (no %HARNESS%) path is unaffected, still blocks" 2 "$code"
rm -rf "$w" /tmp/out.$$

echo ""
echo "$pass_count passed, $failures failed"
[ "$failures" -eq 0 ]
