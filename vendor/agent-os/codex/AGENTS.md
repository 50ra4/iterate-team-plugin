# Codex Instructions — Agent OS

Canonical principles for this Agent OS live in `GLOBAL_AGENTS.md`. This file is the Codex entrypoint for working inside the Agent OS source repo itself — not what `bootstrap-project.sh` installs into a target project (that installs `project-adapter/AGENTS.md` instead); optionally usable as your own user-global Codex config.

## Core principles

1. Read before you change: confirm goal, constraints, blast radius; read
   files you touch and what depends on them; check `git status` first.
2. Make small, reviewable diffs — prefer several safe steps over one rewrite.
3. Respect existing design and architecture boundaries; do not refactor
   beyond the task's scope.
4. Use only build/test/state-changing commands confirmed in
   `.agent-os/command-map.md` — never invent one. Read-only inspection
   (`ls`, `cat`, `grep`, `find`, `git status`/`log`/`diff`) is always
   permitted, even while the map is still empty.
5. Never read, print, or commit secrets (`.env`, keys, tokens, credentials);
   no destructive operations (`rm -rf`, force-push, dropping data,
   migrations) without explicit approval.
6. On failure, record the command, cause, and prevention in
   `.agent-os/failure-log.md` — never hide or misreport a failure.
7. Record user corrections in `.agent-os/review-feedback-log.md`; the same
   correction repeated twice or more becomes an active rule in
   `.agent-os/learned-rules.md`.

## At task start

If `.agent-os/` exists, read before any change: `project-profile.md`
(observed facts), `command-map.md` (verified commands), `learned-rules.md`
(honor rules with `Status: active`; `candidate` rules are not yet
binding; if `.agent-os/rules/` exists, its `Active rules index` points to
`.agent-os/rules/*.md` files that are equally binding — read those too),
and `risk-map.md` (approval-gated areas).

## Skills

Long procedures live in skills, not here — read the relevant skill file before that workflow:

- `project-bootstrap` — first contact with an unfamiliar project; observe only, no changes.
- `project-profile` — create/update `.agent-os/project-profile.md`, facts vs. hypotheses.
- `adapt-to-project` — turn bootstrap output into AGENTS.md and the `.agent-os/` adapter.
- `learn-from-feedback` — record and classify a correction or review comment now.
- `improve-instructions` — propose a cleanup when instructions grow noisy (approval required).
- `generate-agent-files` — regenerate Claude/Codex platform files from the adapter.
- `run-agent-evals` — check for behavior regressions after an instruction change.
- `fix-bug-safely` — reproduce, root-cause, minimal diff, regression test.
- `implement-feature-safely` — confirm scope, reuse patterns, verified small diffs.
- `review-changes` — checklist review of a diff: correctness, scope, security, tests.

## Custom agents

Specialized, bounded roles live in `.codex/agents/*.toml`: `code-reviewer`
(diff correctness), `architecture-reviewer` (design/boundary review),
`test-strategist` (test strategy), `security-reviewer` (secrets, authn/authz,
injection risk), `bug-investigator` (root cause, no fixing), and
`instruction-maintainer` (instruction-improvement proposals).

No project-specific facts belong in this file — those live in `.agent-os/`.
