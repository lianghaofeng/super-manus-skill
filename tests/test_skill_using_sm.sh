#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

F="skills/using-sm/SKILL.md"
[ -f "$F" ] || { echo "FAIL: $F missing"; exit 1; }

# Frontmatter: must have name, description (>=40 chars), user-invocable
python3 - <<'PY' || { echo "FAIL: frontmatter check failed"; exit 1; }
import re, sys
with open("skills/using-sm/SKILL.md") as f:
    text = f.read()
m = re.match(r'^---\n(.*?)\n---\n', text, re.DOTALL)
assert m, "missing YAML frontmatter block"
fm = m.group(1)
# Crude line-by-line key check (no yaml dep)
keys = {}
for line in fm.splitlines():
    if ':' in line:
        k, _, v = line.partition(':')
        keys[k.strip()] = v.strip()
assert keys.get("name") == "using-sm", f"name must be 'using-sm', got {keys.get('name')!r}"
desc = keys.get("description", "")
assert len(desc) >= 40, f"description must be >=40 chars, got {len(desc)}: {desc!r}"
PY

# Body must contain all 6 required topics (loose grep — match the most likely heading variants)
for needle in "Where state lives" "What goes in which file" "When to update" "2-action" "3-strike" "Anti-pattern"; do
  grep -qiF "$needle" "$F" || { echo "FAIL: missing required section topic: $needle"; exit 1; }
done

# Must reference all three state files by name
for ref in "task_plan.md" "findings.md" "progress.md"; do
  grep -qF "$ref" "$F" || { echo "FAIL: missing reference to $ref"; exit 1; }
done

# Must mention the four status values
for s in "pending" "in_progress" "blocked" "closed"; do
  grep -qF "$s" "$F" || { echo "FAIL: missing status value: $s"; exit 1; }
done

# Footer: must credit planning-with-files
grep -qF "planning-with-files" "$F" || { echo "FAIL: missing planning-with-files credit footer"; exit 1; }

echo OK
