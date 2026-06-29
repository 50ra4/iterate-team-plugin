#!/usr/bin/env bash
# Pre-commit validation for agent definitions.
#
# Runs scripts/build-agents.sh --check to detect drift between
# templates/_base/ templates and agents/ outputs.
# Also enforces that common rules listed in templates/_partials/ do not leak back
# into agents/*.md as inline duplicates.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# 1. Drift check: outputs must match what build-agents.sh would produce.
if ! scripts/build-agents.sh --check; then
  echo ""
  echo "agent definition drift detected." >&2
  echo "Run: scripts/build-agents.sh" >&2
  exit 1
fi

# 2. Duplicate-phrase check: shared rule phrases must appear at most once
#    across agents/*.md (occurrences allowed only inside templates/_partials/).
violations=0
check_phrase() {
  local phrase="$1"
  local count
  count=$(grep -rF -- "$phrase" agents/ 2>/dev/null | wc -l || true)
  if (( count > 1 )); then
    echo "duplicate rule phrase ($count occurrences) in agents/: $phrase" >&2
    violations=$((violations + 1))
  fi
}

check_absent_phrase() {
  local phrase="$1"
  local matches
  matches=$(grep -rF -- "$phrase" agents/ 2>/dev/null || true)
  if [ -n "$matches" ]; then
    local count
    count=$(echo "$matches" | wc -l)
    echo "prohibited phrase found inline ($count occurrence(s)) in agents/: $phrase" >&2
    echo "$matches" | sed 's/:.*//' | sort -u | while read -r f; do echo "  $f" >&2; done
    violations=$((violations + 1))
  fi
}

check_phrase '`git add -A` / `git add .` は'
check_phrase 'コミットメッセージは Why'

check_absent_phrase 'permissionMode: plan により Write は構造的に不可'
check_absent_phrase 'タスク分類と探索深度'
check_absent_phrase '各アトミックステップ後に検証'
check_absent_phrase 'パターン検出と適合'

if (( violations > 0 )); then
  echo "" >&2
  echo "Move duplicated phrases to templates/_partials/ and reference via @ref." >&2
  exit 1
fi
