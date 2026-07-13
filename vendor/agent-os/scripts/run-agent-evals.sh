#!/usr/bin/env bash
# run-agent-evals.sh
#
# Semi-automated eval runner for a project's .agent-os/evals.md. The AGENT
# still performs each eval's Task; this script automates enumeration,
# validation-command handling (with a safety gate against command-map.md),
# and recording pass/fail results into the Results table.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_OS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  run-agent-evals.sh --adapter <dir> --list
  run-agent-evals.sh --adapter <dir> --show <eval-name>
  run-agent-evals.sh --adapter <dir> --check <eval-name> [--exec]
  run-agent-evals.sh --adapter <dir> --record <eval-name> --result pass|fail --model <model-name> [--notes <text>]

<dir> must contain .agent-os/evals.md.

Modes (exactly one required):
  --list                 List all "## Eval: <name>" blocks: name, first
                          Task bullet, and most recent recorded result.
  --show <name>          Print the full eval block verbatim.
  --check <name>         Extract and display the Validation command(s).
                          Add --exec to actually run them, gated by
                          .agent-os/command-map.md (a command is only run
                          if it appears, after normalization, in the
                          command map). Recognized command-map formats:
                          a backtick span anywhere in the file (e.g.
                          `npm test`), or the first cell of a markdown
                          table data row (header/separator rows are
                          skipped). Normalization strips exactly one
                          layer of surrounding backticks (and
                          surrounding whitespace) from both the eval's
                          Validation command and each command-map
                          candidate before comparing, so `npm test` and
                          npm test are treated as the same command; the
                          normalized (backtick-free) string is what
                          actually gets executed. A Validation command
                          is treated as a manual placeholder -- reported
                          MANUAL, never gated or run -- only if, after
                          normalization, it case-insensitively equals
                          "manual" or "manual review", or starts with
                          "manual " or "manual:"; a command that merely
                          contains the word "manual" elsewhere (e.g.
                          manual_regression_suite.sh --check) is not a
                          placeholder and is gated/run normally.
                          Executed commands run with the adapter root
                          (--adapter <dir>, resolved to an absolute path)
                          as their working directory, not the caller's cwd.
  --record <name>        Append a result row to the "## Results" table.
                          Requires --result pass|fail and --model <name>;
                          --notes <text> is optional.

Options:
  --adapter <dir>   Directory containing .agent-os/evals.md (required).
  --exec            With --check, execute allow-listed validation commands.
  --result <v>      With --record, "pass" or "fail".
  --model <name>    With --record, the model/agent name used for the run.
  --notes <text>    With --record, free-text notes (pipes/newlines stripped).
  --help            Show this help text and exit.

Exit codes:
  0   success (list/show/record done; check with no failures)
  1   --check --exec found a failing or refused validation command, or
      --record refused because .agent-os is a symlink, .agent-os
      escapes --adapter <dir>, or evals.md is a symlink
  2   usage error (bad flags, unknown eval name, missing files)
EOF
}

