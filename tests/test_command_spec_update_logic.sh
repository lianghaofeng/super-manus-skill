#!/usr/bin/env bash
# Tests commands/spec-update.md — the v0.9.5 R8 spec-side analog of /super-manus:prd-update.
# Standalone command (not a /prd-update --scope=spec flag, per R8 OQ1 ratification).
# Single-section minimum edit on prd/<module>.spec.md, two trigger modes
# (forward iteration vs drift absorption), engineering voice.

set -euo pipefail
cd "$(dirname "$0")/.."
F=commands/spec-update.md
[ -f "$F" ] || { echo "FAIL: missing $F"; exit 1; }

# Frontmatter
grep -qF "description:" "$F" || { echo "FAIL: missing frontmatter description"; exit 1; }

# v0.4 invariant: no .super-manus/active state file
grep -qF ".super-manus/active" "$F" && { echo "FAIL: must NOT reference .super-manus/active in v0.4+"; exit 1; } || true

# Project-global PRD root + per-module spec target
grep -qF "docs/super-manus/prd/" "$F" || { echo "FAIL: must reference docs/super-manus/prd/ as the PRD root"; exit 1; }
grep -qF "<module>.spec.md" "$F" || { echo "FAIL: must operate on per-module <module>.spec.md"; exit 1; }

# Two trigger modes (mirrors prd-update)
grep -qiE "forward iteration" "$F" || { echo "FAIL: must document forward iteration mode"; exit 1; }
grep -qiE "drift absorption" "$F" || { echo "FAIL: must document drift absorption mode"; exit 1; }
# Mode auto-detection from drift_log.md ## Spec drift
grep -qiE "auto.detect|mode auto.detect" "$F" || { echo "FAIL: must auto-detect mode from drift_log.md state"; exit 1; }
grep -qF "drift_log.md" "$F" || { echo "FAIL: must reference drift_log.md (v0.9.5 R10 rename)"; exit 1; }
grep -qF "## Spec drift" "$F" || { echo "FAIL: must scope drift detection to ## Spec drift section (NOT ## PRD drift)"; exit 1; }

# Drift check is LIGHT (engineering voice can move with code) — single soft warning, not a block
grep -qiE "drift check.*light|light.*drift check|engineering voice|move with the code" "$F" \
  || { echo "FAIL: must document the LIGHT drift-check distinction (engineering voice can move with code)"; exit 1; }

# Hard constraints
grep -qiF "no changelog" "$F" || { echo "FAIL: must forbid changelog markers"; exit 1; }
grep -qiF "single section" "$F" || { echo "FAIL: must require single-section minimum edit"; exit 1; }
grep -qF "3000" "$F" || { echo "FAIL: must mention ~3000-word soft cap"; exit 1; }

# Stable headings — 4 H2 sections
for h in "## Data contracts" "## Interface contracts" "## Behavioral contracts" "## Design rationale"; do
  grep -qF "$h" "$F" || { echo "FAIL: must reference stable section '$h'"; exit 1; }
done
# Sub-headings under Interface contracts
grep -qF "### Exposes" "$F" || { echo "FAIL: must reference ### Exposes sub-section"; exit 1; }
grep -qF "### Consumes" "$F" || { echo "FAIL: must reference ### Consumes sub-section"; exit 1; }

# Engineering voice — schemas, code identifiers, file paths ALLOWED here (the differentiator from PRD voice)
grep -qiE "schema sketches|code identifiers|file paths|engineering voice" "$F" \
  || { echo "FAIL: must explicitly allow engineering-voice content (schemas/code/paths)"; exit 1; }

# Drift absorption mode — flips Resolution to spec-update: <section> (NOT prd-update:); skips findings.md write
grep -qiE "Resolution.*spec-update|spec-update:" "$F" \
  || { echo "FAIL: drift absorption must flip Resolution to 'spec-update: <section>' (distinct from PRD's 'prd-update:')"; exit 1; }
grep -qiE "skip the findings.md write|Skip the findings|engineering reality|no findings.md" "$F" \
  || { echo "FAIL: drift absorption must SKIP findings.md write (engineering reality, not product decision)"; exit 1; }

# Must NOT write to progress.md (hook-managed)
grep -qiF "progress.md" "$F" || { echo "FAIL: must mention progress.md (specifically: not to write to it)"; exit 1; }

# Refuse + redirect cases
grep -qiE "Multi-section|multi.section" "$F" \
  || { echo "FAIL: must refuse multi-section edits and redirect"; exit 1; }
grep -qF "/super-manus:reverse-prd-spec" "$F" \
  || { echo "FAIL: must redirect multi-section / large edits to /super-manus:reverse-prd-spec (the rebuild path)"; exit 1; }
grep -qF "/super-manus:prd-update" "$F" \
  || { echo "FAIL: must distinguish from /super-manus:prd-update (push back when edit is actually PRD-level NFR)"; exit 1; }

