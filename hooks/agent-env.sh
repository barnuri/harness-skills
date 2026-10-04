#!/usr/bin/env bash
# Harness-neutral identity resolver — source this, don't execute it.
#
# WHY THIS EXISTS: skills in this repo run under many coding harnesses, but only some
# export a stable session id. A skill that keys state on "${CLAUDE_CODE_SESSION_ID:-unknown}"
# therefore has every session without that var collide on one file literally named `unknown`.
# This file is the single place that resolves identity, so no skill has to know which
# harness it is running under.
#
#   . "<plugin-root>/hooks/agent-env.sh"
#   id=$(agent_session_id)      # never empty, safe as a filename
#   root=$(agent_skill_root)    # plugin root, works in every harness
#   which=$(agent_harness)      # claude|pi|opencode|cursor|codex|copilot|gemini|aider|amp|goose|grok|deepseek|unknown
#
# THE SUBTLE PART — nesting. Env vars are inherited, so launching opencode from a Claude Code
# bash tool gives you an opencode session whose environment still contains
# CLAUDE_CODE_SESSION_ID and CLAUDECODE=1 (measured: ancestry [opencode:56856] -> [zsh] ->
# [claude:64434]). A chain written "try $CLAUDE_CODE_SESSION_ID, then $PI_SESSION_ID, ..."
# would hand the inner session the OUTER harness's id and reintroduce the collision from the
# other direction. So resolution is HARNESS-FIRST: find the innermost harness via process
# ancestry, then read that harness's variable. Env markers alone cannot do this — in the
# nested case several are set at once; only the ancestry says which one is nearest.
#
# Cursor Agent (`CURSOR_AGENT=1`, binary often `~/.local/bin/agent`) exports
# CURSOR_CONVERSATION_ID; its status-line stdin `session_id` is the same UUID. Without a
# cursor branch here, detection falls through to `unknown` → `agent-<pid>`, so
# session-slug publishes under a key the status line never looks up and the 🏷 segment
# stays empty.
#
# GitHub Copilot CLI (binary `copilot`) injects COPILOT_CLI=1 and COPILOT_AGENT_SESSION_ID
# (measured: same UUID copilot reports as the session folder under ~/.copilot/session-state/).
# Copilot also discovers skills from ~/.agents/skills (the claude-harness-sync target) like
# opencode/pi/cursor/codex, even though it has its own ~/.copilot/skills/ dir that stays empty
# in practice — verified 2026-09-30 by cross-checking this session's available_skills against
# the ~/.agents/skills symlink farm.
#
# Codex injects CODEX_THREAD_ID (also seen: CODEX_SESSION_ID / CODEX_CONVERSATION_ID) into
# tool subprocesses. Gemini CLI hooks expose GEMINI_SESSION_ID. Grok Build injects
# GROK_SESSION_ID (plus GROK_HOOK_EVENT / GROK_WORKSPACE_ROOT on hooks). DeepSeek Harness
# uses DSH_* runtime vars (DSH_CWD / DSH_SESSION_ROOT / DSH_SESSION_ID when set); the
# DeepSeek TUI binary is often `deepseek` or `dsc`. Aider / Amp / Goose are detected
# primarily by process name and fall back to a pid-derived id when no session env is
# published.
#
# STABILITY GUARANTEE of the derived ids, and where it breaks:
#   - Stable across every bash invocation within one harness process, and distinct between
#     concurrent harness processes. That is what a status-line key needs.
#   - Two SEQUENTIAL sessions inside one long-lived process (opencode `/new`) share a derived
#     id. claude-harness-sync's opencode plugin fixes that by injecting a real per-session
#     AGENT_SESSION_ID; Claude Code, Cursor, Codex, and pi are unaffected (they expose real
#     session ids).
#   - Without `ps`, detection degrades to env markers and cannot see nesting; the outermost
#     marker may win.
#   - `tty` is deliberately NOT used: measured as "not a tty" inside harness bash tools, so
#     it would be constant garbage.

# Bounded so a pathological process tree or symlink cycle cannot hang a skill.
AGENT_ENV_MAX_HOPS="${AGENT_ENV_MAX_HOPS:-8}"

