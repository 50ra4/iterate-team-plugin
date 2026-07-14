---
name: run-agent-evals
description: Run the project's evals to check whether the Agent OS is actually growing correctly — accurate rules, real learning, no regressions.
---

## Purpose

Verify, with real task execution rather than inspection alone, that the accumulated rules, adapter, and skills are producing correct agent behavior — and that lessons already learned are actually being applied.

## When to use

- Periodically, as a health check on the project's `.agent-os/`.
- After `improve-instructions` makes changes, to confirm they helped rather than regressed anything.
- Before trusting a project's adapter for a high-stakes task.

## Inputs

- `.agent-os/evals.md` (the eval catalog for this project).
- `.agent-os/learned-rules.md`, `.agent-os/failure-log.md` (what should be applied/avoided). If `.agent-os/rules/` exists, also `.agent-os/rules/*.md` — the active rules moved out of `learned-rules.md`, equally binding for the Learning check.
- `.agent-os/command-map.md` (real verification commands).

## Eval perspectives to cover

Choose evals that exercise: a small bug fix, a feature addition, adding tests, a refactor, a security review, a UI change, a dependency-addition judgment call, implementing something to match an existing design, recurrence-prevention from the failure log, and verification that a specific piece of user feedback was actually applied.

## Procedure

1. Use `scripts/run-agent-evals.sh --adapter <dir> --list` to enumerate the evals in `.agent-os/evals.md` and their last recorded result; pick one or more matching the perspectives above. If a perspective has no eval yet, note the gap for `improve-instructions` rather than skip silently.
2. Run `scripts/run-agent-evals.sh --adapter <dir> --show <eval-name>` to read the full eval block before starting.
3. Perform the eval's Task yourself, exactly as specified, using the project's real commands from `command-map.md` — not a simulated shortcut. The script does not do this part; it only enumerates, checks, and records.
4. Run `scripts/run-agent-evals.sh --adapter <dir> --check <eval-name>` to see the Validation command(s). Only add `--exec` to actually run one, and only when it appears verbatim in `.agent-os/command-map.md` — the script refuses to run anything not listed there, and never executes a "Manual review" style command.
5. Check the result against the eval's pass criteria and forbidden behavior list.
6. Record the result with `scripts/run-agent-evals.sh --adapter <dir> --record <eval-name> --result pass|fail --model <name> [--notes <text>]`, which appends a row to the eval's Results table.
7. Answer the eval's **Learning check** questions explicitly: which learned rule should have been used, and did the agent use it; which prior failure should not recur, and did it recur.
8. On failure: write an entry to `.agent-os/failure-log.md` (command, cause, prevention) and consider whether a new or stronger rule is warranted — hand off to `learn-from-feedback` if so.
9. On a **repeated** failure of the same eval (or same failure shape across evals): escalate to `improve-instructions` rather than patching the same rule again in isolation.
10. Summarize overall pass/fail rate and flag any eval perspective that is currently untested.

## Eval format

Use exactly this structure when adding or reading an eval:

```md
## Eval: <name>

Task:
- <what the agent should do>

Expected files to inspect:
- <files>

Expected behavior:
- <behavior>

Forbidden behavior:
- <behavior>

Pass criteria:
- <criteria>

Validation command:
- <command>

Learning check:
- Which learned rule should be used?
- Which failure should not recur?
```

## Outputs

- Updated eval run history (date, eval, model, pass/fail, notes) — append to `.agent-os/evals.md` or a linked results log.
- New/updated entries in `.agent-os/failure-log.md` for failures found.
- A escalation note to `improve-instructions` for repeated failures or systemic gaps.

## Forbidden

- Marking an eval "pass" when a forbidden behavior occurred, even if the end result looked correct.
- Skipping the Learning check questions.
- Simulating or shortcutting the task instead of running the project's real commands.
- Hiding a failing eval or omitting it from the summary.
- Running a validation command with `--exec` that is not listed verbatim in `.agent-os/command-map.md`, or forcing execution of a "Manual review" style command — `run-agent-evals.sh` refuses both by design.

## Done criteria

- Every run eval has a recorded pass/fail and answered Learning check.
- Failures are logged in `failure-log.md`, not just noted verbally.
- Repeated failures were escalated to `improve-instructions`, not silently re-attempted.
- The summary honestly reflects untested perspectives, if any remain.
