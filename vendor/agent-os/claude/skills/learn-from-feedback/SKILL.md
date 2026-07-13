---
name: learn-from-feedback
description: Record a user correction or review comment verbatim, classify it, and promote it to an active rule after repeated occurrences. Use immediately whenever the user corrects you or leaves review feedback — do not defer it to end of session.
---

The canonical procedure lives in `.agent-os/skills/learn-from-feedback/SKILL.md` (inside the Agent OS repository itself, the canonical source is `agent-os/skills/learn-from-feedback/SKILL.md`). Follow that file's steps in full instead of this summary. What follows is a standalone-usable condensation.

## Procedure summary

1. Record the correction verbatim (no paraphrasing, no summarizing) in `.agent-os/review-feedback-log.md`.
2. Classify it into exactly one category: `convention`, `architecture`, `testing`, `security`, `workflow`, `communication`, `forbidden-action`.
3. Check whether the same substance already exists in the log or in `learned-rules.md` (and, if `.agent-os/rules/` exists, in `.agent-os/rules/*.md` — where the split-out active rules live). If it conflicts with an existing active rule, surface the conflict — do not silently overwrite either side.
4. Count occurrences of the same substance: 1 occurrence stays `Status: candidate`; 2+ occurrences promotes it to `Status: active` in `.agent-os/learned-rules.md`, using the Rule format (Status/Source/Scope/Applies to/Rule/Rationale/Examples/Validation). If this project uses the split layout (`.agent-os/rules/` exists), put the active rule in `rules/<scope>.md` instead and update the index in `learned-rules.md`.
5. Never turn a vague or emotional remark ("be more careful") into a rule — only concrete, checkable ones.

## Forbidden

- Paraphrasing the user's words before logging them.
- Promoting a one-off personal preference to `active` or to the Global Layer.
- Silently discarding a rule that contradicts this feedback instead of flagging the conflict.

## Claude-specific notes

- Write to `.agent-os/review-feedback-log.md` verbatim first, before doing anything else in the turn — this is a recording action, not something to batch for later.
- Escalate conflicts to the user for a decision; do not resolve them unilaterally.
