---
name: implement-feature-safely
description: Standard protocol for adding a feature — confirm scope, reuse existing patterns, respect architecture boundaries, implement in small verified diffs.
---

Canonical procedure: `.agent-os/skills/implement-feature-safely/SKILL.md` (inside the
Agent OS repository itself, the canonical source is
`agent-os/skills/implement-feature-safely/SKILL.md`). Read it before running this workflow —
this file is a compact Codex-facing pointer, not a replacement.

## Summary

1. Confirm the goal, constraints, and blast radius before writing any code.
2. Search the codebase for an existing pattern doing something similar;
   prefer reusing its shape over inventing a new one.
3. Check `.agent-os/architecture-map.md` and `.agent-os/risk-map.md` for
   boundaries this feature must respect.
4. Design the smallest viable increment — resist scope creep.
5. State an explicit reason before adding any new dependency.
6. Implement in small, reviewable diffs following the reused pattern.
7. Write tests matching the project's existing test strategy from
   `project-profile.md`.
8. Run the project's real test/lint/typecheck commands from
   `.agent-os/command-map.md` and report actual results.

## Codex-specific notes

- Cite the existing pattern reused (file/path) in the final report so a
  reviewer can verify the reuse claim.
- Only run commands confirmed in `.agent-os/command-map.md` for
  verification — never invent one.

## Forbidden

- Adding a new dependency without a stated, explicit reason.
- Changing unrelated code "while in the area."
- Inventing a new pattern or abstraction when an existing one already fits.
- Crossing an architecture boundary flagged in `architecture-map.md`/
  `risk-map.md` without approval.
- Reporting completion without running real verification commands.
