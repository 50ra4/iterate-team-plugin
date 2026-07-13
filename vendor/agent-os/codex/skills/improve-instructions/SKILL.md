---
name: improve-instructions
description: Clean up accumulated instruction files — merge duplicate rules, resolve conflicts, deprecate stale rules, and move long procedures out of always-loaded files.
---

Canonical procedure: `.agent-os/skills/improve-instructions/SKILL.md` (inside the
Agent OS repository itself, the canonical source is
`agent-os/skills/improve-instructions/SKILL.md`). Read it before running this workflow —
this file is a compact Codex-facing pointer, not a replacement.

## Summary

1. Merge duplicate rules in `.agent-os/learned-rules.md` — and, if
   `.agent-os/rules/` exists, in `.agent-os/rules/*.md` too, where the
   split-out active rules live — that describe the same lesson,
   preserving the strongest evidence from each.
2. Detect and report conflicting rules rather than silently picking one.
3. Deprecate stale or superseded rules by marking `Status: deprecated`
   with a reason — never delete a rule outright.
4. Move any procedure longer than a few lines out of `AGENTS.md` (or a
   skill file that has grown too long) into its own skill, leaving a
   one-line pointer behind.
5. Add evals to `.agent-os/evals.md` for areas with repeated failures in
   `.agent-os/failure-log.md`.
6. Present the result as a diff-style proposal; changes are applied only
   after explicit approval.

## Codex-specific notes

- Keep `AGENTS.md` itself short after cleanup — it is read on every turn,
  so treat every line as a recurring cost.
- Do not apply the proposal directly to `learned-rules.md`, `evals.md`, or
  `AGENTS.md` in the same step as drafting it; approval comes first.

## Forbidden

- Applying merges, deprecations, or moves without a reviewed proposal.
- Deleting a rule instead of marking it deprecated.
- Hiding a detected conflict instead of reporting it.