# Session ids become path components, so anything outside [A-Za-z0-9._-] is folded to `-`.
# Real ids (UUIDs, pi's ids, pid-derived strings) pass through untouched.
#
# `.` and `..` survive that character filter but would resolve to a directory rather than a
# file, so they are rewritten. An empty result gets a placeholder for the same reason: callers
# are promised a usable filename, never an empty string.
agent_env__sanitize() {
  local clean
  clean=$(printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-')
  case "$clean" in
    '' | '.' | '..') clean="id-$clean" ;;
  esac
  printf '%s' "$clean"
}

# Walks up from $PPID looking for the nearest known harness process. Prints "<harness> <pid>"
# and returns 0, or returns 1 when `ps` is unavailable or nothing matched.
#
# pi is invoked through bun (~/.bun/bin/pi is a JS entrypoint), so its process name is `bun`,
# not `pi`. A bun/node ancestor is therefore only read as pi when pi's own marker is present.
# Cursor Agent CLI is often installed as `agent` — require a Cursor marker so a random binary
# named `agent` is not misclassified.
agent_env__nearest_harness() {
  local pid="${PPID:-0}" hops=0 line parent cmd base
  while [ "$hops" -lt "$AGENT_ENV_MAX_HOPS" ]; do
    hops=$((hops + 1))
    case "$pid" in '' | 0 | 1) return 1 ;; esac
    line=$(ps -o ppid=,comm= -p "$pid" 2>/dev/null) || return 1
    [ -n "$line" ] || return 1

    # ps pads with leading spaces and the command may itself contain spaces, so take the
    # first field as the parent pid and everything after it as the command. `read` is used
    # rather than `set -- $line` because the latter glob-expands, and a process name
    # containing `*` or `?` would then be matched against the filesystem.
    parent=""
    cmd=""
    IFS=' ' read -r parent cmd <<EOF
$line
EOF
    base="${cmd##*/}"

    case "$base" in
      claude | claude-code)
        printf 'claude %s\n' "$pid"
        return 0
        ;;
      opencode | opencode-*)
        printf 'opencode %s\n' "$pid"
        return 0
        ;;
      pi)
        printf 'pi %s\n' "$pid"
        return 0
        ;;
      codex | codex-*)
        printf 'codex %s\n' "$pid"
        return 0
        ;;
      copilot | copilot-*)
        printf 'copilot %s\n' "$pid"
        return 0
        ;;
      gemini | gemini-cli)
        printf 'gemini %s\n' "$pid"
        return 0
        ;;
      aider)
        printf 'aider %s\n' "$pid"
        return 0
        ;;
      amp | amp-cli)
        printf 'amp %s\n' "$pid"
        return 0
        ;;
      goose)
        printf 'goose %s\n' "$pid"
        return 0
        ;;
      grok | grok-*)
        printf 'grok %s\n' "$pid"
        return 0
        ;;
      deepseek | deepseek-* | dsh | dsc)
        printf 'deepseek %s\n' "$pid"
        return 0
        ;;
      agent)
        if [ -n "${CURSOR_AGENT:-}" ] || [ -n "${CURSOR_CONVERSATION_ID:-}" ]; then
          printf 'cursor %s\n' "$pid"
          return 0
        fi
        ;;
      bun | node)
        if [ -n "${PI_CODING_AGENT:-}" ]; then
          printf 'pi %s\n' "$pid"
          return 0
        fi
        if [ -n "${GEMINI_SESSION_ID:-}" ] || [ -n "${GEMINI_CLI:-}" ]; then
          printf 'gemini %s\n' "$pid"
          return 0
        fi
        if [ -n "${DSH_SESSION_ID:-}" ] || [ -n "${DSH_CWD:-}" ] || [ -n "${DSH_SESSION_ROOT:-}" ]; then
          printf 'deepseek %s\n' "$pid"
          return 0
        fi
        ;;
    esac
    pid="$parent"
  done
  return 1
}

