#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

REPO_ROOT="$(pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# v0.4: super-manus is project-global. /super-manus:start takes ZERO arguments and idempotently
# creates docs/super-manus/{prd,impl}/ + roadmap.md + prd_drift.md. There is no
# .super-manus/active state file in v0.4.
cd "$TMP"

# Helper: invoke the script with REPO_ROOT visible so it knows where templates live
sm_start() {
  SUPER_MANUS_ROOT="$REPO_ROOT" bash "$REPO_ROOT/scripts/sm-start.sh" "$@"
}

# Case A: any positional argument → exit non-zero (v0.4 takes ZERO arguments)
if sm_start "demo" 2>/dev/null; then echo "FAIL: positional arg 'demo' should be rejected (v0.4 takes 0 args)"; exit 1; fi
if sm_start "anything" 2>/dev/null; then echo "FAIL: any positional arg should be rejected"; exit 1; fi
if sm_start "two" "args" 2>/dev/null; then echo "FAIL: two args should be rejected"; exit 1; fi

# Case B: happy path — no args → creates v0.4 layout
out=$(sm_start)
BASE="docs/super-manus"
[ -d "$BASE" ] || { echo "FAIL: $BASE not created"; exit 1; }

# v0.4 layout: prd/, impl/, roadmap.md, prd_drift.md, NO per-feature wrapper folder
[ -d "$BASE/prd" ] || { echo "FAIL: $BASE/prd/ not created"; exit 1; }
[ -f "$BASE/prd/_index.md" ] || { echo "FAIL: $BASE/prd/_index.md not seeded"; exit 1; }
[ -d "$BASE/impl" ] || { echo "FAIL: $BASE/impl/ not created"; exit 1; }
[ -f "$BASE/roadmap.md" ] || { echo "FAIL: $BASE/roadmap.md not seeded"; exit 1; }
[ -f "$BASE/prd_drift.md" ] || { echo "FAIL: $BASE/prd_drift.md not seeded"; exit 1; }

# v0.4: must NOT create any per-feature wrapper folder under docs/super-manus/<date>-<name>/
shopt -s nullglob
wrappers=("$BASE"/[0-9]*)
shopt -u nullglob
if [ ${#wrappers[@]} -gt 0 ]; then
  echo "FAIL: v0.4 must NOT create per-feature wrapper folders, found: ${wrappers[*]}"
  exit 1
fi

# v0.4: must NOT create the legacy four-file work set at docs/super-manus root
for f in task_plan.md prd.md findings.md progress.md; do
  [ ! -f "$BASE/$f" ] || { echo "FAIL: legacy '$f' must NOT be seeded at $BASE root in v0.4"; exit 1; }
done

# v0.4: prd/_index.md is copied verbatim (no <feature title> substitution; the project's
# README / pyproject / etc. carries the title). The placeholder may remain for the user
# to edit in their first audit pass.

# roadmap and prd_drift remain generic (no per-feature substitution)
grep -q "^# Roadmap" "$BASE/roadmap.md" || { echo "FAIL: roadmap.md missing Roadmap title"; exit 1; }
grep -q "^# PRD drift log" "$BASE/prd_drift.md" || { echo "FAIL: prd_drift.md missing title"; exit 1; }

# .gitignore must still be set up so .session-state files don't leak
[ -f "$BASE/.gitignore" ] || { echo "FAIL: .gitignore not seeded"; exit 1; }
grep -qF ".session-" "$BASE/.gitignore" || { echo "FAIL: .gitignore should ignore .session-* files"; exit 1; }

# v0.4: must NOT write .super-manus/active (state file is gone)
[ ! -f .super-manus/active ] || { echo "FAIL: v0.4 must NOT write .super-manus/active (state file is gone)"; exit 1; }

# v0.8.1: .super-manus/agents.yml is a STATIC user-preference file for
# per-agent model overrides. sm-start MUST seed it from templates/agents.yml.
# Note: .super-manus/ DOES exist in v0.8.1 (re-introduced for static prefs only;
# dynamic state still resolves via mtime scan). This is a deliberate scoping —
# distinct from the v0.3-era .super-manus/active state file that v0.4 removed.
[ -d ".super-manus" ] || { echo "FAIL: v0.8.1 sm-start must create .super-manus/ for static user prefs"; exit 1; }
[ -f ".super-manus/agents.yml" ] || { echo "FAIL: v0.8.1 sm-start must seed .super-manus/agents.yml from templates/agents.yml"; exit 1; }
# Default template must have ALL 6 agents commented out (no override out-of-the-box)
grep -qE "^#impl-architect:" .super-manus/agents.yml || { echo "FAIL: default agents.yml must list impl-architect (commented)"; exit 1; }
grep -qE "^#reverse-prd-architect:" .super-manus/agents.yml || { echo "FAIL: default agents.yml must list reverse-prd-architect (commented)"; exit 1; }
# Active overrides (uncommented) MUST be zero in the seeded default — out-of-the-box
# behavior is "use the agent's pinned default", not "override everything to opus".
active_overrides=$(grep -cE "^[a-z][a-z0-9-]*:" .super-manus/agents.yml || true)
[ "$active_overrides" = "0" ] || { echo "FAIL: seeded agents.yml must have ZERO active overrides (all commented), found $active_overrides"; exit 1; }

# Echoed path should mention $BASE
echo "$out" | grep -q "$BASE" || { echo "FAIL: success output should mention $BASE path, got: $out"; exit 1; }

# Case C: idempotency — re-running with no args should exit 0 silently (already enabled)
out2=$(sm_start)
[ -d "$BASE/prd" ] || { echo "FAIL: re-run should leave prd/ intact"; exit 1; }
echo "$out2" | grep -q "$BASE" || { echo "FAIL: idempotent re-run should still echo $BASE, got: $out2"; exit 1; }

# Case D: missing template root → exit non-zero
rm -rf "$BASE"
TMP_BAD_ROOT=$(mktemp -d)
# Empty template root (no templates/ subdir at all)
if SUPER_MANUS_ROOT="$TMP_BAD_ROOT" bash "$REPO_ROOT/scripts/sm-start.sh" 2>/dev/null; then
  echo "FAIL: missing template root should have caused exit non-zero"; exit 1
fi
rm -rf "$TMP_BAD_ROOT"

echo OK
