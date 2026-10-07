#!/usr/bin/env bash
# Tests for usage-snapshot.sh — the status-line wrapper that captures api/rate_limits
# to ~/.claude/usage-snapshot.json for the `handoff` skill.
#
# The invariant worth protecting is "never break the status line": this script runs
# every ~2 seconds and owns a piece of the user's UI, so no failure mode (missing jq,
# unwritable snapshot path, empty or malformed stdin, absent downstream command) may
# swallow the downstream output or exit non-zero. These cases pin that down.
#
# Run: bash usage-snapshot.test.sh
# Exits non-zero (and prints which case failed) if any assertion fails.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/usage-snapshot.sh"

DOWNSTREAM_MARKER="STATUSLINE_OK:"
VALID_STATUS_JSON='{"session_id":"sess-1","api":{"type":"subscription","plan":"max"},"rate_limits":{"five_hour":{"used_percentage":91,"resets_at":1754260000},"seven_day":{"used_percentage":40}},"context_window":{"used_percentage":12}}'

failures=0
pass_count=0

new_workdir() {
  local d
  d=$(mktemp -d)
  mkdir -p "$d/home/.claude"
  # Stub downstream status line: proves the wrapper passed stdin through verbatim.
  printf '%s\n' '#!/usr/bin/env bash' "printf '%s' \"$DOWNSTREAM_MARKER\"" 'cat' > "$d/stub-statusline.sh"
  printf '%s' "$d"
}

# Runs the wrapper with an isolated HOME and a stub downstream.
# Args: workdir  stdin  [statusline_cmd_override]  [snapshot_path_override]
run_hook() {
  local workdir="$1" stdin="$2" cmd_override="${3:-}" snapshot_override="${4:-}"
  local cmd="bash $workdir/stub-statusline.sh"
  [ -n "$cmd_override" ] && cmd="$cmd_override"
  local snapshot="$workdir/home/.claude/usage-snapshot.json"
  [ -n "$snapshot_override" ] && snapshot="$snapshot_override"
  printf '%s' "$stdin" | HOME="$workdir/home" \
    CLAUDE_STATUSLINE_CMD="$cmd" \
    CLAUDE_USAGE_SNAPSHOT="$snapshot" \
    bash "$HOOK"
}

assert_eq() {
  local description="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass_count=$((pass_count + 1))
    echo "PASS: $description"
  else
    failures=$((failures + 1))
    echo "FAIL: $description (expected '$expected', got '$actual')"
  fi
}

assert_contains() {
  local description="$1" needle="$2" haystack="$3"
  case "$haystack" in
    *"$needle"*)
      pass_count=$((pass_count + 1))
      echo "PASS: $description"
      ;;
    *)
      failures=$((failures + 1))
      echo "FAIL: $description (expected to contain '$needle', got '$haystack')"
      ;;
  esac
}

# --- Case 1: snapshot captures api + rate_limits from valid statusline JSON.
w=$(new_workdir)
run_hook "$w" "$VALID_STATUS_JSON" >/dev/null 2>&1
snapshot=$(cat "$w/home/.claude/usage-snapshot.json" 2>/dev/null || echo "")
assert_contains "case1: snapshot records subscription api type" '"type":"subscription"' "$snapshot"
assert_contains "case1: snapshot records five_hour usage" '91' "$snapshot"
if command -v jq >/dev/null 2>&1; then
  captured=$(printf '%s' "$snapshot" | jq -r '.captured_at // ""' 2>/dev/null)
  assert_contains "case1: snapshot stamps captured_at" "T" "$captured"
  pct=$(printf '%s' "$snapshot" | jq -r '.rate_limits.five_hour.used_percentage // ""' 2>/dev/null)
  assert_eq "case1: snapshot is valid JSON readable by jq" "91" "$pct"
else
  echo "SKIP: case1 jq assertions (jq not installed)"
fi

# --- Case 2: downstream receives stdin verbatim and its output reaches stdout.
w=$(new_workdir)
out=$(run_hook "$w" "$VALID_STATUS_JSON" 2>/dev/null)
assert_eq "case2: passthrough output intact" "$DOWNSTREAM_MARKER$VALID_STATUS_JSON" "$out"

# --- Case 3: empty stdin must not crash and must not write a snapshot.
w=$(new_workdir)
run_hook "$w" "" >/dev/null 2>&1
assert_eq "case3: empty stdin exits 0" "0" "$?"
if [ -f "$w/home/.claude/usage-snapshot.json" ]; then
  failures=$((failures + 1))
  echo "FAIL: case3: empty stdin wrote a snapshot"
else
  pass_count=$((pass_count + 1))
  echo "PASS: case3: empty stdin wrote no snapshot"
