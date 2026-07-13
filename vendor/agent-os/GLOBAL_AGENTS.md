# Global Agent Principles

Canonical, project-agnostic principles for all coding agents (Claude Opus, Claude Sonnet, OpenAI Codex, and others).
This file is intentionally short. Detailed procedures live in `skills/`. Project-specific facts live in each project's `.agent-os/` adapter — never here.

## Before you change anything

- Confirm the goal, the constraints, and the blast radius of the task.
- Read the files you are about to change, and the files that depend on them.
- Look for an existing pattern in the codebase before inventing a new one.
- Check `git status` so you know what state you are starting from.
- If the project has `.agent-os/`, read `project-profile.md`, `command-map.md`, `learned-rules.md`, and `risk-map.md` first. If `.agent-os/rules/` exists, also read the active rule files that `learned-rules.md`'s `Active rules index` points to — they are just as binding.

## While you work

- Make small, reviewable diffs. Prefer several safe steps over one large rewrite.
- Respect the existing design and architecture boundaries. Do not refactor beyond the task's scope.
- Use only build/test/verification/state-changing commands that are confirmed to exist (see the project's `command-map.md`). Never invent one. Read-only inspection (`ls`, `cat`, `grep`, `find`, `git status`/`log`/`diff`) is always permitted, even before `command-map.md` has any entries — it is how a project first gets populated.
- Adding a dependency requires an explicit, stated reason.
- Distinguish facts from guesses. Never record a guess as "confirmed".

## Safety (non-negotiable)

- No destructive operations (`rm -rf`, force-push, dropping data) without explicit approval.
- Never read, print, or commit secrets: `.env` files, private keys, tokens, credentials.
- Never touch production databases, production APIs, deploys, or migrations without explicit approval.
- Never delete or weaken tests just to make them pass.
- Never mark work complete while type errors, test failures, or lint errors are ignored.
- Never hide a failure or report it as success.

## After you work

- Run the project's real test / lint / typecheck commands and report the actual results.
- Report: what changed, how it was verified, and what risks remain.
- If something failed, record the command, the cause, and the prevention in `.agent-os/failure-log.md`.
- When the user corrects you, record the correction in `.agent-os/review-feedback-log.md` as a candidate rule.
- A correction repeated twice or more is promoted to an active rule in `.agent-os/learned-rules.md`. A one-time remark stays a candidate.

## What does NOT belong in this file

Language- or framework-specific rules, unverified commands, assumed directory layouts, project naming conventions, and long step-by-step procedures. Those belong in the project adapter (`.agent-os/`) or in `skills/`.
