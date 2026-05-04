#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

REPO_ROOT="$(pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Set up an isolated project with hooks + an active feature
cp -r hooks "$TMP/"
cp -r scripts "$TMP/"
cp -r templates "$TMP/"
cd "$TMP"
mkdir -p .super-manus
SUPER_MANUS_ROOT="$TMP" bash scripts/sm-start.sh "demo" >/dev/null

# Helper: run hook with given JSON payload, return its stdout
run_hook() {
  local payload="$1"
  printf '%s' "$payload" | bash hooks/post-commit.sh
}

# Helper: assert output equals literal "{}"
assert_noop() {
  local out="$1" label="$2"
  if [ "$out" != "{}" ]; then
    echo "FAIL: $label — expected {} no-op, got: $out"
    exit 1
  fi
}

# Helper: parse JSON output and verify it's a PostToolUse reminder mentioning progress.md
assert_reminder() {
  local out="$1" label="$2"
  printf '%s' "$out" > "$TMP/out.json"
  HOOK_OUT_FILE="$TMP/out.json" LABEL="$label" python3 - <<'PY' || { echo "FAIL: $label — output is not a valid PostToolUse reminder JSON"; exit 1; }
import json, os, sys
label = os.environ["LABEL"]
with open(os.environ["HOOK_OUT_FILE"]) as f:
    d = json.load(f)
assert d["hookSpecificOutput"]["hookEventName"] == "PostToolUse", f"{label}: wrong event"
ctx = d["hookSpecificOutput"]["additionalContext"]
assert "progress.md" in ctx, f"{label}: missing progress.md ref: {ctx[:200]!r}"
assert "Completed commits" in ctx, f"{label}: missing Completed commits ref"
assert "task_plan.md" in ctx, f"{label}: missing task_plan.md ref (phase update)"
assert "refresh-outstanding" in ctx, f"{label}: missing refresh-outstanding invocation"
PY
}

# Case 1: non-Bash tool call → no-op
out=$(run_hook '{"tool_name":"Read","tool_input":{"file_path":"/foo"},"tool_response":{"interrupted":false}}')
assert_noop "$out" "Case 1 (non-Bash tool)"

# Case 2: Bash but not git commit → no-op
out=$(run_hook '{"tool_name":"Bash","tool_input":{"command":"ls -la"},"tool_response":{"interrupted":false},"exit_code":0}')
assert_noop "$out" "Case 2 (Bash ls)"

# Case 3: git commit but exit_code non-zero → no-op (failed commit doesn't trigger)
out=$(run_hook '{"tool_name":"Bash","tool_input":{"command":"git commit -m foo"},"tool_response":{"stdout":"","stderr":"nothing to commit","interrupted":false},"exit_code":1}')
assert_noop "$out" "Case 3 (failed commit)"

# Case 4: successful git commit → emits reminder
out=$(run_hook '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"feat: add x\""},"tool_response":{"stdout":"[main abc1234] feat: add x","stderr":"","interrupted":false},"exit_code":0}')
assert_reminder "$out" "Case 4 (successful commit)"

# Case 5: git commit --amend (still exit 0) → emits reminder (amend is still a commit)
out=$(run_hook '{"tool_name":"Bash","tool_input":{"command":"git commit --amend --no-edit"},"tool_response":{"stdout":"[main abc1234] amended","stderr":"","interrupted":false},"exit_code":0}')
assert_reminder "$out" "Case 5 (commit --amend)"

# Case 6: git aliased commit (e.g. `git ci -m foo`) → no-op (we only match literal "git commit")
out=$(run_hook '{"tool_name":"Bash","tool_input":{"command":"git ci -m foo"},"tool_response":{"stdout":"","stderr":"","interrupted":false},"exit_code":0}')
assert_noop "$out" "Case 6 (git alias 'ci' should not trigger)"

# Case 7: command with leading whitespace + git commit → still triggers
out=$(run_hook '{"tool_name":"Bash","tool_input":{"command":"  git commit -m foo"},"tool_response":{"stdout":"[main abc1234] foo","stderr":"","interrupted":false},"exit_code":0}')
assert_reminder "$out" "Case 7 (leading whitespace)"

# Case 8: multiline command starting with git commit → still triggers
out=$(run_hook '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"$(cat <<EOF\nfoo\nEOF\n)\""},"tool_response":{"stdout":"[main abc1234] foo","stderr":"","interrupted":false},"exit_code":0}')
assert_reminder "$out" "Case 8 (multiline commit message)"

# Case 9: no active feature → no-op even on successful commit (no folder to update)
rm .super-manus/active
out=$(run_hook '{"tool_name":"Bash","tool_input":{"command":"git commit -m foo"},"tool_response":{"stdout":"[main abc1234] foo","stderr":"","interrupted":false},"exit_code":0}')
assert_noop "$out" "Case 9 (no active feature)"

# Restore active feature state for the malformed-JSON test (Case 10) so the
# no-op behavior demonstrates parse-failure handling, not missing-feature handling.
TODAY=$(date +%F)
echo "${TODAY}-demo" > .super-manus/active

# Case 10: malformed JSON payload → no-op (don't crash)
out=$(printf '%s' '{not valid json' | bash hooks/post-commit.sh)
assert_noop "$out" "Case 10 (malformed JSON)"

echo OK
