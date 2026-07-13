# Claude Code — Agent OS Entrypoint

Principles come from the Global Agent OS (`GLOBAL_AGENTS.md`, `GLOBAL_CLAUDE.md`). This file is the Claude Code entrypoint for working *inside the Agent OS source repository itself* — it points, it does not explain. It is not installed by `bootstrap-project.sh` into a target project (that installs `project-adapter/CLAUDE.md` instead); treat it as an optional candidate for your own user-global Claude Code config (e.g. `~/.claude/CLAUDE.md`) if you want these repo-authoring conventions loaded everywhere.

## Core principles

- Read before you change: the target files, their callers, and any existing pattern already in use.
- Make small, reviewable diffs. Prefer several safe steps over one large rewrite.
- Respect existing design and architecture boundaries — do not refactor beyond the task's scope.
- Use only build/test/state-changing commands confirmed in `.agent-os/command-map.md`. Never invent one. Read-only inspection (`ls`, `cat`, `grep`, `find`, `git status`/`log`/`diff`) is always permitted, even while the map is still empty.
- Never read, print, or commit secrets: `.env` files, keys, tokens, credentials.
- No destructive operations (`rm -rf`, force-push, dropping data, migrations) without explicit approval.
- If something fails, record the command, cause, and prevention in `.agent-os/failure-log.md` — never hide a failure.
- If the user corrects you, record it verbatim in `.agent-os/review-feedback-log.md` as a candidate rule.

## At session start

If `.agent-os/` exists in this project, read before making any change:
- `.agent-os/project-profile.md` — observed facts about stack, structure, conventions.
- `.agent-os/command-map.md` — the only commands you may run to verify work.
- `.agent-os/learned-rules.md` — honor every rule whose `Status:` is `active`; `candidate` rules are observations only. If `.agent-os/rules/` exists, follow its `Active rules index` and read `.agent-os/rules/*.md` too — those rules are just as binding.
- `.agent-os/risk-map.md` — areas that need extra care or explicit approval before touching.

## Use skills for procedures

- `project-bootstrap` — first contact with an unfamiliar project; observe stack/commands/risk, no code changes.
- `project-profile` — create/update `.agent-os/project-profile.md`, facts vs. hypotheses kept separate.
- `adapt-to-project` — turn bootstrap output into this project's CLAUDE.md/AGENTS.md and `.agent-os/` adapter.
- `learn-from-feedback` — a correction or review comment just happened; record and classify it now.
- `improve-instructions` — instructions have grown noisy or contradictory; propose a cleanup (approval required).
- `generate-agent-files` — regenerate the Claude/Codex platform files from the Global OS plus the adapter.
- `run-agent-evals` — instructions just changed, or it's time to check for behavior regressions.
- `fix-bug-safely` — any bug report or unexpected behavior needing a code change: reproduce, root-cause, fix, test.
- `implement-feature-safely` — any new-functionality request: confirm scope, reuse patterns, verified diffs.
- `review-changes` — before considering a diff done, or when asked to review a PR.

## Use subagents for specialized judgment

- `code-reviewer` — line-level correctness, scope creep, and convention review of a diff.
- `architecture-reviewer` — layering, dependency direction, and responsibility-boundary review.
- `test-strategist` — test coverage gaps and concrete test-case proposals for a change.
- `security-reviewer` — secrets, authn/authz, injection, and destructive-operation risks.
- `bug-investigator` — root-cause analysis of a bug; reports findings, does not fix.
- `instruction-maintainer` — proposes rule promotions/deprecations/merges; never applies them.

No project-specific facts live in this file — those belong in the project's `.agent-os/`.
