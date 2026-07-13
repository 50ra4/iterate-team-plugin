#!/usr/bin/env bash
# split-learned-rules.sh
#
# Move Status: active rule blocks out of a project's
# .agent-os/learned-rules.md into per-scope files under
# .agent-os/rules/<scope>.md (global|project|directory|file-pattern),
# based on each rule's Scope: field. learned-rules.md stays the
# entrypoint: promotion-criteria header + candidate/deprecated rules +
# an "## Active rules index" section pointing at the moved rules.
#
# A literal "## " line always ends the current markdown block/section
# for this script's heading-based parsing, even one quoted inside a
# rule's own body -- see usage() for how the existing-index merge stays
# minimally destructive around that edge case.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_OS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: split-learned-rules.sh --adapter <dir> [--dry-run]

Move Status: active rule blocks from <dir>/.agent-os/learned-rules.md
into per-scope files under <dir>/.agent-os/rules/<scope>.md, based on
each rule's Scope: field (global | project | directory | file-pattern).
learned-rules.md keeps its promotion-criteria header and candidate/
deprecated rules, and gains an "## Active rules index" section that
points at the moved rules.

Options:
  --adapter <dir>   Directory containing .agent-os/learned-rules.md.
  --dry-run         Print the move plan; make no changes.
  --help            Show this help text and exit.

Rules with a missing or unrecognized Scope: are left in place (WARN).
A rule already present in its target file is left in place (WARN) --
it is never appended twice. This script never deletes rule content;
it only moves verbatim blocks. Safe to rerun: once a rule has been
moved, later runs find no active blocks left to move.

Existing "## Active rules index" handling: when learned-rules.md already
has an index section, only unambiguous index bookkeeping is ever removed
from it when merging in newly-moved entries -- the "## Active rules
index" heading line itself, blank lines, and lines matching the strict
"- <name> -> rules/<scope>.md" entry shape (scope one of the four
recognized scopes). Any other line found in that region (e.g. a
malformed pointer with an unrecognized scope, or rule content that ended
up there) is left in place untouched and is never merged into the
authoritative index. Note: a literal "## " line anywhere in the file --
including one quoted inside a rule's own Rule:/Rationale: body as an
example -- always ends the current block/section (plain markdown-style
heading detection has no way to tell a real heading from quoted text);
the content that follows such a line stays in learned-rules.md rather
than being lost, but the "## " line is heading syntax, not rule content.

Symlink safety: refuses to run (non-dry-run) if .agent-os itself is a
symlink or does not physically resolve inside --adapter <dir>, or if
learned-rules.md, the .agent-os/rules directory, or any rules/<scope>.md
file it is about to write into is a symlink, rather than writing through
it. A temp file used to rewrite learned-rules.md is always created
inside the same verified .agent-os directory.

Exit codes:
  0   completed (see summary line for counts; warnings do not fail)
  1   refused: .agent-os is a symlink or escapes --adapter <dir>, or a
      file/directory to be modified is a symlink
  2   usage error
EOF
}

ADAPTER_DIR=""
DRY_RUN=0

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
    --dry-run)
      DRY_RUN=1
      shift
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

AO_DIR="$ADAPTER_DIR/.agent-os"
RULES_FILE="$AO_DIR/learned-rules.md"
RULES_DIR="$AO_DIR/rules"

echo "===== split-learned-rules: $RULES_FILE ====="

if [[ ! -f "$RULES_FILE" ]]; then
  echo "WARN: learned-rules.md not found: $RULES_FILE"
  echo "RESULT: nothing to do"
  exit 0
fi

low() { tr '[:upper:]' '[:lower:]' <<<"$1"; }

