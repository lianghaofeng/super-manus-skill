#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Source the lib from a known-good location
# (lib expects to be sourced; functions become available)
source hooks/lib.sh

# v0.4: hooks/lib.sh must define sm_active_update and must NOT define sm_active_feature.
# .super-manus/active is gone in v0.4 — active update is resolved purely by mtime scan
# under docs/super-manus/impl/<module>/*/.
if declare -f sm_active_feature >/dev/null 2>&1; then
  echo "FAIL: hooks/lib.sh must NOT define sm_active_feature in v0.4 (state file is gone)"; exit 1
fi
if ! declare -f sm_active_update >/dev/null 2>&1; then
  echo "FAIL: hooks/lib.sh must define sm_active_update in v0.4"; exit 1
fi

# v0.4: lib.sh source must NOT read .super-manus/active in any executable code path.
# Comments mentioning the removed state file are allowed (they document the migration);
# only actual file reads (cat / read / grep / [ -f ... ]) are forbidden.
non_comment_active=$(grep -nF ".super-manus/active" hooks/lib.sh | grep -vE '^[0-9]+:\s*#' || true)
if [ -n "$non_comment_active" ]; then
  echo "FAIL: hooks/lib.sh must NOT read .super-manus/active in v0.4 (found in non-comment lines):"
  echo "$non_comment_active"
  exit 1
fi

# emit_context: takes hook event name + text, prints valid JSON to stdout
out=$(emit_context "SessionStart" "hello world")
printf '%s' "$out" | python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
assert d["hookSpecificOutput"]["hookEventName"] == "SessionStart"
assert d["hookSpecificOutput"]["additionalContext"] == "hello world"
' || { echo "FAIL: emit_context did not produce valid hookSpecificOutput JSON"; exit 1; }

# emit_context with multiline text including double quotes and newlines
multi=$'line one\nline "two"\n\tindented'
out=$(emit_context "PostToolUse" "$multi")
printf '%s' "$out" | python3 -c '
import json, sys
expected = sys.argv[1]
d = json.loads(sys.stdin.read())
assert d["hookSpecificOutput"]["hookEventName"] == "PostToolUse"
assert d["hookSpecificOutput"]["additionalContext"] == expected, (d["hookSpecificOutput"]["additionalContext"], expected)
' "$multi" || { echo "FAIL: emit_context did not preserve multiline/quoted text"; exit 1; }

# Stop event must use decision:block (not systemMessage / additionalContext) so the
# agent actually receives the reminder instead of the user's terminal swallowing it.
out=$(emit_context "Stop" "remember to write the session log")
printf '%s' "$out" | python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
assert d.get("decision") == "block", f"Stop must emit decision:block, got: {d}"
assert d.get("reason") == "remember to write the session log", f"reason mismatch: {d}"
assert "systemMessage" not in d, "Stop must not fall back to systemMessage"
assert "hookSpecificOutput" not in d, "Stop must not use hookSpecificOutput"
' || { echo "FAIL: emit_context Stop branch did not produce decision:block"; exit 1; }

# SubagentStop should follow the same rule
out=$(emit_context "SubagentStop" "x")
printf '%s' "$out" | python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
assert d.get("decision") == "block", f"SubagentStop must emit decision:block, got: {d}"
' || { echo "FAIL: emit_context SubagentStop branch did not produce decision:block"; exit 1; }

# sm_stop_hook_active: empty / malformed / false-flag payload → returns 1 (false)
sm_stop_hook_active "" && { echo "FAIL: empty payload should be false"; exit 1; } || true
sm_stop_hook_active "not json" && { echo "FAIL: malformed payload should be false"; exit 1; } || true
sm_stop_hook_active '{}' && { echo "FAIL: payload without stop_hook_active should be false"; exit 1; } || true
sm_stop_hook_active '{"stop_hook_active": false}' && { echo "FAIL: explicit false should be false"; exit 1; } || true

# sm_stop_hook_active: payload with stop_hook_active=true → returns 0 (true)
sm_stop_hook_active '{"stop_hook_active": true}' || { echo "FAIL: true payload should be true"; exit 1; }
sm_stop_hook_active '{"foo": "bar", "stop_hook_active": true, "session_id": "abc"}' || { echo "FAIL: true payload with extras should be true"; exit 1; }

# sm_payload_field: extracts string fields from payload, empty for missing / malformed
[ "$(sm_payload_field '' session_id)" = "" ] || { echo "FAIL: empty payload should give empty"; exit 1; }
[ "$(sm_payload_field 'not json' session_id)" = "" ] || { echo "FAIL: malformed payload should give empty"; exit 1; }
[ "$(sm_payload_field '{}' session_id)" = "" ] || { echo "FAIL: missing field should give empty"; exit 1; }
[ "$(sm_payload_field '{"session_id": "abc-123"}' session_id)" = "abc-123" ] || { echo "FAIL: should extract session_id"; exit 1; }
[ "$(sm_payload_field '{"session_id": 42}' session_id)" = "" ] || { echo "FAIL: non-string field should give empty"; exit 1; }
[ "$(sm_payload_field '{"foo":"bar","session_id":"x","stop_hook_active":true}' session_id)" = "x" ] || { echo "FAIL: should extract session_id with siblings"; exit 1; }

