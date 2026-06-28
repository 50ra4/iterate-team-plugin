#!/usr/bin/env bash
# iterate-team ハーネスの plan.json ↔ task-x_y_z.md フロントマター整合性検証スクリプト。
# Orchestrator がステップ 3.2 パターン B で実行し、Planner の出力不整合を検出する。
#
# Usage:
#   <plugin_root>/scripts/validate-plan.sh <plan-json-path> <tasks-dir>
#
# 検証項目:
#   - plan.json の tasks[].id に対応する <tasks-dir>/<id>.md が存在する（MISSING 検出）
#   - 各 task-x_y_z.md のフロントマター（id / max_retries / executor / reviewer
#     / depends_on / required_advisors）が plan.json の対応エントリと完全一致する（MISMATCH 検出）
#   - plan.json および各 task-x_y_z.md フロントマターの executor 値が `generator` 唯一
#     許容（INVALID_EXECUTOR 検出。`codex` 等は廃止済み値として errors 加算 exit 1）
#   - plan.json の各 task エントリに required_advisors キーが存在する（MISSING_KEY 検出）
#   - フロントマターに旧キー advisors: 行が残存していないこと（LEGACY_KEY エラー、exit 1）
#   - <tasks-dir> 配下の task-*.md と plan.json の tasks[].id 集合を双方向比較し、
#     plan.json に存在しない余分な task ファイルを検出する（EXTRA 検出）
#
# Exit code:
#   0 = 整合
#   1 = 引数不正 / ファイル欠落 / 不整合（標準エラーに詳細）

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <plan-json-path> <tasks-dir>" >&2
  exit 1
fi

plan_json="$1"
tasks_dir="${2%/}"

if [[ ! -f "$plan_json" ]]; then
  echo "plan.json not found: $plan_json" >&2
  exit 1
fi

if [[ ! -d "$tasks_dir" ]]; then
  echo "tasks-dir not found: $tasks_dir" >&2
  exit 1
fi

if ! jq empty "$plan_json" >/dev/null 2>&1; then
  echo "plan.json is not valid JSON: $plan_json" >&2
  exit 1
fi

# フロントマター（先頭の `---` 行から次の `---` 行まで）の単純な `key: value` を抽出。
# YAML 完全パーサーではないが、Planner が出力する書式（スカラー or インライン配列）には対応する。
extract_frontmatter() {
  local file="$1"
  local key="$2"
  awk -v key="$key" '
    BEGIN { delim=0; found=0; collecting=0; buf="" }
    /^---[[:space:]]*$/ {
      delim++
      if (delim == 2) {
        if (collecting) { gsub(/[[:space:]]+/, " ", buf); print buf }
        exit
      }
      next
    }
    delim == 1 && collecting {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      buf = buf line
      if (buf ~ /\]/) { gsub(/[[:space:]]+/, " ", buf); print buf; exit }
      next
    }
    delim == 1 && found == 1 {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      if (line ~ /^\[/) {
        if (line ~ /\]/) { print line; exit }
        buf = line; collecting = 1
      } else {
        exit
      }
      next
    }
    delim == 1 && $0 ~ "^"key":" {
      sub("^"key":[[:space:]]*", "")
      if (length($0) > 0) { print; exit }
      found = 1
    }
  ' "$file"
}

# `[a, b, c]` または空 / 単独要素のインライン YAML 配列を sort 済み CSV に正規化する。
normalize_list() {
  local raw="$1"
  raw="${raw#[}"
  raw="${raw%]}"
  echo "$raw" \
    | tr ',' '\n' \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;/^$/d' \
    | sort \
    | tr '\n' ',' \
    | sed 's/,$//'
}

errors=0
# bash 3.2（macOS デフォルト）は mapfile を持たないため while ループで代替する
ids=()
while IFS= read -r line; do
  ids+=("$line")
done < <(jq -r '.tasks[].id' "$plan_json")

