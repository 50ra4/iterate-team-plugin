#!/usr/bin/env bash
# `.agent-os/`（Agent OS project adapter）が対象リポに未設置か、設置済みだが
# 未観測（`adapter-bootstrap.sh` 直後のスキャフォールドのまま）かを判定する
# **read-only** な検出スクリプト。`/iterate-plan` の preflight（step 0.3）が
# 「`.agent-os/` が不在/陳腐化なら `/iterate-adapt` を勧める」判断に使う。
#
# 本スクリプトは一切の書込みを行わない（自身のテストの mktemp 作業ディレクトリを
# 除く）。対象ディレクトリ・ファイルを Read するのみ。
#
# Usage:
#   adapter-check-staleness.sh --adapter <adapter_dir>
#
# <adapter_dir> は対象リポ直下の `.agent-os` ディレクトリ（絶対パス推奨。例:
# `<project_dir>/.agent-os`）。存在確認は本スクリプトが行うため、呼び出し前の
# 存在チェックは不要。
#
# 出力契約（呼び出し元は stdout の 1 行目の先頭キーワードのみを解釈する。
# 判定に exit code は使わない ── 常にキーワードを標準出力へ出す）:
#   1 行目 = `fresh` | `absent` | `stale` のいずれか 1 語で始まる。
#   `absent`/`stale` の場合は同じ行に `: <理由>` を付与する（例:
#   `stale: command-map.md に検証済みコマンドが 0 件`）。`fresh` に理由は付けない。
#
# Exit code（呼び出し元は使わないが、独立利用時のスクリプト規約として維持する）:
#   0 = fresh
#   2 = absent
#   3 = stale
#   64 = usage error（`--adapter` 未指定等。真の使用方法エラーのみこの経路を使う。
#        絶対に 10 以上の exit code で「エラー終了」して stdout のキーワード出力を
#        省略しない ── absent/stale はエラーではなく正常な判定結果である）。
#
# 判定規則（正本: operations/adapter-policy.md §2）:
#   absent: <adapter_dir> がディレクトリとして存在しない、または
#           <adapter_dir>/project-profile.md が存在しない。
#   stale:  <adapter_dir> と project-profile.md は存在するが、以下のいずれかが
#           成立する場合（スキャフォールドが「設置されたが未観測」状態）:
#             (a) project-profile.md に実質的な観測内容がない ── HTML コメント
#                 （`<!-- ... -->`）と Markdown 見出し行（`#`〜）と空行を取り除いた
#                 残りが空、または vendored スキャフォールド
#                 `<plugin_root>/vendor/agent-os/project-adapter/.agent-os/project-profile.md`
#                 と正規化後（コメント除去 + 行末空白除去 + 空行除去）で一致する。
#             (b) command-map.md が存在しない。
#             (c) command-map.md に「検証済みコマンドエントリ」が 0 件 ──
#                 HTML コメントを取り除いた残りに Markdown テーブルの
#                 データ行（先頭セルがバッククォート付きコマンドの行、例:
#                 `` | `npm test` | ... | ``）が 1 つも無い場合。または
#                 vendored スキャフォールド
#                 `<plugin_root>/vendor/agent-os/project-adapter/.agent-os/command-map.md`
#                 と正規化後で一致する場合。
#   fresh:  上記のいずれにも該当しない（project-profile.md/command-map.md に
#           観測済みの実内容がある）。
#
# <plugin_root> は本スクリプト自身の親ディレクトリの親（= `scripts/` の 1 つ上）
# として解決する（他スクリプトと同じ `ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"`
# idiom）。vendored スキャフォールドの実体を読んで比較するため、スキャフォールドの
# 内容をこのスクリプトにハードコードすることはしない。
#
# 実行環境前提: Linux / GNU coreutils（dev container・メイン checkout）。
# bash 3.2 / macOS 互換は目標外。オフラインで完結する。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAFFOLD_DIR="$ROOT/vendor/agent-os/project-adapter/.agent-os"

usage() {
  cat <<'EOF'
Usage: adapter-check-staleness.sh --adapter <adapter_dir>

Read-only detector: determine whether <adapter_dir> (a target repo's
.agent-os/ directory) is absent, stale (installed but unobserved
scaffold), or fresh (has real observed content).

Prints exactly one keyword as the first line of stdout: fresh | absent |
stale. absent/stale lines are followed by ": <reason>". Never writes
anything.

Options:
  --adapter <dir>   Target .agent-os directory to inspect (required).
  --help            Show this help text and exit.
EOF
}

