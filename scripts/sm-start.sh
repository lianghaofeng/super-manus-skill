#!/usr/bin/env bash
set -euo pipefail

# /super-manus:start — enable super-manus in this project (no-arg, idempotent).
#
# v0.4 layout (project-global PRD):
#   docs/super-manus/
#     ├── prd/
#     │   └── _index.md          (seeded from templates/prd_index.md)
#     ├── impl/                  (empty; populated by /super-manus:brainstorm + /super-manus:sync)
#     ├── roadmap.md             (seeded from templates/roadmap.md)
#     └── prd_drift.md           (seeded from templates/prd_drift.md)
#
# Per-module PRD files (prd/<module>.md) and the four-file work set
# (impl/<module>/<update>/{task_plan,findings,progress,tasks}) are NOT created
# here — /super-manus:brainstorm and /super-manus:sync seed them.
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

# Idempotent short-circuit: already enabled.
if [ -f "$index_file" ]; then
  echo "$(pwd)/$base"
  exit 0
fi

mkdir -p "$base/prd" "$base/impl"

# prd/_index.md — copy template verbatim (no <feature title> substitution in v0.4;
# the project's own README / pyproject / etc. carries the title)
src="$ROOT/templates/prd_index.md"
[ -f "$src" ] || { echo "sm-start: template missing: $src" >&2; exit 1; }
cp "$src" "$index_file"

# roadmap.md and prd_drift.md — copy verbatim (only if missing, to be safe under
# partial re-runs even though the index_file short-circuit normally guards us)
for f in roadmap.md prd_drift.md; do
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

# Print the resolved folder path for the caller (Claude reads this and confirms to user)
echo "$(pwd)/$base"
