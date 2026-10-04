#!/usr/bin/env bash
# Tests for agent-env.sh — the harness-neutral identity resolver.
#
# Two invariants carry real consequences and are pinned hardest here:
#
#   1. Under Claude Code, agent_session_id must return $CLAUDE_CODE_SESSION_ID *verbatim*.
#      hooks/stop-completion-gate.sh resolves ~/.claude/session-slugs/<session_id> from the id
#      on the Stop hook's stdin, so any transformation silently breaks the completion gate.
#   2. Nesting must resolve to the INNERMOST harness. opencode launched from a Claude Code bash
#      tool inherits CLAUDE_CODE_SESSION_ID and CLAUDECODE=1, so a var-first chain would hand the
#      inner session the outer harness's id — the same collision bug from the other direction.
#
# `ps` is stubbed so ancestry walks are deterministic: the stub returns successive lines of a
# fixture chain file, ignoring the queried pid, which is exactly the shape of walking upward.
#
# Run: bash agent-env.test.sh
# Exits non-zero (and prints which case failed) if any assertion fails.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="$SCRIPT_DIR/agent-env.sh"
PATH_BASE="$PATH"

failures=0
pass_count=0

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

assert_ne() {
  local description="$1" unexpected="$2" actual="$3"
  if [ "$unexpected" != "$actual" ]; then
    pass_count=$((pass_count + 1))
    echo "PASS: $description"
  else
    failures=$((failures + 1))
    echo "FAIL: $description (expected anything but '$unexpected')"
  fi
}

assert_prefix() {
  local description="$1" prefix="$2" actual="$3"
  case "$actual" in
    "$prefix"*)
      pass_count=$((pass_count + 1))
      echo "PASS: $description"
      ;;
    *)
      failures=$((failures + 1))
      echo "FAIL: $description (expected prefix '$prefix', got '$actual')"
      ;;
  esac
}

# --- Fixture -----------------------------------------------------------------------------
W=$(mktemp -d)
mkdir -p "$W/bin" "$W/home"

# Stub ps: hands back successive lines of $PS_CHAIN_FILE ("<parent-pid> <command>"), which
# models walking up an ancestry. Exits 1 once the chain is exhausted, like a pid that is gone.
cat >"$W/bin/ps" <<'STUB'
#!/usr/bin/env bash
n=$(cat "$PS_CALL_COUNT" 2>/dev/null || echo 0)
n=$((n + 1))
printf '%s' "$n" >"$PS_CALL_COUNT"
line=$(sed -n "${n}p" "$PS_CHAIN_FILE" 2>/dev/null)
[ -n "$line" ] || exit 1
printf ' %s\n' "$line"
STUB
chmod +x "$W/bin/ps"

set_chain() { printf '%s\n' "$@" >"$W/ps-chain"; }
clear_chain() { : >"$W/ps-chain"; }

# Runs one resolver function in a pristine environment. Extra args are VAR=value assignments.
# A fresh call-counter per run keeps each ancestry walk independent.
resolve() {
  local fn="$1"
  shift
  : >"$W/ps-count"
  env -i \
    HOME="$W/home" \
    PATH="$W/bin:$PATH_BASE" \
    PS_CHAIN_FILE="$W/ps-chain" \
    PS_CALL_COUNT="$W/ps-count" \
    "$@" \
    bash -c "set -u; . '$RESOLVER'; $fn" 2>&1
}

# --- Case 1: Claude Code — exact passthrough of the session id.
set_chain "999 claude"
out=$(resolve agent_harness CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=b5be7b20-6795-4d04-bd48-2383b673f64b)
assert_eq "case1: harness detected as claude" "claude" "$out"
out=$(resolve agent_session_id CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=b5be7b20-6795-4d04-bd48-2383b673f64b)
assert_eq "case1: session id passed through verbatim" \
  "b5be7b20-6795-4d04-bd48-2383b673f64b" "$out"

# --- Case 2: THE NESTING CASE — opencode launched from Claude Code.
# Both harnesses' env vars are present; ancestry says opencode is nearer. The inner session must
# NOT adopt the outer Claude session id.
set_chain "56854 /home/user/.opencode/bin/opencode" "64434 /bin/zsh" "86836 claude"
out=$(resolve agent_harness \
  CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=outer-claude-id CLAUDE_PID=64434 \
  OPENCODE=1 OPENCODE_PID=56856)
assert_eq "case2: innermost harness wins (opencode, not claude)" "opencode" "$out"
out=$(resolve agent_session_id \
  CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=outer-claude-id CLAUDE_PID=64434 \
  OPENCODE=1 OPENCODE_PID=56856)
