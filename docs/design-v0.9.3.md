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