if [[ ${#ids[@]} -eq 0 ]]; then
  echo "plan.json has empty tasks[]" >&2
  exit 1
fi

for id in "${ids[@]}"; do
  task_file="$tasks_dir/$id.md"
  if [[ ! -f "$task_file" ]]; then
    echo "MISSING: $task_file" >&2
    errors=$((errors + 1))
    continue
  fi

  json_id=$(jq -r --arg id "$id" '.tasks[] | select(.id == $id) | .id' "$plan_json")
  json_max_retries=$(jq -r --arg id "$id" '.tasks[] | select(.id == $id) | .max_retries' "$plan_json")
  json_executor=$(jq -r --arg id "$id" '.tasks[] | select(.id == $id) | .executor' "$plan_json")
  json_reviewer=$(jq -r --arg id "$id" '.tasks[] | select(.id == $id) | .reviewer' "$plan_json")
  json_depends_on=$(jq -r --arg id "$id" '.tasks[] | select(.id == $id) | .depends_on | sort | join(",")' "$plan_json")

  if [[ "$json_executor" != "generator" ]]; then
    echo "INVALID_EXECUTOR ($id, executor): plan.json='$json_executor' (許容値: generator)" >&2
    errors=$((errors + 1))
  fi

  if ! jq -e --arg id "$id" '.tasks[] | select(.id == $id) | has("required_advisors")' "$plan_json" >/dev/null 2>&1; then
    echo "MISSING_KEY ($id, required_advisors): plan.json の当該 task エントリに required_advisors キーが存在しない" >&2
    errors=$((errors + 1))
    json_required_advisors=""
  else
    json_required_advisors=$(jq -r --arg id "$id" '.tasks[] | select(.id == $id) | .required_advisors | sort | join(",")' "$plan_json")
  fi

  fm_id=$(extract_frontmatter "$task_file" "id")
  fm_max_retries=$(extract_frontmatter "$task_file" "max_retries")
  fm_executor=$(extract_frontmatter "$task_file" "executor")
  fm_reviewer=$(extract_frontmatter "$task_file" "reviewer")
  fm_depends_on=$(normalize_list "$(extract_frontmatter "$task_file" "depends_on")")
  fm_required_advisors=$(normalize_list "$(extract_frontmatter "$task_file" "required_advisors")")

  if [[ "$fm_executor" != "generator" ]]; then
    echo "INVALID_EXECUTOR ($id, executor): frontmatter='$fm_executor' (許容値: generator)" >&2
    errors=$((errors + 1))
  fi

  fm_legacy_advisors_raw=$(extract_frontmatter "$task_file" "advisors")
  if [[ -n "$fm_legacy_advisors_raw" ]]; then
    echo "LEGACY_KEY ($id, advisors): フロントマターに旧キー advisors: 行が残存している（required_advisors にリネームすること）" >&2
    errors=$((errors + 1))
  fi

  while IFS='|' read -r key fm_value json_value; do
    if [[ "$fm_value" != "$json_value" ]]; then
      echo "MISMATCH ($id, $key): plan.json='$json_value' frontmatter='$fm_value'" >&2
      errors=$((errors + 1))
    fi
  done <<EOF
id|$fm_id|$json_id
max_retries|$fm_max_retries|$json_max_retries
executor|$fm_executor|$json_executor
reviewer|$fm_reviewer|$json_reviewer
depends_on|$fm_depends_on|$json_depends_on
required_advisors|$fm_required_advisors|$json_required_advisors
EOF
done

# tasks-dir 側の task-*.md を列挙し、plan.json に id がないものを EXTRA として検出する。
# bash 3.2（macOS）は declare -A を持たないため線形探索で代替する
_id_in_plan() {
  local target="$1"
  local id
  for id in "${ids[@]}"; do
    [[ "$id" == "$target" ]] && return 0
  done
  return 1
}

while IFS= read -r task_file; do
  base=$(basename "$task_file" .md)
  if ! _id_in_plan "$base"; then
    echo "EXTRA: $task_file" >&2
    errors=$((errors + 1))
  fi
done < <(find "$tasks_dir" -maxdepth 1 -type f -name 'task-*.md' | sort)

if [[ $errors -gt 0 ]]; then
  echo "validate-plan: $errors error(s) detected" >&2
  exit 1
fi

echo "validate-plan: OK (${#ids[@]} task(s))"
