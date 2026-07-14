---
name: learn-from-feedback
description: Convert user corrections, review comments, and repeated failures into durable, well-classified rules — without overreacting to a single remark.
---

## Purpose

Turn what the user actually said — a correction, a "don't do that," a repeated complaint — into knowledge the agent can reuse, while keeping one-off preferences from calcifying into global law.

## When to use

- The user corrects an approach ("this approach is wrong", "don't touch this directory", "always run this test", "follow this pattern instead").
- The user points out a repeated mistake ("you made the same mistake before").
- A code review leaves comments that imply a standing preference, not just a one-time fix.
- Not for routine bug fixes with no behavioral lesson attached — those just get fixed.

## Inputs

- The verbatim feedback text (chat message, review comment, commit note).
- `.agent-os/review-feedback-log.md` (existing entries, for repeat detection).
- `.agent-os/learned-rules.md` (existing active/candidate rules, for conflict detection) — and `.agent-os/rules/*.md` if `.agent-os/rules/` exists, where the split-out active rules live.

## Procedure

1. Record the feedback **verbatim** in `.agent-os/review-feedback-log.md` with a timestamp and the task context it occurred in. Do not paraphrase or soften it at this stage.
2. Classify it into exactly one of the seven categories: `convention`, `architecture`, `testing`, `security`, `workflow`, `communication`, `forbidden-action`.
3. Search `learned-rules.md` and `review-feedback-log.md` for overlap — and, if `.agent-os/rules/` exists, also search `.agent-os/rules/*.md`, where the split-out active rules live:
   - If it matches an existing candidate rule's substance, treat this as a second occurrence.
   - If it contradicts an existing active rule, do not silently overwrite it — surface the conflict explicitly to the user and ask which should hold, or record both with the conflict noted.
4. If this is the **first** time this specific feedback has appeared, write a **candidate** rule.
5. If this is the **second or later** occurrence (same substance, possibly different wording), promote it to an **active** rule in `.agent-os/learned-rules.md`.
6. When writing any rule, use exactly this format:

```md
## Rule: <short name>

Status: candidate | active | deprecated
Source: user-feedback | failure | review | eval
Scope: global | project | directory | file-pattern
Applies to:
- <path or task type>

Rule:
- <observable instruction>

Rationale:
- <why this prevents failure>

Examples:
- Do: <example>
- Do not: <example>

Validation:
- <command or checklist>
```

7. Write the rule text as an observable instruction ("run `X` before committing to `migrations/`"), not a feeling or a vague preference.
8. If `.agent-os/rules/` exists (this project already uses the split layout — see `split-learned-rules.sh`), write or promote the active rule directly into `.agent-os/rules/<scope>.md` matching the rule's `Scope:` field, and keep the `## Active rules index` in `learned-rules.md` up to date with a pointer to it. Candidate rules always stay in `learned-rules.md`, regardless of layout.
9. Report back to the user which log/rule file was updated and at what status, so they can correct the classification if wrong.

## Outputs

- A new entry in `.agent-os/review-feedback-log.md` (always, verbatim).
- A new or updated rule in `.agent-os/learned-rules.md` (candidate or active) when the feedback yields an actionable rule — or, under the split layout, an active rule in `.agent-os/rules/<scope>.md` plus an updated index entry in `learned-rules.md`.

## Forbidden

- Promoting a single, clearly one-off preference to a global or active rule.
- Emotional or judgmental wording in a rule ("the agent was careless").
- Vague instructions ("write nicer code", "be more careful", "handle appropriately").
- Silently overwriting a conflicting existing rule — the conflict must be surfaced.
- Creating an overly strong ("always"/"never" applied globally) rule from a single failure when `Scope` should be narrower.

## Done criteria

- The verbatim feedback exists in `review-feedback-log.md`.
- Every resulting rule uses the exact Rule format and has a correct `Status`, `Source`, and `Scope`.
- No rule was silently duplicated or silently overwritten.
- Rules read as concrete, checkable instructions, not sentiment.
