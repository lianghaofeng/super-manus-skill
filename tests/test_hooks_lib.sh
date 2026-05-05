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

echo OK