# Voice contrast section vs /super-manus:prd-update — load-bearing for users picking the right command
grep -qiE "Voice contrast|contrast.*prd-update|prd-update.*contrast" "$F" \
  || { echo "FAIL: should include a voice contrast section vs /super-manus:prd-update"; exit 1; }

# Must offer template-seed via AskUserQuestion when spec.md doesn't exist yet (the file is required-mode in v0.9.5)
grep -qiE "AskUserQuestion|create from template|seed from template" "$F" \
  || { echo "FAIL: must offer to seed spec.md from template (via AskUserQuestion) when it doesn't exist"; exit 1; }
grep -qF '${CLAUDE_PLUGIN_ROOT}/templates/prd_spec.md' "$F" \
  || { echo "FAIL: must reference \${CLAUDE_PLUGIN_ROOT}/templates/prd_spec.md as the seed source"; exit 1; }

# Edit tool, not Write — minimum-line surgical edit
grep -qiE "Edit tool|smallest old_string|smallest.*new_string|surgical edit" "$F" \
  || { echo "FAIL: must require Edit tool (not Write) for surgical single-section edit"; exit 1; }

# === v0.9.6 R11: Post-edit spec→PRD topic-overlap check ====================
# Symmetric to the same check in /super-manus:prd-update. After spec edit lands,
# scan PRD for shared-topic bullets. Soft warning, NOT hard gate (R7 OQ3 honor).

# Section heading exists
grep -qiE "^## Post-edit topic-overlap check|## Post-edit topic.overlap" "$F" \
  || { echo "FAIL: v0.9.6 R11 must declare a '## Post-edit topic-overlap check' section"; exit 1; }
# Skip if PRD missing
grep -qiE "Skip if PRD missing|PRD doesn.t exist|skip this whole section" "$F" \
  || { echo "FAIL: v0.9.6 R11 must skip the check when prd/<module>.md is absent"; exit 1; }
# Tokenization with stopwords (reuses prd-update's list)
grep -qiE "tokenize|noun.*verb|alphanumeric|stopword" "$F" \
  || { echo "FAIL: v0.9.6 R11 must define a tokenization rule for the edited bullet"; exit 1; }
# Threshold consistent with prd-update side
grep -qiE "≥3 distinct|3 distinct token|threshold.*3" "$F" \
  || { echo "FAIL: v0.9.6 R11 must specify the same ≥3 distinct token threshold as prd-update side"; exit 1; }
# Scans the right PRD sections (## What users get / ## Quality bar — most likely overlap targets)
grep -qF "## What users get" "$F" \
  || { echo "FAIL: v0.9.6 R11 must scan PRD ## What users get for capability-overlap"; exit 1; }
grep -qF "## Quality bar" "$F" \
  || { echo "FAIL: v0.9.6 R11 must scan PRD ## Quality bar for NFR-overlap (the section most likely to mirror spec ## Behavioral contracts)"; exit 1; }
# AskUserQuestion with same 3 options
grep -qiE "AskUserQuestion" "$F" \
  || { echo "FAIL: v0.9.6 R11 must use AskUserQuestion when overlap is detected"; exit 1; }
grep -qiE "Open PRD to inspect|Confirm consistent|soft-acknowledged" "$F" \
  || { echo "FAIL: v0.9.6 R11 must offer at least 3 user actions (open / confirm / soft-ack)"; exit 1; }
# Logging to drift_log.md ## PRD drift (note: opposite section from prd-update side)
grep -qiE "drift_log.md.*## PRD drift|## PRD drift.*drift_log" "$F" \
  || { echo "FAIL: v0.9.6 R11 spec-side must log to drift_log.md ## PRD drift section (opposite of prd-update side)"; exit 1; }
grep -qiE "acknowledged-soft|acknowledged.soft" "$F" \
  || { echo "FAIL: v0.9.6 R11 must use 'acknowledged-soft' Resolution"; exit 1; }
# Hard-gate exemption explicit
grep -qiE "NOT enter Pass 3|NOT.*hard gate|does NOT gate|R7 OQ3|without blocking" "$F" \
  || { echo "FAIL: v0.9.6 R11 must explicitly state the soft warning does NOT enter the hard gate"; exit 1; }
# Escalation to pending (manual edit on Resolution cell — same shape as prd-update side)
grep -qiE "flip to.*pending|genuinely conflicts.*pending|pending.*real drift|change THAT row.*pending|Resolution cell.*pending|escalation.*hard drift" "$F" \
  || { echo "FAIL: v0.9.6 R11 must document a user escalation path (manually change Resolution from 'acknowledged-soft' to 'pending') when overlap turns out to be a real conflict"; exit 1; }
# Skip logging on no overlap
grep -qiE "silence is the default|skip.*logging|don.t log.*no overlap" "$F" \
  || { echo "FAIL: v0.9.6 R11 must skip logging on no overlap"; exit 1; }

