---
name: implement-feature-safely
description: Standard protocol for adding a feature — confirm scope, reuse existing patterns, respect architecture boundaries, implement in small verified diffs.
---

## Purpose

Add new behavior to a codebase in a way that fits how the project already works, stays inside its architectural boundaries, and is verifiable — rather than introducing a parallel style or an unreviewable large diff.

## When to use

- Any request to add new functionality, an endpoint, a UI element, a CLI command, or similar.
- Not for a pure bug fix (`fix-bug-safely`) or a pure refactor with no new behavior.

## Inputs

- The feature request and its stated goal.
- `.agent-os/project-profile.md` for stack and conventions.
- `.agent-os/architecture-map.md` and `.agent-os/risk-map.md` for boundaries and dangerous areas.
- `.agent-os/learned-rules.md` for anything already known that constrains this kind of change — and, if `.agent-os/rules/` exists, `.agent-os/rules/*.md` too (the active rules moved out of `learned-rules.md`, equally binding).
- `.agent-os/command-map.md` for real verification commands.

## Procedure

1. Confirm the goal, constraints, and blast radius: what must the feature do, what must it not affect, what is explicitly out of scope.
2. Search the codebase for an existing pattern that does something similar (a comparable endpoint, component, command) — prefer reusing that shape over inventing a new one.
3. Check `.agent-os/architecture-map.md` and `.agent-os/risk-map.md` for boundaries this feature must respect (layering, module ownership, dangerous areas requiring approval).
4. Design the smallest viable increment that delivers the goal — resist scope creep toward "while I'm here" additions.
5. If the design requires a new dependency, state the explicit reason before adding it; do not add one silently for convenience.
6. Implement in small, reviewable diffs rather than one large rewrite, following the reused pattern from step 2 unless there is a stated reason to deviate.
7. Write tests for the new behavior, matching the project's existing test strategy (from `project-profile.md`).
8. Run the project's real test, lint, and typecheck commands from `command-map.md` and report actual results.
9. Report: what was added (file/line level), how it was verified, how it fits existing patterns, and what risks or follow-ups remain.

## Outputs

- New code implementing the feature, in small diffs.
- New tests covering the added behavior.
- A verification report (commands run + actual results).
- A stated reason for any new dependency, if one was added.

## Forbidden

- Adding a new dependency without a stated, explicit reason.
- Changing unrelated code "while in the area."
- Inventing a new pattern or abstraction when an existing one already fits.
- Crossing an architecture boundary flagged in `architecture-map.md`/`risk-map.md` without approval.
- Reporting completion without running real verification commands.

## Done criteria

- The implementation matches an existing project pattern, or a deviation is explicitly justified.
- No unrelated files were changed.
- No dependency was added without a stated reason.
- Tests exist for the new behavior and pass under the project's real test command.
- The report clearly states what changed, how it was verified, and remaining risk.
