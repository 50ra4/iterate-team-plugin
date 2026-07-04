#!/usr/bin/env bash
# 検証付き `git switch` ラッパー。Codex レビュー第6ラウンド P1 指摘への対応。
#
# Usage:
#   <plugin_root>/scripts/git-switch-branch.sh <branch>
#
# Example:
#   <plugin_root>/scripts/git-switch-branch.sh main
#
# 動作:
#   引数を「切替先ブランチ名 <branch>」1 個のみに限定し、先頭が `-` の引数を拒否した
#   うえで `git check-ref-format --branch` によりブランチ名として妥当かを検証してから
#   `git -C <repo_root> switch <branch>` を実行する。検証成功後の `git switch` 自体の
#   失敗（未存在ブランチ・dirty worktree との衝突等）は、git の exit code と stderr を
#   そのまま呼び出し元へ伝播する（本スクリプトが握り潰さない）。
#
# 設計判断: なぜ生の `git switch "*` を settings の allow に置かず、本ラッパーを
#   個別 allowlist するか（Codex レビュー第6ラウンド P1 指摘）
#   settings.sample.json の `Bash(git switch "*)` のような「二重引用符で始まる」
#   引用符スコープの allow パターンは、シェルが引用符そのものをコマンド文字列の
#   一部として展開してから allowlist マッチングにかけるため、
#   `git switch "--discard-changes" <branch>` や `git switch "-C" <branch>` のように
#   フラグを引用符で括ってしまうと、シェル展開後の実引用符は除去され
#   `git switch --discard-changes <branch>` 等として実行されてしまい、
#   「二重引用符で始まるブランチ名だけを許可する」という allow パターンの意図（未
#   コミット変更を破棄しうるフラグの注入を防ぐ）を迂回できる。本スクリプトは
#   フラグ形（先頭 `-`）の引数をスクリプト側で拒否し、かつ `git check-ref-format
#   --branch` でブランチ名としての妥当性を検証することで、フラグ注入・ref 名偽装の
#   両方を「引用符の付け方」に依存しない形でスクリプト側に閉じ込める
#   （knowledge-recover.sh / retrospect-list-sessions.sh と同一の「引数検証付き
#   ラッパーを individual allowlist する」パターンを踏襲）。
#   `git switch -- <branch>` のような `--` 区切りは意図的に使わない（git switch は
#   `--` 区切りに対応しないバージョンが存在するため）。先頭 `-` の拒否 +
#   check-ref-format による ref 形式検証の二重チェックで十分と判断する。
#
# 実行環境前提: Linux / GNU coreutils + git（dev container・メイン checkout）。
# bash 3.2 / macOS 互換は目標外。
#
# Exit code:
#   0 = git switch 成功
#   1 = 引数不正（個数不一致 / 先頭 `-` のフラグ形 / check-ref-format 不一致）
#   その他 = git switch 自体の失敗を exit code のまま伝播

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <branch>" >&2
  exit 1
fi

branch="$1"

# フラグ注入対策: 先頭が `-` の引数を拒否する（quoted flag による allowlist 迂回
# 対策。ヘッダコメント「設計判断」参照）。
case "$branch" in
  -*)
    echo "invalid branch (must not start with '-': looks like a flag, not a branch name): $branch" >&2
    exit 1
    ;;
esac

if ! git check-ref-format --branch "$branch" >/dev/null 2>&1; then
  echo "invalid branch (not a valid git ref name): $branch" >&2
  exit 1
fi

# repo_root は対象プロジェクト基準で解決する（プラグイン自身の git root は見ない）。
# CLAUDE_PROJECT_DIR を優先し、未注入時は CWD の git root → pwd の順でフォールバックする。
# knowledge-recover.sh / retrospect-list-sessions.sh と同一規約。
repo_root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# git switch 自体の失敗（未存在ブランチ・dirty worktree との衝突等）は、git の
# exit code と stderr をそのまま呼び出し元へ伝播する（本スクリプトは握り潰さない）。
git -C "$repo_root" switch "$branch"
