---
name: project-profile
description: Create or update .agent-os/project-profile.md, keeping observed facts and open hypotheses strictly separate.
---

Canonical procedure: `.agent-os/skills/project-profile/SKILL.md` (inside the
Agent OS repository itself, the canonical source is
`agent-os/skills/project-profile/SKILL.md`). Read it before running this workflow —
this file is a compact Codex-facing pointer, not a replacement.

## Summary

1. Open the existing `project-profile.md` if present; otherwise start from
   `project-bootstrap`'s observations.
2. Fill/update: Overview, Verified facts (each with an evidence source),
   Directory map, Architecture notes, Risk areas (pointer to `risk-map.md`),
   Open hypotheses (labeled "unverified").
3. Promote a hypothesis to a verified fact only once actually confirmed.
4. If a "verified fact" is proven wrong, correct or remove it immediately
   and note why — do not leave a silent gap.
5. Prune stale, never-confirmed hypotheses; keep the file short and
   scannable, pushing any long procedure into a skill instead.

## Codex-specific notes

- This file is read at task start (see `AGENTS.md`'s "At task start" list)
  — keep it short enough that re-reading it every task stays cheap.
- Only edit `.agent-os/project-profile.md` as part of this workflow; do
  not touch source files.

## Forbidden

- Blending unverified hypotheses into the facts section.
- Recording a single unconfirmed guess as a "verified fact."
- Letting the file grow into a full procedure manual.
- Silently dropping a fact that is now false without noting why.
