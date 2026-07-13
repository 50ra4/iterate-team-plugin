---
name: adapt-to-project
description: Turn project-bootstrap output into the project's adapter — AGENTS.md, CLAUDE.md, and .agent-os/ files — without ever editing the Global Agent OS.
---

## Purpose

Generate the project-specific adapter layer that sits on top of the Global Agent OS. The adapter tells an agent what is true and required for *this* project; the Global OS stays generic and untouched.

## When to use

- Immediately after `project-bootstrap` has produced its observations.
- When a project's adapter files exist but no longer match `project-profile.md` (drifted).
- Not for encoding personal style preferences with no evidence behind them — those wait for `learn-from-feedback`.

## Inputs

- `.agent-os/project-profile.md`, `.agent-os/command-map.md`, `.agent-os/risk-map.md` (from bootstrap).
- Any existing `AGENTS.md` / `CLAUDE.md` / `.agent-os/learned-rules.md` to preserve and merge, not overwrite blindly.
- `GLOBAL_AGENTS.md` for tone and structure reference — read it, never modify it.

## Procedure

1. Read `GLOBAL_AGENTS.md` to confirm what already applies globally; do not repeat it in the adapter.
2. Read `.agent-os/project-profile.md` and pull only verified facts (never hypotheses) into the adapter.
3. Write/update `AGENTS.md` and `CLAUDE.md` at the project root: short, project-specific, pointing to `.agent-os/` and to relevant skills for detail. No long procedures inline. Reconcile the result against the structure of the project's own installed `AGENTS.md`/`CLAUDE.md` (copies of `project-adapter/AGENTS.md`/`CLAUDE.md`, which ARE the standard shape) so nothing from the standard shape is silently dropped — the canonical source of that shape is `templates/AGENTS.md.template`/`CLAUDE.md.template`, but that path only exists in the Agent OS source repo itself, not in a bootstrapped project.
4. Ensure `.agent-os/project-profile.md` is present and current (delegate to the `project-profile` skill if it needs rework).
5. Refresh `.agent-os/architecture-map.md` if it looks stale against current observed facts (new module, changed boundary, new dependency direction) — same observation discipline as `project-bootstrap`: facts vs. hypotheses, no guessing.
6. Create `.agent-os/learned-rules.md` if absent (empty shell with the standard Rule format ready to receive entries — do not pre-populate it with unverified rules).
7. Create `.agent-os/evals.md` if absent (empty shell, or seeded from `run-agent-evals` perspectives relevant to this project's stack).
8. Optionally generate per-directory `AGENTS.md` files only where a directory has genuinely distinct rules (e.g. a `migrations/` directory with its own constraints) — do not create one per directory by default.
9. Optionally generate `.claude/skills/*` or `.agents/skills/*` wrappers only when a project needs a platform-specific entry point; the canonical procedure still lives in the Global OS `skills/`.
10. Cross-check: every rule placed in the adapter must trace back to an observed fact, a repeated failure, or a repeated piece of feedback — not a single guess.
11. Confirm nothing under the vendored Global layer in this project (`.agent-os/GLOBAL_AGENTS.md`, `.agent-os/skills/`) was modified — or, if working directly in the Agent OS source repo, nothing under its root `GLOBAL_AGENTS.md`, `skills/`, `templates/`, `scripts/`.

## Outputs

- `AGENTS.md`, `CLAUDE.md` at project root (short).
- `.agent-os/project-profile.md`, `.agent-os/learned-rules.md`, `.agent-os/evals.md`, `.agent-os/architecture-map.md` (refined if it was stale).
- Optional per-directory `AGENTS.md`, optional `.claude/skills/*`, optional `.agents/skills/*`.

## Forbidden

- Writing strong rules up front with no evidence — only observed facts become rules at this stage.
- Moving hypotheses from `project-profile.md` into the adapter as if they were settled.
- Promoting a single failure or single review comment straight to an active rule (that requires 2+ occurrences; see `learn-from-feedback`).
- Modifying any file under the Global Agent OS root.
- Letting generated `CLAUDE.md`/`AGENTS.md` grow long — details belong in skills, not in the always-loaded file.

## Done criteria

- `AGENTS.md`/`CLAUDE.md` are short and link out to `.agent-os/` and skills for detail.
- Every rule in `learned-rules.md` (if any exist yet) has a real source, not an assumption.
- The Global Agent OS directory is byte-for-byte unchanged.
- A new agent reading only the adapter plus `GLOBAL_AGENTS.md` has enough to work safely in this project.