# Prints "<harness> <pid>". Ancestry first (the only thing that sees nesting), env markers as
# the degraded fallback. Prefer session-specific markers over sticky home-dir vars (e.g. do
# not treat bare CODEX_HOME / CURSOR_* install paths as proof of an active session).
agent_env__detect() {
  local info
  if info=$(agent_env__nearest_harness); then
    printf '%s\n' "$info"
    return 0
  fi

  if [ -n "${PI_CODING_AGENT:-}" ] || [ -n "${PI_SESSION_ID:-}" ]; then
    printf 'pi %s\n' "${PPID:-0}"
  elif [ -n "${OPENCODE:-}" ] || [ -n "${OPENCODE_PID:-}" ]; then
    printf 'opencode %s\n' "${OPENCODE_PID:-${PPID:-0}}"
  elif [ -n "${CURSOR_AGENT:-}" ] || [ -n "${CURSOR_CONVERSATION_ID:-}" ]; then
    printf 'cursor %s\n' "${PPID:-0}"
  elif [ -n "${CODEX_THREAD_ID:-}" ] || [ -n "${CODEX_SESSION_ID:-}" ] || [ -n "${CODEX_CONVERSATION_ID:-}" ]; then
    printf 'codex %s\n' "${PPID:-0}"
  elif [ -n "${COPILOT_CLI:-}" ] || [ -n "${COPILOT_AGENT_SESSION_ID:-}" ]; then
    printf 'copilot %s\n' "${PPID:-0}"
  elif [ -n "${GROK_SESSION_ID:-}" ] || [ -n "${GROK_HOOK_EVENT:-}" ] || [ -n "${GROK_WORKSPACE_ROOT:-}" ]; then
    printf 'grok %s\n' "${PPID:-0}"
  elif [ -n "${GEMINI_SESSION_ID:-}" ] || [ -n "${GEMINI_CLI:-}" ]; then
    printf 'gemini %s\n' "${PPID:-0}"
  elif [ -n "${DSH_SESSION_ID:-}" ] || [ -n "${DSH_CWD:-}" ] || [ -n "${DSH_SESSION_ROOT:-}" ]; then
    printf 'deepseek %s\n' "${PPID:-0}"
  elif [ -n "${AIDER:-}" ] || [ -n "${AIDER_SESSION:-}" ]; then
    printf 'aider %s\n' "${PPID:-0}"
  elif [ -n "${AMP_CURRENT_THREAD_ID:-}" ] || [ -n "${AMP_SESSION_ID:-}" ]; then
    printf 'amp %s\n' "${PPID:-0}"
  elif [ -n "${GOOSE_SESSION_ID:-}" ] || [ -n "${GOOSE_AGENT:-}" ]; then
    printf 'goose %s\n' "${PPID:-0}"
  elif [ -n "${CLAUDECODE:-}" ] || [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then
    printf 'claude %s\n' "${CLAUDE_PID:-${PPID:-0}}"
  else
    printf 'unknown %s\n' "${PPID:-0}"
  fi
}

# claude | pi | opencode | cursor | codex | copilot | gemini | aider | amp | goose | grok | deepseek | unknown
agent_harness() {
  local info
  info=$(agent_env__detect)
  printf '%s\n' "${info%% *}"
}

# A session identifier that is never empty and always filename-safe.
#
# Under Claude Code this returns $CLAUDE_CODE_SESSION_ID *verbatim* — hooks/stop-completion-gate.sh
# looks up ~/.claude/session-slugs/<session_id> using the id from the Stop hook's stdin, so any
# transformation here would silently break the completion gate.
# Under Cursor this returns $CURSOR_CONVERSATION_ID *verbatim* (matches status-line stdin).
# Under Codex this returns $CODEX_THREAD_ID *verbatim* when set (falls back to CODEX_SESSION_ID /
# CODEX_CONVERSATION_ID). Under Gemini this returns $GEMINI_SESSION_ID *verbatim* when set.
# Under Copilot CLI this returns $COPILOT_AGENT_SESSION_ID *verbatim* when set.
# Under Grok Build this returns $GROK_SESSION_ID *verbatim* when set. Under DeepSeek Harness
# this returns $DSH_SESSION_ID (or $DEEPSEEK_SESSION_ID) *verbatim* when set.
agent_session_id() {
  local info harness pid id=""

  if [ -n "${AGENT_SESSION_ID:-}" ]; then
    printf '%s\n' "$(agent_env__sanitize "$AGENT_SESSION_ID")"
    return 0
  fi

  info=$(agent_env__detect)
  harness="${info%% *}"
  pid="${info##* }"

  case "$harness" in
    claude)
      id="${CLAUDE_CODE_SESSION_ID:-}"
      [ -n "$id" ] || id="claude-${CLAUDE_PID:-$pid}"
      ;;
    pi)
      id="${PI_SESSION_ID:-}"
      if [ -z "$id" ] && [ -n "${PI_SESSION_FILE:-}" ]; then
        id="${PI_SESSION_FILE##*/}"
        id="${id%.jsonl}"
      fi
      [ -n "$id" ] || id="pi-$pid"
      ;;
    opencode)
      # opencode exposes no session id; OPENCODE_PID is stable per opencode process and is
      # upgraded to a real per-session id when claude-harness-sync's plugin injects
      # AGENT_SESSION_ID (handled by the override above).
      id="opencode-${OPENCODE_PID:-$pid}"
      ;;
    cursor)
      id="${CURSOR_CONVERSATION_ID:-}"
      [ -n "$id" ] || id="cursor-$pid"
      ;;
    codex)
      id="${CODEX_THREAD_ID:-${CODEX_SESSION_ID:-${CODEX_CONVERSATION_ID:-}}}"
      [ -n "$id" ] || id="codex-$pid"
      ;;
    copilot)
      id="${COPILOT_AGENT_SESSION_ID:-}"
      [ -n "$id" ] || id="copilot-$pid"
      ;;
    gemini)
      id="${GEMINI_SESSION_ID:-}"
      [ -n "$id" ] || id="gemini-$pid"
      ;;
    grok)
      id="${GROK_SESSION_ID:-}"
      [ -n "$id" ] || id="grok-$pid"
      ;;
    deepseek)
      id="${DSH_SESSION_ID:-${DEEPSEEK_SESSION_ID:-}}"
      [ -n "$id" ] || id="deepseek-$pid"
      ;;
    aider)
      id="${AIDER_SESSION:-}"
      [ -n "$id" ] || id="aider-$pid"
      ;;
    amp)
      id="${AMP_CURRENT_THREAD_ID:-${AMP_SESSION_ID:-}}"
      [ -n "$id" ] || id="amp-$pid"
      ;;
    goose)
      id="${GOOSE_SESSION_ID:-}"
      [ -n "$id" ] || id="goose-$pid"
      ;;
    *)
      id="agent-$pid"
      ;;
  esac

  printf '%s\n' "$(agent_env__sanitize "$id")"
}

