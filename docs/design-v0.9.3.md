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

## 2. PRD voice discipline — fix at the architect

### What the PRD is supposed to be

A PRD describes the **current actual state of the module** in a way that is **easy for a human to understand**. Two properties, both load-bearing:

1. **Faithful** — every bullet matches what the code actually does; no fabricated capabilities, no stale claims.
2. **Readable** — a PM, designer, support engineer, or end user can read the PRD without grepping the source code to figure out what each line means.

The first property is enforced by `reverse-prd-architect`'s existing cross-validation discipline (runtime probe + source grep + `(audit)` markers for unverified claims). v0.9.0 + v0.8.3 made it solid.

The second property is **not** enforced today, and v0.9.0 audit of teachagent `tutor-agent.md` shows the architect failing it.

### Observation

Real-world reverse-prd output (teachagent `tutor-agent.md` after dynamic-analysis pass) demonstrates the architect promoting impl detail into PM-voice prose:

- LLM tuning parameters in `## What users get`: `task_type=chinese_language`, `temperature=0.1`, `max_tokens=80`, `httpx.Timeout(0.3s)`
- Internal state struct field names: `active_agent`, `current_mode`, `target_agent`, `intent_decision={source:"manual_override"}`
- Verbatim wire schemas: `{"kind":"set_mode","mode":"chat|practice|lesson"}`
- Tuning constants as bullet content: "tail 6 条压成 ≤3 句 4 字段摘要"

The bullets are **faithful** (they cite real code). They are **not readable** by anyone who hasn't already read the source. The architect's existing "be specific, ground claims" pressure rewarded verbatim impl reproduction over translation to user observation.

### Single requirement: architect persona gains voice discipline

`agents/reverse-prd-architect.md` adds a `## PRD voice discipline` section. The discipline says:

**Each bullet describes user-observable behavior, not the code that produces it.** Engineering evidence — file paths, function names, struct fields, constants, tuning parameters — goes into the `Backed by:` citation that already trails every bullet. The bullet body itself reads as PM voice.

**Worked examples** (concrete before/after the architect can pattern-match against):

```
❌ Before: rule miss 才走 LLM gateway fallback (task_type=chinese_language,
            temperature=0.1, max_tokens=80, httpx.Timeout(0.3s)), LLM 也 miss
            则 stub passthrough current_mode. conf ≥ 0.5 且 target_agent != current
            时把 active_agent + current_mode 写回 state...

✅ After:  rule miss 才走 LLM 兜底分类 (300ms 超时硬约束), LLM 也无法判断时
            维持当前 mode. 低置信度或目标 = 当前不切档 (避免反复抖动).
            学生不必手动 set_mode, 下一轮 sub-agent 自然接管.

           Backed by: intent_classifier.py:139-191 (rule layer) +
           intent_classifier.py:217-251 (LLM fallback) +
           supervisor.py:45-90 (gating)
```

The before is faithful. The after is faithful AND readable. Same evidence chain, same cite line; just the bullet body translated from "what the code does" to "what the user observes."

**Self-check the architect runs before committing each bullet**:

> Could a PM, customer success engineer, or support engineer who has not read the source code understand this bullet? If not, the impl detail belongs in the `Backed by:` cite line, not the bullet body.

### How existing dirty PRDs get cleaned

`/super-manus:reverse-prd <module>` is already the regeneration path. Once the architect persona has the discipline, running reverse-prd on a dirty PRD produces a clean one. Same command, better output.

No separate `voice-pass` mode. No `--flag`. No lint regex. The architect IS the lint.

### Tests

Single test extension:

`tests/test_agent_reverse_prd_architect.sh` asserts:
- A `## PRD voice discipline` section heading exists in the persona file
- The discipline contains at least one worked before/after example
- The "self-check question" (PM / support engineer comprehension test) appears verbatim
- The principle "engineering evidence goes in `Backed by:` cite, not bullet body" appears verbatim

No new test files. No regex lint. The discipline is enforced by the LLM architect at draft time, not by a static checker.

### Open question (just one)

How many before/after examples does the architect persona need to reliably internalize the discipline? One per leakage category (LLM params / state-struct names / wire schema / tuning constants) = ~4 examples. Two examples per category for redundancy = ~8. Past 8 the persona file gets long without much marginal benefit. Initial guess: 4 worked examples is enough; iterate if real PRD outputs still leak.

### Status: open, no ship date — single requirement above is the spec

User said: "我只要产出来的 prd 文件是符合系统当前模块实现逻辑的, 然后以一种便于人理解的方式描述当前实际状态就行" — this entry IS the spec. Ratify the discipline + worked examples count, then v0.9.3 can ship as a small persona-edit + test-extension milestone.
