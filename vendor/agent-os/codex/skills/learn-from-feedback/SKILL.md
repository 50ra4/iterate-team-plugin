---
name: learn-from-feedback
description: Record and classify user corrections and review comments so repeated lessons become active rules instead of being relearned every session.
---

Canonical procedure: `.agent-os/skills/learn-from-feedback/SKILL.md` (inside the
Agent OS repository itself, the canonical source is
`agent-os/skills/learn-from-feedback/SKILL.md`). Read it before running this workflow —
this file is a compact Codex-facing pointer, not a replacement.

## Summary

1. Record the user's feedback verbatim (not summarized or reworded) in
   `.agent-os/review-feedback-log.md`.
2. Classify it into one category: convention, architecture, testing,
   security, workflow, communication, or forbidden-action.
3. Check whether it conflicts with an existing rule in
   `.agent-os/learned-rules.md` — and, if `.agent-os/rules/` exists, in
   `.agent-os/rules/*.md`, where the split-out active rules live;
   if so, surface the conflict rather than silently overwriting the
   older rule.
4. Apply the promotion rule: a single occurrence stays `Status: candidate`;
   the same lesson observed 2 or more times independently is promoted to
   `Status: active` in `.agent-os/learned-rules.md` — or, if `.agent-os/rules/`
   already exists (split layout), into `rules/<scope>.md` with the index in
   `learned-rules.md` updated to match.
5. Write every rule in the standard Rule format (Status, Source, Scope,
   Applies to, Rule, Rationale, Examples, Validation).

## Codex-specific notes

- Store the user's words exactly as given in `review-feedback-log.md` —
  do not paraphrase or "clean up" the wording before logging it.
- Rules must be observable and checkable; reject vague or emotional
  wording (e.g. "be more careful") in favor of a concrete, checkable
  instruction.

## Forbidden

- Promoting a one-time remark straight to `active`.
- Silently overwriting a conflicting existing rule instead of reporting
  the conflict.
- Recording anything other than the user's literal statement in the log.
