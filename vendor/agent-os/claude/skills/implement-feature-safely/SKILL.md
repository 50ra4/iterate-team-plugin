---
name: implement-feature-safely
description: Standard protocol for adding a feature — confirm scope, reuse existing patterns, respect architecture boundaries, implement in small verified diffs. Use for any request to add new functionality, not a pure bug fix or refactor.
---

The canonical procedure lives in `.agent-os/skills/implement-feature-safely/SKILL.md` (inside the Agent OS repository itself, the canonical source is `agent-os/skills/implement-feature-safely/SKILL.md`). Follow that file's steps in full instead of this summary. What follows is a standalone-usable condensation.

## Procedure summary

1. Confirm the goal, constraints, and blast radius: what the feature must do, must not affect, and what is out of scope.
2. Search the codebase for an existing pattern doing something similar; prefer reusing its shape over inventing a new one.
3. Check `.agent-os/architecture-map.md` and `.agent-os/risk-map.md` for boundaries this feature must respect.
4. Design the smallest viable increment — resist "while I'm here" scope creep.
5. State an explicit reason before adding any new dependency; never add one silently.
6. Implement in small, reviewable diffs following the reused pattern, unless there is a stated reason to deviate.
7. Write tests matching the project's existing test strategy from `project-profile.md`.
8. Run the project's real test/lint/typecheck commands from `.agent-os/command-map.md` and report actual results.
9. Report what was added, how it was verified, how it fits existing patterns, and remaining risk.

## Forbidden

- Adding a new dependency without a stated, explicit reason.
- Changing unrelated code "while in the area."
- Inventing a new pattern or abstraction when an existing one already fits.
- Crossing an architecture boundary flagged in `architecture-map.md`/`risk-map.md` without approval.
- Reporting completion without running real verification commands.

## Claude-specific notes

- Use `Grep`/`Glob` to find the existing pattern before writing any new code; cite the file it was reused from in the final report.
- Keep the diff reviewable — prefer several small `Edit` calls over one large rewrite.
