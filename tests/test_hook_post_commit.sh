#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

REPO_ROOT="$(pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Set up an isolated project with hooks + a v0.2 feature with one update folder
cp -r hooks "$TMP/"
cp -r scripts "$TMP/"
cp -r templates "$TMP/"
cd "$TMP"
mkdir -p .super-manus
SUPER_MANUS_ROOT="$TMP" bash scripts/sm-start.sh "demo" >/dev/null
TODAY=$(date +%F)
FEATURE="docs/super-manus/${TODAY}-demo"
SUPER_MANUS_ROOT="$TMP" bash scripts/sm-update.sh "api" "mvp" >/dev/null
UPDATE_REL="api/${TODAY}-mvp"
UPDATE_DIR="$FEATURE/impl/$UPDATE_REL"

# Helper: run hook with given JSON payload, return its stdout
run_hook() {
  local payload="$1"
  printf '%s' "$payload" | bash hooks/post-commit.sh
}

assert_noop() {
  local out="$1" label="$2"
  if [ "$out" != "{}" ]; then
    echo "FAIL: $label — expected {} no-op, got: $out"
    exit 1
  fi
}

# Helper: parse JSON output and verify it's a PostToolUse reminder mentioning a target dir
assert_reminder_at() {
  local out="$1" expected_dir="$2" label="$3"
  printf '%s' "$out" > "$TMP/out.json"
  HOOK_OUT_FILE="$TMP/out.json" EXPECTED_DIR="$expected_dir" LABEL="$label" python3 - <<'PY' || { echo "FAIL: $label — output is not a valid PostToolUse reminder JSON pointing at $EXPECTED_DIR"; exit 1; }
import json, os, sys
label = os.environ["LABEL"]
expected = os.environ["EXPECTED_DIR"]
with open(os.environ["HOOK_OUT_FILE"]) as f:
    d = json.load(f)
assert d["hookSpecificOutput"]["hookEventName"] == "PostToolUse", f"{label}: wrong event"
ctx = d["hookSpecificOutput"]["additionalContext"]
assert f"{expected}/progress.md" in ctx, f"{label}: missing {expected}/progress.md ref: {ctx[:300]!r}"
assert f"{expected}/task_plan.md" in ctx, f"{label}: missing {expected}/task_plan.md ref"
assert "Completed commits" in ctx, f"{label}: missing Completed commits ref"
assert "refresh-outstanding" in ctx, f"{label}: missing refresh-outstanding invocation"
assert f'"{expected}"' in ctx, f"{label}: refresh-outstanding should be passed {expected!r}"
PY
}

# === v0.2 cases (active update is api/${TODAY}-mvp) ===

# Case 1: non-Bash tool call → no-op
out=$(run_hook '{"tool_name":"Read","tool_input":{"file_path":"/foo"},"tool_response":{"interrupted":false}}')
assert_noop "$out" "Case 1 (non-Bash tool)"

# Case 2: Bash but not git commit → no-op
out=$(run_hook '{"tool_name":"Bash","tool_input":{"command":"ls -la"},"tool_response":{"interrupted":false},"exit_code":0}')
assert_noop "$out" "Case 2 (Bash ls)"

# Case 3: git commit but exit_code non-zero → no-op
out=$(run_hook '{"tool_name":"Bash","tool_input":{"command":"git commit -m foo"},"tool_response":{"stdout":"","stderr":"nothing to commit","interrupted":false},"exit_code":1}')
assert_noop "$out" "Case 3 (failed commit)"

# Case 4: successful git commit on v0.2 → reminder targets the active update folder
out=$(run_hook '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"feat: add x\""},"tool_response":{"stdout":"[main abc1234] feat: add x","stderr":"","interrupted":false},"exit_code":0}')
assert_reminder_at "$out" "$UPDATE_DIR" "Case 4 (v0.2 successful commit → impl/<m>/<u>/progress.md)"

# Case 5: --amend on v0.2 → still targets active update
out=$(run_hook '{"tool_name":"Bash","tool_input":{"command":"git commit --amend --no-edit"},"tool_response":{"stdout":"[main abc1234] amended","stderr":"","interrupted":false},"exit_code":0}')
assert_reminder_at "$out" "$UPDATE_DIR" "Case 5 (v0.2 --amend)"

# Case 6: aliased commit → no-op
out=$(run_hook '{"tool_name":"Bash","tool_input":{"command":"git ci -m foo"},"tool_response":{"stdout":"","stderr":"","interrupted":false},"exit_code":0}')
assert_noop "$out" "Case 6 (git alias 'ci' should not trigger)"

# Case 7: leading whitespace + git commit → still triggers v0.2 reminder
out=$(run_hook '{"tool_name":"Bash","tool_input":{"command":"  git commit -m foo"},"tool_response":{"stdout":"[main abc1234] foo","stderr":"","interrupted":false},"exit_code":0}')
assert_reminder_at "$out" "$UPDATE_DIR" "Case 7 (v0.2 leading whitespace)"

# Case 8: multiline commit message → still triggers v0.2 reminder
out=$(run_hook '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"$(cat <<EOF\nfoo\nEOF\n)\""},"tool_response":{"stdout":"[main abc1234] foo","stderr":"","interrupted":false},"exit_code":0}')
assert_reminder_at "$out" "$UPDATE_DIR" "Case 8 (v0.2 multiline)"

# Case 9: no active feature → no-op
mv .super-manus/active "$TMP/active.bak"
out=$(run_hook '{"tool_name":"Bash","tool_input":{"command":"git commit -m foo"},"tool_response":{"stdout":"[main abc1234] foo","stderr":"","interrupted":false},"exit_code":0}')
assert_noop "$out" "Case 9 (no active feature)"
mv "$TMP/active.bak" .super-manus/active

# Case 10: malformed JSON → no-op
out=$(printf '%s' '{not valid json' | bash hooks/post-commit.sh)
assert_noop "$out" "Case 10 (malformed JSON)"

# Case 11: v0.2 feature but NO impl/<m>/<u>/ yet → no-op
SECOND_FEATURE="docs/super-manus/${TODAY}-empty-v02"
mkdir -p "$SECOND_FEATURE/prd" "$SECOND_FEATURE/impl"
echo "${TODAY}-empty-v02" > .super-manus/active
out=$(run_hook '{"tool_name":"Bash","tool_input":{"command":"git commit -m foo"},"tool_response":{"stdout":"[main abc1234] foo","stderr":"","interrupted":false},"exit_code":0}')
assert_noop "$out" "Case 11 (v0.2 feature with no impl/<m>/<u>/ yet)"
echo "${TODAY}-demo" > .super-manus/active

# === v0.1 fallback case (legacy feature with prd.md as a file, no prd/ folder) ===
V01_NAME="${TODAY}-legacy"
V01_FOLDER="docs/super-manus/$V01_NAME"
mkdir -p "$V01_FOLDER"
for f in task_plan.md prd.md findings.md progress.md; do
  sed "s|<feature title>|legacy|g" "templates/$f" > "$V01_FOLDER/$f"
done
echo "$V01_NAME" > .super-manus/active

# Case 12: v0.1 feature → reminder targets feature root (legacy behavior unchanged)
out=$(run_hook '{"tool_name":"Bash","tool_input":{"command":"git commit -m foo"},"tool_response":{"stdout":"[main abc1234] foo","stderr":"","interrupted":false},"exit_code":0}')
assert_reminder_at "$out" "$V01_FOLDER" "Case 12 (v0.1 fallback — reminder at feature root)"

echo OK
