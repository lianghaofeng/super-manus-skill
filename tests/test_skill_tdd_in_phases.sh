#!/usr/bin/env bash
# Tests skills/tdd-in-phases/SKILL.md — phase-scoped TDD discipline for v0.5.
# When /super-manus:impl enters a phase, impl-test-writer commits red phase tests
# + e2e tests BEFORE impl-code-writer runs. Tests derived from PRD spec, not impl plan.

set -euo pipefail
cd "$(dirname "$0")/.."
F="skills/tdd-in-phases/SKILL.md"
[ -f "$F" ] || { echo "FAIL: $F missing"; exit 1; }

# Frontmatter — name + non-empty description
python3 - <<'PY' || { echo "FAIL: frontmatter check failed"; exit 1; }
import re, sys
with open("skills/tdd-in-phases/SKILL.md") as f:
    text = f.read()
m = re.match(r'^---\n(.*?)\n---\n', text, re.DOTALL)
assert m, "missing YAML frontmatter block"
fm = m.group(1)
keys = {}
for line in fm.splitlines():
    if ':' in line:
        k, _, v = line.partition(':')
        keys[k.strip()] = v.strip()
assert keys.get("name") == "tdd-in-phases", f"name must be 'tdd-in-phases', got {keys.get('name')!r}"
desc = keys.get("description", "")
assert len(desc) >= 40, f"description must be >=40 chars, got {len(desc)}"
PY

# Phase test path pattern — use the full v0.5 path so the skill stays load-bearing
# for the orchestrator's parsing.
grep -qF "docs/super-manus/impl/" "$F" || { echo "FAIL: must reference docs/super-manus/impl/ phase test path"; exit 1; }
grep -qF "tests/" "$F" || { echo "FAIL: must reference tests/ subdirectory inside the update folder"; exit 1; }
grep -qF "phase_p" "$F" || { echo "FAIL: must reference phase_p<n>_ phase test naming pattern"; exit 1; }

# PRD-derived test source: ## What users get + ## Demo
grep -qF "## What users get" "$F" || { echo "FAIL: must mention prd/<module>.md ## What users get as test source"; exit 1; }
grep -qF "## Demo" "$F" || { echo "FAIL: must mention prd/_index.md ## Demo as test source"; exit 1; }

# Sequencing: test-writer commits red BEFORE code-writer runs. (Non-negotiable order.)
grep -qiE "BEFORE.*code-writer|test-writer.*BEFORE|before the code-writer|before impl-code-writer" "$F" \
  || { echo "FAIL: must say test-writer commits BEFORE code-writer runs (sequencing)"; exit 1; }
grep -qiE "red.*tests|red bar|red \(failing\)|currently failing" "$F" \
  || { echo "FAIL: must say tests are committed in red (failing) state"; exit 1; }

# Code-writer must NOT edit/skip tests.
grep -qiE "MUST NOT.*edit|do NOT.*modify|forbidden.*edit|cannot edit" "$F" \
  || { echo "FAIL: must say code-writer must NOT edit tests"; exit 1; }
grep -qiE "skip|@pytest\.skip|it\.skip" "$F" \
  || { echo "FAIL: must say code-writer must NOT skip tests"; exit 1; }

echo OK
