#!/usr/bin/env bash
# Run: bash session-audit.test.sh
# Exits non-zero and names the failed case if an assertion fails.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIT="$SCRIPT_DIR/session-audit.py"
WORK="$(mktemp -d)"
trap 'trash "$WORK" 2>/dev/null || true' EXIT

failures=0
pass_count=0

check() {
  local label="$1" pattern="$2"
  if grep -qF -- "$pattern" "$WORK/report.md"; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $label (expected: $pattern)"
    failures=$((failures + 1))
  fi
}

check_absent() {
  local label="$1" pattern="$2"
  if grep -qF -- "$pattern" "$WORK/report.md"; then
    echo "FAIL: $label (unexpected: $pattern)"
    failures=$((failures + 1))
  else
    pass_count=$((pass_count + 1))
  fi
}

SPEC="$WORK/repo/agent-spec/2026-01-01-demo"
mkdir -p "$SPEC"
printf '# Tasks\n\n## Status\n🔄 In progress\n\n- [x] ✓ one\n- [ ] two\n' > "$SPEC/tasks.md"

cat > "$WORK/session.jsonl" <<EOF
{"type":"user","timestamp":"T1","message":{"content":"add a login page"}}
{"type":"attachment","timestamp":"T2","attachment":{"type":"queued_command","prompt":"also add logout"}}
{"type":"user","isMeta":true,"timestamp":"T3","message":{"content":"meta noise"}}
{"type":"assistant","timestamp":"T4","message":{"content":[{"type":"tool_use","id":"u1","name":"Bash","input":{"command":"sleep 99","run_in_background":true,"description":"long sleep"}},{"type":"tool_use","id":"u2","name":"Agent","input":{"description":"review agent"}},{"type":"tool_use","id":"u3","name":"Monitor","input":{"description":"ci watch"}},{"type":"tool_use","id":"u4","name":"Write","input":{"file_path":"$SPEC/tasks.md"}}]}}
{"type":"user","timestamp":"T5","message":{"content":[{"type":"tool_result","tool_use_id":"u1","content":"Command running in background with ID: bash1. Output is being written to: x"},{"type":"tool_result","tool_use_id":"u2","content":[{"type":"text","text":"Async agent launched successfully. agentId: agent1 (internal ID)"}]},{"type":"tool_result","tool_use_id":"u3","content":"Monitor started (task mon1, expires in 30m)"}]}}
{"type":"user","timestamp":"T6","message":{"content":"<task-notification>\n<task-id>agent1</task-id>\n<status>completed</status>\n</task-notification>"}}
{"type":"user","timestamp":"T7","message":{"content":[{"type":"tool_result","tool_use_id":"u9","content":"Successfully stopped task: mon1 (sleep)"}]}}
{"type":"user","timestamp":"T8","message":{"content":"<command-message>demo:cr</command-message>\n<command-name>/demo:cr</command-name>\n<command-args>PR #5</command-args>"}}
EOF

python3 -I "$AUDIT" --transcript "$WORK/session.jsonl" > "$WORK/report.md"

check "prompt request" "M1. [T1] (prompt) add a login page"
check "mid-turn request" "M2. [T2] (sent mid-turn) also add logout"
check "slash command request" "M3. [T8] (prompt) /demo:cr PR #5"
check_absent "meta entries are not requests" "meta noise"
check_absent "notifications are not requests" "task-notification"
check "agent ended by notification" "agent1 | Agent | review agent | started T5 | completed"
check "monitor ended by stop" "mon1 | Monitor | ci watch | started T5 | stopped"
check "bash task still open" "bash1 | Bash | long sleep | started T5 | OPEN"
check "open count" "OPEN background work: 1"
check "tasks.md counts" "status 🔄 In progress | open 1, in progress 0, blocked 0, done 1"

echo "session-audit: $pass_count passed, $failures failed"
[ "$failures" -eq 0 ]
