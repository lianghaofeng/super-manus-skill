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

# Case E: happy path — name "demo" creates v0.2 layout
out=$(sm_start "demo")
TODAY=$(date +%F)
FOLDER="docs/super-manus/${TODAY}-demo"
[ -d "$FOLDER" ] || { echo "FAIL: folder not created at $FOLDER"; exit 1; }

# v0.2 layout: prd/ folder with _index.md, empty impl/, roadmap.md, prd_drift.md
[ -d "$FOLDER/prd" ] || { echo "FAIL: prd/ dir not created"; exit 1; }
[ -f "$FOLDER/prd/_index.md" ] || { echo "FAIL: prd/_index.md not seeded"; exit 1; }
[ -d "$FOLDER/impl" ] || { echo "FAIL: impl/ dir not created"; exit 1; }
[ -f "$FOLDER/roadmap.md" ] || { echo "FAIL: roadmap.md not seeded"; exit 1; }
[ -f "$FOLDER/prd_drift.md" ] || { echo "FAIL: prd_drift.md not seeded"; exit 1; }

# v0.1 four-file set must NOT be created at feature root anymore — they live inside
# impl/<module>/<update>/ now, populated by /super-manus:brainstorm.
[ ! -f "$FOLDER/task_plan.md" ] || { echo "FAIL: task_plan.md should NOT be seeded at feature root in v0.2"; exit 1; }
[ ! -f "$FOLDER/prd.md" ] || { echo "FAIL: legacy prd.md should NOT be seeded in v0.2 (use prd/_index.md)"; exit 1; }
[ ! -f "$FOLDER/findings.md" ] || { echo "FAIL: findings.md should NOT be seeded at feature root in v0.2"; exit 1; }
[ ! -f "$FOLDER/progress.md" ] || { echo "FAIL: progress.md should NOT be seeded at feature root in v0.2"; exit 1; }

# Substitution: <feature title> in prd/_index.md should be replaced with the name
grep -q "^# demo$" "$FOLDER/prd/_index.md" || { echo "FAIL: <feature title> not substituted in prd/_index.md"; exit 1; }
# But the placeholder must be GONE from the title heading
grep -q "^# <feature title>" "$FOLDER/prd/_index.md" && { echo "FAIL: <feature title> placeholder still present in prd/_index.md title"; exit 1; } || true

# roadmap and prd_drift remain generic — no per-feature substitution
grep -q "^# Roadmap" "$FOLDER/roadmap.md" || { echo "FAIL: roadmap.md missing Roadmap title"; exit 1; }
grep -q "^# PRD drift log" "$FOLDER/prd_drift.md" || { echo "FAIL: prd_drift.md missing title"; exit 1; }

# .gitignore + .super-manus/active must still be set up
[ -f "$FOLDER/.gitignore" ] || { echo "FAIL: .gitignore not seeded"; exit 1; }
grep -qF ".session-*" "$FOLDER/.gitignore" || { echo "FAIL: .gitignore should ignore .session-*"; exit 1; }
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
cp "$REPO_ROOT/templates/prd_index.md" "$TMP_BAD_ROOT/templates/"
# Deliberately omit roadmap.md and prd_drift.md
TODAY2=$(date +%F)
TARGET="docs/super-manus/${TODAY2}-cleanup-test"
if SUPER_MANUS_ROOT="$TMP_BAD_ROOT" bash "$REPO_ROOT/scripts/sm-start.sh" "cleanup-test" 2>/dev/null; then
  echo "FAIL: missing template should have caused exit non-zero"; exit 1
fi
[ ! -d "$TARGET" ] || { echo "FAIL: partial folder should have been cleaned up, but still exists at $TARGET"; exit 1; }
rm -rf "$TMP_BAD_ROOT"

echo OK
