---
name: project-profile
description: Create or update .agent-os/project-profile.md, keeping observed facts and open hypotheses strictly separate.
---

## Purpose

Maintain `.agent-os/project-profile.md` as the single, trustworthy description of a project: what it is, how it is verifiably built and tested, and what remains uncertain. This file is read before most other work, so it must stay short, accurate, and honest about its own confidence level.

## When to use

- Right after `project-bootstrap` produces its raw observations.
- After a major structural change (new build system, new test framework, directory reorganization, framework migration).
- Whenever a recorded fact turns out to be wrong (e.g. a command in `command-map.md` no longer runs, a described architecture boundary was removed).
- Not for routine, small changes — this file should not need edits after every commit.

## Inputs

- Output of `project-bootstrap` (or the existing `project-profile.md` being updated).
- `.agent-os/command-map.md`, `.agent-os/risk-map.md`, `.agent-os/architecture-map.md` if present.
- Any new evidence that confirms or contradicts an existing entry (a failed command, a corrected assumption, a user statement).

## Procedure

1. Open the existing `project-profile.md` if present; otherwise start from the bootstrap observations.
2. Fill or update these sections:
   - **Overview** — one paragraph: what the project is, primary language/framework.
   - **Verified facts** — stack, entry points, how to run/build/test, each with an evidence source (file + key/line).
   - **Directory map** — short, high-signal structure (not a full tree).
   - **Architecture notes** — key boundaries and patterns actually observed in code.
   - **Risk areas** — pointer to `risk-map.md`, not a duplicate of it.
   - **Open hypotheses** — anything inferred but not directly verified, explicitly labeled "unverified."
3. When a hypothesis becomes verified (e.g. it was tested and confirmed, or corroborated by a second independent source), move it from "Open hypotheses" into "Verified facts" with its new evidence.
4. When a "verified fact" is proven wrong, remove or correct it immediately — do not leave contradictory statements in the file.
5. Keep the hypothesis section clean: prune stale hypotheses that were never confirmed and are no longer relevant instead of letting them accumulate indefinitely.
6. Keep the whole file scannable — prefer short bullet lists over prose. If a section grows into a long procedure, move the procedure into a skill and leave a pointer here instead.
7. Note the update in the file itself (e.g. a "last updated" line with reason) so future readers know why it changed.

## Outputs

- An up-to-date `.agent-os/project-profile.md` with facts and hypotheses clearly separated.

## Forbidden

- Blending unverified hypotheses into the facts section.
- Recording a single unconfirmed guess as a "verified fact."
- Letting the file grow into a full procedure manual — procedures belong in `skills/`.
- Silently dropping a fact that is now false without noting why (future readers need the correction, not just its absence).

## Done criteria

- Every entry under "Verified facts" cites evidence.
- Every entry under "Open hypotheses" is labeled as unverified.
- No contradictions between this file and the current state of the repository.
- The file is short enough to read in under a minute.
