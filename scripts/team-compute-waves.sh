#!/usr/bin/env bash
# iterate-team ハーネスの wave 計算スクリプト。
# plan.json の tasks[] を読み込み、depends_on のトポロジカルレベル化を行い、
# 同 level を 1 wave にまとめた JSONL を stdout に出力する。
#
# Usage:
#   <plugin_root>/scripts/team-compute-waves.sh <plan-json-path>
#
# 出力フォーマット:
#   1 行 1 wave の JSONL:
#     {"wave": <integer>, "tasks": [<task-id>, ...]}
#   wave は 0 始まりの昇順、tasks は plan.json の宣言順を保持する。
#
# Exit code:
#   0 = 正常
#   1 = サイクル検出 / 存在しない依存 / 引数不正 / JSON 不正

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <plan-json-path>" >&2
  exit 1
fi

plan_json="$1"

if [[ ! -f "$plan_json" ]]; then
  echo "plan.json not found: $plan_json" >&2
  exit 1
fi

if ! jq empty "$plan_json" >/dev/null 2>&1; then
  echo "plan.json is not valid JSON: $plan_json" >&2
  exit 1
fi

# 依存先の存在検証（不明な depends_on を検出）
unknown=$(jq -r '
  (.tasks | map(.id)) as $ids
  | ($ids | map({key: ., value: true}) | from_entries) as $known
  | .tasks
  | map(
      . as $t
      | (.depends_on // [])
      | map(select(($known[.] // false) | not) | "UNKNOWN_DEPENDENCY: \($t.id) -> \(.)")
    )
  | flatten
  | join("\n")
' "$plan_json")

if [[ -n "$unknown" ]]; then
  echo "$unknown" >&2
  exit 1
fi

# 各タスクの level を BFS で計算し、wave ごとにグループ化した JSONL を出力する。
# - レベル計算は反復 (fixed point)。タスク数 + 1 回反復しても確定しないノードはサイクル。
# - 出力は plan.json の tasks[] 宣言順を保持した JSONL 形式 wave。
out=$(jq -r '
  (.tasks | map(.id)) as $ids
  | (.tasks | map({key: .id, value: (.depends_on // [])}) | from_entries) as $deps_map
  | ($ids | length) as $n_tasks
  | (reduce range(0; $n_tasks + 1) as $_iter (
      ($ids | map({key: ., value: null}) | from_entries);
      reduce $ids[] as $id (
        .;
        if .[$id] != null then .
        else
          $deps_map[$id] as $ds
          | if ($ds | length) == 0 then
              .[$id] = 0
            else
              (. as $cur | $ds | map($cur[.])) as $dep_levels
              | if ($dep_levels | all(. != null)) then
                  .[$id] = (($dep_levels | max) + 1)
                else .
                end
            end
        end
      )
    )) as $levels
  | ([$ids[] | select($levels[.] == null)]) as $unresolved
  | if ($unresolved | length) > 0 then
      $unresolved | map("CYCLE: \(.)") | .[]
    else
      ($ids | map({id: ., level: $levels[.]})) as $entries
      | ([$entries[].level] | unique | sort) as $wave_levels
      | $wave_levels[]
      | . as $w
      | {wave: $w, tasks: ($entries | map(select(.level == $w) | .id))}
      | tojson
    end
' "$plan_json")

if echo "$out" | grep -q '^CYCLE:'; then
  echo "$out" | grep '^CYCLE:' >&2
  exit 1
fi

echo "$out"
