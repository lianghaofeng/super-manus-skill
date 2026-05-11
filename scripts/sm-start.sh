#!/usr/bin/env bash
set -euo pipefail

# /super-manus:start — enable super-manus in this project (no-arg, idempotent).
#
# Project-global layout:
#   docs/super-manus/
#     ├── prd/
#     │   └── _index.md          (seeded from templates/prd_index.md)
#     ├── impl/                  (empty; populated by /super-manus:brainstorm + /super-manus:sync)
#     ├── roadmap.md             (seeded from templates/roadmap.md)
#     └── drift_log.md           (seeded from templates/drift_log.md; v0.9.5 R10 — renamed from prd_drift.md, two H2 sections: ## PRD drift / ## Spec drift)
#
# Per-module PRD files (prd/<module>.md) and per-module engineering reference
# files (prd/<module>.spec.md, v0.9.5 R7 — sibling to PRD), plus the four-file
# work set (impl/<module>/<update>/{task_plan,findings,progress,tasks}) are NOT
# created here — /super-manus:brainstorm seeds the per-module PRD + spec pair,
# and /super-manus:sync seeds update folders. On re-run of this script against
# an existing project, missing <module>.spec.md siblings ARE seeded (idempotent
# spec-coverage repair for projects that pre-date v0.9.5).
#
# Idempotent: if docs/super-manus/prd/_index.md already exists, exits 0 silently.
#
# Templates are sourced from $SUPER_MANUS_ROOT/templates (defaults to plugin root via $CLAUDE_PLUGIN_ROOT).

