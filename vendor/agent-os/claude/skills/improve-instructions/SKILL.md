---
name: improve-instructions
description: Clean up and consolidate accumulated instructions (CLAUDE.md, skills, learned-rules.md) — merge duplicates, flag conflicts, deprecate stale rules, extract long procedures into skills. Use when instructions have grown noisy, contradictory, or bloated; always propose, never apply without approval.
---

The canonical procedure lives in `.agent-os/skills/improve-instructions/SKILL.md` (inside the Agent OS repository itself, the canonical source is `agent-os/skills/improve-instructions/SKILL.md`). Follow that file's steps in full instead of this summary. What follows is a standalone-usable condensation.

## Procedure summary

1. Read `.agent-os/learned-rules.md`, `review-feedback-log.md`, `failure-log.md`, `evals.md`, and the current `CLAUDE.md`/`AGENTS.md`. If `.agent-os/rules/` exists, also read `.agent-os/rules/*.md` — those active rules were moved out of `learned-rules.md` and are just as binding.
2. Merge duplicate or overlapping rules into one.
3. Detect conflicting rules (e.g. via `scripts/detect-rule-conflicts.sh` if present) and surface them rather than silently picking a winner.
4. Mark stale or superseded rules `Status: deprecated` with a reason — never delete a rule outright.
5. If an always-loaded file (`CLAUDE.md`/`AGENTS.md`) has accumulated a procedure longer than a few lines, move it into a skill and leave a one-line pointer behind.
6. Add or update evals in `.agent-os/evals.md` for areas with repeated failures from `failure-log.md`, so regressions are caught going forward.
7. Present the result as a diff-style proposal.

## Forbidden

- Applying instruction changes without explicit approval.
- Deleting a rule instead of marking it deprecated.
- Resolving a genuine rule conflict unilaterally instead of surfacing it.

## Claude-specific notes

- This is a proposal skill: produce the diff and wait for explicit go-ahead before writing any file.
- Pairs well with the `instruction-maintainer` subagent, which can produce the same proposal from a fresh context for a second opinion.
