#!/usr/bin/env bash
# iterate-validate-session.sh
# 目的: /iterate-build / /iterate-review が必須化する --session <session-id> 引数のバリデーション。
#       Orchestrator メインセッションから Bash 経由で呼び出す。
#
# Usage:
#   <plugin_root>/scripts/iterate-validate-session.sh <session-id> <expected-phase>
#
# Arguments:
#   <session-id>      バリデーション対象のセッション ID
#   <expected-phase>  期待するフェーズ: build または review
#
# Exit codes:
#   0  全検証 pass（stdout に JSON 出力）
#   1  Usage エラー（引数不足 / 不正な <expected-phase>）
#   2  session-id 形式不正
#   3  runlog 不在（.iterate-team/state/<session-id>/runlog.jsonl が存在しない）
#   4  plan phase 未完了（<expected-phase>=build かつ plan_approved/plan_presented/step4 checkpoint いずれもなし）
#   5  build phase 未完了（<expected-phase>=review かつ build 完了イベントなし）

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <session-id> <expected-phase>" >&2
  echo "  <expected-phase>: build or review" >&2
  exit 1
fi

session_id="$1"
expected_phase="$2"

case "$expected_phase" in
  build|review)
    ;;
  *)
    echo "Usage: $0 <session-id> <expected-phase>" >&2
    echo "  <expected-phase> must be 'build' or 'review', got: $expected_phase" >&2
    exit 1
    ;;
esac

# 先頭英数字制限で -flag 始まりの引数注入を防止
if [[ ! "$session_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
  echo "invalid session-id format" >&2
  exit 2
fi

# . が文字クラス内でリテラルのため正規表現だけでは .. を拒否できない
if [[ "$session_id" == *..* ]]; then
  echo "invalid session-id format" >&2
  exit 2
fi

# repo_root は対象プロジェクト基準で解決する。プラグインを対象リポ外へ配布
# （npm/global install・別 checkout の marketplace install）してもセッション状態を
# 取り違えないよう、プラグイン自身の git root（script の場所）ではなく対象リポを見る。
# Claude Code が注入する CLAUDE_PROJECT_DIR を優先し、未注入時は CWD の git root →
# pwd の順でフォールバックする（session-start.sh / team-worktree-*.sh と同一規約）。
repo_root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
runlog_path="${repo_root}/.iterate-team/state/${session_id}/runlog.jsonl"

if [[ ! -f "$runlog_path" ]]; then
  echo "runlog not found: 該当 session-id は存在しません" >&2
  exit 3
fi

case "$expected_phase" in
  build)
    # plan phase 完了シグナルが 1 件以上含まれることを確認。
    # 承認を 1 回に集約したため env で発火イベントが異なる:
    #   - dev container: ステップ 4 で承認 → plan_approved
    #   - host/Web:      ステップ 4 は提示のみ → plan_presented（承認は 4.5 で実施）
    # いずれの env でもステップ 4 完了 checkpoint（next_step:"4.5"）を出すため併せて許容。
    # pipefail 下で jq -e のストリーム終了コードに依存しないよう -s で全件スラープし
    # any() の単一 boolean で判定する（マッチ有→exit 0 / 無→exit 1）。
    if ! jq -e -s 'any(.[];
      .event == "plan_approved" or
      .event == "plan_presented" or
      (.event == "step_checkpoint" and ((.next_step | tostring) == "4.5"))
    )' "$runlog_path" >/dev/null; then
      echo "plan phase not completed: 先に /iterate-plan を実行してください" >&2
      exit 4
    fi
    ;;
  review)
    # step_checkpoint の next_step:"6" イベント、または all_tasks_completed イベントが含まれることを確認
    if ! jq -e -s 'any(.[];
      (.event == "step_checkpoint" and ((.next_step | tostring) == "6")) or
      .event == "all_tasks_completed"
    )' "$runlog_path" >/dev/null; then
      echo "build phase not completed: 先に /iterate-build を実行してください" >&2
      exit 5
    fi
    ;;
esac

integration_branch="$(jq -r 'select(.integration_branch != null) | .integration_branch' "$runlog_path" | tail -n 1)"

jq -cn \
  --arg session_id "$session_id" \
  --arg integration_branch "$integration_branch" \
  '{"session_id": $session_id, "integration_branch": $integration_branch}'