ADAPTER_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --adapter)
      [[ $# -ge 2 ]] || { echo "ERROR: --adapter requires a value" >&2; usage >&2; exit 64; }
      ADAPTER_DIR="$2"
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

if [[ -z "$ADAPTER_DIR" ]]; then
  echo "ERROR: --adapter <adapter_dir> is required" >&2
  usage >&2
  exit 64
fi

# ---- HTML コメント除去（複数行コメント対応の状態機械） ----
# `<!-- ... -->` を取り除く。開始・終了タグが同一行内に収まらないケース（vendored
# スキャフォールドの説明コメントブロックはすべて複数行）にも対応するため、行を
# またいだコメント状態（incmt）を awk の状態変数として保持する。
strip_comments() {
  awk '
    BEGIN { incmt = 0 }
    {
      line = $0
      out = ""
      while (length(line) > 0) {
        if (incmt) {
          pos = index(line, "-->")
          if (pos > 0) {
            line = substr(line, pos + 3)
            incmt = 0
          } else {
            line = ""
          }
        } else {
          pos = index(line, "<!--")
          if (pos > 0) {
            out = out substr(line, 1, pos - 1)
            line = substr(line, pos + 4)
            incmt = 1
          } else {
            out = out line
            line = ""
          }
        }
      }
      print out
    }
  ' "$1"
}

# ---- 正規化（コメント除去 + 各行の行末空白除去 + 空行除去） ----
# 2 ファイル間の「実質同一（≒ near-identical）」比較に用いる。
normalize() {
  strip_comments "$1" | sed -e 's/[[:space:]]*$//' | sed '/^[[:space:]]*$/d'
}

# ---- コメント除去後、さらに Markdown 見出し行(#...)も取り除いた残り ----
# project-profile.md の「見出しだけで本文が無い」状態（= 未観測スキャフォールド）
# を検出するのに使う。
strip_comments_and_headings() {
  strip_comments "$1" | grep -Ev '^[[:space:]]*#' | sed -e 's/[[:space:]]*$//' | sed '/^[[:space:]]*$/d'
}

# ---- command-map.md の「検証済みコマンドエントリ」件数 ----
# コメント除去後の内容から、先頭セルがバッククォート付きコマンドの Markdown
# テーブルデータ行（例: `| \`npm test\` | ... |`）を数える。ベンダースキャフォールド
# ではこの形の行は「Example (delete me)」という HTML コメント内にのみ存在するため、
# コメント除去後は 0 件になる（= 素の未観測スキャフォールドは常に 0 件と判定される）。
count_command_entries() {
  # shellcheck disable=SC2016 # 正規表現内のバッククォートは Markdown の
  # コードスパン記号そのもの（コマンド置換の対象ではない）を意図した literal 文字。
  strip_comments "$1" | grep -cE '^[[:space:]]*\|[[:space:]]*`[^`]+`[[:space:]]*\|' || true
}

# ---- 1. absent 判定 ----
if [[ ! -d "$ADAPTER_DIR" ]]; then
  echo "absent: .agent-os ディレクトリが存在しない ($ADAPTER_DIR)"
  exit 2
fi

PROFILE="$ADAPTER_DIR/project-profile.md"
if [[ ! -f "$PROFILE" ]]; then
  echo "absent: project-profile.md が存在しない ($PROFILE)"
  exit 2
fi

# ---- 2. stale 判定 ----
REASONS=()

SCAFFOLD_PROFILE="$SCAFFOLD_DIR/project-profile.md"
if [[ -f "$SCAFFOLD_PROFILE" ]]; then
  if [[ "$(normalize "$PROFILE")" == "$(normalize "$SCAFFOLD_PROFILE")" ]]; then
    REASONS+=("project-profile.md がベンダースキャフォールドと同一（未観測）")
  fi
fi

if [[ ${#REASONS[@]} -eq 0 ]]; then
  BODY="$(strip_comments_and_headings "$PROFILE")"
  if [[ -z "$BODY" ]]; then
    REASONS+=("project-profile.md に実質的な観測内容がない")
  fi
fi

COMMAND_MAP="$ADAPTER_DIR/command-map.md"
if [[ ! -f "$COMMAND_MAP" ]]; then
  REASONS+=("command-map.md が存在しない")
else
  SCAFFOLD_COMMAND_MAP="$SCAFFOLD_DIR/command-map.md"
  command_map_matches_scaffold=0
  if [[ -f "$SCAFFOLD_COMMAND_MAP" ]] && [[ "$(normalize "$COMMAND_MAP")" == "$(normalize "$SCAFFOLD_COMMAND_MAP")" ]]; then
    command_map_matches_scaffold=1
  fi

  entry_count="$(count_command_entries "$COMMAND_MAP" | tr -d '[:space:]')"
  entry_count="${entry_count:-0}"

  if [[ "$command_map_matches_scaffold" -eq 1 ]]; then
    REASONS+=("command-map.md がベンダースキャフォールドと同一（検証済みコマンド 0 件）")
  elif [[ "$entry_count" -eq 0 ]]; then
    REASONS+=("command-map.md に検証済みコマンドが 0 件")
  fi
fi

if [[ ${#REASONS[@]} -gt 0 ]]; then
  joined="${REASONS[0]}"
  for ((i = 1; i < ${#REASONS[@]}; i++)); do
    joined="$joined; ${REASONS[$i]}"
  done
  echo "stale: $joined"
  exit 3
fi

# ---- 3. fresh ----
echo "fresh"
exit 0
