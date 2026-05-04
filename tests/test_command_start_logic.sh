#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

REPO_ROOT="$(pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# We need access to the templates and the script from the repo root,
# but we want to RUN against a fresh project dir. Set up a fake project that
# can find the script via absolute path and the templates via env var.
cd "$TMP"

# Helper: invoke the script with REPO_ROOT visible so it knows where templates live
sm_start() {
  SUPER_MANUS_ROOT="$REPO_ROOT" bash "$REPO_ROOT/scripts/sm-start.sh" "$@"
}

# Case A: invalid name (uppercase) → exit non-zero
if sm_start "My-Feature" 2>/dev/null; then echo "FAIL: uppercase name should be rejected"; exit 1; fi

# Case B: invalid name (leading hyphen) → exit non-zero
if sm_start "-leading" 2>/dev/null; then echo "FAIL: leading hyphen should be rejected"; exit 1; fi

# Case C: invalid name (empty) → exit non-zero
if sm_start "" 2>/dev/null; then echo "FAIL: empty name should be rejected"; exit 1; fi

# Case D: invalid name (with space) → exit non-zero
if sm_start "two words" 2>/dev/null; then echo "FAIL: spaces should be rejected"; exit 1; fi

# Case E: happy path — name "demo"
out=$(sm_start "demo")
TODAY=$(date +%F)
FOLDER="docs/super-manus/${TODAY}-demo"
[ -d "$FOLDER" ] || { echo "FAIL: folder not created at $FOLDER"; exit 1; }
[ -f "$FOLDER/task_plan.md" ] || { echo "FAIL: task_plan.md not copied"; exit 1; }
[ -f "$FOLDER/findings.md" ] || { echo "FAIL: findings.md not copied"; exit 1; }
[ -f "$FOLDER/progress.md" ] || { echo "FAIL: progress.md not copied"; exit 1; }
grep -q "# Task Plan: demo" "$FOLDER/task_plan.md" || { echo "FAIL: <feature title> not substituted in task_plan.md"; exit 1; }
grep -q "# Findings: demo" "$FOLDER/findings.md" || { echo "FAIL: <feature title> not substituted in findings.md"; exit 1; }
grep -q "# Progress: demo" "$FOLDER/progress.md" || { echo "FAIL: <feature title> not substituted in progress.md"; exit 1; }
# .super-manus/active should contain the basename
[ -f .super-manus/active ] || { echo "FAIL: .super-manus/active not written"; exit 1; }
content=$(cat .super-manus/active)
[ "$content" = "${TODAY}-demo" ] || { echo "FAIL: .super-manus/active content wrong: '$content'"; exit 1; }
# Echoed path should mention the folder
echo "$out" | grep -q "$FOLDER" || { echo "FAIL: success output should mention folder path, got: $out"; exit 1; }

# Case F: re-running with the same name → exit non-zero (folder exists)
if sm_start "demo" 2>/dev/null; then echo "FAIL: duplicate name should be rejected"; exit 1; fi

# Case G: partial template set → script must clean up the half-created folder
TMP_BAD_ROOT=$(mktemp -d)
mkdir -p "$TMP_BAD_ROOT/templates"
cp "$REPO_ROOT/templates/task_plan.md" "$TMP_BAD_ROOT/templates/"
cp "$REPO_ROOT/templates/findings.md" "$TMP_BAD_ROOT/templates/"
# Deliberately omit progress.md
TODAY2=$(date +%F)
TARGET="docs/super-manus/${TODAY2}-cleanup-test"
if SUPER_MANUS_ROOT="$TMP_BAD_ROOT" bash "$REPO_ROOT/scripts/sm-start.sh" "cleanup-test" 2>/dev/null; then
  echo "FAIL: missing template should have caused exit non-zero"; exit 1
fi
[ ! -d "$TARGET" ] || { echo "FAIL: partial folder should have been cleaned up, but still exists at $TARGET"; exit 1; }
rm -rf "$TMP_BAD_ROOT"

echo OK
