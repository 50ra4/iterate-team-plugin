#!/usr/bin/env bash
# /iterate-retrospect ステップ1（対象セッション列挙）専用スクリプト。
#
# 旧手順（commands/iterate-retrospect.md 旧 §ステップ1）は以下の生パイプラインを
# Orchestrator に直接実行させていた:
#
#   find .iterate-team/state -mindepth 1 -maxdepth 1 -type d -name 'retro_*' -prune \
#       -o -mindepth 1 -maxdepth 1 -type d -print \
#     | while read -r d; do
#         [[ -f "$d/runlog.jsonl" ]] && printf '%s\t%s\n' \
#           "$(stat -c %Y "$d/runlog.jsonl" 2>/dev/null || echo 0)" "${d##*/}"
#       done \
#     | sort -rn | cut -f2- | head -n "<N>"
#
# 本スクリプトはこの生パイプラインと同一の意味論（runlog.jsonl を持つディレクトリのみ
# 対象、runlog.jsonl の mtime 降順）を、allowlist 迂回を防ぐラッパーとして実装する。
#
# Usage:
#   <plugin_root>/scripts/retrospect-list-sessions.sh <N>
#
# Example:
#   <plugin_root>/scripts/retrospect-list-sessions.sh 10
#
# 動作:
#   `<repo_root>/.iterate-team/state/` 直下のディレクトリのうち、`retro_*`（本コマンド
#   自身が生成する retro 用ディレクトリ）を除外し、かつ直下に `runlog.jsonl` を持つ
#   ものだけを対象とする（`runlog.jsonl` が実在しないディレクトリは「ハーネスセッション
#   ディレクトリ」とみなさない。後段の `runlog-tail.sh <session_id>` が runlog 不在で
#   exit 1 になることを防ぐ）。ソートキーは `runlog.jsonl` 自体の mtime（ディレクトリ
#   自体の mtime ではない。runlog への追記で更新される = セッションの実活動順になる）
#   で降順に並べ、先頭から <N> 件のディレクトリ名（= セッション id）のみを 1 行 1 件で
#   stdout に出力する（旧パイプライン（commands/iterate-retrospect.md 旧版で
#   Orchestrator に直接実行させていた find/stat/sort パイプライン）と同一の意味論）。
#   `.iterate-team/state/` が存在しない場合、または対象ディレクトリ（runlog.jsonl を
#   持つもの）が 0 件の場合は何も出力せず exit 0 とする（呼び出し側が「0 件」を
#   検出できるようにする）。
#
# 設計判断: なぜ生の `find` を settings の allow に置かず、本ラッパースクリプトを
#   個別 allowlist するか（セキュリティレビュー指摘）
#   生の `find` を Bash allow パターンに置くと、`-exec` / `-delete` などの副作用オプションや、
#   任意のパス引数（`find / -name ...` 等）を渡すことで allowlist の意図（state/ 配下の
#   ディレクトリ列挙に限定する）を迂回できてしまう。本スクリプトは引数を「分析対象件数
#   <N>（正整数）」1 個のみに限定し、列挙対象パスを `<repo_root>/.iterate-team/state/`
#   に固定したうえで内部的にのみ `find` を呼ぶことで、allowlist 上は本スクリプトの
#   パス1本だけを許可すればよい状態にする（knowledge-recover.sh / runlog-tail.sh と
#   同一の「引数検証付きラッパーを individual allowlist する」パターンを踏襲）。
#
# 実装上の注意: ディレクトリ名がスペース・タブ等を含む場合でも安全に扱うため、
#   `find -print0` の NUL 区切りでディレクトリ一覧を取得する（改行を含む名前は
#   運用上想定しないため、mtime との組（内部的にはタブ区切り1行）で sort する）。
#
# 実行環境前提: Linux / GNU coreutils（dev container・メイン checkout）。
# bash 3.2 / macOS 互換は目標外。
#
# stdout 契約: 採用されたセッション id を runlog.jsonl の mtime 降順で 1 行 1 件出力する。
# 0 件の場合は何も出力しない。
#
# Exit code:
#   0 = 正常終了（0 件を含む）
#   1 = 引数不正（N が `^[1-9][0-9]*$` に一致しない、または引数個数が 1 個でない）
#
# 仕様の正本: <plugin_root>/commands/iterate-retrospect.md ステップ1

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <N>" >&2
  exit 1
fi

n="$1"

if [[ ! "$n" =~ ^[1-9][0-9]*$ ]]; then
  echo "Usage: $0 <N>" >&2
  echo "invalid N (must be a positive integer): $n" >&2
  exit 1
fi

# repo_root は対象プロジェクト基準で解決する（プラグイン自身の git root は見ない）。
# CLAUDE_PROJECT_DIR を優先し、未注入時は CWD の git root → pwd の順でフォールバックする。
# knowledge-recover.sh / runlog-append.sh と同一規約で state 先の分裂を防ぐ。
repo_root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
state_root="${repo_root}/.iterate-team/state"

if [[ ! -d "$state_root" ]]; then
  exit 0
fi

# ディレクトリ名（NUL 区切りで安全に取得） + runlog.jsonl の mtime（タブ区切り）の
# 一覧を作り、runlog.jsonl の mtime 降順で並べる。`retro_*` および直下に runlog.jsonl
# を持たないディレクトリはこの時点で除外する。ここまでは command substitution 内で
# 完結させ、`sort`/`cut` の出力を pipe 経由で `head` に渡すことを避ける
# （`sort ... | head -n N` のように pipefail 下で消費側が途中終了すると、書き込み側が
# SIGPIPE を受けて非ゼロ終了し、`set -e` によりスクリプト全体が異常終了しうるため。
# 先頭 N 件の切り出しは末尾で bash 配列スライスにより行う）。
sorted="$(
  while IFS= read -r -d '' dir; do
    name="${dir##*/}"
    case "$name" in
      retro_*) continue ;;
    esac
    runlog_path="${dir}/runlog.jsonl"
    [[ -f "$runlog_path" ]] || continue
    mtime="$(stat -c '%Y' "$runlog_path" 2>/dev/null || echo 0)"
    printf '%s\t%s\n' "$mtime" "$name"
  done < <(find "$state_root" -mindepth 1 -maxdepth 1 -type d -print0) \
    | sort -t $'\t' -k1,1rn | cut -f2-
)"

if [[ -z "$sorted" ]]; then
  exit 0
fi

mapfile -t lines_arr <<< "$sorted"
printf '%s\n' "${lines_arr[@]:0:$n}"

exit 0
