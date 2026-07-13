---
name: project-profile
description: Create or update .agent-os/project-profile.md, keeping observed facts and open hypotheses strictly separate. Use after project-bootstrap, after a major structural change, or whenever a recorded fact turns out wrong.
---

The canonical procedure lives in `.agent-os/skills/project-profile/SKILL.md` (inside the Agent OS repository itself, the canonical source is `agent-os/skills/project-profile/SKILL.md`). Follow that file's steps in full instead of this summary. What follows is a standalone-usable condensation.

## Procedure summary

1. Open the existing `project-profile.md` if present; otherwise start from `project-bootstrap`'s observations.
2. Fill/update: Overview, Verified facts (each with an evidence source), Directory map, Architecture notes, Risk areas (pointer to `risk-map.md`, not a duplicate), Open hypotheses (explicitly labeled "unverified").
3. Promote a hypothesis to a verified fact only once it is actually confirmed — not on a second guess.
4. If a "verified fact" is proven wrong, correct or remove it immediately and note why, rather than leaving a silent gap.
5. Prune stale, never-confirmed hypotheses instead of letting them accumulate.
6. Keep it scannable (short bullets, not prose); if a section grows into a procedure, move it into a skill and leave a pointer.
7. Note a "last updated" line with the reason so future readers know why it changed.

## Forbidden

- Blending unverified hypotheses into the facts section.
- Recording a single unconfirmed guess as a "verified fact."
- Letting the file grow into a full procedure manual.
- Silently dropping a fact that is now false without noting why.

## Claude-specific notes

- This file is read at the start of every session (see `CLAUDE.md`'s session-start list) — keep it short enough that re-reading it every session stays cheap.
- Use `Read`/`Grep`/`Glob` to gather evidence; do not use `Edit` on anything outside `.agent-os/project-profile.md` as part of this skill.
