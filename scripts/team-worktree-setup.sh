#!/usr/bin/env bash
# iterate-team ハーネスの worktree 作成スクリプト。
# <repo-root>/.team-worktrees/<session-id>/<task-id>/ に worktree を作成し、
# ブランチ team-task/<session-id>/<task-id> を <integration-branch> から派生させる。
# node_modules はメイン worktree から symlink で共有する。
#
# Usage:
#   <plugin_root>/scripts/team-worktree-setup.sh <session-id> <task-id> <integration-branch>
#
# 出力:
#   stdout: worktree の絶対パス（1 行）
#
# Exit code:
#   0 = 正常
#   1 = 既存 worktree 衝突 / integration-branch 不在 / 引数不正 / バリデーション失敗
#   2 = git エラー

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <session-id> <task-id> <integration-branch>" >&2
  exit 1
fi

session_id="$1"
task_id="$2"
integration_branch="$3"

# session-id / task-id バリデーション（path traversal 防止）
# 先頭ドット禁止 / / 禁止 / .. 連続ドット禁止
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
# 本スクリプトは settings.sample.json で無確認 allow されるため、保護ブランチや任意ブランチを
# worktree の派生元にしないよう構造的に弾く。
case "$integration_branch" in
  claude/?*) ;;
  *) echo "INVALID_INTEGRATION_BRANCH: ${integration_branch}" >&2; exit 1 ;;
esac
if [[ "$integration_branch" == *..* ]]; then
  echo "INVALID_INTEGRATION_BRANCH: ${integration_branch}" >&2
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
worktree_path="${repo_root}/.team-worktrees/${session_id}/${task_id}"

# 既存 worktree 衝突チェック
if [[ -e "$worktree_path" ]]; then
  echo "WORKTREE_EXISTS: ${worktree_path}" >&2
  exit 1
fi

# integration-branch 存在チェック（ローカル）
if ! git -C "$repo_root" show-ref --verify --quiet "refs/heads/${integration_branch}"; then
  echo "INTEGRATION_BRANCH_NOT_FOUND: ${integration_branch}" >&2
  exit 1
fi

task_branch="team-task/${session_id}/${task_id}"

# 親ディレクトリ作成
mkdir -p "${repo_root}/.team-worktrees/${session_id}"

# worktree add（git エラーは exit 2）
if ! git -C "$repo_root" worktree add -b "$task_branch" "$worktree_path" "$integration_branch" >&2; then
  echo "git worktree add failed" >&2
  exit 2
fi

# node_modules symlink（worktree 内に node_modules がない場合のみ）
if [[ -d "${repo_root}/node_modules" && ! -e "${worktree_path}/node_modules" ]]; then
  ln -s "${repo_root}/node_modules" "${worktree_path}/node_modules"
fi

# nested node_modules symlink（packages/*/node_modules）
# ルートの node_modules シンボリックリンクだけでは npm workspaces の
# nested install（バージョン競合解決用）が worktree に引き継がれないため、
# メイン worktree 内の nested node_modules を動的に検出してリンクを貼る。
while IFS= read -r -d '' nested_nm; do
  # nested_nm の例: <repo_root>/<pkg>/node_modules
  rel_path="${nested_nm#${repo_root}/}"   # <pkg>/node_modules
  worktree_nm="${worktree_path}/${rel_path}"
  parent_dir="$(dirname "$worktree_nm")"
  if [[ ! -e "$worktree_nm" ]]; then
    mkdir -p "$parent_dir"
    ln -s "$nested_nm" "$worktree_nm"
  fi
done < <(find "${repo_root}/packages" "${repo_root}/features" \
    -maxdepth 2 -name node_modules -type d -print0 2>/dev/null)

# 結果（worktree 絶対パス）を stdout に出力
echo "$worktree_path"
