---
name: run-agent-evals
description: Run the project's recorded agent evaluation scenarios and check for precision regressions after an instruction change.
---

Canonical procedure: `.agent-os/skills/run-agent-evals/SKILL.md` (inside the
Agent OS repository itself, the canonical source is
`agent-os/skills/run-agent-evals/SKILL.md`). Read it before running this workflow —
this file is a compact Codex-facing pointer, not a replacement.

## Summary

1. Load the scenarios recorded in `.agent-os/evals.md` — `scripts/run-agent-evals.sh --adapter <dir> --list` enumerates them with their last result, and `--show <name>` prints one in full.
2. For each scenario, run it yourself and check both the stated pass criteria and
   the absence of any explicitly forbidden behavior. The script does not perform the task.
3. Use `--check <name>` to see the Validation command(s); only pass `--exec` for a command
   listed verbatim in `.agent-os/command-map.md` — the script refuses anything else.
4. Record each result with `--record <name> --result pass|fail --model <name> [--notes <text>]`.
5. Route any failure to `.agent-os/failure-log.md` and, if the same
   failure pattern recurs, propose it as a rule candidate (via
   `learn-from-feedback` / `improve-instructions`).
6. Run this workflow whenever `AGENTS.md`, a skill, or
   `.agent-os/learned-rules.md` changes, to confirm no regression was
   introduced.

## Codex-specific notes

- Only execute commands already confirmed in `.agent-os/command-map.md`;
  do not improvise a command to make a scenario runnable. `run-agent-evals.sh --check --exec`
  enforces this gate automatically and never runs a "Manual review" command.
- Do not invent pass/fail criteria beyond what a scenario in `evals.md`
  actually states — if a scenario is ambiguous, report that instead of
  guessing a criterion.

## Forbidden

- Reporting a scenario as passing when a forbidden behavior occurred.
- Skipping the failure-log/rule-candidate step after a failed eval.
- Modifying source files as part of running an eval.
