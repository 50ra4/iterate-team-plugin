#!/usr/bin/env bash
# validate-agent-os.sh
#
# Validate the structural integrity of the Agent OS repository itself:
# required files/dirs exist, SKILL.md frontmatter is well-formed, codex
# agent TOMLs have required keys, and the "keep it short" line-count
# guard on the core instruction files holds. Optionally also validates
# a project's installed .agent-os/ adapter.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_OS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: validate-agent-os.sh [--adapter <dir>]

Validate the Agent OS repository structure (required files, SKILL.md
frontmatter, codex agent TOML keys, and line-count guards).

Options:
  --adapter <dir>   Additionally validate <dir>/.agent-os as an installed
                    project adapter (checks the 8 required files, that
                    GLOBAL_AGENTS.md was vendored, and that any Status:
                    lines in learned-rules.md are one of
                    candidate/active/deprecated). If .agent-os/rules/
                    exists (the split-by-scope layout), also validates
                    Status: lines in each rules/*.md and warns on any
                    file there not named global.md/project.md/
                    directory.md/file-pattern.md.
  --help            Show this help text and exit.

Exit codes:
  0   all checks passed (warnings are allowed)
  1   one or more checks failed
  2   usage error
EOF
}

ADAPTER_DIR=""

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
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

# ---- Counters -----------------------------------------------------------
PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

pass() { PASS_COUNT=$((PASS_COUNT + 1)); }
warn() { WARN_COUNT=$((WARN_COUNT + 1)); echo "WARN: $*"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); echo "FAIL: $*"; }

check_file_exists() {
  local path="$1"
  local label="${2:-$1}"
  if [[ -f "$path" ]]; then
    pass
  else
    fail "missing required file: $label ($path)"
  fi
}

check_skill_md() {
  local f="$1"
  if [[ ! -f "$f" ]]; then
    fail "missing SKILL.md: $f"
    return
  fi
  local first_line
  first_line="$(sed -n '1p' "$f")"
  # Strip a trailing \r so a CRLF-line-ended file (where the raw first
  # line is "---\r") is not false-FAILed here.
  first_line="${first_line%$'\r'}"
  if [[ "$first_line" != "---" ]]; then
    fail "SKILL.md frontmatter must start with '---' on line 1: $f"
    return
  fi
  # Frontmatter body = lines between the opening and closing '---'. The
  # closing-marker regex also tolerates a trailing \r (CRLF) so it still
  # matches and the loop actually terminates at the frontmatter boundary.
  local block
  block="$(awk 'NR==1{next} /^---\r?$/{exit} {print}' "$f")"
  local ok=1
  if ! grep -q '^name:' <<<"$block"; then
    fail "SKILL.md frontmatter missing 'name:' key: $f"
    ok=0
  fi
  if ! grep -q '^description:' <<<"$block"; then
    fail "SKILL.md frontmatter missing 'description:' key: $f"
    ok=0
  fi
  [[ "$ok" -eq 1 ]] && pass
}

check_codex_toml() {
  local f="$1"
  if [[ ! -f "$f" ]]; then
    fail "missing codex agent TOML: $f"
    return
  fi
  local ok=1
  grep -qE '^[[:space:]]*name[[:space:]]*=' "$f" || { fail "TOML missing 'name' key: $f"; ok=0; }
  grep -qE '^[[:space:]]*description[[:space:]]*=' "$f" || { fail "TOML missing 'description' key: $f"; ok=0; }
  grep -qE '^[[:space:]]*developer_instructions[[:space:]]*=' "$f" || { fail "TOML missing 'developer_instructions' key: $f"; ok=0; }
  [[ "$ok" -eq 1 ]] && pass
}

strip_html_comments() {
  # Remove HTML comment blocks (<!-- ... -->, possibly multi-line) before
  # scanning for real content, so documentation examples embedded in
  # templates (e.g. "Status: candidate | active | deprecated" inside a
  # "<!-- Example (delete me) -->" block) are not mistaken for live data.
  local file="$1"
  awk '
    {
      sub(/\r$/, "")
      # Span-aware HTML comment strip: iteratively remove "<!-- ... -->"
      # spans from the line so a same-line open+close (e.g. "<!-- oops
      # --> Status: bogus-value") does not swallow trailing real content
      # the way a simple line-based in_comment toggle would. Text before
      # an unclosed "<!--" is kept and in_comment carries into the next
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
      # A comment that prefixed real content on this line can leave
      # leading whitespace in `out`; strip it (only when actually
      # introduced by a stripped leading comment span, so genuinely
      # indented content elsewhere is untouched) so anchored regexes
      # like "^Status:" downstream still match.
      if (trimmed) sub(/^[ \t]+/, "", out)
      print out
    }
  ' "$file"
}

check_line_count() {
  local f="$1"
  if [[ ! -f "$f" ]]; then
    fail "missing file for line-count guard: $f"
    return
  fi
  local n
  # `wc -l` counts newline characters, so a file with no trailing
  # newline undercounts by one (its last line has no terminating \n).
  # `awk 'END{print NR}'` counts actual lines regardless of a trailing
  # newline, so an 81-line file missing its final newline is still
  # correctly seen as 81 lines (FAIL), not 80 (WARN).
  n="$(awk 'END{print NR}' "$f")"
  if [[ "$n" -gt 80 ]]; then
    fail "line count $n exceeds 80-line max: $f"
  elif [[ "$n" -gt 60 ]]; then
    warn "line count $n exceeds 60-line soft limit (max 80): $f"
    pass
  else
    pass
  fi
}

echo "===== validate-agent-os: checking $AGENT_OS_ROOT ====="

# ---- Top-level required files -------------------------------------------
for f in GLOBAL_AGENTS.md GLOBAL_CLAUDE.md README.md INSTALL.md; do
  check_file_exists "$AGENT_OS_ROOT/$f" "$f"
done

# ---- Templates ------------------------------------------------------------
TEMPLATES=(
  AGENTS.md.template
  CLAUDE.md.template
  learned-rules.md.template
  project-profile.md.template
  agent-evals.md.template
  failure-log.md.template
  review-feedback-log.md.template
)
for t in "${TEMPLATES[@]}"; do
  check_file_exists "$AGENT_OS_ROOT/templates/$t" "templates/$t"
done

# ---- Canonical skills (10) -------------------------------------------------
CANONICAL_SKILLS=(
  project-bootstrap
  project-profile
  adapt-to-project
  learn-from-feedback
  improve-instructions
  generate-agent-files
  run-agent-evals
  fix-bug-safely
  implement-feature-safely
  review-changes
)
for s in "${CANONICAL_SKILLS[@]}"; do
  check_skill_md "$AGENT_OS_ROOT/skills/$s/SKILL.md"
done

# ---- Claude assistant wiring ------------------------------------------------
check_file_exists "$AGENT_OS_ROOT/claude/CLAUDE.md" "claude/CLAUDE.md"

CLAUDE_SKILLS=(project-bootstrap project-profile adapt-to-project learn-from-feedback improve-instructions generate-agent-files run-agent-evals fix-bug-safely implement-feature-safely review-changes)
for s in "${CLAUDE_SKILLS[@]}"; do
  check_skill_md "$AGENT_OS_ROOT/claude/skills/$s/SKILL.md"
done

CLAUDE_AGENTS=(code-reviewer architecture-reviewer test-strategist security-reviewer bug-investigator instruction-maintainer)
for a in "${CLAUDE_AGENTS[@]}"; do
  check_file_exists "$AGENT_OS_ROOT/claude/agents/$a.md" "claude/agents/$a.md"
done

# ---- Codex assistant wiring -------------------------------------------------
check_file_exists "$AGENT_OS_ROOT/codex/AGENTS.md" "codex/AGENTS.md"

CODEX_AGENTS=(code-reviewer architecture-reviewer test-strategist security-reviewer bug-investigator instruction-maintainer)
for a in "${CODEX_AGENTS[@]}"; do
  check_codex_toml "$AGENT_OS_ROOT/codex/agents/$a.toml"
done

CODEX_SKILLS=(project-bootstrap project-profile adapt-to-project learn-from-feedback improve-instructions generate-agent-files run-agent-evals fix-bug-safely implement-feature-safely review-changes)
for s in "${CODEX_SKILLS[@]}"; do
  check_skill_md "$AGENT_OS_ROOT/codex/skills/$s/SKILL.md"
done

# ---- project-adapter template set -------------------------------------------
check_file_exists "$AGENT_OS_ROOT/project-adapter/AGENTS.md" "project-adapter/AGENTS.md"
check_file_exists "$AGENT_OS_ROOT/project-adapter/CLAUDE.md" "project-adapter/CLAUDE.md"

ADAPTER_FILES=(project-profile learned-rules failure-log review-feedback-log evals command-map architecture-map risk-map)
for f in "${ADAPTER_FILES[@]}"; do
  check_file_exists "$AGENT_OS_ROOT/project-adapter/.agent-os/$f.md" "project-adapter/.agent-os/$f.md"
done

# ---- The required scripts ------------------------------------------------
SCRIPTS=(
  bootstrap-project.sh
  validate-agent-os.sh
  summarize-learning-log.sh
  detect-rule-conflicts.sh
  run-agent-evals.sh
  split-learned-rules.sh
)
for s in "${SCRIPTS[@]}"; do
  check_file_exists "$AGENT_OS_ROOT/scripts/$s" "scripts/$s"
done

# ---- Line-count guard on core instruction files ----------------------------
echo "--- line-count guard (WARN > 60, FAIL > 80) ---"
LINE_GUARD_FILES=(
  GLOBAL_AGENTS.md
  GLOBAL_CLAUDE.md
  claude/CLAUDE.md
  codex/AGENTS.md
  project-adapter/AGENTS.md
  project-adapter/CLAUDE.md
)
for f in "${LINE_GUARD_FILES[@]}"; do
  check_line_count "$AGENT_OS_ROOT/$f"
done

# ---- Optional: validate an installed project adapter -----------------------
if [[ -n "$ADAPTER_DIR" ]]; then
  echo "--- validating installed adapter: $ADAPTER_DIR ---"
  AO="$ADAPTER_DIR/.agent-os"
  if [[ ! -d "$AO" ]]; then
    fail "adapter .agent-os directory missing: $AO"
  else
    for f in "${ADAPTER_FILES[@]}"; do
      check_file_exists "$AO/$f.md" "$ADAPTER_DIR/.agent-os/$f.md"
    done

    # bootstrap-project.sh always vendors GLOBAL_AGENTS.md into every
    # installed adapter (GLOBAL_CLAUDE.md is only vendored for --for
    # claude|both installs, so it is not required here).
    check_file_exists "$AO/GLOBAL_AGENTS.md" "$ADAPTER_DIR/.agent-os/GLOBAL_AGENTS.md"

    RULES_FILE="$AO/learned-rules.md"
    if [[ -f "$RULES_FILE" ]]; then
      BAD_STATUS="$(strip_html_comments "$RULES_FILE" | grep -n '^Status:' | grep -Ev 'Status:[[:space:]]*(candidate|active|deprecated)[[:space:]]*$' || true)"
      if [[ -n "$BAD_STATUS" ]]; then
        fail "invalid Status: value(s) in $RULES_FILE:"
        echo "$BAD_STATUS"
      else
        pass
      fi
    fi

    # ---- Optional split-by-scope layout: .agent-os/rules/*.md -----------
    RULES_DIR="$AO/rules"
    if [[ -d "$RULES_DIR" ]]; then
      echo "--- validating split rules layout: $RULES_DIR ---"
      EXPECTED_RULE_FILES=(global.md project.md directory.md file-pattern.md)

      while IFS= read -r rf; do
        base="$(basename "$rf")"
        is_expected=0
        for ef in "${EXPECTED_RULE_FILES[@]}"; do
          [[ "$base" == "$ef" ]] && is_expected=1
        done
        if [[ "$is_expected" -eq 0 ]]; then
          warn "unexpected file in $RULES_DIR (expected one of: ${EXPECTED_RULE_FILES[*]}): $base"
        fi

        BAD_STATUS="$(strip_html_comments "$rf" | grep -n '^Status:' | grep -Ev 'Status:[[:space:]]*(candidate|active|deprecated)[[:space:]]*$' || true)"
        if [[ -n "$BAD_STATUS" ]]; then
          fail "invalid Status: value(s) in $rf:"
          echo "$BAD_STATUS"
        else
          pass
        fi
      done < <(find "$RULES_DIR" -maxdepth 1 -type f -name '*.md' | sort)
    fi
  fi
fi

# ---- Summary ----------------------------------------------------------
echo
echo "===== validate-agent-os summary ====="
echo "PASS: $PASS_COUNT   WARN: $WARN_COUNT   FAIL: $FAIL_COUNT"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  echo "RESULT: FAIL"
  exit 1
fi

echo "RESULT: PASS"
exit 0
