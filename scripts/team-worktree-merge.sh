#!/usr/bin/env bash
# iterate-team ハーネスの worktree merge スクリプト。
# wave 完了後、メイン worktree の <integration-branch> へ
# team-task/<session-id>/<task-id> ブランチを `git merge --no-ff` で取り込む。
# コンフリクト発生時は --abort して競合ファイル一覧を stderr に出す。
#
# Usage:
#   <plugin_root>/scripts/team-worktree-merge.sh <session-id> <task-id> <integration-branch>
#
# Exit code:
#   0 = マージ成功 / 既にマージ済み (冪等)
#   1 = コンフリクト / ブランチ不在 / 引数不正
#   2 = git エラー

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <session-id> <task-id> <integration-branch>" >&2
  exit 1
fi

session_id="$1"
task_id="$2"
integration_branch="$3"

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

# integration-branch はハーネスの統合ブランチ claude/* に限定する（main/master/任意ブランチを拒否）。
# 本スクリプトは settings.sample.json で無確認 allow されるため、状態復元ミスや prompt 注入で
# 第3引数が保護ブランチになっても checkout / merge --no-ff で書き換えないよう構造的に弾く。
case "$integration_branch" in
  claude/?*) ;;
  *) echo "INVALID_INTEGRATION_BRANCH: ${integration_branch}" >&2; exit 1 ;;
esac
if [[ "$integration_branch" == *..* ]]; then
  echo "INVALID_INTEGRATION_BRANCH: ${integration_branch}" >&2
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
task_branch="team-task/${session_id}/${task_id}"

# integration-branch 存在確認
if ! git -C "$repo_root" show-ref --verify --quiet "refs/heads/${integration_branch}"; then
  echo "INTEGRATION_BRANCH_NOT_FOUND: ${integration_branch}" >&2
  exit 1
fi

# task-branch 存在確認
if ! git -C "$repo_root" show-ref --verify --quiet "refs/heads/${task_branch}"; then
  echo "BRANCH_NOT_FOUND: ${task_branch}" >&2
  exit 1
fi

# 冪等性: 既に merge 済みなら何もしない
if git -C "$repo_root" merge-base --is-ancestor "$task_branch" "$integration_branch" 2>/dev/null; then
  echo "ALREADY_MERGED: ${task_id}"
  exit 0
fi

# 統合ブランチに HEAD を切り替える（メイン worktree でのみ実行）
current_branch=$(git -C "$repo_root" symbolic-ref --short HEAD 2>/dev/null || echo "")
if [[ "$current_branch" != "$integration_branch" ]]; then
  if ! git -C "$repo_root" checkout "$integration_branch" >&2; then
    echo "git checkout failed" >&2
    exit 2
  fi
fi

# merge --no-ff
merge_msg="merge: ${task_id} を統合ブランチへ取り込み

iterate-team wave 並列実装で ${task_branch} ブランチで
作成された変更を ${integration_branch} に統合する。

Refs: ${task_id}"

if git -C "$repo_root" merge --no-ff "$task_branch" -m "$merge_msg" >&2; then
  echo "MERGED: ${task_id} -> ${integration_branch}"
  exit 0
fi

# コンフリクト発生時
conflict_files=$(git -C "$repo_root" diff --name-only --diff-filter=U 2>/dev/null || true)
git -C "$repo_root" merge --abort 2>/dev/null || true
echo "CONFLICT: ${task_id}" >&2
if [[ -n "$conflict_files" ]]; then
  echo "$conflict_files" >&2
fi
exit 1
