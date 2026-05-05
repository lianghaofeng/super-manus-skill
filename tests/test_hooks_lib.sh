#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Source the lib from a known-good location
# (lib expects to be sourced; functions become available)
source hooks/lib.sh

# Set up a temp project and exercise sm_active_folder()
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

# Case A: no .super-manus/active → empty result
got=$(sm_active_folder || true)
[ -z "$got" ] || { echo "FAIL: sm_active_folder should be empty when no active file, got: $got"; exit 1; }

# Case B: active file exists, folder exists → returns the path
mkdir -p .super-manus docs/super-manus/2026-05-04-foo
echo "2026-05-04-foo" > .super-manus/active
got=$(sm_active_folder)
[ "$got" = "docs/super-manus/2026-05-04-foo" ] || { echo "FAIL: expected docs/super-manus/2026-05-04-foo, got: $got"; exit 1; }

# Case C: active file exists but content has trailing whitespace → still works
printf "2026-05-04-foo\n  \n" > .super-manus/active
got=$(sm_active_folder)
[ "$got" = "docs/super-manus/2026-05-04-foo" ] || { echo "FAIL: whitespace-tolerant, got: $got"; exit 1; }

# Case D: active file exists but is empty → empty result
> .super-manus/active
got=$(sm_active_folder || true)
[ -z "$got" ] || { echo "FAIL: empty active file should yield empty, got: $got"; exit 1; }

# Case E: active file names a folder that doesn't exist on disk → still returns the path (caller checks)
echo "2026-05-04-ghost" > .super-manus/active
got=$(sm_active_folder)
[ "$got" = "docs/super-manus/2026-05-04-ghost" ] || { echo "FAIL: should return path even when folder absent, got: $got"; exit 1; }

# Case F: active file with embedded slash (path-traversal attempt) → empty result
echo "2026-05-04-foo/extra" > .super-manus/active
got=$(sm_active_folder || true)
[ -z "$got" ] || { echo "FAIL: path-traversal name should yield empty, got: $got"; exit 1; }

# Case G: active file with .. (path-traversal attempt) → empty result
echo "../../etc/passwd" > .super-manus/active
got=$(sm_active_folder || true)
[ -z "$got" ] || { echo "FAIL: parent-dir name should yield empty, got: $got"; exit 1; }

# Exercise emit_context: takes hook event name + text, prints valid JSON to stdout
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
trap 'rm -f "$TMP_PROG"' RETURN

# Missing file → false
sm_has_unlogged_commits "/nonexistent/$$.md" && { echo "FAIL: missing file should be false"; exit 1; } || true

# Empty progress.md (no sections) → false
> "$TMP_PROG"
sm_has_unlogged_commits "$TMP_PROG" && { echo "FAIL: empty progress should be false"; exit 1; } || true

# Only commits, no session log → true (commits exist, none narrated)
cat > "$TMP_PROG" <<'EOF'
# Progress: x
## Completed commits
- 2026-05-05 09:00 · `abc123` · advanced P1
## Session log
EOF
sm_has_unlogged_commits "$TMP_PROG" || { echo "FAIL: commits without log should be true"; exit 1; }

# Commit older than latest log entry → false (already narrated)
cat > "$TMP_PROG" <<'EOF'
# Progress: x
## Completed commits
- 2026-05-05 09:00 · `abc123` · advanced P1
## Session log
### Session 2026-05-05 #1 (10:00 – 11:00)
- closed P1
EOF
sm_has_unlogged_commits "$TMP_PROG" && { echo "FAIL: commit older than log should be false"; exit 1; } || true

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
sm_has_unlogged_commits "$TMP_PROG" || { echo "FAIL: newer commit than latest log should be true"; exit 1; }

# No commits at all → false (nothing to log)
cat > "$TMP_PROG" <<'EOF'
# Progress: x
## Completed commits
## Session log
### Session 2026-05-05 #1 (10:00 – 11:00)
- nothing happened
EOF
sm_has_unlogged_commits "$TMP_PROG" && { echo "FAIL: no commits should be false"; exit 1; } || true

# sm_active_update: returns "<module>/<update>" of most recently modified update folder,
# or empty if feature folder has no impl/<module>/<update> structure yet.
TMP_FEAT=$(mktemp -d)
trap 'rm -f "$TMP_PROG"; rm -rf "$TMP_FEAT"' RETURN

# Case A: feature folder has no impl/ dir → empty
got=$(sm_active_update "$TMP_FEAT" || true)
[ -z "$got" ] || { echo "FAIL: missing impl/ should give empty, got: $got"; exit 1; }

# Case B: empty impl/ dir → empty
mkdir -p "$TMP_FEAT/impl"
got=$(sm_active_update "$TMP_FEAT" || true)
[ -z "$got" ] || { echo "FAIL: empty impl/ should give empty, got: $got"; exit 1; }

# Case C: module dir exists but no update folders → empty
mkdir -p "$TMP_FEAT/impl/api"
got=$(sm_active_update "$TMP_FEAT" || true)
[ -z "$got" ] || { echo "FAIL: module without updates should give empty, got: $got"; exit 1; }

# Case D: single update folder → returns "<module>/<update>"
mkdir -p "$TMP_FEAT/impl/api/2026-05-06-foo"
got=$(sm_active_update "$TMP_FEAT")
[ "$got" = "api/2026-05-06-foo" ] || { echo "FAIL: single update, expected api/2026-05-06-foo, got: $got"; exit 1; }

# Case E: two updates same module → most recently modified wins
mkdir -p "$TMP_FEAT/impl/api/2026-05-07-bar"
# Force older mtime on the first folder
touch -t 202504010800 "$TMP_FEAT/impl/api/2026-05-06-foo"
got=$(sm_active_update "$TMP_FEAT")
[ "$got" = "api/2026-05-07-bar" ] || { echo "FAIL: expected api/2026-05-07-bar, got: $got"; exit 1; }

# Case F: two modules with updates → most recently modified across all wins
mkdir -p "$TMP_FEAT/impl/frontend/2026-05-08-baz"
# Make api/2026-05-07-bar older than frontend/2026-05-08-baz
touch -t 202504020800 "$TMP_FEAT/impl/api/2026-05-07-bar"
got=$(sm_active_update "$TMP_FEAT")
[ "$got" = "frontend/2026-05-08-baz" ] || { echo "FAIL: expected frontend/2026-05-08-baz, got: $got"; exit 1; }

# Case G: feature path that does not exist on disk → empty
got=$(sm_active_update "/nonexistent/feature/$$" || true)
[ -z "$got" ] || { echo "FAIL: nonexistent feature path should give empty, got: $got"; exit 1; }

# Case H: empty / missing argument → empty
got=$(sm_active_update "" || true)
[ -z "$got" ] || { echo "FAIL: empty arg should give empty, got: $got"; exit 1; }
got=$(sm_active_update || true)
[ -z "$got" ] || { echo "FAIL: missing arg should give empty, got: $got"; exit 1; }

echo OK