# ---- Argument parsing -----------------------------------------------------
ADAPTER_DIR=""
MODE=""
MODE_ARG=""
MODE_COUNT=0
EXEC_FLAG=0
RESULT_VAL=""
MODEL_VAL=""
NOTES_VAL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --adapter)
      [[ $# -ge 2 ]] || { echo "ERROR: --adapter requires a value" >&2; exit 2; }
      ADAPTER_DIR="$2"
      shift 2
      ;;
    --list)
      MODE="list"
      MODE_COUNT=$((MODE_COUNT + 1))
      shift
      ;;
    --show)
      [[ $# -ge 2 ]] || { echo "ERROR: --show requires an eval name" >&2; exit 2; }
      MODE="show"
      MODE_ARG="$2"
      MODE_COUNT=$((MODE_COUNT + 1))
      shift 2
      ;;
    --check)
      [[ $# -ge 2 ]] || { echo "ERROR: --check requires an eval name" >&2; exit 2; }
      MODE="check"
      MODE_ARG="$2"
      MODE_COUNT=$((MODE_COUNT + 1))
      shift 2
      ;;
    --record)
      [[ $# -ge 2 ]] || { echo "ERROR: --record requires an eval name" >&2; exit 2; }
      MODE="record"
      MODE_ARG="$2"
      MODE_COUNT=$((MODE_COUNT + 1))
      shift 2
      ;;
    --exec)
      EXEC_FLAG=1
      shift
      ;;
    --result)
      [[ $# -ge 2 ]] || { echo "ERROR: --result requires a value" >&2; exit 2; }
      RESULT_VAL="$2"
      shift 2
      ;;
    --model)
      [[ $# -ge 2 ]] || { echo "ERROR: --model requires a value" >&2; exit 2; }
      MODEL_VAL="$2"
      shift 2
      ;;
    --notes)
      [[ $# -ge 2 ]] || { echo "ERROR: --notes requires a value" >&2; exit 2; }
      NOTES_VAL="$2"
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$ADAPTER_DIR" ]]; then
  echo "ERROR: --adapter <dir> is required" >&2
  usage >&2
  exit 2
fi

if [[ "$MODE_COUNT" -eq 0 ]]; then
  echo "ERROR: one of --list, --show, --check, --record is required" >&2
  usage >&2
  exit 2
fi

if [[ "$MODE_COUNT" -gt 1 ]]; then
  echo "ERROR: --list/--show/--check/--record are mutually exclusive" >&2
  usage >&2
  exit 2
fi

if [[ "$EXEC_FLAG" -eq 1 && "$MODE" != "check" ]]; then
  echo "ERROR: --exec is only valid with --check" >&2
  exit 2
fi

if [[ -n "$RESULT_VAL" || -n "$MODEL_VAL" || -n "$NOTES_VAL" ]] && [[ "$MODE" != "record" ]]; then
  echo "ERROR: --result/--model/--notes are only valid with --record" >&2
  exit 2
fi

EVALS_FILE="$ADAPTER_DIR/.agent-os/evals.md"
COMMAND_MAP_FILE="$ADAPTER_DIR/.agent-os/command-map.md"

if [[ ! -f "$EVALS_FILE" ]]; then
  echo "ERROR: evals.md not found: $EVALS_FILE" >&2
  exit 2
fi

# Absolute adapter root. evals.md was just confirmed to exist under
# "$ADAPTER_DIR/.agent-os", so ADAPTER_DIR itself is known to exist here.
# Validation commands (--check --exec) are run from this directory, not
# the caller's cwd, since they are documented as project-relative (e.g.
# `npm test` run against the adapter's own workspace).
ADAPTER_DIR_ABS="$(cd "$ADAPTER_DIR" && pwd)"

# ---- Shared helpers ---------------------------------------------------

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# Strip exactly one layer of backticks fully surrounding a string, if
# present (i.e. "`npm test`" -> "npm test"; "npm test" is left as-is).
# Does not touch backticks that are not both a leading and a trailing
# character of the whole string.
strip_backtick_wrap() {
  local s="$1"
  if [[ "${#s}" -ge 2 && "${s:0:1}" == '`' && "${s: -1}" == '`' ]]; then
    s="${s:1:${#s}-2}"
  fi
  printf '%s' "$s"
}

# Normalize a command string for gate comparison and execution: trim
# whitespace, strip one layer of surrounding backticks, then trim again
# (covers "` npm test `" style spacing inside the backticks). Applied
# uniformly to both command-map candidates and eval Validation commands
# so a command written `npm test` in one place and npm test (no
# backticks) in the other still compare equal -- and so the string that
# is actually executed is always backtick-free (never handed to `bash
# -c` with literal backticks, which would trigger command substitution).
normalize_cmd() {
  local s
  s="$(trim "$1")"
  s="$(strip_backtick_wrap "$s")"
  s="$(trim "$s")"
  printf '%s' "$s"
}

# Extract candidate command strings from a (comment-stripped)
# command-map.md. Two sources, both emitted one candidate per line:
#   (a) every backtick-delimited span, anywhere in the file (how
#       commands are quoted in the documented command-map table, e.g.
#       `npm test -- --grep widgets`, and also how they may appear
#       inline in prose)
#   (b) the first cell of every real markdown table data row (a line
#       starting with "|"): header rows (first cell "Command", any
#       case) and separator rows (first cell made up only of "-", ":",
#       and whitespace) are skipped
# A bare prose/bullet line (not a backtick span, not a table row) is
# deliberately NOT a candidate on its own -- e.g. a line under a
# "do not run" heading must not become an approved command just because
# it was comment-stripped and trimmed of a leading "-". Candidates are
# normalized (normalize_cmd) by the caller before comparing; the
# Validation command must match one of them EXACTLY after normalization
# -- a containment/substring match is not enough, since a shorter
# command being a substring of a longer verified one does not mean the
# shorter command itself was ever verified.
command_map_candidates() {
  local content="$1"
  grep -oE '`[^`]+`' <<<"$content" 2>/dev/null | sed -E 's/^`//; s/`$//'
  awk -F'|' '
    /^[[:space:]]*\|/ {
      cell = $2
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", cell)
      if (cell == "") next
      if (cell ~ /^[-: ]+$/) next
      if (tolower(cell) == "command") next
      print cell
    }
  ' <<<"$content"
}

strip_html_comments() {
  # Remove HTML comment blocks (<!-- ... -->, possibly multi-line) before
  # parsing, so the commented-out "Example (delete me)" eval in the
  # template is never treated as a real eval. Also strips a trailing \r
  # from every line first, so a CRLF-converted evals.md still parses
  # correctly (exact-match comparisons like heading names would
  # otherwise silently carry a trailing \r and never match).
  local file="$1"
  awk '
    {
      sub(/\r$/, "")
      # Span-aware HTML comment strip: iteratively remove "<!-- ... -->"
      # spans from the line so a same-line open+close (e.g. "<!-- note
      # --> ## Eval: second") does not swallow trailing real content the
      # way a simple line-based in_comment toggle would. Text before an
      # unclosed "<!--" is kept and in_comment carries into the next
      # line; while in_comment, text up to a closing "-->" is dropped and
      # the remainder of the line is processed normally.
      line = $0; out = ""; trimmed = 0
      while (length(line) > 0) {
        if (in_comment) {
          p = index(line, "-->")
          if (p == 0) {
            line = ""
          } else {
            line = substr(line, p + 3)
            in_comment = 0
            if (out == "") trimmed = 1
          }
        } else {
          p = index(line, "<!--")
          if (p == 0) {
            out = out line
            line = ""
          } else {
            out = out substr(line, 1, p - 1)
            line = substr(line, p + 4)
            in_comment = 1
          }
        }
      }
      # A comment that prefixed a heading/field on this line can leave
      # leading whitespace in `out`; strip it (only when actually
      # introduced by a stripped leading comment span, so genuinely
      # indented content elsewhere is untouched) so the "^## Eval:"
      # anchor downstream still matches.
      if (trimmed) sub(/^[ \t]+/, "", out)
      print out
    }
  ' "$file"
}

# List all eval names, in file order. The inner grep is wrapped with
# "|| true" so an evals.md with zero evals (grep exit 1) does not trip
# "set -o pipefail" and abort the script.
list_eval_names() {
  strip_html_comments "$EVALS_FILE" | { grep -E '^## Eval:' || true; } | \
    sed -E 's/^## Eval:[ \t]*//; s/[ \t]+$//'
}

eval_exists() {
  local target="$1"
  list_eval_names | grep -qxF "$target"
}

die_unknown_eval() {
  local target="$1"
  echo "ERROR: no such eval: $target" >&2
  echo "Available evals:" >&2
  list_eval_names | sed 's/^/  - /' >&2
  exit 2
}

# Count how many "## Eval: <name>" headings share the given exact name.
count_eval_name() {
  local target="$1"
  list_eval_names | grep -cxF "$target" || true
}

# Fail loudly if the eval name is ambiguous (two or more "## Eval:"
# headings share it). get_eval_block re-enters capture on every matching
# heading, so a duplicate name would otherwise silently concatenate both
# blocks together for --show/--check, and --exec would run both blocks'
# validation commands. Align in spirit with detect-rule-conflicts.sh's
# "DUPLICATE RULE NAME" finding: name the duplicate and refuse.
require_unique_eval() {
  local target="$1"
  local count
  count="$(count_eval_name "$target")"
  if [[ "$count" -gt 1 ]]; then
    echo "ERROR: duplicate eval name \"$target\" -- $count \"## Eval:\" blocks in $EVALS_FILE share this exact name; rename one of them before using --show/--check/--record on it" >&2
    exit 1
  fi
}

# Print the full "## Eval: <name>" block verbatim (up to but excluding the
# next top-level "## " heading, e.g. the next eval or "## Results").
get_eval_block() {
  local target="$1"
  strip_html_comments "$EVALS_FILE" | awk -v target="$target" '
    BEGIN { capturing = 0 }
    /^## Eval:/ {
      name = $0
      sub(/^## Eval:[ \t]*/, "", name)
      gsub(/[ \t]+$/, "", name)
      if (name == target) { capturing = 1; print; next }
      capturing = 0
      next
    }
    /^## / { capturing = 0; next }
    capturing { print }
  '
}

# First bullet under the "Task:" section of an eval block (read on stdin).
get_task_first_bullet() {
  awk '
    /^Task:/ { infield = 1; next }
    infield && /^-/ {
      line = $0
      sub(/^-[ \t]*/, "", line)
      print line
      exit
    }
    infield && /^[[:space:]]*$/ { next }
    infield { exit }
  '
}

# Validation command bullet(s) under the "Validation command:" section of
# an eval block (read on stdin).
get_validation_commands() {
  awk '
    /^Validation command:/ { infield = 1; next }
    infield && /^-/ {
      line = $0
      sub(/^-[ \t]*/, "", line)
      print line
      next
    }
    infield && /^[[:space:]]*$/ { infield = 0; next }
    infield { infield = 0 }
  '
}

# Most recent recorded result for an eval, from the "## Results" table.
# Prints "date\tresult\tmodel" or nothing if never run.
get_latest_result() {
  local target="$1"
  strip_html_comments "$EVALS_FILE" | awk -v target="$target" -F'|' '
    /^## Results/ { in_results = 1; next }
    in_results && /^\|/ {
      date = $2; gsub(/^[ \t]+|[ \t]+$/, "", date)
      ev = $3; gsub(/^[ \t]+|[ \t]+$/, "", ev)
      model = $4; gsub(/^[ \t]+|[ \t]+$/, "", model)
      result = $5; gsub(/^[ \t]+|[ \t]+$/, "", result)
      if (date == "Date" || date ~ /^-+$/) next
      if (ev == target) { last_date = date; last_result = result; last_model = model }
    }
    END {
      if (last_date != "") print last_date "\t" last_result "\t" last_model
    }
  '
}

# ---- Mode: --list -----------------------------------------------------
run_list() {
  local names
  mapfile -t names < <(list_eval_names)
  echo "===== run-agent-evals: $EVALS_FILE ====="
  echo
  if [[ "${#names[@]}" -eq 0 ]]; then
    echo "(no evals defined)"
    echo
    echo "Total evals: 0"
    exit 0
  fi
  # Count occurrences of each name up front: a name shared by 2+ "## Eval:"
  # headings is ambiguous for --show/--check/--record (see
  # require_unique_eval), so flag it here rather than silently showing
  # merged/wrong per-block details.
  declare -A name_count=()
  local n
  for n in "${names[@]}"; do
    name_count["$n"]=$(( ${name_count["$n"]:-0} + 1 ))
  done

  local block task latest date result model dup_note
  for n in "${names[@]}"; do
    block="$(get_eval_block "$n")"
    task="$(echo "$block" | get_task_first_bullet)"
    [[ -z "$task" ]] && task="(no Task bullet found)"
    latest="$(get_latest_result "$n")"
    dup_note=""
    [[ "${name_count[$n]}" -gt 1 ]] && dup_note=" [DUPLICATE NAME]"
    if [[ -z "$latest" ]]; then
      echo "- $n$dup_note"
      echo "    Task: $task"
      echo "    Last result: never run"
    else
      IFS=$'\t' read -r date result model <<<"$latest"
      echo "- $n$dup_note"
      echo "    Task: $task"
      echo "    Last result: $result ($date, $model)"
    fi
  done
  echo
  echo "Total evals: ${#names[@]}"
  exit 0
}

# ---- Mode: --show -------------------------------------------------------
run_show() {
  local target="$1"
  eval_exists "$target" || die_unknown_eval "$target"
  require_unique_eval "$target"
  get_eval_block "$target"
  exit 0
}

# ---- Mode: --check ------------------------------------------------------
run_check() {
  local target="$1"
  eval_exists "$target" || die_unknown_eval "$target"
  require_unique_eval "$target"

  local block
  block="$(get_eval_block "$target")"

  local commands
  mapfile -t commands < <(echo "$block" | get_validation_commands)

  if [[ "${#commands[@]}" -eq 0 ]]; then
    echo "No Validation command found for eval: $target"
    exit 0
  fi

  echo "===== validation command(s) for: $target ====="

  if [[ "$EXEC_FLAG" -eq 0 ]]; then
    local c
    for c in "${commands[@]}"; do
      echo "  - $c"
    done
    echo
    echo "Not executed (pass --exec to run allow-listed commands). Run manually and record the result."
    exit 0
  fi

  # --exec: gate each command against command-map.md before running.
  # The gate is an EXACT match (after normalize_cmd on both sides) against
  # candidate command strings extracted from command-map.md, not a
  # substring/containment check -- a command that merely happens to be a
  # substring of a longer verified command (e.g. "npm test" vs. a mapped
  # "npm test -- --grep widgets") was never itself verified and must not
  # be allowed to run.
  local overall_fail=0
  local stripped_map=""
  local map_candidates=""
  if [[ -f "$COMMAND_MAP_FILE" ]]; then
    stripped_map="$(strip_html_comments "$COMMAND_MAP_FILE")"
    map_candidates="$(command_map_candidates "$stripped_map")"
  fi

  # Normalize every extracted candidate once, up front, so the per-command
  # comparison below is a plain exact-line match against already-
  # normalized candidates.
  local normalized_candidates="" cand
  if [[ -n "$map_candidates" ]]; then
    while IFS= read -r cand; do
      [[ -z "$cand" ]] && continue
      normalized_candidates+="$(normalize_cmd "$cand")"$'\n'
    done <<<"$map_candidates"
  fi

  local c c_norm lower
  for c in "${commands[@]}"; do
    c_norm="$(normalize_cmd "$c")"
    lower="$(echo "$c_norm" | tr '[:upper:]' '[:lower:]')"

    # Manual-placeholder gate: word-anchored on the normalized, trimmed
    # command, not a substring test -- a command merely containing the
    # word "manual" (e.g. manual_regression_suite.sh --check) is a real,
    # approved command, not a placeholder for a human-performed check.
    if [[ "$lower" == "manual" || "$lower" == "manual review" || "$lower" == "manual "* || "$lower" == "manual:"* ]]; then
      echo "MANUAL: $c"
      continue
    fi

    if [[ -z "$stripped_map" ]] || ! grep -qxF -- "$c_norm" <<<"$normalized_candidates"; then
      echo "REFUSED: command does not appear exactly in .agent-os/command-map.md -- run manually after verifying"
      echo "  command: $c"
      overall_fail=1
      continue
    fi

    echo "RUN (in $ADAPTER_DIR_ABS): $c"
    if (cd "$ADAPTER_DIR_ABS" && bash -c "$c_norm"); then
      echo "PASS: $c"
    else
      local rc=$?
      echo "FAIL (exit $rc): $c"
      overall_fail=1
    fi
  done

  if [[ "$overall_fail" -ne 0 ]]; then
    exit 1
  fi
  exit 0
}

# ---- Mode: --record -------------------------------------------------------
run_record() {
  local target="$1"
  eval_exists "$target" || die_unknown_eval "$target"
  require_unique_eval "$target"

  # Symlink safety: --record rewrites evals.md in place (via a temp file
  # + mv). Shared-style guard (same principle as bootstrap-project.sh
  # and split-learned-rules.sh): operate on a path only if no existing
  # component of it is a symlink and its physical resolution (pwd -P)
  # stays inside the adapter root; otherwise refuse explicitly without
  # acting. Check .agent-os itself first (this is the layer that was
  # previously missing -- only evals.md itself was checked), then
  # evals.md specifically.
  if [[ ! -d "$ADAPTER_DIR" ]]; then
    echo "ERROR: --adapter directory does not exist: $ADAPTER_DIR" >&2
    exit 2
  fi
  local adapter_phys ao_dir
  adapter_phys="$(cd "$ADAPTER_DIR" && pwd -P)"
  ao_dir="$ADAPTER_DIR/.agent-os"
  if [[ -L "$ao_dir" ]]; then
    echo "ERROR: refusing to record into $ao_dir: it is a symlink (remove it manually if you want a regular directory there)" >&2
    exit 1
  fi
  if [[ -e "$ao_dir" ]]; then
    local ao_phys
    ao_phys="$(cd "$ao_dir" && pwd -P)"
    if [[ "$ao_phys" != "$adapter_phys/.agent-os" ]]; then
      echo "ERROR: refusing to record into $ao_dir: it resolves to $ao_phys, outside $adapter_phys/.agent-os (a symlinked ancestor directory redirected it)" >&2
      exit 1
    fi
  fi

  # Refuse outright if evals.md is a symlink rather than writing a fresh
  # file over/through it.
  if [[ -L "$EVALS_FILE" ]]; then
    echo "ERROR: refusing to record into $EVALS_FILE: it is a symlink (remove it manually if you want a regular file there)" >&2
    exit 1
  fi

  if [[ "$RESULT_VAL" != "pass" && "$RESULT_VAL" != "fail" ]]; then
    echo "ERROR: --result must be 'pass' or 'fail' (got: '$RESULT_VAL')" >&2
    exit 2
  fi

  if [[ -z "$MODEL_VAL" ]]; then
    echo "ERROR: --model <model-name> is required with --record" >&2
    exit 2
  fi

  # Sanitize notes: strip pipes and newlines so the markdown table stays
  # well-formed.
  local notes="$NOTES_VAL"
  notes="${notes//$'\n'/ }"
  notes="${notes//$'\r'/ }"
  notes="${notes//|/}"

  local today
  today="$(date +%F)"
  local new_row="| $today | $target | $MODEL_VAL | $RESULT_VAL | $notes |"

  # tmp_file is created alongside EVALS_FILE, i.e. inside ao_dir, which
  # the guard above already verified is not a symlink and physically
  # resolves inside --adapter <dir>.
  local tmp_file
  tmp_file="$(mktemp "${EVALS_FILE}.XXXXXX")"

  awk -v newrow="$new_row" '
    # Strip a trailing \r so a CRLF-converted evals.md still matches the
    # exact-line comparisons below ("## Results" heading, the "|---|"
    # separator row anchored at end-of-line); the rewritten file is
    # written back out without it.
    { line = $0; sub(/\r$/, "", line); lines[NR] = line }
    END {
      n = NR
      results_line = 0
      for (i = 1; i <= n; i++) {
        if (lines[i] == "## Results") { results_line = i; break }
      }
      if (results_line == 0) {
        for (i = 1; i <= n; i++) print lines[i]
        print ""
        print "## Results"
        print ""
        print "| Date | Eval | Model | Pass/Fail | Notes |"
        print "|------|------|-------|-----------|-------|"
        print newrow
        exit
      }
      for (i = 1; i <= results_line; i++) print lines[i]
      i = results_line + 1
      while (i <= n && lines[i] ~ /^[[:space:]]*$/) { print lines[i]; i++ }
      header_line = 0
      if (i <= n && lines[i] ~ /^\|.*Date.*\|.*Eval.*\|/) header_line = i
      if (header_line > 0) {
        print lines[header_line]
        i++
        if (i <= n && lines[i] ~ /^\|[-| ]+\|$/) { print lines[i]; i++ }
        while (i <= n && lines[i] ~ /^\|/) { print lines[i]; i++ }
        print newrow
        while (i <= n) { print lines[i]; i++ }
      } else {
        print "| Date | Eval | Model | Pass/Fail | Notes |"
        print "|------|------|-------|-----------|-------|"
        print newrow
        while (i <= n) { print lines[i]; i++ }
      }
    }
  ' "$EVALS_FILE" > "$tmp_file"

  mv "$tmp_file" "$EVALS_FILE"

  echo "Recorded: $new_row"
  exit 0
}

case "$MODE" in
  list)
    run_list
    ;;
  show)
    run_show "$MODE_ARG"
    ;;
  check)
    run_check "$MODE_ARG"
    ;;
  record)
    run_record "$MODE_ARG"
    ;;
esac