fi

# --- Case 4: malformed (non-JSON) stdin still exits 0, still passes through, and must
# NOT clobber a previously captured good snapshot with unparseable content.
w=$(new_workdir)
run_hook "$w" "$VALID_STATUS_JSON" >/dev/null 2>&1
out=$(run_hook "$w" "not json at all {{{" 2>/dev/null)
assert_eq "case4: malformed stdin exits 0" "0" "$?"
assert_eq "case4: malformed stdin still passes through" "${DOWNSTREAM_MARKER}not json at all {{{" "$out"
if command -v jq >/dev/null 2>&1; then
  snapshot=$(cat "$w/home/.claude/usage-snapshot.json" 2>/dev/null || echo "")
  assert_contains "case4: last good snapshot survives malformed stdin" '"type":"subscription"' "$snapshot"
else
  echo "SKIP: case4 snapshot-preservation assertion (jq not installed)"
fi

# --- Case 5b: no jq on PATH — snapshot falls back to stdin verbatim, still passes through.
w=$(new_workdir)
mkdir -p "$w/bin"
for tool in bash cat dirname mkdir mv rm date; do
  tool_path=$(command -v "$tool" 2>/dev/null) && ln -sf "$tool_path" "$w/bin/$tool"
done
out=$(printf '%s' "$VALID_STATUS_JSON" \
  | HOME="$w/home" \
    PATH="$w/bin" \
    CLAUDE_STATUSLINE_CMD="bash $w/stub-statusline.sh" \
    CLAUDE_USAGE_SNAPSHOT="$w/home/.claude/usage-snapshot.json" \
    bash "$HOOK" 2>/dev/null)
assert_eq "case5b: no-jq fallback still passes through" "$DOWNSTREAM_MARKER$VALID_STATUS_JSON" "$out"
snapshot=$(cat "$w/home/.claude/usage-snapshot.json" 2>/dev/null || echo "")
assert_contains "case5b: no-jq fallback writes stdin verbatim" '"type":"subscription"' "$snapshot"

# --- Case 5: unwritable snapshot path must not break the status line.
w=$(new_workdir)
mkdir -p "$w/locked"
chmod 500 "$w/locked"
out=$(run_hook "$w" "$VALID_STATUS_JSON" "" "$w/locked/nested/usage-snapshot.json" 2>/dev/null)
assert_eq "case5: unwritable snapshot path exits 0" "0" "$?"
assert_eq "case5: unwritable snapshot path still passes through" "$DOWNSTREAM_MARKER$VALID_STATUS_JSON" "$out"
chmod 700 "$w/locked"

# --- Case 6: missing downstream command exits 0 quietly (snapshot still captured).
w=$(new_workdir)
out=$(run_hook "$w" "$VALID_STATUS_JSON" "definitely-not-a-real-binary-xyz --flag" 2>/dev/null)
assert_eq "case6: missing downstream command exits 0" "0" "$?"
assert_eq "case6: missing downstream command emits nothing" "" "$out"
snapshot=$(cat "$w/home/.claude/usage-snapshot.json" 2>/dev/null || echo "")
assert_contains "case6: snapshot still captured without downstream" '"type":"subscription"' "$snapshot"

# --- Case 7: no leftover temp files next to the snapshot.
w=$(new_workdir)
run_hook "$w" "$VALID_STATUS_JSON" >/dev/null 2>&1
leftovers=$(find "$w/home/.claude" -name 'usage-snapshot.json.tmp*' 2>/dev/null | wc -l | tr -d ' ')
assert_eq "case7: no temp files left behind" "0" "$leftovers"

# --- Case 8: with no hooks/local.env beside the script, ~/.config/harness-skills/hooks/local.env is sourced.
w=$(new_workdir)
cp "$HOOK" "$w/usage-snapshot.sh"
mkdir -p "$w/home/.config/harness-skills/hooks"
printf 'CLAUDE_STATUSLINE_CMD="bash %s/stub-statusline.sh"\n' "$w" > "$w/home/.config/harness-skills/hooks/local.env"
out=$(printf '%s' "$VALID_STATUS_JSON" | env -u CLAUDE_STATUSLINE_CMD HOME="$w/home" \
  CLAUDE_USAGE_SNAPSHOT="$w/home/.claude/usage-snapshot.json" bash "$w/usage-snapshot.sh" 2>/dev/null)
assert_eq "case8: config-dir local.env sets the downstream command" "$DOWNSTREAM_MARKER$VALID_STATUS_JSON" "$out"

echo
echo "$pass_count passed, $failures failed"
[ "$failures" -eq 0 ] || exit 1
