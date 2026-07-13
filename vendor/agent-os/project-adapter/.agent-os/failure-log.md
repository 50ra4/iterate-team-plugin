<!--
Role: verbatim record of failed commands/approaches for THIS project — raw
material for the Learning Layer. Written by: the agent, at the end of any
task where a command failed, a test broke, or an approach did not work (see
GLOBAL_AGENTS.md "After you work"). Read by learn-from-feedback and
project-profile ("Areas where AI tends to err") when looking for patterns.

Header note: a failure whose recurrence count reaches 2+ must be turned
into a rule via the learn-from-feedback skill (recorded in
learned-rules.md, with Source: failure), not just logged again.
-->

# Failure Log: {{PROJECT_NAME}}

<!-- No entries yet. -->

<!--
Example (delete me):

## 2026-01-15 — Failure

Task: Add index migration for `orders` table.

Failed command:
```
npm run migrate:up
```

Error (verbatim):
```
Error: relation "orders_idx_customer" already exists
```

Root cause: a previous, unapplied migration file already defined the same
index name; the migration runner does not check for name collisions.

Impact: migration aborted partway; no data was changed, but the migration
state table was left marked as partially applied.

Prevention: always run `npm run migrate:status` before writing a new
migration to check for name collisions with pending migrations.

Recurrence count: 1

Promoted rule: none yet (needs a second occurrence).
-->
