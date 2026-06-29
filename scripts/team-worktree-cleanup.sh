#!/usr/bin/env bash
# iterate-team ハーネスの worktree クリーンアップスクリプト。
# タスク完了 + 統合ブランチへの merge 完了後、当該 worktree と
# task-branch を削除する。冪等な実装（既に削除済みなら exit 0）。
#
# Usage:
#   <plugin_root>/scripts/team-worktree-cleanup.sh <session-id> <task-id>
#
# Exit code:
#   0 = 正常 / 既に削除済み (冪等)
#   1 = 引数不正 / git worktree remove or branch -D エラー

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <session-id> <task-id>" >&2
  exit 1
fi

session_id="$1"
task_id="$2"

# バリデーション
validate_id() {
  local kind="$1"
  local val="$2"
  if ! [[ "$val" =~ ^[A-Za-z0-9_-][A-Za-z0-9._-]*$ ]]; then
    echo "INVALID_ID: ${kind}=${val}" >&2
    exit 1
  fi
  if [[ "$val" == *..* ]]; then
    echo "INVALID_ID: ${kind}=${val}" >&2
    exit 1
  fi
}

validate_id "session-id" "$session_id"
validate_id "task-id" "$task_id"

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
worktree_path="${repo_root}/.team-worktrees/${session_id}/${task_id}"
task_branch="team-task/${session_id}/${task_id}"
session_dir="${repo_root}/.team-worktrees/${session_id}"

# 1. node_modules symlink を unlink（リンク先のメイン node_modules は誤削除しない）
if [[ -L "${worktree_path}/node_modules" ]]; then
  unlink "${worktree_path}/node_modules" 2>/dev/null || true
fi

# 2. worktree 削除（存在しない場合は warning で exit 0）
if [[ -d "$worktree_path" ]]; then
  if ! git -C "$repo_root" worktree remove --force "$worktree_path" >&2; then
    echo "git worktree remove failed: ${worktree_path}" >&2
    exit 1
  fi
else
  echo "WORKTREE_NOT_FOUND: ${worktree_path}"
fi

# 3. ブランチ削除（強制削除、マージ済み判定は呼出側責務）
if git -C "$repo_root" show-ref --verify --quiet "refs/heads/${task_branch}"; then
  if ! git -C "$repo_root" branch -D "$task_branch" >&2; then
    echo "git branch -D failed: ${task_branch}" >&2
    exit 1
  fi
else
  echo "BRANCH_NOT_FOUND: ${task_branch}"
fi

# 4. 親ディレクトリが空なら削除
if [[ -d "$session_dir" ]] && [[ -z "$(ls -A "$session_dir" 2>/dev/null)" ]]; then
  rmdir "$session_dir" 2>/dev/null || true
fi

exit 0
