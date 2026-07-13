---
name: project-bootstrap
description: First contact with a new project — observe and record facts about stack, commands, structure, and risk areas without changing anything.
---

## Purpose

Build a truthful, evidence-backed picture of an unfamiliar project before any code is touched. This is the first skill run in any project that has no `.agent-os/` yet, or whose `.agent-os/` looks stale.

## When to use

- The project has no `.agent-os/` directory yet.
- `.agent-os/project-profile.md` is missing, empty, or clearly out of date (e.g. references a build system no longer present).
- The user explicitly asks for a fresh scan of the project.

Do not use this skill to make changes. It produces observations only; `adapt-to-project` consumes them to generate the adapter.

## Inputs

- Repository root (read access only).
- Any existing `README*`, `docs/`, `package.json` / `pyproject.toml` / `go.mod` / `Cargo.toml` / etc., build config, test config, CI config (`.github/workflows/`, `.gitlab-ci.yml`, etc.).
- Any existing agent files: `CLAUDE.md`, `AGENTS.md`, `.agent-os/`.

## Procedure

1. Read `README*`, `docs/`, package/build/test/CI manifests, and any existing `CLAUDE.md`, `AGENTS.md`, `.agent-os/*`.
2. Infer the tech stack (language, framework, package manager, runtime versions) from manifests, not from guessing.
3. Extract ONLY commands that verifiably exist — from `package.json` `scripts`, `Makefile` targets, CI workflow steps. For each command, record its source file and line/key as evidence.
4. Map the directory structure at a useful depth (source, tests, config, infra, generated) — not a full file listing.
5. Identify dangerous areas: migrations, deploy scripts, infra-as-code, generated code, production config, anything touching secrets or credentials.
6. Understand the test strategy: test runner, test locations, how CI invokes tests, coverage expectations if stated.
7. Hypothesize AI-error-prone spots (e.g. codegen that looks hand-written, subtle async ordering, shared mutable state, ambiguous naming) — label these clearly as hypotheses, not facts.
8. Generate `.agent-os/project-profile.md` (see the `project-profile` skill for section layout).
9. Generate `.agent-os/command-map.md` — one entry per verified command, each with its evidence source.
10. Generate `.agent-os/risk-map.md` — dangerous areas from step 5, each with why it is dangerous and what approval is required before touching it.
11. Generate an initial `.agent-os/architecture-map.md` from what was observed in steps 2-6: layers/modules and their responsibilities, allowed dependency directions, boundaries that must not be crossed, and extension points. Observation only, same discipline as everywhere else in this skill — separate confirmed facts from hypotheses, and leave a section empty (not guessed) if nothing was actually observed for it.
12. Record observations and hypotheses in separate, clearly labeled sections. Do not create `learned-rules.md` entries yet — bootstrapping is not the same as learning.

## Outputs

- `.agent-os/project-profile.md`
- `.agent-os/command-map.md`
- `.agent-os/risk-map.md`
- `.agent-os/architecture-map.md` — initial pass; `adapt-to-project` refines it as the adapter matures.
- A short summary to the user: stack, verified commands, top risk areas, open hypotheses.

Read-only inspection commands (`ls`, `cat`, `grep`, `find`, `git status`/
`log`/`diff`, and equivalents) are always permitted while carrying out
this procedure, even though `.agent-os/command-map.md` is still an empty
scaffold at this point — the always-loaded command-map rule governs
build/test/state-changing commands, not read-only inspection.

## Forbidden

- Modifying any source, config, or test file during analysis.
- Inventing commands that were not found in a manifest or CI file.
- Recording a guess as a confirmed fact.
- Adding dependencies, changing configuration, or refactoring "while looking around."
- Reading `.env` files, key material, or other secrets, even to "understand config."

## Done criteria

- Every command in `command-map.md` has a cited source.
- `project-profile.md` clearly separates observed facts from hypotheses.
- `risk-map.md` lists concrete paths/areas, not vague categories.
- `architecture-map.md` reflects actually-observed layering, not an unpopulated scaffold.
- No file outside `.agent-os/` was modified.
- The user has a short, accurate summary of what this project is and where the danger is.