assert_eq "case2: derived from opencode, not the inherited claude id" "opencode-56856" "$out"
assert_ne "case2: does not leak the outer harness's session id" "outer-claude-id" "$out"

# --- Case 2b: the reverse nesting — claude running under an opencode-launched shell.
set_chain "56854 claude" "64434 /home/user/.opencode/bin/opencode"
out=$(resolve agent_session_id \
  CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=inner-claude-id \
  OPENCODE=1 OPENCODE_PID=56856)
assert_eq "case2b: nearest ancestor claude wins over opencode markers" "inner-claude-id" "$out"

# --- Case 3: pi via PI_SESSION_ID.
set_chain "999 pi"
out=$(resolve agent_harness PI_CODING_AGENT=true PI_SESSION_ID=sess-abc)
assert_eq "case3: harness detected as pi" "pi" "$out"
out=$(resolve agent_session_id PI_CODING_AGENT=true PI_SESSION_ID=sess-abc)
assert_eq "case3: uses PI_SESSION_ID" "sess-abc" "$out"

# --- Case 3b: pi with no PI_SESSION_ID falls back to the session file's basename.
set_chain "999 pi"
out=$(resolve agent_session_id \
  PI_CODING_AGENT=true PI_SESSION_FILE=/home/x/.pi/agent/sessions/proj/sess-from-file.jsonl)
assert_eq "case3b: derives the id from PI_SESSION_FILE" "sess-from-file" "$out"

# --- Case 3c: pi runs through bun, so a bun ancestor counts as pi only with pi's marker set.
set_chain "999 /home/user/.bun/bin/bun"
out=$(resolve agent_harness PI_CODING_AGENT=true)
assert_eq "case3c: bun ancestor + pi marker resolves to pi" "pi" "$out"
out=$(resolve agent_harness)
assert_eq "case3c: bun ancestor without pi marker is not pi" "unknown" "$out"

# --- Case 4: opencode derived id is stable across calls and distinct between processes.
set_chain "999 /home/user/.opencode/bin/opencode"
first=$(resolve agent_session_id OPENCODE=1 OPENCODE_PID=4242)
set_chain "999 /home/user/.opencode/bin/opencode"
second=$(resolve agent_session_id OPENCODE=1 OPENCODE_PID=4242)
assert_eq "case4: derived id stable across invocations" "$first" "$second"
set_chain "999 /home/user/.opencode/bin/opencode"
other=$(resolve agent_session_id OPENCODE=1 OPENCODE_PID=9999)
assert_ne "case4: distinct between concurrent harness processes" "$first" "$other"

# --- Case 5: explicit AGENT_SESSION_ID beats every detected value.
set_chain "999 claude"
out=$(resolve agent_session_id \
  AGENT_SESSION_ID=injected-by-plugin CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=should-lose)
assert_eq "case5: override wins" "injected-by-plugin" "$out"

# --- Case 6: nothing known — still returns a usable, non-empty id.
clear_chain
out=$(resolve agent_harness)
assert_eq "case6: unknown harness reported as such" "unknown" "$out"
out=$(resolve agent_session_id)
assert_prefix "case6: still yields a non-empty derived id" "agent-" "$out"

# --- Case 6b: Cursor Agent — CURSOR_CONVERSATION_ID is the status-line / publish key.
set_chain "999 /home/user/.local/bin/agent"
out=$(resolve agent_harness CURSOR_AGENT=1 CURSOR_CONVERSATION_ID=56b683bd-14f2-410d-ad61-f36601c9c117)
assert_eq "case6b: harness detected as cursor" "cursor" "$out"
out=$(resolve agent_session_id CURSOR_AGENT=1 CURSOR_CONVERSATION_ID=56b683bd-14f2-410d-ad61-f36601c9c117)
assert_eq "case6b: conversation id passed through verbatim" \
  "56b683bd-14f2-410d-ad61-f36601c9c117" "$out"
# Bare process name `agent` without Cursor markers must not be misclassified.
set_chain "999 /usr/bin/agent"
out=$(resolve agent_harness)
assert_eq "case6b: agent binary without Cursor markers is unknown" "unknown" "$out"

