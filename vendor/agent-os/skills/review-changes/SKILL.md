---
name: review-changes
description: Checklist-driven review of a diff (own or someone else's) for correctness, scope, architecture, tests, security, and consistency with learned rules.
---

## Purpose

Give a diff a structured, honest review instead of a vague pass/fail impression — catching real problems (correctness, security, scope creep, boundary violations) while not blocking on style opinions that contradict the project's own conventions.

## When to use

- Before considering a diff (self-authored or from another agent/person) done.
- When asked to review a pull request or a pending set of local changes.

## Inputs

- The diff itself (`git diff`, PR diff, or equivalent).
- `.agent-os/learned-rules.md` (active rules only for enforcement; candidates are informative, not enforceable). If `.agent-os/rules/` exists, also read the files its `Active rules index` points to — equally binding. Active rules with a missing or unrecognized `Scope:` stay directly in `learned-rules.md` and are still binding.
- `.agent-os/architecture-map.md`, `.agent-os/risk-map.md`.
- `.agent-os/project-profile.md` for naming/conventions.
- `.agent-os/command-map.md` for what "passing checks" actually means here.

## Procedure

1. Read the full diff, not just the summary — including test files and config changes.
2. Check **correctness**: does the change do what it claims; are there logic errors, off-by-one issues, unhandled edge cases, or incorrect assumptions.
3. Check **scope creep**: does the diff contain unrelated changes beyond its stated purpose.
4. Check **architecture boundaries**: does the diff cross a boundary flagged in `architecture-map.md`/`risk-map.md` without justification or approval.
5. Check **test coverage**: does new/changed behavior have corresponding new/updated tests; were any tests weakened or deleted to make the suite pass.
6. Check **security**: secrets or credentials introduced or logged, injection risks (SQL, command, template), missing authorization checks, unsafe deserialization.
7. Check **destructive-operation risk**: migrations, data deletion, force operations, production config changes — confirm they have the required approval per `risk-map.md`.
8. Check **consistency with active learned rules**: cross-reference `learned-rules.md` entries with `Status: active` whose `Applies to` matches the changed paths — and, if `.agent-os/rules/` exists, the entries in `.agent-os/rules/*.md` that `learned-rules.md`'s `Active rules index` points to.
9. Check **naming/conventions**: compare against `project-profile.md`'s documented conventions, not personal taste.
10. Confirm the project's real test/lint/typecheck commands (from `command-map.md`) were actually run and passed — do not approve on the basis of "looks fine."
11. Write findings ordered by severity; each finding states the problem, why it matters, the file:line, and a suggested fix. If there are no findings in a category, say so explicitly rather than omitting it.

## Outputs

A review report with:
- Findings ordered by severity, each as: `file:line` — problem — why it matters — suggested fix.
- An explicit "no findings" statement for any checklist category that is clean.
- A final verdict: approve, approve with follow-ups, or request changes — never silent on failing checks.

## Forbidden

- Approving a diff with known failing tests, lint errors, or type errors.
- Style nitpicks that contradict the project's own documented conventions in `project-profile.md`.
- Skipping the security or destructive-operation checks because the diff "looks small."
- Treating a candidate (not yet active) learned rule as mandatory for blocking approval.

## Done criteria

- Every checklist category was explicitly addressed (finding or "no findings").
- All findings include file:line, problem, rationale, and a suggested fix.
- The verdict is explicit and consistent with the findings (no approval alongside an unresolved failing check).
- Active learned rules relevant to the changed paths were checked, not just architecture and tests.
