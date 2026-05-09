# super-manus v0.9.3 — deferred items log

This file is a forward-looking note, NOT a shipped release. Items recorded here are deferred design ideas surfaced during v0.9.x usage. Each entry stays here until either (a) it ships in a v0.9.x release (move to that release's design doc) or (b) it's rejected (record the rejection inline). Do NOT implement any item below without a separate user "ship it" directive.

## 1. probe-runtime listening-ports grayfilter

### Observation

`scripts/probe-runtime.sh` step 2 ("Listening ports") prints `lsof -iTCP -sTCP:LISTEN | head -40` raw. On a developer's macOS machine the output is dominated by system / IDE / chat-app processes that are guaranteed-not-project:

```
ControlCe (Control Center, ports 5000/7000)
rapportd (macOS handoff)
Code\x20H (VS Code helper)
Electron, language_ (IDE-internal)
WeChat (multiple ports)
privoxy, ss-local (proxy stacks)
com.docke (docker desktop manager, NOT the docker daemon's containers)
```

These dilute signal-to-noise to roughly 5-10 useful lines / 30-35 noise lines. The downstream architect agent has to filter mentally on every reverse-prd run.

### Why it's not in v0.9.0

The probe philosophy is "raw evidence → let the LLM judge." A blanket filter risks dropping legitimate processes for projects that genuinely use these binaries (e.g. an Electron-based app, a project that wraps `Code\x20H` Server). v0.9.0 chose to ship the raw dump and trust LLM filtering.

### Proposed v0.9.3 intervention (NOT yet ratified)

Add a **grayfilter** of known-false-positive process names. Inclusion criteria for the list: process name is high-confidence "macOS / chat / IDE noise" AND no plausible super-manus project would name a process this way.

Initial list (add only when corroborated by real false-positive observation):

```
ControlCe, rapportd, Code\x20H, Electron, language_, WeChat, privoxy, ss-local, com.docke
```

Implementation sketch (~5 lines):

```bash
# In probe-runtime.sh step 2, after lsof, before head -40:
GRAYFILTER='^(ControlCe|rapportd|Code\\x20H|Electron|language_|WeChat|privoxy|ss-local|com\.docke)'
listen_out=$(... | grep -vE "$GRAYFILTER" | head -40)
```

Plus a regression test (`tests/test_probe_runtime.sh` extension) that asserts the grayfilter is wired and the list is exhaustive against a synthetic lsof fixture.

### Open questions before ship

- **Scope.** macOS-only? Linux developer machines may have completely different noise (gnome-keyring, systemd-resolved, etc.).
- **Override.** Should the user be able to override the grayfilter via `.super-manus/agents.yml` (or a new config key) for projects where `Electron` is genuinely a project process?
- **Visibility.** When grayfilter drops lines, should the probe emit a one-line note ("filtered N grayfilter hits — set `probe.noise_filter = false` to disable") so users know it happened?

These three questions need to be answered before v0.9.3 implements. Until then: deferred.

### Status: open, no ship date

User said: "记一下到 0.9.3 design 吧 先不改". Surface in a future session when probe-runtime usage data is richer.

---

## 2. PRD voice discipline — prevent + retro-clean impl leakage

### Observation

Real-world reverse-prd output (teachagent `tutor-agent.md` after dynamic-analysis pass) demonstrates that `reverse-prd-architect` cheerfully promotes implementation tuning into PM-voice sections of the PRD. Concrete examples found in audit:

- **LLM tuning parameters in `## What users get`**: `task_type=chinese_language`, `temperature=0.1`, `max_tokens=80`, `httpx.Timeout(0.3s)` — these are call-site config, invisible to end users.
- **Internal state struct field names in user-facing prose**: `active_agent`, `current_mode`, `target_agent`, `intent_decision={source:"manual_override"}` — schema details, not user observations.
- **Verbatim wire schemas**: `{"kind":"set_mode","mode":"chat|practice|lesson"}` JSON literal pasted into a capability bullet.
- **Specific tuning constants**: "tail 6 条压成 ≤3 句 4 字段摘要 (课题 / 最近 KP / 学生状态 / 关键词)" — the 6 / 3 / 4 numbers are impl knobs, not UX claims.

Symptom: bullets become unreadable to non-engineers (PMs, designers, support, end users) — exactly the audience the PRD is supposed to serve. This is the predictable failure mode of using runtime probe + source-grep evidence: the architect over-cites by pasting config in raw rather than translating to user observation.

The architect persona at `agents/reverse-prd-architect.md` currently has no voice discipline beyond "PM-flavored H2 sections." The cite bias of v0.8.3 reverse-prd ("be specific, ground claims in source") accidentally rewards verbatim impl reproduction.

### Why this matters more than the grayfilter (item 1)

This is **PRD-driven development** infrastructure rot. If the PRD that drives every downstream phase plan is itself muddied with impl-spec, the test-writer mirror-test risk goes up (test-writer reads the PRD's impl-detail and builds tests against the wire schema rather than user observation), and the user loses the ability to read PRD as the canonical user-visible contract.

### Requirement R1 — architect prevention discipline (forward)

`agents/reverse-prd-architect.md` MUST add a `## PRD voice discipline` section that enumerates:

**Banned in PM-voice prose** (the body text of `## What users get` / `## Why this exists` / `## Users` / `## Success metric statements` / `## Quality bar` claim text):

1. LLM tuning parameters: `temperature`, `max_tokens`, `top_k`, `task_type`, model name (e.g. `gpt-4o`, `claude-opus`)
2. Internal state struct field names referenced verbatim (`active_agent`, `current_mode`, etc.)
3. HTTP/WS payload JSON literals (the schema goes elsewhere; the user observation goes here)
4. Wire field names (`payload.intent_decision.source`)
5. Tuning constants without user-observable framing (e.g. "frozen-set of 23 keywords", "tail 6 turns", "≤3 sentences" used as engineering knob)

**Allowed in PM-voice prose** (genuine user-facing contract surface):

1. WS event names the client UI binds (`lesson.choice_needed`, `mode.switched`) — the user-visible protocol
2. HTTP route paths (`/api/ask`, `/healthz`, `/metrics`)
3. User-observable durations / counts when expressed as user observation: "切档延迟 ≤ 300ms" ✅; "`httpx.Timeout(0.3s)`" ❌ (same number, opposite voice)
4. Concrete UX numbers ("15-30 min session", "p95 first-token <2s")

**Rewrite rule** (the operating principle, generalizable beyond the lists above):

> Replace "the system does X with parameter Y at line Z" with "the user experiences observable behavior B" and put X/Y/Z in the `Backed by:` citation, NOT in the bullet body.

**Self-check before write**:

> For every bullet you draft, ask: "would a PM / customer success engineer / support engineer who has never seen the source code understand this without grepping?" If not, rewrite. The `Backed by:` cite line is where engineering evidence belongs.

### Requirement R2 — `/super-manus:prd-update <module>` retro-cleanup mode

`commands/prd-update.md` MUST gain a third mode in addition to its existing two (forward iteration / drift absorption):

**Mode 3: voice-pass cleanup** — invoked explicitly via `/super-manus:prd-update <module> --voice-pass` (flag name TBD), OR auto-detected when `prd-update` opens an existing PRD whose body contains impl-leakage patterns above a threshold.

Procedure:

1. Read `prd/<module>.md`.
2. **Lint pass** — regex-scan PM-voice sections for the banlist (R1 categories 1-5). Output per-match list with file:line.
3. **Spawn `reverse-prd-architect` in `voice-cleanup` mode** (new mode parameter — architect's existing scope/per-module mode is preserved). The architect:
   - Receives the lint hits as input.
   - For each hit, drafts a PM-voice rewrite that preserves the user-observable claim and demotes impl detail to the `Backed by:` cite line.
   - Returns a side-by-side diff (before/after per bullet).
4. Orchestrator surfaces each rewrite via `AskUserQuestion` (multi-question, one per bullet) — user picks `accept` / `reject` / `edit-myself`.
5. On accept, edit the PRD in place — preserve the `Backed by:` cite line unchanged so the evidence chain holds.
6. Append a row to `prd_drift.md` documenting the voice-pass: `| <date> | <module> | voice-cleanup applied: N bullets reworded | resolved-by-prd-update |` — the drift log captures the cleanup so it shows up in `git log -p prd/<module>.md` audit.

This mode is **idempotent** — running twice on a clean PRD lints zero hits and exits with "no impl-leakage detected; PRD already in PM voice."

### Requirement R3 — tests

1. `tests/test_agent_reverse_prd_architect.sh` MUST assert:
   - `## PRD voice discipline` section heading is present
   - The five banned categories are enumerated by name
   - The "rewrite rule" (replace impl phrasing with user-observable phrasing) appears verbatim
   - The "self-check" question (PM / support engineer would understand) appears verbatim
2. New test `tests/test_prd_voice_lint.sh` — runs the banlist regex against a synthetic PRD fixture with intentional leakage, asserts the lint catches all of them. Edge cases: a "## Quality bar" line containing "300ms" must NOT trip lint when phrased as user observation (test asserts the lint distinguishes "≤ 300ms" from "`httpx.Timeout(0.3s)`").
3. `tests/test_command_prd_update_logic.sh` extension — assert the new `voice-pass` mode is documented and the dispatch logic mentions all three modes (forward / drift / voice-pass).

### How this fits PRD-driven development

The v0.9.3 design doc (this file) IS the requirement spec. R1 / R2 / R3 are the three normative claims. When v0.9.3 actually ships:

- R1 lands as agent persona changes (`agents/reverse-prd-architect.md`)
- R2 lands as command logic + new architect mode (`commands/prd-update.md`, `agents/reverse-prd-architect.md` new mode parameter)
- R3 lands as test files

The user's existing dirty PRDs (e.g. teachagent `tutor-agent.md`) get cleaned by running `/super-manus:prd-update tutor-agent --voice-pass` once — no manual editing required.

### Open questions before ship

- **Lint precision.** The banlist must NOT false-positive on legitimate user-observable mentions ("response within 300ms" is fine; "`httpx.Timeout(0.3s)`" is not). Need to design the regex to distinguish — likely "presence of code-formatting backticks around the impl detail" is the signal.
- **Threshold for auto-detect.** If `prd-update` should auto-suggest voice-pass mode when leakage is detected (rather than requiring the explicit flag), what's the trigger threshold? "≥1 hit" surfaces too often; "≥5 hits" lets small leakage accumulate. Probably "≥3 hits in a single section" or "≥1 hit in `## What users get` (highest user visibility)" — needs experimentation.
- **`AskUserQuestion` cost on big cleanups.** A PRD with 20 leakage hits would mean 20 user prompts. Should the cleanup batch them ("here are 20 rewrites; review all together") rather than one-at-a-time? Probably batch UI is friendlier; needs UX iteration.
- **Cite preservation guarantee.** R2 step 5 says "preserve the `Backed by:` cite line unchanged." If the rewrite changes which file/line is the most precise evidence, the cite may need updating too. Conservative shape: the architect proposes both bullet-body and cite-line rewrites; the user approves both as a unit. Permissive shape: cite stays frozen (forces architect to translate without changing evidence). Conservative wins on safety; permissive wins on simplicity. TBD.
- **Granularity of voice-pass on multi-module project.** Run on one module at a time (current `--voice-pass <module>` shape) or whole-project sweep? Whole-project is faster but harder to review; per-module is safer. Probably per-module ships first; whole-project as a follow-up if usage demand surfaces.

### Status: open, no ship date — R1/R2/R3 ratification needed first

User said: "肯定是要 reverse-prd-architect 改…和 0.9.3 一起更新吧…要符合 prd 文档风格，改 requirement 之后能落实到 impl". This entry IS the requirement spec; once you ratify R1-R3 (or amend them), v0.9.3 can ship as a single milestone covering all three.
