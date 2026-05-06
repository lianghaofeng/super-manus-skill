#!/usr/bin/env bash
# Layout-invariant test for v0.5: additive on top of v0.4 (project-global PRD
# layout intact). Asserts the v0.5 layout invariants — design-v0.5.md is the
# current source of truth, design-v0.4.md is SUPERSEDED, README + CLAUDE.md
# document the e2e/ permanent regression directory + impl/<m>/<u>/tests/ phase
# tests separation, the three new skills exist, the two new impl agents exist,
# /super-manus:impl-all command exists.

set -euo pipefail
cd "$(dirname "$0")/.."

# 1. design-v0.5.md exists
[ -f "docs/design-v0.5.md" ] || { echo "FAIL: docs/design-v0.5.md must exist (current source of truth)"; exit 1; }

# 2. design-v0.4.md has SUPERSEDED banner
grep -qF "SUPERSEDED" docs/design-v0.4.md \
  || { echo "FAIL: docs/design-v0.4.md must carry a SUPERSEDED banner"; exit 1; }

# 3. README.md mentions the v0.5 e2e/ and impl/ paths.
grep -qF "docs/super-manus/e2e/" README.md \
  || { echo "FAIL: README.md must mention docs/super-manus/e2e/ path"; exit 1; }
grep -qF "docs/super-manus/impl/" README.md \
  || { echo "FAIL: README.md must mention docs/super-manus/impl/ path"; exit 1; }

# 4. README mentions the phase-tests vs e2e-tests separation.
grep -qiE "phase tests" README.md || { echo "FAIL: README.md must mention 'phase tests'"; exit 1; }
grep -qiE "e2e tests|e2e regression|e2e suite|permanent regression" README.md \
  || { echo "FAIL: README.md must mention e2e tests / regression suite"; exit 1; }

# 5. plugin.json exists with a "version" key. (DO NOT assert "0.5.0" yet — the
# version bump happens AFTER tests pass; we don't want this test to fail before
# the bump.)
[ -f ".claude-plugin/plugin.json" ] || { echo "FAIL: .claude-plugin/plugin.json must exist"; exit 1; }
grep -qE '"version"[[:space:]]*:[[:space:]]*"' .claude-plugin/plugin.json \
  || { echo "FAIL: .claude-plugin/plugin.json must have a \"version\" key"; exit 1; }

# 6. CLAUDE.md mentions the v0.5 e2e/ and impl/.../tests/ paths.
grep -qF "docs/super-manus/e2e/" CLAUDE.md \
  || { echo "FAIL: CLAUDE.md must mention docs/super-manus/e2e/ path"; exit 1; }
# Accept either the long form (impl/<module>/<update>/tests/) or the short form
# (impl/<m>/<u>/tests/) — both denote the same v0.5 phase-tests location.
grep -qE "impl/<module>/<update>/tests/|impl/<m>/<u>/tests/" CLAUDE.md \
  || { echo "FAIL: CLAUDE.md must mention impl/<module>/<update>/tests/ (or impl/<m>/<u>/tests/) path"; exit 1; }

# 7. CLAUDE.md has a "v0.5 layout" subsection.
grep -qiF "v0.5 layout" CLAUDE.md \
  || { echo "FAIL: CLAUDE.md must contain a 'v0.5 layout' subsection"; exit 1; }

# 8. skills/using-sm/SKILL.md mentions the 3 new v0.5 skill names.
for skill in tdd-in-phases verification-before-phase-close systematic-debugging-in-phase; do
  grep -qF "$skill" skills/using-sm/SKILL.md \
    || { echo "FAIL: skills/using-sm/SKILL.md must reference the v0.5 skill '$skill'"; exit 1; }
done

# 9. The 3 new skill SKILL.md files exist.
for skill in tdd-in-phases verification-before-phase-close systematic-debugging-in-phase; do
  [ -f "skills/$skill/SKILL.md" ] \
    || { echo "FAIL: skills/$skill/SKILL.md must exist"; exit 1; }
done

# 10. The 2 new agent files exist.
[ -f "agents/impl-test-writer.md" ] || { echo "FAIL: agents/impl-test-writer.md must exist"; exit 1; }
[ -f "agents/impl-code-writer.md" ] || { echo "FAIL: agents/impl-code-writer.md must exist"; exit 1; }

# 11. The new command file exists.
[ -f "commands/impl-all.md" ] || { echo "FAIL: commands/impl-all.md must exist"; exit 1; }

echo OK