if [ $# -ne 0 ]; then
  echo "usage: sm-start.sh   (no arguments — v0.4 super-manus is project-global)" >&2
  exit 2
fi

# Resolve template root: explicit env var wins, then CLAUDE_PLUGIN_ROOT, then self-locate via $0.
# The script lives at <plugin-root>/scripts/sm-start.sh, so two `dirname`s up is the plugin root.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DERIVED_ROOT="$(dirname "$SCRIPT_DIR")"
ROOT="${SUPER_MANUS_ROOT:-${CLAUDE_PLUGIN_ROOT:-$DERIVED_ROOT}}"
if [ ! -d "$ROOT/templates" ]; then
  echo "sm-start: template root not found at '$ROOT' (set SUPER_MANUS_ROOT or run via Claude Code plugin context)" >&2
  exit 1
fi

base="docs/super-manus"
index_file="$base/prd/_index.md"

# v0.9.5 R10 migration (runs on both fresh + idempotent paths so re-runs of
# sm-start against a pre-v0.9.5 project actually pick up the rename): legacy
# prd_drift.md present but no drift_log.md yet → seed drift_log.md from template,
# refile legacy rows under ## PRD drift, move legacy file to a .legacy backup.
# Conservative: only runs when prd_drift.md exists AND drift_log.md does not, so
# a second invocation finds drift_log.md present and skips this whole block.
if [ -f "$base/prd_drift.md" ] && [ ! -f "$base/drift_log.md" ]; then
  legacy="$base/prd_drift.md"
  src="$ROOT/templates/drift_log.md"
  [ -f "$src" ] || { echo "sm-start: template missing during prd_drift→drift_log migration: $src" >&2; exit 1; }
  cp "$src" "$base/drift_log.md"
  # Insert legacy data rows under ## PRD drift section, after the schema separator row.
  # Python because awk -v doesn't accept multi-line variables cleanly.
  LEGACY="$legacy" TARGET="$base/drift_log.md" python3 - <<'PY'
import os, re, sys
legacy = open(os.environ["LEGACY"]).read()
# Capture rows starting with "|", drop the first two (schema header + separator).
rows = [ln for ln in legacy.splitlines() if ln.startswith("|")]
data_rows = rows[2:] if len(rows) > 2 else []
if not data_rows:
    sys.exit(0)
target_path = os.environ["TARGET"]
target = open(target_path).read().splitlines()
out = []
inserted = False
for line in target:
    out.append(line)
    if not inserted and line == "| --- | --- | --- | --- |":
        # First match is ## PRD drift's separator; insert legacy rows here.
        out.extend(data_rows)
        inserted = True
open(target_path, "w").write("\n".join(out) + "\n")
PY
  mv "$legacy" "$base/prd_drift.md.legacy-pre-v0.9.5"
fi

# Idempotent short-circuit: already enabled. Still seed any missing per-module
# <module>.spec.md siblings (v0.9.5 R7 — required-mode requirement). On a re-run
# of /super-manus:start in an existing project, modules declared in roadmap.md
# may have <module>.md but no <module>.spec.md yet (e.g. project pre-dates
# v0.9.5). Seed the missing siblings so the end-of-update drift gate's spec
# check doesn't fire pending rows on the next run.
if [ -f "$index_file" ]; then
  spec_template="$ROOT/templates/prd_spec.md"
  if [ -f "$spec_template" ] && [ -d "$base/prd" ]; then
    for prd_file in "$base/prd"/*.md; do
      [ -f "$prd_file" ] || continue
      fname=$(basename "$prd_file")
      # Skip _index.md and any *.spec.md (siblings, not modules)
      case "$fname" in
        _index.md|*.spec.md) continue ;;
      esac
      module="${fname%.md}"
      spec_file="$base/prd/${module}.spec.md"
      if [ ! -f "$spec_file" ]; then
        sed "s|<module name>|${module}|g" "$spec_template" > "$spec_file"
      fi
    done
  fi
  echo "$(pwd)/$base"
  exit 0
fi

mkdir -p "$base/prd" "$base/impl"

# prd/_index.md — copy template verbatim (no <feature title> substitution in v0.4;
# the project's own README / pyproject / etc. carries the title)
src="$ROOT/templates/prd_index.md"
[ -f "$src" ] || { echo "sm-start: template missing: $src" >&2; exit 1; }
cp "$src" "$index_file"

# roadmap.md and drift_log.md — copy verbatim (only if missing, to be safe under
# partial re-runs even though the index_file short-circuit normally guards us).
# v0.9.5 R10 renamed prd_drift.md → drift_log.md (two H2 sections: ## PRD drift / ## Spec drift).
# The legacy migration ran above (before the short-circuit), so by the time we
# hit this loop drift_log.md may already exist with refiled rows; the test below
# is the normal "don't overwrite" guard, not the migration logic.
for f in roadmap.md drift_log.md; do
  src="$ROOT/templates/$f"
  [ -f "$src" ] || { echo "sm-start: template missing: $src" >&2; exit 1; }
  if [ ! -f "$base/$f" ]; then
    cp "$src" "$base/$f"
  fi
done

# Drop a .gitignore so hook-managed runtime state (.session-state and friends)
# inside impl/<module>/<update>/ doesn't pollute `git status`.
if [ ! -f "$base/.gitignore" ]; then
  cat > "$base/.gitignore" <<'EOF'
# super-manus runtime state — managed by Stop hook, do not commit
**/.session-*
EOF
fi

# v0.8.1: seed .super-manus/agents.yml — static user preference for per-agent
# model override. .super-manus/ is intentionally separate from docs/super-manus/:
# the latter holds business state (PRD, roadmap, impl history) that's reviewed
# in PR diffs; the former holds tool config that's set once and rarely touched.
# .super-manus/ MUST NOT be used for dynamic runtime state — active update
# resolution still goes through sm_active_update's mtime scan.
if [ ! -d ".super-manus" ]; then
  mkdir -p .super-manus
fi
if [ ! -f ".super-manus/agents.yml" ]; then
  src="$ROOT/templates/agents.yml"
  if [ -f "$src" ]; then
    cp "$src" ".super-manus/agents.yml"
  fi
fi

# Print the resolved folder path for the caller (Claude reads this and confirms to user)
echo "$(pwd)/$base"