# === v0.9.6 R11.1: symmetric resolution paths after choice (a) ============
# Symmetric to prd-update side. (a) follow-up offers BOTH "fix PRD now" AND
# "revert/refine spec edit" as first-class options. R7 OQ3 symmetry honored.

# Section heading exists
grep -qiE "^### After choice \(a\)|## After choice \(a\)|symmetric resolution paths" "$F" \
  || { echo "FAIL: v0.9.6 R11.1 must declare a follow-up section after (a) for symmetric resolution"; exit 1; }
# 4 equal-weight options — both fix-PRD and fix-spec (revert-mine) are first-class
grep -qiE "fix PRD now|PRD is stale.*fix PRD" "$F" \
  || { echo "FAIL: v0.9.6 R11.1 (i) must offer 'fix PRD now' (inline prd-update)"; exit 1; }
grep -qiE "fix PRD later|prd-edit-deferred" "$F" \
  || { echo "FAIL: v0.9.6 R11.1 (ii) must offer 'fix PRD later' (acknowledged-soft: prd-edit-deferred)"; exit 1; }
grep -qiE "Spec edit was wrong|revert.*spec|refine.*spec edit" "$F" \
  || { echo "FAIL: v0.9.6 R11.1 (iii) must offer 'revert/refine spec' as a first-class option (R7 OQ3 symmetric direction)"; exit 1; }
grep -qiE "Both are correct.*voice|confirmed-consistent" "$F" \
  || { echo "FAIL: v0.9.6 R11.1 (iv) must offer 'both correct in their voices' option"; exit 1; }
# Inline-execution discipline
grep -qiE "inline-execut|inline execut|do NOT spawn.*sub-Skill|drive.*pattern|nest.*slash command" "$F" \
  || { echo "FAIL: v0.9.6 R11.1 must declare inline-execution discipline (no nested slash commands; main-thread execution like drive.md)"; exit 1; }
# Resolution-precedence rule
grep -qiE "chained command.*precedence|don.t double-write|takes precedence|NOT.*acknowledged-soft" "$F" \
  || { echo "FAIL: v0.9.6 R11.1 must specify chained command's logging takes precedence (no double-write of Resolution)"; exit 1; }
# Edit-irreversibility caveat
grep -qiE "cannot be auto-reverted|Edit is destructive|manually restore.*prior wording" "$F" \
  || { echo "FAIL: v0.9.6 R11.1 (iii) must surface that the original Edit can't be auto-reverted"; exit 1; }

# === v0.9.6 R11.1 row-write timing discipline (symmetric to prd-update) ====
grep -qiE "Row-write timing|R11 does NOT write.*at the moment of overlap detection|deferred until the user's.*choice" "$F" \
  || { echo "FAIL: v0.9.6 R11.1 must declare row-write-timing discipline"; exit 1; }
grep -qiE "no R11 row.*chained|chained.*writes.*own row.*from scratch|R11 stays out of.*drift_log.md" "$F" \
  || { echo "FAIL: v0.9.6 R11.1 must specify (a→i) and (a→iii) branches defer to chained command for row writing"; exit 1; }
# spec-update side: (a→iii) goes to ## Spec drift (the spec-edit-revised path); (a→i) goes to ## PRD drift (chained prd-update)
grep -qF "## Spec drift" "$F" \
  || { echo "FAIL: v0.9.6 R11.1 logging table (in spec-update.md) must reference ## Spec drift (used when (a→iii) chained spec-update writes its own row from spec-edit-revised path)"; exit 1; }
grep -qiE "Hard-gates|enter.*hard gate|blocks.*roadmap" "$F" \
  || { echo "FAIL: v0.9.6 R11.1 logging table should make hard-gate status explicit per branch"; exit 1; }
grep -qiE "case-insensitive equality.*NOT substring|equality.*NOT substring|equals.*case-insensitive" "$F" \
  || { echo "FAIL: v0.9.6 R11.1 must clarify Pass 3 uses case-insensitive EQUALITY (not substring grep)"; exit 1; }

# === v0.9.7 R15: drift_log row append uses 5-column schema with Author ===
# spec-update.md writes drift_log rows in branches (b)/(c)/(a→ii)/(a→iv). The full
# row-template example must use the 5-column form with <author> as the second cell.
grep -qF "| <YYYY-MM-DD> | <author> | <module> |" "$F" \
  || { echo "FAIL: v0.9.7 R15 — spec-update.md must show a 5-column drift_log row template with <author> as the second cell (branches b/c/a→ii/a→iv)"; exit 1; }
grep -qF "git config user.name" "$F" \
  || { echo "FAIL: v0.9.7 R15 — spec-update.md must document Author cell source ('git config user.name')"; exit 1; }
grep -qiE "Date \| Author \| Module \| Conflict \| Resolution|5 column|5-column" "$F" \
  || { echo "FAIL: v0.9.7 R15 — spec-update.md must call out the 5-column drift_log schema explicitly so writers know the cell order"; exit 1; }

echo OK
