---
name: project-bootstrap
description: First contact with a new project — observe and record facts about stack, commands, structure, and risk areas without changing anything.
---

Canonical procedure: `.agent-os/skills/project-bootstrap/SKILL.md` (inside the
Agent OS repository itself, the canonical source is
`agent-os/skills/project-bootstrap/SKILL.md`). Read it before running this workflow —
this file is a compact Codex-facing pointer, not a replacement.

## Summary

1. Read `README*`, `docs/`, package/build/test/CI manifests, and any
   existing `AGENTS.md` / `.agent-os/*`.
2. Infer the tech stack from manifests, not from guessing.
3. Extract only commands that verifiably exist (from `package.json`
   scripts, `Makefile` targets, CI steps); record the source file and
   line/key as evidence for each.
4. Map the directory structure at a useful depth (source, tests, config,
   infra, generated).
5. Identify risk areas: migrations, deploy scripts, infra-as-code,
   generated code, production config, anything touching secrets.
6. Generate `.agent-os/project-profile.md`, `.agent-os/command-map.md`,
   `.agent-os/risk-map.md`, and an initial `.agent-os/architecture-map.md`
   (observed layers, dependency direction, boundaries, extension points).
7. Keep observations and hypotheses in clearly separate, labeled sections.

## Codex-specific notes

- This workflow is observation-only. Read files and run only read-only
  shell commands (`ls`, `cat`, `grep`, and equivalents) to inspect the
  repository — never edit, build, install, or run tests during bootstrap.
  This is permitted even though `.agent-os/command-map.md` is still an
  empty scaffold — AGENTS.md's command-map rule covers build/test/
  state-changing commands only, not read-only inspection.
- Never read `.env` files, key material, or other secrets, even to
  "understand config."

## Forbidden

- Modifying any source, config, or test file during analysis.
- Inventing a command not found in a manifest or CI file.
- Recording a guess as a confirmed fact.
