#!/usr/bin/env bash
# runlog の bounded read（末尾 N 行のみ取得）専用スクリプト。
#
# 旧手順（commands/iterate-retrospect.md 旧 §ステップ3）は、team-retrospector agent に
# 対象セッションごとの runlog を「`Bash tail -n 400 <runlog_path>`」という生コマンドで
# 直接読ませる指示になっていた。
#
# Usage:
#   <plugin_root>/scripts/runlog-tail.sh <session-id> [<lines>]
#
# Example:
#   <plugin_root>/scripts/runlog-tail.sh 20260507_my-topic
#   <plugin_root>/scripts/runlog-tail.sh 20260507_my-topic 200
#
# 動作:
#   `<repo_root>/.iterate-team/state/<session-id>/runlog.jsonl` の末尾 <lines> 行
#   （省略時 400）を stdout にそのまま出力する。対象ファイルが存在しない場合は
#   診断を stderr に出して exit 1 する。
#
# 設計判断: なぜ生の `tail` を settings の allow に置かず、本ラッパースクリプトを
#   個別 allowlist するか（セキュリティレビュー指摘）
#   生の `tail` を Bash allow パターンに置くと、任意のパス引数（`tail -n 1
#   ~/.ssh/id_rsa` 等）を渡すことで、Read ツールの deny 設定（機密パスの読み取り拒否）を
#   迂回して任意ファイルの内容を読み出せてしまう。本スクリプトは読み取り対象パスを
#   `<repo_root>/.iterate-team/state/<session-id>/runlog.jsonl` に固定し、<session-id> は
#   knowledge-recover.sh と同一の検証（空・'/' 含み・'..' ・許容文字集合外を拒否）を
#   適用することで、allowlist 上は「本スクリプトのパス1本 + 引数2個」のみを許可すれば
#   よい状態にする（knowledge-recover.sh / retrospect-list-sessions.sh と同一の
#   「引数検証付きラッパーを individual allowlist する」パターンを踏襲）。
#
# lines の検証: 省略時は 400。指定時は正整数（`^[1-9][0-9]*$`）であることを要求し、
#   不正な値（0 / 負数 / 非数値）は exit 1 で拒否する。上限は 10000 に固定し、
#   これを超える指定はエラーにせず 10000 にクランプする（bounded read という本スクリプト
#   の目的上、上限を超えても「読めるだけ読む」動作にしておけば呼び出し側の実害がなく、
#   拒否よりも呼び出し側の呼び出しコードを単純化できるため）。
#
# 実行環境前提: Linux / GNU coreutils（dev container・メイン checkout）。
# bash 3.2 / macOS 互換は目標外。
#
# stdout 契約: `tail -n <lines> <runlog_path>` の内容をそのまま出力する（追加の
# 装飾・ヘッダ行は一切付与しない）。
#
# Exit code:
#   0 = 正常終了
#   1 = 引数個数不正 / session-id 不正 / lines 不正 / runlog.jsonl が存在しない
#
# 仕様の正本: <plugin_root>/commands/iterate-retrospect.md ステップ3

set -euo pipefail

MAX_LINES=10000
DEFAULT_LINES=400

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <session-id> [<lines>]" >&2
  exit 1
fi

session_id="$1"
lines="${2:-$DEFAULT_LINES}"

# ---- session-id パス安全性検証（knowledge-recover.sh と完全同一） ----
if [[ -z "$session_id" ]]; then
  echo "invalid session-id: (empty)" >&2
  exit 1
fi
case "$session_id" in
  */* | *..*)
    echo "invalid session-id (must not contain '/' or '..'): $session_id" >&2
    exit 1
    ;;
esac
if [[ "$session_id" =~ [^A-Za-z0-9._-] ]]; then
  echo "invalid session-id (allowed chars: A-Za-z0-9._-): $session_id" >&2
  exit 1
fi

# ---- lines 検証 ----
if [[ ! "$lines" =~ ^[1-9][0-9]*$ ]]; then
  echo "invalid lines (must be a positive integer): $lines" >&2
  exit 1
fi
if [[ "$lines" -gt "$MAX_LINES" ]]; then
  lines="$MAX_LINES"
fi

# repo_root は対象プロジェクト基準で解決する（プラグイン自身の git root は見ない）。
# CLAUDE_PROJECT_DIR を優先し、未注入時は CWD の git root → pwd の順でフォールバックする。
# knowledge-recover.sh / runlog-append.sh と同一規約で state 先の分裂を防ぐ。
repo_root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
runlog_path="${repo_root}/.iterate-team/state/${session_id}/runlog.jsonl"

if [[ ! -f "$runlog_path" ]]; then
  echo "runlog not found: $runlog_path" >&2
  exit 1
fi

tail -n "$lines" -- "$runlog_path"
