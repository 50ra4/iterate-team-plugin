<!--
Role: the authoritative, verified list of build/test/lint/typecheck/run
commands for THIS project. Written by: the agent, during the
project-bootstrap skill (initial extraction from manifests/CI) and updated
whenever a command is newly verified or found to no longer work. Read at
the start of every task — agents must not run a command that is not
listed here without first verifying it exists.

Rule: only commands verified to exist may be recorded. Each entry must
cite its evidence (package.json script, Makefile target, CI config, docs).
Agents must not run commands that are not in this map without verifying
them first.

Scope: this map is the allow-list for build/test/lint/typecheck/run and
any other state-changing command. Read-only inspection (`ls`, `cat`,
`grep`, `find`, `git status`/`log`/`diff`) is out of its scope and is
always permitted, including before this map has any verified entries —
it is what the project-bootstrap skill uses to populate the map.
-->

# Command Map: {{PROJECT_NAME}}

## Build

<!-- Not yet observed. Populated by the project-bootstrap skill. -->

## Test

<!-- Not yet observed. Populated by the project-bootstrap skill. -->

## Lint

<!-- Not yet observed. Populated by the project-bootstrap skill. -->

## Typecheck

<!-- Not yet observed. Populated by the project-bootstrap skill. -->

## Format

<!-- Not yet observed. Populated by the project-bootstrap skill. -->

## Run

<!-- Not yet observed. Populated by the project-bootstrap skill. -->

## Other

<!-- Not yet observed. Populated by the project-bootstrap skill. -->

<!--
Example (delete me):

| Command | What it does | Evidence | Last verified |
|---|---|---|---|
| `npm test` | Runs the Jest test suite | `package.json` scripts."test" | 2026-01-15 |
-->
