#!/usr/bin/env bash
# /iterate-retrospect fail-open（コミット 0 件だった retro ブランチの削除）専用スクリプト。
#
# Usage:
#   <plugin_root>/scripts/retrospect-delete-branch.sh <retro-branch>
#
# Example:
#   <plugin_root>/scripts/retrospect-delete-branch.sh claude/knowledge-retrospect-20260704
#
# 動作:
#   引数を「削除対象ブランチ名 <retro-branch>」1 個のみに限定し、
#   `^claude/knowledge-retrospect-[A-Za-z0-9._-]+$` に完全一致しない場合は非ゼロ終了で
#   拒否する。一致する場合のみ `git -C <repo_root> branch -D <retro-branch>` を実行する。
#   検証成功後の `git branch -D` 自体の失敗（未存在ブランチ等）は、git の exit code と
#   stderr をそのまま呼び出し元へ伝播する（本スクリプトが握り潰さない）。
#
# 設計判断: なぜ生の `git branch -D claude/knowledge-retrospect-*` を settings の
#   allow に置かず、本ラッパーを個別 allowlist するか（Codex レビュー第6ラウンド
#   P1 指摘）
#   settings.sample.json の `Bash(git branch -D claude/knowledge-retrospect-*)` の
#   ような末尾ワイルドカードの allow パターンは、「コマンド文字列がこのパターンで
#   前方一致するか」だけを見るため、`git branch -D claude/knowledge-retrospect-x main`
#   のように許可パターンにマッチする引数の後ろへ余剰引数（他ブランチ名）を追加注入
#   できてしまい、`git branch -D` が可変長引数を取る性質上、対象外の任意ブランチ
#   （例では main）も同時に削除されてしまう。本スクリプトは引数をちょうど 1 個に
#   限定し、かつその 1 個が retro ブランチの命名規則に完全一致することを要求する
#   ことで、余剰引数注入・対象外ブランチ削除を構造的に排除する
#   （knowledge-recover.sh / retrospect-list-sessions.sh / git-switch-branch.sh と同一の
#   「引数検証付きラッパーを individual allowlist する」パターンを踏襲）。
#
# 実行環境前提: Linux / GNU coreutils + git（dev container・メイン checkout）。
# bash 3.2 / macOS 互換は目標外。
#
# Exit code:
#   0 = git branch -D 成功
#   1 = 引数不正（個数不一致 / retro ブランチ命名規則に不一致）
#   その他 = git branch -D 自体の失敗を exit code のまま伝播

set -euo pipefail

RETRO_BRANCH_PATTERN='^claude/knowledge-retrospect-[A-Za-z0-9._-]+$'

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <retro-branch>" >&2
  exit 1
fi

branch="$1"

if [[ ! "$branch" =~ $RETRO_BRANCH_PATTERN ]]; then
  echo "invalid branch (must match ${RETRO_BRANCH_PATTERN}): $branch" >&2
  exit 1
fi

# repo_root は対象プロジェクト基準で解決する（プラグイン自身の git root は見ない）。
# CLAUDE_PROJECT_DIR を優先し、未注入時は CWD の git root → pwd の順でフォールバックする。
# knowledge-recover.sh / retrospect-list-sessions.sh と同一規約。
repo_root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# git branch -D 自体の失敗（未存在ブランチ等）は、git の exit code と stderr を
# そのまま呼び出し元へ伝播する（本スクリプトは握り潰さない）。
git -C "$repo_root" branch -D "$branch"