# --- Case 6c: Codex — prefer CODEX_THREAD_ID (tool-subprocess env).
set_chain "999 /opt/homebrew/bin/codex"
out=$(resolve agent_harness CODEX_THREAD_ID=019d1afb-b2c7-72d3-b240-f3ee9d31b2c9)
assert_eq "case6c: harness detected as codex" "codex" "$out"
out=$(resolve agent_session_id CODEX_THREAD_ID=019d1afb-b2c7-72d3-b240-f3ee9d31b2c9)
assert_eq "case6c: thread id passed through verbatim" \
  "019d1afb-b2c7-72d3-b240-f3ee9d31b2c9" "$out"
clear_chain
out=$(resolve agent_session_id CODEX_SESSION_ID=sess-fallback)
assert_eq "case6c: env-marker fallback uses CODEX_SESSION_ID" "sess-fallback" "$out"

# --- Case 6d: Gemini CLI — GEMINI_SESSION_ID.
set_chain "999 gemini"
out=$(resolve agent_harness GEMINI_SESSION_ID=a1b2c3d4-e5f6-7890-abcd-ef1234567890)
assert_eq "case6d: harness detected as gemini" "gemini" "$out"
out=$(resolve agent_session_id GEMINI_SESSION_ID=a1b2c3d4-e5f6-7890-abcd-ef1234567890)
assert_eq "case6d: session id passed through verbatim" \
  "a1b2c3d4-e5f6-7890-abcd-ef1234567890" "$out"

# --- Case 6e: Aider / Amp / Goose — process detection, pid-derived id when no session env.
set_chain "999 aider"
out=$(resolve agent_harness)
assert_eq "case6e: aider process detected" "aider" "$out"
out=$(resolve agent_session_id)
assert_prefix "case6e: aider falls back to pid-derived id" "aider-" "$out"
set_chain "999 amp"
out=$(resolve agent_harness)
assert_eq "case6e: amp process detected" "amp" "$out"
set_chain "999 goose"
out=$(resolve agent_harness)
assert_eq "case6e: goose process detected" "goose" "$out"

# --- Case 6f: nesting — Codex under Claude must not adopt the outer Claude session id.
set_chain "111 /opt/homebrew/bin/codex" "222 /bin/zsh" "333 claude"
out=$(resolve agent_session_id \
  CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=outer-claude-id \
  CODEX_THREAD_ID=inner-codex-thread)
assert_eq "case6f: nested codex keeps its own thread id" "inner-codex-thread" "$out"

# --- Case 7: no `ps` on PATH — detection degrades to env markers instead of failing.
: >"$W/ps-count"
clear_chain
mkdir -p "$W/nops"
for tool in bash sed tr dirname readlink cat env; do
  tool_path=$(command -v "$tool" 2>/dev/null) && ln -sf "$tool_path" "$W/nops/$tool"
done
out=$(env -i HOME="$W/home" PATH="$W/nops" \
  CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=marker-only-id \
  bash -c "set -u; . '$RESOLVER'; agent_session_id" 2>&1)
assert_eq "case7: marker fallback works without ps" "marker-only-id" "$out"

# --- Case 8: ids are filename-safe — they become path components.
set_chain "999 claude"
out=$(resolve agent_session_id AGENT_SESSION_ID='we ird/../id')
assert_eq "case8: separators and spaces folded to dashes" "we-ird-..-id" "$out"
out=$(resolve agent_session_id AGENT_SESSION_ID='../..')
assert_eq "case8: no slashes survive, so no traversal is possible" "..-.." "$out"
# `.` and `..` pass the character filter but name directories, so they get rewritten.
out=$(resolve agent_session_id AGENT_SESSION_ID='..')
assert_eq "case8: a bare .. is not usable as a filename" "id-.." "$out"
out=$(resolve agent_session_id AGENT_SESSION_ID='/')
assert_eq "case8: a value that sanitises to nothing still yields a name" "-" "$out"

# --- Case 8b: a glob character in a process name must not be expanded against the filesystem.
# Regression: splitting the ps line with `set -- $line` glob-expanded the command field.
set_chain "999 /weird/pa*th/opencode"
out=$(resolve agent_harness OPENCODE=1 OPENCODE_PID=4242)
assert_eq "case8b: glob in a process name still resolves the harness" "opencode" "$out"
set_chain "999 *"
out=$(resolve agent_harness)
assert_eq "case8b: a bare glob process name does not expand or crash" "unknown" "$out"

# --- Case 9: agent_skill_root precedence.
out=$(resolve agent_skill_root AGENT_SKILL_ROOT=/explicit/root CLAUDE_PLUGIN_ROOT=/plugin/root)
assert_eq "case9: AGENT_SKILL_ROOT wins" "/explicit/root" "$out"
out=$(resolve agent_skill_root CLAUDE_PLUGIN_ROOT=/plugin/root)
assert_eq "case9: CLAUDE_PLUGIN_ROOT is next" "/plugin/root" "$out"

