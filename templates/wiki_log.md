<!-- Append-only chronological log of wiki events. Written by the
     /super-manus:impl phase-close promote gate (promote / promote-rejected
     entries) and by /super-manus:wiki-lint (lint entries). NEVER hand-edit
     past entries; only append new ones — `grep "^## \[" wiki/_log.md | tail`
     is the canonical "what happened recently" query.

     This log is the ONLY provenance record connecting a wiki rule to its
     source findings.md entry. No back-annotation lives on the source side;
     the wiki/<topic>.md rule body has a "Source:" line pointing here, and
     this log entry's body records the source findings path + phase heading.
     Bidirectional reconstruction is by grep.

     Entry prefix is load-bearing (parsed by tools and shown in lint
     summaries): `## [YYYY-MM-DD] <event> | <details>`.

     Schema (v0.9.8 R16, headings stable):
       - H1: "# Wiki log"
       - H2 per event: `## [YYYY-MM-DD] <event> | <details>`
       - Body: freeform bullets under each event

     Event types (extend over time as new operations are added):
       - `promote`           — a wiki-candidate was accepted; rule appended
                               to wiki/<topic>.md and index regenerated
       - `promote-rejected`  — a wiki-candidate was rejected by the user;
                               body records the source so reviewer can
                               cross-check before re-flagging in a later
                               phase (orchestrator may also auto-check)
       - `lint`              — /super-manus:wiki-lint (standalone or as
                               drift-gate Pass 4) ran; body lists
                               contradictions / stale / orphan / gap /
                               cross-ref miss counts -->
# Wiki log

<!-- No events logged yet. First promote / lint pass will append an entry. -->
