#!/usr/bin/env bash
# Shared Stop-hook completion gate for skills that track progress in a per-session
# agent-spec/<slug>/<state-file> (code-gen, cr, skills-evolvement, arch-verify).
#
# Scopes the lookup to the CURRENT session's own active slug — read from the
# per-session file the `session-slug` skill publishes at
# ~/.claude/session-slugs/<session_id> on bootstrap (keyed by the same session_id
# the Stop hook receives on stdin) — instead of grepping the transcript for every
# "agent-spec/<slug>" string it has ever mentioned (e.g. from reading another
# session's file while investigating something) and guessing via mtime. That
# transcript-grep approach picked up slugs this session merely *read about*, and
# once picked, a slug with no code-review.md/tasks.md of its own yet (this
# session's own file, not written until later in the run) lost out by
# elimination to a stale, unrelated session's file — causing this session's Stop
# hook to block forever on someone else's still-open review instead of its own.
#
# Usage (invoked from a skill's frontmatter `hooks.Stop` command):
#   bash "${CLAUDE_PLUGIN_ROOT}/hooks/stop-completion-gate.sh" <state-filename> <open-pattern> <label>
#
# Args:
#   state-filename  e.g. tasks.md, code-review.md, arch-design-diff.md — the file this
#                   skill maintains under agent-spec/<slug>/. May instead contain the
#                   literal token `%HARNESS%` (e.g. `code-review.%HARNESS%.md`) for skills
#                   whose output filename carries a `<harness>-<model>` suffix so multiple
#                   harnesses/models can review the same slug concurrently without
#                   clobbering each other's file — see the %HARNESS% handling below.
#   open-pattern    grep -E pattern matching an "still open" marker in that file.
#   label           short skill name used in retry/diagnostic messages.
#
# Reads the Stop hook's JSON payload from stdin for `session_id`, resolves the
# active slug from ~/.claude/session-slugs/<session_id>, and gates only on
# agent-spec/<that-slug>/<state-filename>. Exits 2 (block) while that file still
# has an open marker, capped at MAX_RETRIES — after that it releases the block,
# resets the counter, and asks the model to self-diagnose instead of looping.
#
# NEVER GUESSES. If the active slug can't be resolved this way (no session_id
# on stdin, no published session-slugs file, or that slug has no state file of
# its own yet), there is nothing safe to gate on — exit 0 unconditionally
# rather than falling back to scanning agent-spec/* for "the newest matching
# file" or any other heuristic. A wrong guess here means blocking Stop forever
# on a completely unrelated session's work (see the regression above); an
# unresolved slug should surface as "nothing to gate", not as a guessed one.

set -u

state_filename="$1"
open_pattern="$2"
label="$3"
MAX_RETRIES=7  # must stay below Claude Code's own cap of 8 consecutive Stop-hook blocks

input=$(cat)
session_id=$(printf '%s' "$input" | jq -r '.session_id // ""' 2>/dev/null)

f=""
if [ -n "$session_id" ] && [ -f "$HOME/.claude/session-slugs/$session_id" ]; then
  active_slug=$(cat "$HOME/.claude/session-slugs/$session_id" 2>/dev/null)
  if [ -n "$active_slug" ]; then
    case "$state_filename" in
      *'%HARNESS%'*)
        # This session's own harness only — never another concurrent session's. The Stop
        # hook always runs inside the same process tree as the session that is stopping,
        # so `agent_harness` here reports THIS session's harness, not a guess about which
        # of several files "belongs" to it.
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        harness="unknown"
        # shellcheck source=agent-env.sh
        if . "$script_dir/agent-env.sh" 2>/dev/null; then
          harness="$(agent_harness 2>/dev/null || echo unknown)"
        fi
        pattern="${state_filename//%HARNESS%/$harness-*}"
        matches=()
        while IFS= read -r -d '' m; do matches+=("$m"); done < <(
          find "agent-spec/$active_slug" -maxdepth 1 -name "$pattern" -print0 2>/dev/null
        )
        # Exactly one match is the only case worth gating on. Zero means this session
        # hasn't written its file yet (same as the pre-existing "no file" case below).
        # More than one is genuine ambiguity (e.g. two models under the same harness on
        # the same slug at once) — NEVER GUESS which one is "this" session's; exit 0.
        [ "${#matches[@]}" -eq 1 ] && f="${matches[0]}"
        ;;
      *)
        [ -f "agent-spec/$active_slug/$state_filename" ] && f="agent-spec/$active_slug/$state_filename"
        ;;
    esac
  fi
fi

[ -z "$f" ] && exit 0

retry_file="$(dirname "$f")/.stop-hook-retries-$label"
n=$(cat "$retry_file" 2>/dev/null || echo 0)
n=$((n + 1))
echo "$n" > "$retry_file"

if grep -qE "$open_pattern" "$f"; then
  if [ "$n" -ge "$MAX_RETRIES" ]; then
    echo "$label: Stop hook retried ${MAX_RETRIES}x against $f without clearing '$open_pattern' — stopping the forced loop. Re-read $f yourself, confirm it actually belongs to this session, and report status to the user instead of looping silently." >&2
    rm -f "$retry_file"
    exit 0
  fi
  echo "$label: $f still has an open item matching '$open_pattern' — continue until resolved (retry $n/$MAX_RETRIES)" >&2
  exit 2
fi

rm -f "$retry_file"
exit 0
