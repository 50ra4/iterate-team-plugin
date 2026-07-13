---
name: generate-agent-files
description: Generate the real per-platform agent files (Claude and Codex) from the Global Agent OS plus the project adapter, keeping both platforms in sync in meaning.
---

Canonical procedure: `.agent-os/skills/generate-agent-files/SKILL.md` (inside the
Agent OS repository itself, the canonical source is
`agent-os/skills/generate-agent-files/SKILL.md`). Read it before running this workflow —
this file is a compact Codex-facing pointer, not a replacement.

## Summary

1. Read the vendored `.agent-os/skills/*/SKILL.md` files (canonical
   source: `skills/*/SKILL.md` in the Agent OS source repo) — never
   author new procedure content directly inside a platform wrapper.
2. Read the project adapter for project-specific facts, commands, and
   active rules.
3. Generate/update Codex targets: `AGENTS.md`, `.agents/skills/*/SKILL.md`,
   `.codex/agents/*.toml`.
4. Generate/update Claude targets equivalently: `CLAUDE.md`,
   `.claude/skills/*/SKILL.md`, `.claude/agents/*.md`.
5. Treat `.agent-os/learned-rules.md`, `.agent-os/evals.md`,
   `.agent-os/failure-log.md`, and `.agent-os/review-feedback-log.md` as
   read-only inputs — those change only via `learn-from-feedback`/
   `improve-instructions`, never here. `.agent-os/project-profile.md`
   may be refreshed if stale.
6. Diff Claude and Codex outputs side by side for the same source:
   wording may differ, behavior/rules must not.
7. Confirm no project-specific fact leaked into `.agent-os/GLOBAL_AGENTS.md`
   or the vendored `.agent-os/skills/`.

## Codex-specific notes

- Keep `AGENTS.md`'s "At task start" file list and skill list in sync
  with what `CLAUDE.md` lists for Claude — both must name the same files
  and skills.
- Re-run this workflow whenever a canonical skill's Forbidden list or
  procedure changes, so `.agents/skills/*` does not drift stale.

## Forbidden

- Letting Claude and Codex outputs diverge in meaning (different rules,
  risk areas, or commands).
- Writing long, always-loaded instructions instead of pointing to a skill.
- Leaking project-specific rules or facts into `.agent-os/GLOBAL_AGENTS.md`
  or the vendored `.agent-os/skills/`.
- Designing any file to be "re-read as a giant prompt every run" instead
  of structured, skill-based loading.
- Duplicating the same procedure text in more than one platform's skill
  file instead of both pointing to the same canonical content.
