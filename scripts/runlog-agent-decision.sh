#!/usr/bin/env bash
# agent_decision イベントを runlog.jsonl に追記する専用ラッパー。
# <plugin_root>/scripts/runlog-append.sh を event=agent_decision で呼び出す。
#
# Usage:
#   <plugin_root>/scripts/runlog-agent-decision.sh <session-id> <agent> <decision> <reason> \
#     [--task-id <id>] [--attempt <n>] [--request-id <id>]
#
# decision の値域: invoked / skipped / adopted / rejected
#
# Example:
#   <plugin_root>/scripts/runlog-agent-decision.sh team_20260511_my-topic researcher invoked \
#     "Planner 要求: <topic>" --task-id task-1_2_3 --attempt 1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── 必須引数チェック ─────────────────────────────────────────────────────────
if [[ $# -lt 4 ]]; then
  echo "Usage: $0 <session-id> <agent> <decision> <reason> [--task-id <id>] [--attempt <n>] [--request-id <id>]" >&2
  exit 1
fi

session_id="$1"
agent="$2"
decision="$3"
reason="$4"
shift 4

# ── session-id バリデーション（path traversal 防止）─────────────────────────
if [[ -z "$session_id" || "$session_id" =~ [^A-Za-z0-9._-] ]]; then
  echo "invalid session-id: $session_id" >&2
  exit 1
fi

# ── agent バリデーション ──────────────────────────────────────────────────────
if [[ -z "$agent" ]]; then
  echo "Usage: $0 <session-id> <agent> <decision> <reason> [--task-id <id>] [--attempt <n>] [--request-id <id>]" >&2
  exit 1
fi

# ── decision バリデーション ──────────────────────────────────────────────────
case "$decision" in
  invoked|skipped|adopted|rejected)
    ;;
  "")
    echo "Usage: $0 <session-id> <agent> <decision> <reason> [--task-id <id>] [--attempt <n>] [--request-id <id>]" >&2
    exit 1
    ;;
  *)
    echo "invalid decision: $decision" >&2
    exit 1
    ;;
esac

# ── reason バリデーション ─────────────────────────────────────────────────────
if [[ -z "$reason" ]]; then
  echo "Usage: $0 <session-id> <agent> <decision> <reason> [--task-id <id>] [--attempt <n>] [--request-id <id>]" >&2
  exit 1
fi

# ── 任意引数パース ────────────────────────────────────────────────────────────
task_id=""
attempt=""
request_id=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-id)
      if [[ -z "${2:-}" || "${2:-}" == --* ]]; then
        echo "Usage: $0 <session-id> <agent> <decision> <reason> [--task-id <id>] [--attempt <n>] [--request-id <id>]" >&2
        exit 1
      fi
      task_id="$2"
      shift 2
      ;;
    --attempt)
      if [[ -z "${2:-}" || "${2:-}" == --* ]]; then
        echo "Usage: $0 <session-id> <agent> <decision> <reason> [--task-id <id>] [--attempt <n>] [--request-id <id>]" >&2
        exit 1
      fi
      if [[ ! "$2" =~ ^[0-9]+$ ]]; then
        echo "invalid --attempt value: $2 (must be a non-negative integer)" >&2
        exit 1
      fi
      attempt="$2"
      shift 2
      ;;
    --request-id)
      if [[ -z "${2:-}" || "${2:-}" == --* ]]; then
        echo "Usage: $0 <session-id> <agent> <decision> <reason> [--task-id <id>] [--attempt <n>] [--request-id <id>]" >&2
        exit 1
      fi
      request_id="$2"
      shift 2
      ;;
    *)
      echo "unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# ── JSON payload 構築 ─────────────────────────────────────────────────────────
# 必須フィールドから開始し、任意フィールドは値がある場合のみ追加する
payload="$(
  jq -cn \
    --arg agent    "$agent" \
    --arg decision "$decision" \
    --arg reason   "$reason" \
    '{agent: $agent, decision: $decision, reason: $reason}'
)"

if [[ -n "$task_id" ]]; then
  payload="$(echo "$payload" | jq -c --arg v "$task_id" '. + {task_id: $v}')"
fi

if [[ -n "$attempt" ]]; then
  payload="$(echo "$payload" | jq -c --argjson v "$attempt" '. + {attempt: $v}')"
fi

if [[ -n "$request_id" ]]; then
  payload="$(echo "$payload" | jq -c --arg v "$request_id" '. + {request_id: $v}')"
fi

# ── runlog-append.sh 経由で追記 ───────────────────────────────────────────────
"${SCRIPT_DIR}/runlog-append.sh" "$session_id" "agent_decision" "$payload"