# ---- Parse "## Rule:" blocks (comment-aware) into raw line ranges --------
# Strips HTML comment blocks (same line-based semantics as the other
# scripts) before recognizing headings, so the commented-out example
# rule in the template is never treated as a real block. Emits:
#   start<TAB>end<TAB>name<TAB>status<TAB>scope
# "end" is inclusive: the line just before the next "## " heading, or
# EOF. Trailing blank lines inside that range are trimmed later so the
# spacing left behind in the source file looks natural.
find_blocks() {
  awk '
    function flush(end_line) {
      print start "\t" end_line "\t" name "\t" status "\t" scope
    }
    BEGIN { in_comment = 0; in_block = 0 }
    {
      # Strip a trailing \r first, so a CRLF-converted learned-rules.md
      # still parses correctly (name/status/scope exact-match comparisons
      # below would otherwise carry a trailing \r and never match).
      sub(/\r$/, "")

      # Span-aware HTML comment strip, done inline (not a separate pipe)
      # so NR stays the real physical line number of the source file --
      # find_blocks reports start/end as raw line numbers used later to
      # sed -n a range out of the original file. Iteratively remove
      # "<!-- ... -->" spans from the line; this handles a same-line
      # open+close (e.g. "<!-- note --> ## Rule: Bravo") that a simple
      # line-based in_comment toggle would otherwise swallow whole, as
      # well as a comment opened on an earlier line and closed on this
      # one. Text before an unclosed "<!--" is kept and in_comment
      # carries into the next line; while in_comment, text up to a
      # closing "-->" is dropped and the remainder of the line (if any)
      # is processed normally.
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
      # A comment that prefixed content on this same line (or carried in
      # from an earlier line and closed here) can leave leading
      # whitespace in `out` (e.g. "<!-- x --> ## Rule: Y" strips to
      # " ## Rule: Y"); strip it so the heading/field regexes below,
      # anchored at line start, still match. Only done when a comment
      # was actually stripped from the leading edge of the line (the
      # `trimmed` flag), so genuinely indented content elsewhere is
      # never touched.
      if (trimmed) sub(/^[ \t]+/, "", out)

      if (out ~ /^## Rule:/) {
        if (in_block) flush(NR - 1)
        in_block = 1
        start = NR
        name = out
        sub(/^## Rule:[ \t]*/, "", name)
        gsub(/[ \t]+$/, "", name)
        status = ""; scope = ""
      } else if (in_block && out ~ /^## /) {
        flush(NR - 1)
        in_block = 0
      } else if (in_block) {
        if (out ~ /^Status:/) {
          status = out; sub(/^Status:[ \t]*/, "", status); gsub(/[ \t]+$/, "", status)
        } else if (out ~ /^Scope:/) {
          scope = out; sub(/^Scope:[ \t]*/, "", scope); gsub(/[ \t]+$/, "", scope)
        }
      }
    }
    END { if (in_block) flush(NR) }
  ' "$1"
}

target_has_rule() {
  # Case-insensitive lookup of a "## Rule: <name>" heading in a target
  # rules/<scope>.md file.
  local target="$1" name="$2" lname
  [[ -f "$target" ]] || return 1
  lname="$(low "$name")"
  grep -i '^## Rule:' "$target" 2>/dev/null \
    | sed -E 's/^## Rule:[ \t]*//; s/[ \t\r]+$//' \
    | tr '[:upper:]' '[:lower:]' \
    | grep -qxF "$lname"
}

mapfile -t LINES < "$RULES_FILE"
# Strip a trailing \r from every loaded line so a CRLF-converted
# learned-rules.md still works with the exact-string comparisons below
# (blank-line detection when trimming trailing blanks, "## Active rules
# index"/"## Active rules" heading matches, existing index-line
# matching) -- otherwise a line like "## Active rules index\r" would
# never equal the literal "## Active rules index".
for ((_li = 0; _li < ${#LINES[@]}; _li++)); do
  LINES[$_li]="${LINES[$_li]%$'\r'}"
done
TOTAL_LINES=${#LINES[@]}

declare -a B_START=() B_END=() B_NAME=() B_STATUS=() B_SCOPE=()
while IFS=$'\t' read -r s e n st sc; do
  [[ -z "$s" ]] && continue
  B_START+=("$s"); B_END+=("$e"); B_NAME+=("$n"); B_STATUS+=("$st"); B_SCOPE+=("$sc")
done < <(find_blocks "$RULES_FILE")
NUM_BLOCKS=${#B_START[@]}

echo
echo "Total rule blocks found: $NUM_BLOCKS"

# ---- Classify each block ---------------------------------------------
declare -a ACTION=() TARGET=() MSG=()
declare -A SEEN_IN_TARGET=()
MOVED=0
SKIPPED=0
WARNCOUNT=0

for ((i = 0; i < NUM_BLOCKS; i++)); do
  status_lower="$(low "${B_STATUS[$i]}")"
  if [[ "$status_lower" != "active" ]]; then
    ACTION[$i]="KEEP"
    continue
  fi

  name="${B_NAME[$i]}"
  scope="${B_SCOPE[$i]}"
  scope_lower="$(low "$scope")"

  valid=0
  case "$scope_lower" in
    global|project|directory|file-pattern) valid=1 ;;
  esac

  if [[ "$valid" -eq 0 ]]; then
    ACTION[$i]="SKIP_SCOPE"
    MSG[$i]="WARN: \"$name\" has unknown/missing Scope (\"$scope\") -- left in place"
    SKIPPED=$((SKIPPED + 1))
    WARNCOUNT=$((WARNCOUNT + 1))
    continue
  fi

  target="$RULES_DIR/$scope_lower.md"
  lname="$(low "$name")"
  key="$scope_lower|$lname"

  dup=0
  [[ -n "${SEEN_IN_TARGET[$key]:-}" ]] && dup=1
  if [[ "$dup" -eq 0 ]] && target_has_rule "$target" "$name"; then
    dup=1
  fi

  if [[ "$dup" -eq 1 ]]; then
    ACTION[$i]="SKIP_DUP"
    MSG[$i]="WARN: \"$name\" already present in rules/$scope_lower.md -- left in place (bodies are not compared; run detect-rule-conflicts.sh to check for a duplicate-name conflict)"
    SKIPPED=$((SKIPPED + 1))
    WARNCOUNT=$((WARNCOUNT + 1))
    continue
  fi

  SEEN_IN_TARGET[$key]=1
  ACTION[$i]="MOVE"
  TARGET[$i]="$target"
  MSG[$i]="MOVE: \"$name\" (Scope: $scope) -> rules/$scope_lower.md"
  MOVED=$((MOVED + 1))
done

# ---- Print the plan ----------------------------------------------------
echo
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "--- Move plan (dry run; no files modified) ---"
else
  echo "--- Move plan ---"
fi
ANY=0
for ((i = 0; i < NUM_BLOCKS; i++)); do
  [[ "${ACTION[$i]}" == "KEEP" ]] && continue
  echo "${MSG[$i]}"
  ANY=1
done
[[ "$ANY" -eq 0 ]] && echo "(no active rule blocks to move)"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo
  echo "Summary (dry-run): would move $MOVED, skip $SKIPPED, warnings $WARNCOUNT"
  exit 0
fi

# ---- Symlink safety: refuse to write through a symlink -----------------
# Shared-style guard (same principle as bootstrap-project.sh): operate on
# a path only if (1) no existing component of it is a symlink, and (2)
# its physical resolution (pwd -P) stays inside the adapter root;
# otherwise refuse explicitly without acting. Checked in order from the
# outside in: .agent-os itself first (it did not exist as a check before
# this fix -- only the specific files under it did), then the specific
# files/directories about to be written below (rewritten in place /
# appended into).
if [[ ! -d "$ADAPTER_DIR" ]]; then
  echo "ERROR: --adapter directory does not exist: $ADAPTER_DIR" >&2
  exit 1
fi
ADAPTER_PHYS="$(cd "$ADAPTER_DIR" && pwd -P)"

if [[ -L "$AO_DIR" ]]; then
  echo "ERROR: refusing to modify $AO_DIR: it is a symlink (remove it manually if you want a regular directory there)" >&2
  exit 1
fi
if [[ -e "$AO_DIR" ]]; then
  AO_PHYS="$(cd "$AO_DIR" && pwd -P)"
  if [[ "$AO_PHYS" != "$ADAPTER_PHYS/.agent-os" ]]; then
    echo "ERROR: refusing to modify $AO_DIR: it resolves to $AO_PHYS, outside $ADAPTER_PHYS/.agent-os (a symlinked ancestor directory redirected it)" >&2
    exit 1
  fi
fi

if [[ -L "$RULES_FILE" ]]; then
  echo "ERROR: refusing to modify $RULES_FILE: it is a symlink (remove it manually if you want a regular file there)" >&2
  exit 1
fi
if [[ -e "$RULES_DIR" && -L "$RULES_DIR" ]]; then
  echo "ERROR: refusing to write into $RULES_DIR: it is a symlink (remove it manually if you want a regular directory there)" >&2
  exit 1
fi

# ---- Apply: append moved blocks to their target rules/*.md files -------
declare -a DEL_START=() DEL_END=()
declare -a NEW_INDEX_LINES=()
declare -a NEW_INDEX_NAMES=()

for ((i = 0; i < NUM_BLOCKS; i++)); do
  [[ "${ACTION[$i]}" != "MOVE" ]] && continue

  start=${B_START[$i]}
  end=${B_END[$i]}
  # Trim trailing blank lines so the source keeps natural spacing.
  trimmed_end=$end
  while [[ $trimmed_end -gt $start ]] && [[ -z "${LINES[$((trimmed_end - 1))]}" ]]; do
    trimmed_end=$((trimmed_end - 1))
  done

  target="${TARGET[$i]}"
  scope_lower="$(low "${B_SCOPE[$i]}")"

  if [[ -L "$target" ]]; then
    echo "ERROR: refusing to write into $target: it is a symlink (remove it manually if you want a regular file there)" >&2
    exit 1
  fi

  mkdir -p "$RULES_DIR"
  if [[ ! -f "$target" ]]; then
    {
      echo "<!-- Active rules for scope: $scope_lower. Populated by split-learned-rules.sh from learned-rules.md; entrypoint stays learned-rules.md. Every rule below has Status: active and is binding, exactly as if it were still in learned-rules.md. -->"
      echo
    } >"$target"
  else
    echo >>"$target"
  fi
  sed -n "${start},${trimmed_end}p" "$RULES_FILE" >>"$target"

  DEL_START+=("$start")
  DEL_END+=("$trimmed_end")
  NEW_INDEX_LINES+=("- ${B_NAME[$i]} → rules/${scope_lower}.md")
  NEW_INDEX_NAMES+=("${B_NAME[$i]}")
done

# ---- Locate an existing "## Active rules index" section, if any -------
# Detection stays simple: the first literal "## Active rules index" line
# in the file, extending to the next "## " heading (or EOF). A literal
# "## " line always ends the current markdown section for this script's
# heading-based parsing (find_blocks above works the same way) -- even
# one quoted inside a rule's own body -- so a rule that itself contains
# a line reading exactly "## Active rules index" will still be found
# here and will still end that rule's block early. That is a documented
# limitation of plain "## "-anchored parsing, not something this script
# tries to see through (see usage() and the header comment above).
#
# What IS handled carefully here: within the located region, only lines
# that are unambiguously index bookkeeping are ever deleted -- the
# heading line itself, blank lines, and lines matching the strict
# "- <name> -> rules/<scope>.md" entry shape (see match_index_line()).
# Any other line in the region (e.g. a bogus "- fake -> rules/nowhere.md"
# pointer, or a rule's own Rationale: text that falls in range only
# because of a stray "## " match) is left exactly where it is: never
# deleted, never harvested. This script never deletes rule content.
EXIST_INDEX_START=0
EXIST_INDEX_END=0
for ((li = 0; li < TOTAL_LINES; li++)); do
  if [[ "${LINES[$li]}" == "## Active rules index" ]]; then
    EXIST_INDEX_START=$((li + 1))
    break
  fi
done
if [[ "$EXIST_INDEX_START" -gt 0 ]]; then
  EXIST_INDEX_END=$TOTAL_LINES
  for ((ln = EXIST_INDEX_START + 1; ln <= TOTAL_LINES; ln++)); do
    if [[ "${LINES[$((ln - 1))]}" == "## "* ]]; then
      EXIST_INDEX_END=$((ln - 1))
      break
    fi
  done
fi

ARROW=$'\xe2\x86\x92'  # UTF-8 "→", matches the literal char used above

# Strict index-entry shape: "- <name> -> rules/<scope>.md" where <scope>
# is exactly one of the four recognized scopes, anchored at the end of
# the line. This is the ONLY shape ever treated as index bookkeeping --
# e.g. "- fake -> rules/nowhere.md" (an unrecognized scope) does not
# match, so it is neither harvested into the merged index nor deleted
# from the source; it stays in place as ordinary content. On a match,
# sets MATCH_NAME to the rule name, derived by stripping the strict
# trailing " -> rules/<scope>.md" suffix -- anchored at the end, not a
# greedy "everything before the first ' rules/'" glob -- so a rule name
# that itself contains the substring " rules/" (e.g. "fix rules/foo bug")
# is not mangled.
match_index_line() {
  local content="$1" scope suffix rest
  MATCH_NAME=""
  case "$content" in
    "- "*) ;;
    *) return 1 ;;
  esac
  rest="${content#- }"
  for scope in global project directory file-pattern; do
    suffix=" $ARROW rules/$scope.md"
    if [[ "$rest" == *"$suffix" ]]; then
      local candidate="${rest%$suffix}"
      if [[ -n "$candidate" ]]; then
        MATCH_NAME="$candidate"
        return 0
      fi
    fi
  done
  return 1
}

declare -a EXISTING_INDEX_LINES=()
declare -a EXISTING_INDEX_NAMES=()
declare -a EXIST_INDEX_DEL_LINES=()
if [[ "$EXIST_INDEX_START" -gt 0 ]]; then
  for ((ln = EXIST_INDEX_START; ln <= EXIST_INDEX_END; ln++)); do
    content="${LINES[$((ln - 1))]}"
    if [[ "$ln" -eq "$EXIST_INDEX_START" ]]; then
      # The heading line itself: always removed.
      EXIST_INDEX_DEL_LINES+=("$ln")
      continue
    fi
    if [[ -z "$content" ]]; then
      EXIST_INDEX_DEL_LINES+=("$ln")
      continue
    fi
    if match_index_line "$content"; then
      EXISTING_INDEX_LINES+=("$content")
      EXISTING_INDEX_NAMES+=("$MATCH_NAME")
      EXIST_INDEX_DEL_LINES+=("$ln")
    fi
    # Anything else: preserved in place, not deleted, not harvested.
  done
fi

# ---- Merge existing + new index lines, deduped by rule name -----------
declare -A INDEX_SEEN=()
declare -a ALL_INDEX_LINES=()
add_index_line() {
  local line="$1" name="$2" lname
  lname="$(low "$name")"
  [[ -n "${INDEX_SEEN[$lname]:-}" ]] && return
  INDEX_SEEN[$lname]=1
  ALL_INDEX_LINES+=("$line")
}
for idx in "${!EXISTING_INDEX_LINES[@]}"; do
  add_index_line "${EXISTING_INDEX_LINES[$idx]}" "${EXISTING_INDEX_NAMES[$idx]}"
done
for idx in "${!NEW_INDEX_LINES[@]}"; do
  add_index_line "${NEW_INDEX_LINES[$idx]}" "${NEW_INDEX_NAMES[$idx]}"
done

# ---- Find insertion point: right after "## Active rules" heading ------
INSERT_LINE=0
for ((li = 0; li < TOTAL_LINES; li++)); do
  if [[ "${LINES[$li]}" == "## Active rules" ]]; then
    INSERT_LINE=$((li + 1))
    break
  fi
done

# ---- Mark lines to delete: moved rule blocks + old index section ------
declare -a DEL=()
for ((li = 0; li < TOTAL_LINES; li++)); do DEL[$li]=0; done
for idx in "${!DEL_START[@]}"; do
  s=${DEL_START[$idx]}; e=${DEL_END[$idx]}
  for ((ln = s; ln <= e; ln++)); do DEL[$((ln - 1))]=1; done
done
for ln in "${EXIST_INDEX_DEL_LINES[@]:-}"; do
  [[ -z "$ln" ]] && continue
  DEL[$((ln - 1))]=1
done

# ---- Rewrite learned-rules.md ------------------------------------------
# The temp file is created alongside RULES_FILE, i.e. inside AO_DIR,
# which the guard above already verified is not a symlink and physically
# resolves inside --adapter <dir>.
TMP_FILE="$(mktemp "${RULES_FILE}.XXXXXX")"

write_index_section() {
  [[ "${#ALL_INDEX_LINES[@]}" -eq 0 ]] && return
  {
    echo
    echo "## Active rules index"
    echo
    for il in "${ALL_INDEX_LINES[@]}"; do
      echo "$il"
    done
  } >>"$TMP_FILE"
}

wrote_index=0
for ((li = 0; li < TOTAL_LINES; li++)); do
  ln=$((li + 1))
  if [[ "${DEL[$li]}" -eq 0 ]]; then
    printf '%s\n' "${LINES[$li]}" >>"$TMP_FILE"
  fi
  if [[ "$INSERT_LINE" -gt 0 && "$ln" -eq "$INSERT_LINE" && "$wrote_index" -eq 0 ]]; then
    write_index_section
    wrote_index=1
  fi
done
if [[ "$INSERT_LINE" -eq 0 && "$wrote_index" -eq 0 ]]; then
  write_index_section
fi

mv "$TMP_FILE" "$RULES_FILE"

# ---- Summary ------------------------------------------------------------
echo
echo "===== split-learned-rules summary ====="
echo "Moved: $MOVED   Skipped: $SKIPPED   Warnings: $WARNCOUNT"
echo "RESULT: done"
exit 0
