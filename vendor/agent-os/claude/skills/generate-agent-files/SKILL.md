---
name: generate-agent-files
description: Generate the real per-platform agent files (Claude and Codex) from the Global Agent OS plus the project adapter, keeping both platforms in sync in meaning. Use after adapt-to-project, or when a new platform target is added.
---

The canonical procedure lives in `.agent-os/skills/generate-agent-files/SKILL.md` (inside the Agent OS repository itself, the canonical source is `agent-os/skills/generate-agent-files/SKILL.md`). Follow that file's steps in full instead of this summary. What follows is a standalone-usable condensation.

## Procedure summary

1. Read the vendored `.agent-os/skills/*/SKILL.md` files (canonical source: `skills/*/SKILL.md` in the Agent OS source repo) — never author new procedure content directly inside a platform wrapper.
2. Read the project adapter for project-specific facts, commands, and active rules.
3. Generate/update Claude targets: `CLAUDE.md` (short, always-loaded), `.claude/skills/*/SKILL.md` (thin wrappers), `.claude/agents/*.md` (specialty subagents).
4. Generate/update Codex targets: `AGENTS.md`, `.agents/skills/*/SKILL.md`, `.codex/agents/*.toml` — equivalent in meaning to the Claude outputs.
5. Treat `.agent-os/learned-rules.md`, `.agent-os/evals.md`, `.agent-os/failure-log.md`, and `.agent-os/review-feedback-log.md` as read-only inputs — those change only via `learn-from-feedback`/`improve-instructions`, never here. `.agent-os/project-profile.md` may be refreshed if stale.
6. Diff Claude and Codex outputs side by side for the same source: wording may differ, behavior/rules must not.
7. Confirm no project-specific fact leaked into `.agent-os/GLOBAL_AGENTS.md` or the vendored `.agent-os/skills/`.
8. Confirm always-loaded files stayed short and agents are split by specialty.
9. Report which files were generated/updated per platform.

## Forbidden

- Letting Claude and Codex outputs diverge in meaning (different rules, risk areas, or commands).
- Writing long, always-loaded instructions instead of pointing to a skill.
- Leaking project-specific rules or facts into `.agent-os/GLOBAL_AGENTS.md` or the vendored `.agent-os/skills/`.
- Designing any file to be "re-read as a giant prompt every run" instead of structured, skill-based loading.
- Duplicating the same procedure text in more than one platform's skill file instead of both pointing to the same canonical content.

## Claude-specific notes

- When this skill regenerates `CLAUDE.md`, keep the session-start file list and skill list in sync with what `AGENTS.md` lists for Codex — both should name the same files and skills.
- This skill is the mechanism that keeps `claude/skills/*` from drifting out of the canonical `skills/*` — re-run it whenever a canonical skill's Forbidden list or procedure changes.
