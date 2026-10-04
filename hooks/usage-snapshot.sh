#!/usr/bin/env bash
# Status-line wrapper that captures the subscription/rate-limit snapshot the
# `handoff` skill needs, then hands the untouched JSON to the real status line.
#
# WHY THIS EXISTS: Claude Code delivers `api.type` (subscription vs api_key) and
# `rate_limits` (session / five_hour / day / week / seven_day, each with
# used_percentage + resets_at) on the **status line command's stdin only**. Skills,
# subagents, and Stop/PreToolUse hooks never see them, so a skill cannot ask "how
# much of my daily/weekly budget is left?" on its own. This wrapper is the only
# place that JSON is observable, so it snapshots it to a well-known file that any
# skill can read later.
#
# Usage (from ~/.claude/settings.json):
#   "statusLine": {
#     "type": "command",
#     "command": "CLAUDE_STATUSLINE_CMD='<your status line command>' bash <repo>/hooks/usage-snapshot.sh",
#     "refreshInterval": 2000
#   }
#
# Env:
#   CLAUDE_STATUSLINE_CMD    downstream status line command (none: snapshot only, no output).
#                            May be set in an optional, untracked hooks/local.env next to this script.
#   CLAUDE_USAGE_SNAPSHOT    snapshot destination (default ~/.claude/usage-snapshot.json).
#
# HARD RULE — never break the status line. It re-runs every couple of seconds and
# its stdout is UI, so every step here is best-effort: a missing jq, an unwritable
# snapshot path, malformed stdin, or a missing downstream command must all still
# end in a clean exit 0 with the downstream output (if any) intact.

set -u

local_env="$(dirname "${BASH_SOURCE[0]}")/local.env"
# shellcheck source=/dev/null
[ -f "$local_env" ] && . "$local_env" 2>/dev/null
statusline_cmd="${CLAUDE_STATUSLINE_CMD:-}"
snapshot_path="${CLAUDE_USAGE_SNAPSHOT:-$HOME/.claude/usage-snapshot.json}"

input=$(cat)

# Writes {api, rate_limits, session_id, captured_at} atomically (temp file + mv) so a
# reader never sees a half-written file.
write_snapshot() {
  [ -n "$input" ] || return 0

  local snapshot_dir payload tmp
  snapshot_dir=$(dirname "$snapshot_path")
  mkdir -p "$snapshot_dir" 2>/dev/null || return 0

  if command -v jq >/dev/null 2>&1; then
    # jq present but failing to parse means stdin wasn't the expected status line JSON.
    # Keep the last good snapshot rather than clobbering it with unparseable content —
    # a reader would treat garbage as "no signal" and lose a still-valid budget reading.
    payload=$(printf '%s' "$input" \
      | jq -c --arg captured_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
          '{api, rate_limits, session_id, captured_at: $captured_at}' 2>/dev/null) || return 0
    [ -n "$payload" ] || return 0
  else
    # No jq: copy stdin verbatim. It still carries api/rate_limits, and readers fall back
    # to the file's mtime for freshness when captured_at is absent.
    payload="$input"
  fi

  tmp="$snapshot_path.tmp.$$"
  if ! printf '%s\n' "$payload" > "$tmp" 2>/dev/null; then
    # Only ever removes the temp file this invocation just created.
    rm -f "$tmp" 2>/dev/null
    return 0
  fi
  mv -f "$tmp" "$snapshot_path" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  return 0
}

write_snapshot

# Pass the original JSON through unchanged. `bash -c` is required because the
# downstream is a configured command *string* ("bun run …"), exactly how Claude Code
# itself invokes a statusLine command — not user input being evaluated.
[ -n "$statusline_cmd" ] || exit 0
downstream_bin=${statusline_cmd%% *}
command -v "$downstream_bin" >/dev/null 2>&1 || exit 0
printf '%s' "$input" | bash -c "$statusline_cmd" || exit 0
exit 0
