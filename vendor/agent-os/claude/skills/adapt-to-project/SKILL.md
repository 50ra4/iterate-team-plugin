---
name: adapt-to-project
description: Generate this project's short CLAUDE.md/AGENTS.md and .agent-os adapter files (learned-rules.md, evals.md) from project-bootstrap's output. Use once bootstrap facts exist and no adapter is wired up yet.
---

The canonical procedure lives in `.agent-os/skills/adapt-to-project/SKILL.md` (inside the Agent OS repository itself, the canonical source is `agent-os/skills/adapt-to-project/SKILL.md`). Follow that file's steps in full instead of this summary. What follows is a standalone-usable condensation.

## Procedure summary

1. Require `project-bootstrap` output to already exist (`project-profile.md`, `command-map.md`, `risk-map.md`). If missing, run `project-bootstrap` first.
2. Generate a short project-root `CLAUDE.md` (and/or `AGENTS.md`) matching the shape of the project's own installed `CLAUDE.md`/`AGENTS.md` (a copy of `project-adapter/CLAUDE.md`/`AGENTS.md` — canonical source: `templates/CLAUDE.md.template` in the Agent OS source repo, not present in a bootstrapped project): pointers only, no procedures, under the same length discipline as the global entrypoint.
3. Generate `.agent-os/learned-rules.md` (scaffold, ready to receive rules) and `.agent-os/evals.md` (initial scenarios derived from `risk-map.md` and `command-map.md`). Refresh `.agent-os/architecture-map.md` too if it looks stale against current facts.
4. Write only facts confirmed by bootstrap into the adapter. Anything uncertain stays a hypothesis in `project-profile.md` — never promoted to a rule.
5. Never modify the Global Layer (`GLOBAL_AGENTS.md`, `GLOBAL_CLAUDE.md`) — it stays project-agnostic and is not restated here.

## Forbidden

- Promoting a hypothesis to a confirmed rule.
- Writing project-specific facts into the Global Layer.
- Inventing a command not present in `command-map.md`.
- Overwriting an existing, actively-used `learned-rules.md` instead of merging into it.

## Claude-specific notes

- The CLAUDE.md this skill produces is what Claude Code will load every turn in this project going forward — keep it a table of contents, not a manual.
- Touch only `.agent-os/*` and the root `CLAUDE.md`/`AGENTS.md`; do not edit source code as part of this skill.
