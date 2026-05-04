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

echo OK
