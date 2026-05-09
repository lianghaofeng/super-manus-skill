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

### Three requirements (all in the same architect persona file)

These three changes ship together because they all answer the same goal: "make the PRD read like a user manual of the current system."

#### R1. Voice discipline

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

#### R2. Use cases preamble inside `## What users get`

PRD as user manual benefits from "scenarios first, capabilities second" reading order. v0.9.3 adds a short use-cases preamble at the top of `## What users get`, BEFORE the capability bullets:

```markdown
## What users get

主要使用场景:
- **学生上一节正式课**: GREET → NEGOTIATE → PLAN → TEACH ⇄ PRACTICE → WRAPUP → PERSIST (15-30 分钟)
- **学生中途自由问答**: 不走剧本直接问"为什么 X = 5", server 走同款 RAG + actions JSON 输出
- **学生切换学习模式**: lesson / practice / chat 三档自由切, 切档时旧上下文压缩成短摘要喂新 sub-agent

实现这些场景的能力:

- **WebSocket 实时一节课** — ...
  Backed by: ws_server.py:619-624.

- **NEGOTIATE 选课卡片** — ...
  Backed by: ws_server.py:271-336.
```

**Format rules** for use-case bullets (kept lightweight):

- Bold name + colon + one-line scenario description.
- NO rigid `As [Actor], I want [Action], so that [Value]` template — too mechanical, forces awkward phrasing.
- Each use-case should map to ≥1 capability bullet below it (architect verifies the mapping when drafting).
- 2–4 use cases is typical; if you have 1, the module is probably too thin to need this preamble (skip it); if you have >5, you're listing capabilities not scenarios (consolidate).
- Skippable for tightly-scoped utility modules (a pure CRUD API, a passive metric exporter) where "the user uses it" doesn't decompose into multiple scenarios.

#### R3. User-facing flow Mermaid sub-section in `## How it connects`

Currently `## How it connects` shows an integration view (which module connects to which). For modules with **multi-step user flows** (e.g. tutor-agent's GREET → NEGOTIATE → PLAN → TEACH ⇄ PRACTICE → WRAPUP → PERSIST), add a separate "User-facing flow" Mermaid sub-section that shows the flow from the **user's perspective**, not the architecture:

```markdown
## How it connects

### User-facing flow

```mermaid
flowchart LR
  A[GREET] --> B[NEGOTIATE]
  B --> C[PLAN]
  C --> D[TEACH]
  D <--> E[PRACTICE]
  D --> F[WRAPUP]
  E --> F
  F --> G[PERSIST]
```

### Integration

(existing Mermaid showing web-student → ws_server → supervisor → tutor sub-graph etc.)
```

**Trigger rule** for the architect: only add User-facing flow when the module has **≥3 sequential user-visible steps** OR conditional branching the user observes. A pure CRUD API ("user POSTs, server returns") doesn't need it. Tutor-agent does. Reverse-prd does (Stage 1 / Stage 2 / Stage 3).

If the module doesn't qualify, the architect skips the sub-section (no empty headings).

### How existing dirty PRDs get cleaned

`/super-manus:reverse-prd <module>` is already the regeneration path. Once the architect persona has the discipline, running reverse-prd on a dirty PRD produces a clean one. Same command, better output.

No separate `voice-pass` mode. No `--flag`. No lint regex. The architect IS the lint.

### Tests

Test extensions on existing `tests/test_agent_reverse_prd_architect.sh` (no new test files):

R1 (voice discipline) assertions:
- A `## PRD voice discipline` section heading exists in the persona file
- The discipline contains at least one worked before/after example
- The "self-check question" (PM / support engineer comprehension test) appears verbatim
- The principle "engineering evidence goes in `Backed by:` cite, not bullet body" appears verbatim

R2 (use cases preamble) assertions:
- The `## What users get` description in the persona file mentions "use cases" / "使用场景" / "用例" preamble
- Format guidance: bold name + colon + one-line scenario; explicitly NO `As [Actor], I want [Action]` template
- The "≥1 capability maps to each use case" mapping rule appears

R3 (user-facing flow) assertions:
- The `## How it connects` description in the persona file mentions "User-facing flow" sub-section
- The trigger rule (≥3 sequential user-visible steps OR conditional branching) appears
- The "skip when unqualified" rule appears (no empty headings)

Plus optionally extend `tests/test_template_prd_module.sh` if `templates/prd_module.md` is updated in lockstep with the persona changes (TBD whether the template carries the use-case preamble placeholder by default or only the persona instruction does).

No new test files. No regex lint. The discipline is enforced by the LLM architect at draft time, not by a static checker.

### Open questions

1. **Worked examples count for R1.** How many before/after examples does the architect persona need to reliably internalize voice discipline? One per leakage category (LLM params / state-struct names / wire schema / tuning constants) = ~4 examples. Two per category for redundancy = ~8. Initial guess: 4 worked examples is enough; iterate if real PRD outputs still leak.

2. **Template vs persona for R2/R3 instruction.** The use-case preamble (R2) and User-facing flow (R3) — should they appear as **placeholder sections** in `templates/prd_module.md` (so a fresh PRD has the headings ready and the architect just fills them), OR only as **persona instructions** in `agents/reverse-prd-architect.md` (architect knows to add them when applicable, doesn't pre-pollute the template)?
   - Template approach: more visible, harder to forget, but creates empty headings for modules that don't qualify (R3 skip case especially).
   - Persona approach: cleaner output for thin modules, but architect may forget to add for modules that DO qualify.
   - Initial guess: persona-only for R3 (Mermaid is conditional on multi-step flow), template placeholder for R2 (use cases preamble is universal enough for non-trivial modules).

### Final scope

The whole v0.9.3 milestone is now: one persona file edit (R1 + R2 + R3 instructions) + test extension on `test_agent_reverse_prd_architect.sh` (assertions for all three) + optional `templates/prd_module.md` update for R2 placeholder. Persona file grows from 334 lines to ~420 lines. No new commands, no new agents, no new modes. One small milestone, one phase plan, one phase to implement.

### Status: open, no ship date — three requirements above are the spec

User confirmed (across multiple turns):
- "肯定是要 reverse-prd-architect 改" (R1 is needed)
- "我只要产出来的 prd 文件是符合系统当前模块实现逻辑的, 然后以一种便于人理解的方式描述当前实际状态就行" (the goal: faithful + readable user-manual)
- "用户视角流程图，这个要，用 mermaid 画" (R3)
- "用例/用户故事 要的 简单描述" (R2 confirmed)
- "Verify by 这个不要了" (no per-capability acceptance criteria)
- Format preference: "**bold 用例名 + 一句话场景描述**" — no rigid As/I want/So that

Ratify the two open questions above (worked examples count + template-vs-persona scoping), then v0.9.3 can ship.
