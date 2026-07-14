---
name: fix-bug-safely
description: Standard protocol for fixing a bug — reproduce, find root cause with evidence, make a minimal diff, add a regression test, verify for real.
---

## Purpose

Fix bugs in a way that actually resolves the cause, is checkable by someone else, and does not quietly reduce the project's safety net.

## When to use

- Any bug report, failing test, or unexpected behavior that needs a code change to resolve.
- Not for exploratory investigation with no intent to fix yet — that is plain research, not this skill.

## Inputs

- The bug report or failing test/output.
- `.agent-os/command-map.md` for real test/lint/typecheck commands.
- `.agent-os/risk-map.md` and `.agent-os/architecture-map.md` for danger areas and boundaries.
- `.agent-os/learned-rules.md` for anything already known about this area of the code — and, if `.agent-os/rules/` exists, `.agent-os/rules/*.md` too (the active rules moved out of `learned-rules.md`, equally binding).

## Procedure

1. Reproduce the bug first. Run the failing scenario (test, command, manual repro) and observe the actual failure. If it cannot be reproduced, state that clearly and explicitly rather than proceeding on assumption.
2. Read the related code and its existing tests before changing anything — understand current behavior and intent.
3. Locate the root cause with evidence (a stack trace, a logged value, a failing assertion pinpointing the exact line/condition) — do not patch a symptom based on a guess.
4. Check `.agent-os/risk-map.md`: if the fix touches a flagged dangerous area, get explicit approval before changing it.
5. Design the smallest diff that fixes the root cause. Do not refactor surrounding code as part of this fix.
6. Implement the fix.
7. Add or extend a regression test that fails before the fix and passes after it. If the project's test strategy makes this genuinely impossible, say so explicitly and explain why.
8. Run the project's real test, lint, and typecheck commands from `command-map.md` — never invented or approximated commands.
9. Report: what changed (file/line level), how it was verified (exact commands and their results), and what residual risk remains (edge cases not covered, related code not audited).
10. If the first fix attempt failed (test still fails, root cause was wrong), log it in `.agent-os/failure-log.md` before trying again — command, cause, what will be done differently.

## Outputs

- A minimal code diff addressing the confirmed root cause.
- A new or extended regression test.
- A verification report (commands run + actual results).
- A `.agent-os/failure-log.md` entry if an earlier attempt failed.

## Forbidden

- Deleting or weakening a test to make the suite pass.
- Drive-by refactoring unrelated to the bug.
- Guessing the root cause without reproducing or otherwise evidencing it.
- Reporting the bug as fixed without running real verification commands.
- Touching a `risk-map.md`-flagged area without the required approval.

## Done criteria

- The bug is reproduced (or its non-reproducibility is stated plainly) before any fix is attempted.
- The change is traceable to an evidenced root cause, not a guess.
- A regression test exists and demonstrably fails without the fix.
- Real test/lint/typecheck commands were run and their actual results reported.
- Any failed first attempt is recorded in `failure-log.md`.
