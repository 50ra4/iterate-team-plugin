---
name: fix-bug-safely
description: Standard protocol for fixing a bug — reproduce, find root cause with evidence, make a minimal diff, add a regression test, verify for real. Use for any bug report or unexpected behavior that needs a code change.
---

The canonical procedure lives in `.agent-os/skills/fix-bug-safely/SKILL.md` (inside the Agent OS repository itself, the canonical source is `agent-os/skills/fix-bug-safely/SKILL.md`). Follow that file's steps in full instead of this summary. What follows is a standalone-usable condensation.

## Procedure summary

1. Reproduce the bug first — run the failing scenario and observe the actual failure. If it cannot be reproduced, say so explicitly rather than proceeding on assumption.
2. Read the related code and its existing tests before changing anything.
3. Locate the root cause with evidence (stack trace, logged value, failing assertion) — never patch a symptom based on a guess.
4. Check `.agent-os/risk-map.md`; get explicit approval before touching a flagged area.
5. Design and implement the smallest diff that fixes the root cause — no surrounding refactor.
6. Add or extend a regression test that fails before the fix and passes after it.
7. Run the project's real test/lint/typecheck commands from `.agent-os/command-map.md` — never invented ones.
8. Report file/line-level changes, exact verification commands and results, and residual risk.
9. If a first fix attempt failed, log it in `.agent-os/failure-log.md` before retrying.

## Forbidden

- Deleting or weakening a test to make the suite pass.
- Drive-by refactoring unrelated to the bug.
- Guessing the root cause without reproducing or otherwise evidencing it.
- Reporting the bug as fixed without running real verification commands.
- Touching a `risk-map.md`-flagged area without the required approval.

## Claude-specific notes

- Reproduce before changing anything: run the failing test/command with `Bash` and observe the real failure before opening `Edit` on any file.
- If reproduction is not possible in this environment, state that plainly in the report instead of silently skipping it.
