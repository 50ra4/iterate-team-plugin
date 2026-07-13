---
name: project-bootstrap
description: First contact with a new project — observe and record facts about stack, commands, structure, and risk areas without changing anything. Use when there is no `.agent-os/` yet, or it looks stale, or the user asks for a fresh scan.
---

The canonical procedure lives in `.agent-os/skills/project-bootstrap/SKILL.md` (inside the Agent OS repository itself, the canonical source is `agent-os/skills/project-bootstrap/SKILL.md`). Follow that file's steps in full instead of this summary. What follows is a standalone-usable condensation.

## Procedure summary

1. Read `README*`, `docs/`, package/build/test/CI manifests, and any existing `CLAUDE.md`, `AGENTS.md`, `.agent-os/*`.
2. Infer the stack from manifests — never from guessing.
3. Extract ONLY commands that verifiably exist (`package.json` scripts, `Makefile` targets, CI steps); cite the source file/line for each.
4. Map the directory structure at a useful depth (source, tests, config, infra, generated).
5. Identify dangerous areas: migrations, deploy scripts, infra-as-code, generated code, anything touching secrets.
6. Note the test strategy: runner, locations, how CI invokes it.
7. Hypothesize AI-error-prone spots, clearly labeled as hypotheses, not facts.
8. Write `.agent-os/project-profile.md`, `.agent-os/command-map.md`, `.agent-os/risk-map.md`, and an initial `.agent-os/architecture-map.md` (observed layers, dependency direction, boundaries, extension points), keeping observations and hypotheses in separate, labeled sections.

## Forbidden

- Modifying any source, config, or test file during this pass.
- Inventing commands not found in a manifest or CI file.
- Recording a guess as a confirmed fact.
- Adding dependencies, changing configuration, or refactoring "while looking around."
- Reading `.env` files, key material, or other secrets.

## Claude-specific notes

- Use read-only tools only (`Read`, `Grep`, `Glob`, `Bash` for read-only inspection like `git status`, `cat`, listing). Do not use `Edit` on anything outside `.agent-os/`. This is permitted even though `.agent-os/command-map.md` is still an empty scaffold — CLAUDE.md's command-map rule covers build/test/state-changing commands only, not read-only inspection.
- End with a short summary to the user: stack, verified commands, top risk areas, open hypotheses — do not silently finish.
