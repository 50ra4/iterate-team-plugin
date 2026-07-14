---
name: improve-instructions
description: Periodic maintenance pass over learned-rules, failure-log, and eval results — merge, deprecate, extract skills, and propose changes as diffs requiring approval.
---

## Purpose

Keep the accumulated knowledge in `.agent-os/` coherent as it grows. Rules and files that were fine individually can conflict, duplicate, or rot over time; this skill is the housekeeping pass that catches that before it degrades agent behavior.

## When to use

- On a schedule (e.g. periodically, or after a batch of `run-agent-evals` results).
- When `AGENTS.md`/`CLAUDE.md` have grown noticeably long.
- When the same kind of failure keeps recurring despite an existing rule (escalation target from `run-agent-evals`).
- Not for acting on a single new piece of feedback — that is `learn-from-feedback`'s job.

## Inputs

- `.agent-os/learned-rules.md`
- `.agent-os/rules/*.md`, if `.agent-os/rules/` exists (where the split-out active rules live; equally binding)
- `.agent-os/failure-log.md`
- `.agent-os/review-feedback-log.md`
- `.agent-os/evals.md` and recent eval run results
- `AGENTS.md` / `CLAUDE.md` (root and per-directory)
- `scripts/detect-rule-conflicts.sh`, `scripts/split-learned-rules.sh` if present in the Global OS

## Procedure

1. Read all of `learned-rules.md`, `failure-log.md`, and recent eval results — and, if `.agent-os/rules/` exists, all of `.agent-os/rules/*.md` too, where the split-out active rules live.
2. Merge duplicate rules: same substance, different wording — keep the clearer wording, keep the stronger evidence trail, note the merge.
3. Detect conflicting rules — rules whose instructions contradict each other on the same scope. Run `scripts/detect-rule-conflicts.sh` if it exists; otherwise do this by manual comparison of `Applies to` and `Rule` fields.
4. Deprecate stale rules: set `Status: deprecated` (never delete outright) for rules whose `Applies to` no longer exists, or that are superseded by a merged/newer rule. Keep the rationale for why it was deprecated.
5. If `AGENTS.md`/`CLAUDE.md` contain long, step-by-step procedures, extract them into a new or existing skill under `skills/`, leaving a short pointer in the always-loaded file.
6. If `failure-log.md` or feedback logs show the same *task shape* recurring (not just the same fix), propose turning that recurring task into a dedicated skill.
7. For areas with a cluster of failures, propose new entries for `.agent-os/evals.md` using the standard Eval format so future regressions are caught automatically.
8. If `learned-rules.md` has grown past roughly 10 active rules or 300 lines, propose splitting it: run `scripts/split-learned-rules.sh --adapter <dir> --dry-run` to show the move plan (active rules move into `.agent-os/rules/<scope>.md` by their `Scope:` field; candidates and deprecated rules stay in `learned-rules.md`). This skill is proposal-based, so present the dry-run plan as part of the diff and only run it for real (without `--dry-run`) after approval. Note that `detect-rule-conflicts.sh`, `summarize-learning-log.sh`, and `validate-agent-os.sh` all support both the single-file and split layouts, so splitting is optional and never required for those scripts to keep working.
9. Present every proposed change as a diff (before/after) with a one-line reason per change — never apply merges, deprecations, or deletions silently.
10. Group the proposal into: rules merged, rules deprecated, procedures extracted into skills, evals to add, learned-rules.md split (if proposed), and anything ambiguous that needs the user's explicit confirmation.
11. Wait for approval before applying anything destructive (deleting a rule file section, removing an eval, renaming a skill others may reference) or the learned-rules.md split. Non-destructive additions (new eval, new skill file) can proceed once reasoning is presented, unless the project's own rules require more caution.

## Outputs

A report with these sections:
- **Update candidates** — what could change and why.
- **Reasons** — the evidence behind each candidate (which failures/feedback/evals triggered it).
- **Impact** — what breaks or changes in agent behavior if applied.
- **Merged/removed rules** — before/after diff, with deprecation rationale for anything removed from active use.
- **Evals to add** — new `.agent-os/evals.md` entries in the standard Eval format.
- **learned-rules.md split** — the `split-learned-rules.sh --dry-run` plan, if proposed, and confirmation once run for real.
- **Needs manual confirmation** — anything ambiguous, conflicting, or destructive that the user must decide on.

## Forbidden

- Applying destructive changes (deleting rules outright, removing evals, rewriting `learned-rules.md` history) without explicit approval.
- Resolving a genuine rule conflict by silently picking one side.
- Deprecating a rule just because it is inconvenient, without evidence it is stale or superseded.
- Letting proposed changes bypass the diff-and-approval step "to save time."

## Done criteria

- Every proposed change is presented as an explicit diff with a reason.
- No destructive change was applied without approval.
- Conflicting rules are either resolved with the user or clearly flagged, never silently merged.
- `AGENTS.md`/`CLAUDE.md` trend shorter over time as procedures move into skills.