# --- Case 10: self-location — with no env help at all, resolve the real repo root.
expected_root=$(cd "$SCRIPT_DIR/.." && pwd -P)
out=$(resolve agent_skill_root)
assert_eq "case10: self-locates the plugin root" "$expected_root" "$out"

# --- Case 11: self-location through a symlink, which is how other harnesses see this tree.
mkdir -p "$W/linkfarm"
ln -sfn "$RESOLVER" "$W/linkfarm/agent-env.sh"
out=$(env -i HOME="$W/home" PATH="$W/bin:$PATH_BASE" \
  PS_CHAIN_FILE="$W/ps-chain" PS_CALL_COUNT="$W/ps-count" \
  bash -c "set -u; . '$W/linkfarm/agent-env.sh'; agent_skill_root" 2>&1)
assert_eq "case11: symlinked copy still resolves to the real root" "$expected_root" "$out"

# --- Case 12: sourcing is side-effect free and safe under `set -u`.
out=$(env -i HOME="$W/home" PATH="$W/bin:$PATH_BASE" \
  bash -c "set -u; . '$RESOLVER'; printf 'sourced-ok'" 2>&1)
assert_eq "case12: sourcing emits nothing and does not fail under set -u" "sourced-ok" "$out"

# --- Case 13: Grok Build — GROK_SESSION_ID verbatim.
set_chain "999 grok"
out=$(resolve agent_harness GROK_SESSION_ID=grok-sess-abc)
assert_eq "case13: harness detected as grok" "grok" "$out"
out=$(resolve agent_session_id GROK_SESSION_ID=grok-sess-abc)
assert_eq "case13: grok session id verbatim" "grok-sess-abc" "$out"
clear_chain
out=$(resolve agent_harness GROK_WORKSPACE_ROOT=/work/repo)
assert_eq "case13: GROK_WORKSPACE_ROOT marker detects grok" "grok" "$out"

# --- Case 14: DeepSeek Harness — DSH_SESSION_ID / process names.
set_chain "999 dsh"
out=$(resolve agent_harness DSH_SESSION_ID=dsh-example-001)
assert_eq "case14: harness detected as deepseek" "deepseek" "$out"
out=$(resolve agent_session_id DSH_SESSION_ID=dsh-example-001)
assert_eq "case14: DSH_SESSION_ID verbatim" "dsh-example-001" "$out"
set_chain "999 dsc"
out=$(resolve agent_harness)
assert_eq "case14: dsc binary resolves to deepseek" "deepseek" "$out"
clear_chain
out=$(resolve agent_harness DSH_CWD=/tmp/workspace)
assert_eq "case14: DSH_CWD marker detects deepseek" "deepseek" "$out"

# --- Case 15: nesting — grok under claude must not adopt Claude's session id.
set_chain "111 grok" "222 claude"
out=$(resolve agent_session_id \
  GROK_SESSION_ID=inner-grok \
  CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=outer-claude)
assert_eq "case15: innermost grok wins over inherited claude id" "inner-grok" "$out"

# --- Case 16: GitHub Copilot CLI — COPILOT_AGENT_SESSION_ID verbatim, binary `copilot`.
set_chain "999 copilot"
out=$(resolve agent_harness COPILOT_CLI=1 COPILOT_AGENT_SESSION_ID=copilot-sess-abc)
assert_eq "case16: harness detected as copilot" "copilot" "$out"
out=$(resolve agent_session_id COPILOT_CLI=1 COPILOT_AGENT_SESSION_ID=copilot-sess-abc)
assert_eq "case16: copilot session id verbatim" "copilot-sess-abc" "$out"
clear_chain
out=$(resolve agent_harness COPILOT_CLI=1)
assert_eq "case16: COPILOT_CLI marker alone detects copilot" "copilot" "$out"

# --- Case 17: nesting — copilot under claude must not adopt Claude's session id.
set_chain "111 copilot" "222 claude"
out=$(resolve agent_session_id \
  COPILOT_CLI=1 COPILOT_AGENT_SESSION_ID=inner-copilot \
  CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=outer-claude)
assert_eq "case17: innermost copilot wins over inherited claude id" "inner-copilot" "$out"

echo
echo "$pass_count passed, $failures failed"
[ "$failures" -eq 0 ] || exit 1
