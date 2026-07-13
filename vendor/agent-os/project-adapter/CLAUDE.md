<!--
Role: always-loaded entry point for this project in Claude Code. Starter-kit
copy from agent-os/project-adapter/CLAUDE.md, filled in ({{PROJECT_NAME}}
and links) by the adapt-to-project skill. Kept short by improve-instructions
if it ever drifts or grows.
-->

# {{PROJECT_NAME}} — Claude Code Instructions

Global, project-agnostic principles live in `.agent-os/GLOBAL_AGENTS.md` /
`.agent-os/GLOBAL_CLAUDE.md`, installed alongside this project. Read them
first; not repeated here.

## Where things live

- **This file** — short, always-loaded pointers only.
- **`.claude/skills/*/SKILL.md`** — on-demand procedures, if installed.
- **`.claude/agents/*.md`** — specialized subagents, if installed.
- **`.agent-os/`** — this project's observed facts and learned rules.

## At the start of every task, read

1. `.agent-os/project-profile.md`, `.agent-os/command-map.md`,
   `.agent-os/risk-map.md`.
2. `.agent-os/learned-rules.md` — honor every `Status: active` rule.
   `Status: candidate` rules are observations only, not yet binding. If
   `.agent-os/rules/` exists, active rule bodies live in
   `.agent-os/rules/*.md` — follow the `Active rules index` in
   `learned-rules.md` and read those files too; they are just as binding.

## Safety (non-negotiable)

- No destructive operations (`rm -rf`, force-push, dropping data, migrations)
  without explicit user approval.
- Never read, print, or commit secrets (`.env`, keys, tokens, credentials).
- Build, test, and any state-changing commands: run only what is listed
  in `.agent-os/command-map.md` — never invent one. Read-only inspection
  (`ls`, `cat`, `grep`, `find`, `git status`/`log`/`diff`) is always
  permitted, including while the map is still an empty scaffold.

## After you work / learning loop

- If something fails, record the command, the cause, and the prevention
  in `.agent-os/failure-log.md` — never hide a failure.
- If corrected, record it verbatim in `.agent-os/review-feedback-log.md`.
- Never mark work done while tests, types, or lint are failing or skipped.

## This file stays short

Procedures live in skills; project facts and learning history live in
`.agent-os/`. Do not let this file grow into a manual.
