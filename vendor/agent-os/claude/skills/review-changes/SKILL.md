---
name: review-changes
description: Checklist-driven review of a diff (own or someone else's) for correctness, scope, architecture, tests, security, and consistency with learned rules. Use before considering any diff done, or when asked to review a PR.
---

The canonical procedure lives in `.agent-os/skills/review-changes/SKILL.md` (inside the Agent OS repository itself, the canonical source is `agent-os/skills/review-changes/SKILL.md`). Follow that file's steps in full instead of this summary. What follows is a standalone-usable condensation.

## Procedure summary

1. Read the full diff, including test and config files, not just the summary.
2. Check correctness, scope creep, and architecture-boundary crossings against `architecture-map.md`/`risk-map.md`.
3. Check test coverage — new/changed behavior has tests, and no test was weakened or deleted to pass.
4. Check security: secrets/credentials, injection risks, missing authorization, unsafe deserialization.
5. Check destructive-operation risk (migrations, deletion, force ops) against `risk-map.md`'s approval requirements.
6. Cross-reference `learned-rules.md` entries with `Status: active` whose `Applies to` matches the changed paths. If `.agent-os/rules/` exists, also check the files its `Active rules index` points to — they are just as binding.
7. Check naming/conventions against `project-profile.md`, not personal taste.
8. Confirm the project's real test/lint/typecheck commands were actually run and passed — never approve on "looks fine."
9. Write findings ordered by severity as `file:line` — problem — why it matters — suggested fix; state "no findings" explicitly for clean categories.
10. Give a final verdict: approve, approve with follow-ups, or request changes.

## Forbidden

- Approving a diff with known failing tests, lint errors, or type errors.
- Style nitpicks that contradict the project's own documented conventions in `project-profile.md`.
- Skipping the security or destructive-operation checks because the diff "looks small."
- Treating a candidate (not yet active) learned rule as mandatory for blocking approval.

## Claude-specific notes

- This is a read-only skill: use `Read`/`Grep`/`Glob`/`Bash` (read-only inspection and running existing verification commands) only — do not `Edit` the diff's files as part of this skill. Pairs well with the `code-reviewer` subagent for a fresh-context second opinion.
