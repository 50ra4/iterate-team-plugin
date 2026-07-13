---
name: adapt-to-project
description: Turn project-bootstrap output into the project's adapter — AGENTS.md and .agent-os/ files — without ever editing the Global Agent OS.
---

Canonical procedure: `.agent-os/skills/adapt-to-project/SKILL.md` (inside the
Agent OS repository itself, the canonical source is
`agent-os/skills/adapt-to-project/SKILL.md`). Read it before running this workflow —
this file is a compact Codex-facing pointer, not a replacement.

## Summary

1. Read `GLOBAL_AGENTS.md` to confirm what already applies globally; do
   not repeat it in the project adapter.
2. Read `.agent-os/project-profile.md`, `.agent-os/command-map.md`, and
   `.agent-os/risk-map.md`; pull only verified facts, never hypotheses.
3. Write/update a short `AGENTS.md` at the project root pointing to
   `.agent-os/` and to relevant skills for detail — no long procedures
   inline. Match the shape of the project's own installed `AGENTS.md`
   (a copy of `project-adapter/AGENTS.md` — canonical source:
   `templates/AGENTS.md.template` in the Agent OS source repo, not
   present in a bootstrapped project), under the same length discipline
   as the global entrypoint.
4. Create `.agent-os/learned-rules.md` and `.agent-os/evals.md` if absent
   (empty shells, not pre-populated with unverified rules). Refresh
   `.agent-os/architecture-map.md` too if it looks stale against current
   facts.
5. Every rule placed in the adapter must trace back to an observed fact
   or a repeated failure/feedback item — never a single guess.

## Codex-specific notes

- Generate `AGENTS.md` for the Codex entrypoint; only generate files for
  other platforms (e.g. Claude-facing files) if the user separately asks
  for them.
- Never modify the vendored Global layer in this project
  (`.agent-os/GLOBAL_AGENTS.md`, `.agent-os/skills/`) — or, if working
  directly in the Agent OS source repo, its root `GLOBAL_AGENTS.md`,
  `skills/`, `templates/`, `scripts/`. The adapter is project-local only.

## Forbidden

- Writing strong rules up front with no evidence.
- Promoting a single failure or single review comment straight to an
  active rule (that requires 2+ occurrences — see `learn-from-feedback`).
- Letting the generated `AGENTS.md` grow long — details belong in skills.
