#!/usr/bin/env bash
# Build agents/team-<name>.md from
# templates/_base/<name>.md templates.
#
# squad 出力は恒久停止済（理由: /iterate-squad は /iterate-team に置換）。
# 本スクリプトは team 出力（agents/team-<name>.md）のみを生成する。
# templates/_base/ 配下の squad 名テンプレートは team 出力生成の SoT として保持する。
#
# Placeholders:
#   {{NAME}}      → team-<name>
#   {{HARNESS}}   → iterate-team
#
# Directives:
#   <!-- @ref _partials/<file>.md -->
#     → replaced with a runtime Read instruction pointing at the partial.
#   <!-- @if team -->...<!-- @endif -->
#     → kept in team output.
#   <!-- @if squad -->...<!-- @endif -->
#     → always removed (squad 出力は恒久停止済）。
#
# Usage (run from the plugin root):
#   scripts/build-agents.sh              # write team outputs; remove stale squad outputs
#   scripts/build-agents.sh --check      # diff team outputs and detect stale squad outputs (exit 1 on drift)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_DIR="$ROOT/templates/_base"
OUT_DIR="$ROOT/agents"
# Runtime path baked into @ref expansions. Resolved by the Orchestrator from
# init.json's plugin_root (the <plugin_root> placeholder), since ${CLAUDE_PLUGIN_ROOT}
# is not guaranteed to expand inside agent/command body text.
PARTIALS_REL="<plugin_root>/templates/_partials"

mode="write"
case "${1:-}" in
  --check) mode="check" ;;
  "") ;;
  *) echo "unknown arg: $1" >&2; exit 2 ;;
esac

# 出力ディレクトリは初回ビルドや clean checkout で未作成のことがある（write 時のみ作成）。
[[ "$mode" == "write" ]] && mkdir -p "$OUT_DIR"

render() {
  # stdout: rendered template
  # args: <tmpl> <name> <harness-kind: squad|team>
  local tmpl="$1" name="$2" kind="$3"
  local harness
  if [[ "$kind" == "squad" ]]; then harness="iterate-squad"; else harness="iterate-team"; fi

  local skip=0
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    # @if blocks
    if [[ "$line" =~ ^\<!--\ @if\ (squad|team)\ --\>$ ]]; then
      if [[ "${BASH_REMATCH[1]}" != "$kind" ]]; then skip=1; fi
      continue
    fi
    if [[ "$line" == "<!-- @endif -->" ]]; then
      skip=0
      continue
    fi
    (( skip )) && continue

    # @ref directive
    if [[ "$line" =~ ^\<!--\ @ref\ _partials/([^\ ]+)\ --\>$ ]]; then
      printf '本 agent は起動直後に `%s/%s` を `Read` し、その内容を遵守すること。\n' \
        "$PARTIALS_REL" "${BASH_REMATCH[1]}"
      continue
    fi

    # Placeholder substitution
    line="${line//\{\{NAME\}\}/$name}"
    line="${line//\{\{HARNESS\}\}/$harness}"
    printf '%s\n' "$line"
  done < "$tmpl"
}

drift=0
shopt -s nullglob

# Stale squad output files: derived from _base/ (non-team-prefixed templates).
SQUAD_FILES=()
for f in "$BASE_DIR"/*.md; do
  f_base="$(basename "$f" .md)"
  [[ "$f_base" != team-* ]] && SQUAD_FILES+=("$f_base.md")
done

for squad_file in "${SQUAD_FILES[@]}"; do
  squad_path="$OUT_DIR/$squad_file"
  if [[ "$mode" == "check" ]]; then
    if [[ -f "$squad_path" ]]; then
      echo "drift: stale squad output $squad_path" >&2
      drift=1
    fi
  else
    rm -f "$squad_path"
  fi
done

# Build team outputs for each unique agent name.
#
# team output  ← _base/team-<name>.md (team mode) if exists,
#                else _base/<name>.md (team mode)
# bash 3.2（macOS デフォルト）は declare -A を持たないため、indexed array + 線形探索で
# canonical 名を重複排除する（validate-plan.sh と同じ bash 3.2 互換方針）。
CANONICALS=()
for tmpl in "$BASE_DIR"/*.md; do
  basename="$(basename "$tmpl" .md)"
  # Strip team- prefix to compute the canonical agent name
  if [[ "$basename" == team-* ]]; then
    canonical="${basename#team-}"
  else
    canonical="$basename"
  fi
  dup=0
  for c in ${CANONICALS[@]+"${CANONICALS[@]}"}; do
    [[ "$c" == "$canonical" ]] && { dup=1; break; }
  done
  (( dup )) || CANONICALS+=("$canonical")
done

for canonical in ${CANONICALS[@]+"${CANONICALS[@]}"}; do
  squad_tmpl="$BASE_DIR/${canonical}.md"
  team_tmpl="$BASE_DIR/team-${canonical}.md"

  out="$OUT_DIR/team-${canonical}.md"
  name="team-$canonical"
  [[ -f "$team_tmpl" ]] && tmpl="$team_tmpl" || tmpl="$squad_tmpl"

  if [[ ! -f "$tmpl" ]]; then
    echo "missing template for $canonical: $tmpl" >&2
    drift=1
    continue
  fi

  # Render and collapse 3+ consecutive newlines into 2 (handles blank-line
  # adjacency around stripped @if/@endif blocks).
  rendered="$(render "$tmpl" "$name" "team" | awk '
    /^$/ { blank++; next }
    { if (blank > 0) { print ""; blank = 0 } print }
    END { }
  ')"

  if [[ "$mode" == "check" ]]; then
    if ! diff_out="$(diff -u "$out" <(printf '%s\n' "$rendered") 2>/dev/null)"; then
      echo "drift: $out" >&2
      [[ -n "$diff_out" ]] && printf '%s\n' "$diff_out" >&2
      drift=1
    fi
  else
    printf '%s\n' "$rendered" > "$out"
  fi
done

if [[ "$mode" == "check" && "$drift" -ne 0 ]]; then
  echo "" >&2
  echo "Drift detected. Run scripts/build-agents.sh to regenerate." >&2
  exit 1
fi
