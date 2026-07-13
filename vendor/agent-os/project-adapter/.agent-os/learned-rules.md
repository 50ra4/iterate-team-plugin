<!--
Role: durable, promoted behavioral rules for THIS project — the output of
the Learning Layer. Written by: the agent, during the learn-from-feedback
skill (new/updated rules from corrections and failures) and improve-
instructions (merging duplicates, marking deprecated). Read at the start
of every task; only Status: active rules are binding.

Promotion criteria:
- 1 occurrence (a single correction, review comment, or failure) → Status:
  candidate. An observation, not yet binding.
- 2+ occurrences of the same substance (possibly worded differently) →
  Status: active. Now binding for every session.
- A rule that is stale (no longer matches the codebase) or conflicts with
  another rule → Status: deprecated. Do not delete it; keep it with the
  reason, so future sessions understand why it stopped applying.
- Rules must be observable and checkable ("run X before committing to
  migrations/"), never vague wording ("be careful", "write nicer code").

Initially this file holds everything in one place. If it grows past
roughly 10 active rules or 300 lines, run `scripts/split-learned-rules.sh
--adapter <dir>` to move `Status: active` rule blocks into
`.agent-os/rules/<scope>.md` (global/project/directory/file-pattern, by
each rule's Scope field). This file then keeps an "## Active rules index"
pointing at the moved rules; candidate and deprecated rules always stay
here. After a split, `.agent-os/rules/*.md` is part of this file's active
rules, not a separate concern: agents must read those files too — the
index entries are pointers to binding rule bodies, equally binding as if
they were still listed here.
-->

# Learned Rules: {{PROJECT_NAME}}

## Active rules

<!-- None yet. Populated by learn-from-feedback after 2+ occurrences. -->

## Candidate rules

<!-- None yet. Populated by learn-from-feedback after a single occurrence. -->

<!--
Example (delete me):

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
-->