# The plugin/skills root. Self-location is the primary mechanism: it needs no cooperation from
# the harness, and it works because claude-harness-sync symlinks whole skill directories at
# ~/.agents/skills/<name> -> <root>/skills/<name>, so resolving physically lands in the real
# tree. The env vars are overrides for callers that already know better.
agent_skill_root() {
  if [ -n "${AGENT_SKILL_ROOT:-}" ]; then
    printf '%s\n' "$AGENT_SKILL_ROOT"
    return 0
  fi
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    printf '%s\n' "$CLAUDE_PLUGIN_ROOT"
    return 0
  fi

  # This file lives at <root>/hooks/agent-env.sh, so the root is two levels up from the
  # fully-resolved path of this file.
  local self dir
  self="${BASH_SOURCE[0]:-$0}"
  self=$(agent_env__resolve_link "$self") || return 1
  dir=$(cd "$(dirname "$self")/.." 2>/dev/null && pwd -P) || return 1
  printf '%s\n' "$dir"
}

# readlink -f without depending on GNU coreutils: follows a chain of symlinks (bounded), then
# resolves the containing directory physically.
agent_env__resolve_link() {
  local path="$1" hops=0 target dir base
  while [ -L "$path" ] && [ "$hops" -lt "$AGENT_ENV_MAX_HOPS" ]; do
    hops=$((hops + 1))
    target=$(readlink "$path" 2>/dev/null) || break
    case "$target" in
      /*) path="$target" ;;
      *) path="$(dirname "$path")/$target" ;;
    esac
  done
  dir=$(cd "$(dirname "$path")" 2>/dev/null && pwd -P) || return 1
  base="${path##*/}"
  printf '%s/%s\n' "$dir" "$base"
}
