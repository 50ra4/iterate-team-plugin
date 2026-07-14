---
name: review-changes
description: Checklist-driven review of a diff (own or someone else's) for correctness, scope, architecture, tests, security, and consistency with learned rules.
---

Canonical procedure: `.agent-os/skills/review-changes/SKILL.md` (inside the
Agent OS repository itself, the canonical source is
`agent-os/skills/review-changes/SKILL.md`). Read it before running this workflow —
this file is a compact Codex-facing pointer, not a replacement.

## Summary

1. Read the full diff, including test and config files, not just the
   summary.
2. Check correctness, scope creep, and architecture-boundary crossings
   against `architecture-map.md`/`risk-map.md`.
3. Check test coverage and that no test was weakened or deleted to pass.
4. Check security: secrets, injection risks, missing authorization,
   unsafe deserialization.
5. Check destructive-operation risk against `risk-map.md`'s approval
   requirements.
6. Cross-reference `learned-rules.md` entries with `Status: active`
   matching the changed paths. If `.agent-os/rules/` exists, also check
   the files its `Active rules index` points to — equally binding.
7. Confirm the project's real test/lint/typecheck commands were actually
   run and passed — never approve on "looks fine."
8. Write findings ordered by severity as `file:line` — problem — why it
   matters — suggested fix; state "no findings" explicitly where clean.
9. Give a final verdict: approve, approve with follow-ups, or request
   changes.

## Codex-specific notes

- This is a read-only workflow: inspect the diff and run only existing,
  already-confirmed verification commands from `.agent-os/command-map.md`
  — do not edit the reviewed files as part of this skill.

## Forbidden

- Approving a diff with known failing tests, lint errors, or type errors.
- Style nitpicks that contradict the project's own documented conventions
  in `project-profile.md`.
- Skipping the security or destructive-operation checks because the diff
  "looks small."
- Treating a candidate (not yet active) learned rule as mandatory for
  blocking approval.
