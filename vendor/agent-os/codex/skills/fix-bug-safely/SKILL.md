---
name: fix-bug-safely
description: Standard protocol for fixing a bug — reproduce, find root cause with evidence, make a minimal diff, add a regression test, verify for real.
---

Canonical procedure: `.agent-os/skills/fix-bug-safely/SKILL.md` (inside the
Agent OS repository itself, the canonical source is
`agent-os/skills/fix-bug-safely/SKILL.md`). Read it before running this workflow —
this file is a compact Codex-facing pointer, not a replacement.

## Summary

1. Reproduce the bug first; if it cannot be reproduced, say so explicitly
   instead of proceeding on assumption.
2. Read the related code and its existing tests before changing anything.
3. Locate the root cause with evidence (stack trace, logged value, failing
   assertion) — never patch a symptom based on a guess.
4. Check `.agent-os/risk-map.md`; get explicit approval before touching a
   flagged area.
5. Implement the smallest diff that fixes the root cause, with no
   surrounding refactor.
6. Add or extend a regression test that fails before the fix and passes
   after it.
7. Run the project's real test/lint/typecheck commands from
   `.agent-os/command-map.md` and report actual results.
8. If a first fix attempt failed, log it in `.agent-os/failure-log.md`
   before retrying.

## Codex-specific notes

- Reproduce before changing anything: run the failing test/command
  read-only first and observe the real failure before editing any file.
- Only run build/test/state-changing commands confirmed in
  `.agent-os/command-map.md` when verifying the fix — never invent one.

## Forbidden

- Deleting or weakening a test to make the suite pass.
- Drive-by refactoring unrelated to the bug.
- Guessing the root cause without reproducing or otherwise evidencing it.
- Reporting the bug as fixed without running real verification commands.
- Touching a `risk-map.md`-flagged area without the required approval.
