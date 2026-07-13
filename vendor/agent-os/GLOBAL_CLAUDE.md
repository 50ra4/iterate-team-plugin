# Global Claude Code Delta

`GLOBAL_AGENTS.md` is the canonical source of principles. This file does not restate them — it only adds Claude-Code-specific mechanics for how those principles are loaded and applied inside Claude Code.

## Where things live

Claude Code gives you three different loading mechanisms. Use the right one:

- **CLAUDE.md (memory)** — short, always-loaded-every-turn principles and pointers. It should read like a table of contents: "here is what matters, here is where the detail lives." Never put a procedure here.
- **Skills (`.claude/skills/*/SKILL.md`)** — on-demand, long-form procedures. Loaded only when relevant. This is where step-by-step instructions, checklists, and multi-stage workflows belong.
- **Subagents (`.claude/agents/*.md`)** — specialized roles invoked for a bounded piece of work, each with its own scoped context and tool access. Use them for tasks that benefit from a distinct persona or a fresh context window: `code-reviewer`, `architecture-reviewer`, `test-strategist`, `security-reviewer`, `bug-investigator`, `instruction-maintainer`.

## The rule of thumb

If it takes more than a few lines to explain, it does not belong in CLAUDE.md — it belongs in a skill. CLAUDE.md is paid for on every single turn, so treat every line in it as a recurring cost. When CLAUDE.md starts accumulating procedures, extract them into a skill and leave a one-line pointer behind.

## Session start

If the project has a `.agent-os/` directory, read its adapter files (`project-profile.md`, `learned-rules.md`, `risk-map.md`, `command-map.md`) at the start of the session, before making any change. They contain project facts that CLAUDE.md intentionally omits. If `.agent-os/rules/` exists, the active rule bodies live in `.agent-os/rules/*.md` — follow the `Active rules index` in `learned-rules.md` and read those files too; they are just as binding as if they were still in `learned-rules.md`.
