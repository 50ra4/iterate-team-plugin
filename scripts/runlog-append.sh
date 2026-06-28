#!/usr/bin/env bash
# iterate-team ハーネスの runlog 追記用スクリプト。
# Orchestrator / agents は本スクリプトを 1 行で呼び出すことで、
# Write ツール経由の JSON 構築を context から排除する（トークン削減目的）。
#
# Usage:
#   <plugin_root>/scripts/runlog-append.sh <session-id> <event-name> <json-payload>
#
# Example:
#   <plugin_root>/scripts/runlog-append.sh 20260507_my-topic plan_ready '{"topic_slug":"my-topic","task_count":5}'
#
# 動作:
#   - $REPO_ROOT/.iterate-team/state/<session-id>/runlog.jsonl に 1 行追記する
#   - 必要なら親ディレクトリを mkdir -p する
#   - payload が空文字列の場合は {} として扱う
#   - 出力 JSON: payload オブジェクトに ts / event / session_id を merge した 1 行（jq -c）
#   - **排他ロック取得後に append**（並列 Generator / Advisor 完了通知が
#     同時発生してもデータ競合せず JSON 行が破損しないことを保証。
#     iterate-team の wave 並列実行で必須）。
#     flock（Linux）が無い macOS ホストでは mkdir の原子性を用いた
#     ポータブルロックにフォールバックする（no-op 素通りはしない）

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <session-id> <event-name> <json-payload>" >&2
  exit 1
fi

session_id="$1"
event_name="$2"
payload="${3:-}"

# session-id バリデーション（path traversal 防止）
if [[ -z "$session_id" || "$session_id" =~ [^A-Za-z0-9._-] ]]; then
  echo "invalid session-id: $session_id" >&2
  exit 1
fi

# event-name バリデーション
if [[ -z "$event_name" || "$event_name" =~ [^A-Za-z0-9_-] ]]; then
  echo "invalid event-name: $event_name" >&2
  exit 1
fi

# payload が空なら {} を使う
if [[ -z "$payload" ]]; then
  payload='{}'
fi

# JSON 妥当性チェック
if ! echo "$payload" | jq empty >/dev/null 2>&1; then
  echo "invalid JSON payload: $payload" >&2
  exit 1
fi

# repo_root は対象プロジェクト基準で解決する（プラグイン自身の git root は見ない）。
# CLAUDE_PROJECT_DIR を優先し、未注入時は CWD の git root → pwd の順でフォールバックする。
# iterate-validate-session.sh / session-start.sh と同一規約で state 先の分裂を防ぐ。
repo_root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
log_dir="${repo_root}/.iterate-team/state/${session_id}"
log_file="${log_dir}/runlog.jsonl"

mkdir -p "$log_dir"

ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# merge した 1 行を log_file へ追記する（ロック保持中に呼ぶ前提）。
_locked_append() {
  echo "$payload" \
    | jq -c \
        --arg ts "$ts" \
        --arg event "$event_name" \
        --arg session_id "$session_id" \
        '. + {ts: $ts, event: $event, session_id: $session_id}' \
    >> "$log_file"
}

# 並列 append 安全化: flock（Linux）または mkdir（macOS ホスト）で排他ロックを取得後に追記する。
# どちらの経路でも wave 並列実行下で JSON 行の競合追記による破損を防ぐ。
if command -v flock >/dev/null 2>&1; then
  lock_file="${log_file}.lock"
  exec 9>>"$lock_file"
  if ! flock -x -w 5 9; then
    echo "flock timeout: $log_file" >&2
    exit 1
  fi
  _locked_append
  flock -u 9
  exec 9>&-
else
  # flock 非搭載（macOS ホスト）: mkdir の原子性を利用したポータブルな排他制御。
  # mkdir は既存ディレクトリに対して非 0 で失敗するため mutex として機能する。
  # 取得できるまで 0.1s 間隔でリトライし、5s（= 50 回）でタイムアウト失敗する。
  lock_dir="${log_file}.lock.d"
  waited=0
  until mkdir "$lock_dir" 2>/dev/null; do
    if [[ "$waited" -ge 50 ]]; then
      echo "lock timeout: $log_file" >&2
      exit 1
    fi
    sleep 0.1
    waited=$((waited + 1))
  done
  # 異常終了時もロックを解放する（bash 3.2 互換の EXIT トラップ）。
  trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT
  _locked_append
  rmdir "$lock_dir" 2>/dev/null || true
  trap - EXIT
fi
