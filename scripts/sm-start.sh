#!/usr/bin/env bash
set -euo pipefail

# /super-manus:start <name> — create a new super-manus feature folder and set it active.
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

# Resolve template root: explicit env var wins, then CLAUDE_PLUGIN_ROOT, else error.
ROOT="${SUPER_MANUS_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
if [ -z "$ROOT" ] || [ ! -d "$ROOT/templates" ]; then
  echo "sm-start: template root not found (set SUPER_MANUS_ROOT or run via Claude Code plugin context)" >&2
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

mkdir -p "$folder" .super-manus
for f in task_plan.md findings.md progress.md; do
  src="$ROOT/templates/$f"
  [ -f "$src" ] || { echo "sm-start: template missing: $src" >&2; cleanup_partial; exit 1; }
  # Substitute <feature title> placeholder. Use sed with a delimiter unlikely to collide.
  sed "s|<feature title>|${name}|g" "$src" > "$folder/$f"
done

trap - ERR
echo "$basename" > .super-manus/active

# Print the resolved folder path for the caller (Claude reads this and confirms to user)
echo "$(pwd)/$folder"
