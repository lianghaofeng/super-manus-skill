#!/usr/bin/env bash
set -euo pipefail

# /super-manus:start <name> — create a new super-manus v0.2 feature folder and set it active.
#
# v0.2 layout:
#   docs/super-manus/<YYYY-MM-DD>-<name>/
#     prd/_index.md          (seeded from templates/prd_index.md, <feature title> substituted)
#     impl/                  (empty; populated by /super-manus:brainstorm and /super-manus:sync)
#     roadmap.md             (seeded from templates/roadmap.md)
#     prd_drift.md           (seeded from templates/prd_drift.md)
#
# Per-module PRD files (prd/<module>.md) and the four-file work set
# (impl/<module>/<update>/{task_plan,findings,progress,tasks}) are NOT created
# here — /super-manus:brainstorm seeds them after module-split Q&A.
#
# Templates are sourced from $SUPER_MANUS_ROOT/templates (defaults to plugin root via $CLAUDE_PLUGIN_ROOT).

if [ $# -ne 1 ] || [ -z "${1:-}" ]; then
  echo "usage: sm-start.sh <feature-name>" >&2
  exit 2
fi

name="$1"
if ! [[ "$name" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "sm-start: invalid name '$name' — must match ^[a-z0-9][a-z0-9-]*\$ (lowercase, kebab-case, no leading hyphen)" >&2
  exit 1
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

today=$(date +%F)
basename="${today}-${name}"
folder="docs/super-manus/${basename}"

if [ -e "$folder" ]; then
  echo "sm-start: feature folder already exists: $folder — use /super-manus:switch ${name} instead" >&2
  exit 1
fi

cleanup_partial() {
  rm -rf "$folder"
}
trap cleanup_partial ERR

mkdir -p "$folder/prd" "$folder/impl" .super-manus

# prd/_index.md — substitute <feature title>
src="$ROOT/templates/prd_index.md"
[ -f "$src" ] || { echo "sm-start: template missing: $src" >&2; cleanup_partial; exit 1; }
sed "s|<feature title>|${name}|g" "$src" > "$folder/prd/_index.md"

# roadmap.md and prd_drift.md — copy verbatim (no <feature title> placeholder)
for f in roadmap.md prd_drift.md; do
  src="$ROOT/templates/$f"
  [ -f "$src" ] || { echo "sm-start: template missing: $src" >&2; cleanup_partial; exit 1; }
  cp "$src" "$folder/$f"
done

trap - ERR

# Drop a .gitignore so hook-managed runtime state (.session-state and friends)
# doesn't pollute `git status` for the project that uses super-manus.
cat > "$folder/.gitignore" <<'EOF'
# super-manus runtime state — managed by Stop hook, do not commit
.session-*
EOF

echo "$basename" > .super-manus/active

# Print the resolved folder path for the caller (Claude reads this and confirms to user)
echo "$(pwd)/$folder"
