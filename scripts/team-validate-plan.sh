#!/usr/bin/env bash
# iterate-team ハーネスの plan 整合性検証スクリプト。
# 既存 <plugin_root>/scripts/validate-plan.sh をそのまま呼び出し（6 キー整合検証）、
# 加えて <plugin_root>/scripts/team-compute-waves.sh で wave 計算を行いサイクル / 不明依存を検出する。
#
# Usage:
#   <plugin_root>/scripts/team-validate-plan.sh <plan-json-path> <tasks-dir>
#
# Exit code:
#   0 = 両検証が pass
#   1 = 引数不正 / 依存スクリプト不在 / 検証失敗

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <plan-json-path> <tasks-dir>" >&2
  exit 1
fi

plan_json="$1"
tasks_dir="$2"

script_dir="$(cd "$(dirname "$0")" && pwd)"
validate_plan="${script_dir}/validate-plan.sh"
compute_waves="${script_dir}/team-compute-waves.sh"

if [[ ! -x "$validate_plan" ]]; then
  echo "dependency script not found: ${validate_plan}" >&2
  exit 1
fi

if [[ ! -x "$compute_waves" ]]; then
  echo "dependency script not found: ${compute_waves}" >&2
  exit 1
fi

# 既存 6 キー整合検証
if ! "$validate_plan" "$plan_json" "$tasks_dir"; then
  exit 1
fi

# wave 計算（サイクル / 不明依存検出）
waves_out=$("$compute_waves" "$plan_json")
wave_count=$(echo "$waves_out" | wc -l | tr -d ' ')

# tasks 数を取得
task_count=$(jq '.task_count // (.tasks | length)' "$plan_json")

echo "OK: plan validated (tasks=${task_count}, waves=${wave_count})"