# sm_has_unlogged_commits: progress.md timestamp comparison
TMP_PROG=$(mktemp)
cleanup_prog() { rm -f "$TMP_PROG"; }

# Missing file → false
sm_has_unlogged_commits "/nonexistent/$$.md" && { echo "FAIL: missing file should be false"; cleanup_prog; exit 1; } || true

# Empty progress.md (no sections) → false
> "$TMP_PROG"
sm_has_unlogged_commits "$TMP_PROG" && { echo "FAIL: empty progress should be false"; cleanup_prog; exit 1; } || true

# Only commits, no session log → true (commits exist, none narrated)
cat > "$TMP_PROG" <<'EOF'
# Progress: x
## Completed commits
- 2026-05-05 09:00 · `abc123` · advanced P1
## Session log
EOF
sm_has_unlogged_commits "$TMP_PROG" || { echo "FAIL: commits without log should be true"; cleanup_prog; exit 1; }

# Commit older than latest log entry → false (already narrated)
cat > "$TMP_PROG" <<'EOF'
# Progress: x
## Completed commits
- 2026-05-05 09:00 · `abc123` · advanced P1
## Session log
### Session 2026-05-05 #1 (10:00 – 11:00)
- closed P1
EOF
sm_has_unlogged_commits "$TMP_PROG" && { echo "FAIL: commit older than log should be false"; cleanup_prog; exit 1; } || true

# New commit after the latest log entry → true (unlogged)
cat > "$TMP_PROG" <<'EOF'
# Progress: x
## Completed commits
- 2026-05-05 09:00 · `abc123` · advanced P1
- 2026-05-05 12:30 · `def456` · closed P2
## Session log
### Session 2026-05-05 #1 (10:00 – 11:00)
- closed P1
EOF
sm_has_unlogged_commits "$TMP_PROG" || { echo "FAIL: newer commit than latest log should be true"; cleanup_prog; exit 1; }

# No commits at all → false (nothing to log)
cat > "$TMP_PROG" <<'EOF'
# Progress: x
## Completed commits
## Session log
### Session 2026-05-05 #1 (10:00 – 11:00)
- nothing happened
EOF
sm_has_unlogged_commits "$TMP_PROG" && { echo "FAIL: no commits should be false"; cleanup_prog; exit 1; } || true

cleanup_prog

# sm_active_update: in v0.4, takes ZERO arguments and scans
# docs/super-manus/impl/<module>/<update>/ relative to cwd. Returns "<module>/<update>"
# of the most recently modified update folder, or empty if there are none.
TMP_PROJ=$(mktemp -d)
trap 'rm -rf "$TMP_PROJ"' EXIT
pushd "$TMP_PROJ" >/dev/null

# Case A: no docs/super-manus/impl/ dir → empty
got=$(sm_active_update || true)
[ -z "$got" ] || { echo "FAIL: missing docs/super-manus/impl/ should give empty, got: $got"; exit 1; }

# Case B: empty impl/ dir → empty
mkdir -p docs/super-manus/impl
got=$(sm_active_update || true)
[ -z "$got" ] || { echo "FAIL: empty impl/ should give empty, got: $got"; exit 1; }

# Case C: module dir exists but no update folders → empty
mkdir -p docs/super-manus/impl/api
got=$(sm_active_update || true)
[ -z "$got" ] || { echo "FAIL: module without updates should give empty, got: $got"; exit 1; }

# Case D: single update folder → returns "<module>/<update>"
mkdir -p docs/super-manus/impl/api/2026-05-06-foo
got=$(sm_active_update)
[ "$got" = "api/2026-05-06-foo" ] || { echo "FAIL: single update, expected api/2026-05-06-foo, got: $got"; exit 1; }

# Case E: two updates same module → most recently modified wins
mkdir -p docs/super-manus/impl/api/2026-05-07-bar
touch -t 202504010800 docs/super-manus/impl/api/2026-05-06-foo
got=$(sm_active_update)
[ "$got" = "api/2026-05-07-bar" ] || { echo "FAIL: expected api/2026-05-07-bar, got: $got"; exit 1; }

# Case F: two modules with updates → most recently modified across all wins
mkdir -p docs/super-manus/impl/frontend/2026-05-08-baz
touch -t 202504020800 docs/super-manus/impl/api/2026-05-07-bar
got=$(sm_active_update)
[ "$got" = "frontend/2026-05-08-baz" ] || { echo "FAIL: expected frontend/2026-05-08-baz, got: $got"; exit 1; }

popd >/dev/null

echo OK
