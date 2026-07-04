#!/usr/bin/env bash
# knowledge（クロスセッション自己学習）機構の lessons.jsonl 物理圧縮スクリプト。
#
# 実行環境前提: Linux / GNU coreutils（dev container・メイン checkout）。
# bash 3.2 / macOS 互換は目標外（flock は使うが macOS 固有分岐は持たない。
# ロック節のみ runlog-append.sh と同じ mkdir fallback を残す）。
#
# Usage:
#   knowledge-prune.sh --compact [--apply]
#
# Options:
#   --compact   圧縮モード（必須。他モードは未定義のため予約）
#   --apply     実書き換えを行う（未指定時は dry-run。件数と id を表示するのみ）
#
# compact 内容（knowledge-policy.md §6「物理削除」）:
#   (1) 同一 id の中間レコードを物理削除し、同一 id の中で最新 ts のレコードのみ残す
#       （最新 ts 勝ち。max_by(.ts // "")。物理行順非依存。理由は「修正5」参照）
#   (2) status=deprecated かつ初回記録（同一 id の最初のレコードの ts）から
#       90 日超のレコードを物理削除する
#
# ロックは git-tracked の knowledge/ を汚染しないよう state/ 配下に置く
# （knowledge-append.sh と同一パスを共有して相互排他する）。
#
# TOCTOU 対策: 圧縮結果の算出（lessons.jsonl の jq 読み取り）はロック取得後に行う。
# ロック取得より前に読み取ると、並走する knowledge-append.sh がその隙に追記した行が
# --apply の mv で消失しうるため（PR レビュー指摘）。ロックは dry-run 表示 / --apply の
# 書き込み・mv 完了までの一連の処理を通じて保持する。
#
# 修正4: 不正行に対する fail-closed 検証（ロック取得後・compact 算出前）
#   knowledge-digest.sh は「黙って不正行をスキップし残りで再生成する」tolerant 方式だが、
#   prune は lessons.jsonl 自体を物理的に書き換える（--apply 時に mv で原本を置換する）
#   ため、同じ tolerant 方式だと「不正行のせいで意図せず一部レコードが消えたまま
#   --apply が原本を上書きする」というデータ喪失リスクがある。そのため prune は
#   fail-closed とし、JSON としてパースできない行・object でない行が1行でもあれば
#   （dry-run / --apply 共通で）該当行番号を明示したエラーを stderr に出して exit 1 する
#   （書き換えを一切行わない）。
#
# 修正5: 同一 id の勝者選定を「最終行勝ち」から「最新 ts 勝ち」へ変更した理由
#   .gitattributes の `lessons.jsonl merge=union` はブランチ統合時に同一 id のレコードの
#   物理行順を保証しない（ours 側の行が後段の theirs 側更新より後に来る再現実験済み）。
#   そのため旧実装の `group_by(.id) | map(last)`（物理最終行勝ち）は、統合後に古い
#   レコードを正として採用してしまい、--apply がその古いレコードで新しいレコードを
#   物理削除しうる（実機再現済みの P0 バグ）。`max_by(.ts // "")` に変更することで、
#   物理行順に依存せず ts が最新のレコードを採用する（jq の max_by はタイ時に入力順で
#   後の要素を返すため、同一 ts の場合は物理順が自然なタイブレークになる。ts 欠落
#   レコードは `.ts // ""` で最劣位になる）。初回記録（first_ts。90日判定の基準）の
#   算出は本修正の対象外で、従来どおり物理先頭（group_by の安定ソート順で先頭）を使う。
#
# Exit code:
#   0 = 正常終了（dry-run 完了 / --apply 完了）
#   1 = 異常終了（lessons.jsonl 不在 / 引数不正 / path 検証失敗 /
#       不正行検出によるfail-closed中断（修正4） 等）

set -euo pipefail

readonly DEPRECATED_RETENTION_DAYS=90

COMPACT=false
APPLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --compact)
      COMPACT=true
      shift
      ;;
    --apply)
      APPLY=true
      shift
      ;;
    *)
      echo "ERROR: 不明な引数: $1" >&2
      echo "Usage: knowledge-prune.sh --compact [--apply]" >&2
      exit 1
      ;;
  esac
done

if [[ "$COMPACT" != true ]]; then
  echo "ERROR: --compact は必須です。" >&2
  echo "Usage: knowledge-prune.sh --compact [--apply]" >&2
  exit 1
fi

# repo_root は対象プロジェクト基準で解決する（runlog-append.sh と同一規約）。
repo_root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
knowledge_dir="${repo_root}/.iterate-team/knowledge"
lessons_jsonl="${knowledge_dir}/lessons.jsonl"

# ---- ガード: lessons.jsonl 不在は必ずエラー終了 ----
if [[ ! -f "$lessons_jsonl" ]]; then
  echo "ERROR: lessons.jsonl が存在しません: $lessons_jsonl" >&2
  exit 1
fi

# ---- 対象パスの妥当性検証（state-prune.sh のガード思想を踏襲） ----
# knowledge_dir の解決後実パスが「repo_root 配下の .iterate-team/knowledge」から
# 逸脱していないことを確認してから書き換える（symlink 経由の誤爆・パス逸脱防止）。
CANONICAL_KNOWLEDGE="$(realpath -m -- "${repo_root}/.iterate-team/knowledge" 2>/dev/null || echo "${repo_root}/.iterate-team/knowledge")"
RESOLVED_KNOWLEDGE="$(realpath -e -- "$knowledge_dir" 2>/dev/null || echo "")"
if [[ -z "$RESOLVED_KNOWLEDGE" || "$RESOLVED_KNOWLEDGE" != "$CANONICAL_KNOWLEDGE" ]]; then
  echo "ERROR: knowledge root が想定パスと一致しません（誤削除防止のため中断）。" >&2
  echo "  想定: $CANONICAL_KNOWLEDGE" >&2
  echo "  実際: ${RESOLVED_KNOWLEDGE:-<resolve失敗>}" >&2
  exit 1
fi

RESOLVED_LESSONS="$(realpath -e -- "$lessons_jsonl" 2>/dev/null || echo "")"
if [[ -z "$RESOLVED_LESSONS" || "$RESOLVED_LESSONS" != "$CANONICAL_KNOWLEDGE"/* ]]; then
  echo "ERROR: lessons.jsonl の解決後パスが knowledge root 配下ではありません（symlink 逸脱の疑い）。" >&2
  exit 1
fi

# ---- ロック取得（jq 読み取りより前に取得し、dry-run 表示 / --apply の書き込み・mv
#       完了までロックを保持する。TOCTOU 対策の要） ----
# knowledge-append.sh の追記ロックと同一パスを奪い合う（append 中の書き換え衝突防止）。
# ロックパスは git 除外領域の state/ 配下に置く（knowledge/ 内に .lock を残置すると
# untracked 差分として git status を汚染し誤コミットのリスクがあるため）。
lock_base_dir="${repo_root}/.iterate-team/state"
mkdir -p "$lock_base_dir"

# tmp_file・lock_dir は _cleanup から参照するため、ロック取得前に空文字で宣言しておく
# （--apply 分岐に入らない dry-run や、mkdir フォールバック未使用時でも set -u で
# 未定義変数エラーにならないようにする）。
tmp_file=""
lock_dir=""
USE_FLOCK=false

_cleanup() {
  [[ -n "$tmp_file" && -f "$tmp_file" ]] && rm -f "$tmp_file"
  if [[ "$USE_FLOCK" == true ]]; then
    flock -u 9 2>/dev/null || true
    exec 9>&- 2>/dev/null || true
  elif [[ -n "$lock_dir" ]]; then
    rmdir "$lock_dir" 2>/dev/null || true
  fi
}
trap _cleanup EXIT

if command -v flock >/dev/null 2>&1; then
  USE_FLOCK=true
  lock_file="${lock_base_dir}/knowledge-lessons.lock"
  exec 9>>"$lock_file"
  if ! flock -x -w 5 9; then
    echo "flock timeout: $lessons_jsonl" >&2
    exit 1
  fi
else
  lock_dir="${lock_base_dir}/knowledge-lessons.lock.d"
  waited=0
  until mkdir "$lock_dir" 2>/dev/null; do
    if [[ "$waited" -ge 50 ]]; then
      echo "lock timeout: $lessons_jsonl" >&2
      exit 1
    fi
    sleep 0.1
    waited=$((waited + 1))
  done
fi

# ---- 全行検証（ロック取得後・compact 算出前。fail-closed。修正4） ----
# JSON としてパースできない行、または object でない行（例: `42` 単体の行）が
# 1行でもあれば、行番号（先頭最大10件）を明示したエラーを stderr に出して中断する
# （dry-run / --apply 共通。書き換えは一切行わない）。
invalid_line_numbers_json="$(jq -R -n -c '
  [inputs] as $lines
  | [range(0; ($lines | length))
      | select(($lines[.] | (try fromjson catch null) | type) != "object")
      | . + 1]
' "$lessons_jsonl" 2>/dev/null || echo '[]')"
invalid_line_count="$(printf '%s' "$invalid_line_numbers_json" | jq 'length')"

if [[ "$invalid_line_count" -gt 0 ]]; then
  invalid_line_numbers_display="$(printf '%s' "$invalid_line_numbers_json" | jq -r '.[0:10] | join(", ")')"
  echo "ERROR: lessons.jsonl に不正な行があります（JSON としてパースできない、または object でない）。件数: ${invalid_line_count}" >&2
  echo "  行番号（先頭最大10件）: ${invalid_line_numbers_display}" >&2
  echo "  データ喪失防止のため prune を中断します（無変更。lessons.jsonl を手動で修正してください）。" >&2
  exit 1
fi

# ---- 圧縮結果の算出（ロック取得後。dry-run / --apply 共通） ----
# group_by(.id) は id 昇順の安定ソートのため、各 id グループ内の相対順序は
# 元ファイルの出現順のまま保たれる。
#   .[0]           = 初回記録（first_ts の算出に使う。物理先頭のまま。修正5の対象外）
#   max_by(.ts//"") = 最新 ts のレコード（残す対象。物理行順非依存。修正5参照）
NOW_EPOCH="$(date +%s)"
CUTOFF_SECS=$(( DEPRECATED_RETENTION_DAYS * 86400 ))

compact_summary="$(jq -s \
  --argjson now "$NOW_EPOCH" \
  --argjson cutoff "$CUTOFF_SECS" \
  '
    group_by(.id)
    | map({
        id: .[0].id,
        first_ts: .[0].ts,
        last: (max_by(.ts // ""))
      })
    | map(. + {
        first_epoch: (try (.first_ts | fromdateiso8601) catch 0)
      })
    | map(. + {
        remove: ((.last.status == "deprecated") and (($now - .first_epoch) > $cutoff))
      })
  ' "$lessons_jsonl")"

total_lines="$(jq -s 'length' "$lessons_jsonl")"
total_ids="$(printf '%s' "$compact_summary" | jq 'length')"
duplicate_lines_removed=$(( total_lines - total_ids ))

removed_ids="$(printf '%s' "$compact_summary" | jq -r '[.[] | select(.remove) | .id] | join(", ")')"
removed_count="$(printf '%s' "$compact_summary" | jq '[.[] | select(.remove)] | length')"
kept_count=$(( total_ids - removed_count ))

if [[ "$APPLY" != true ]]; then
  # ---- dry-run: 削除対象の件数と id を表示するのみ（無変更）。ロックは trap で解放される ----
  echo "=== knowledge-prune.sh --compact dry-run ==="
  echo "lessons.jsonl: $lessons_jsonl"
  echo "現在の行数: $total_lines"
  echo "重複（中間レコード）として圧縮される行数: $duplicate_lines_removed"
  echo "圧縮後に残る id 件数: $total_ids"
  if [[ "$removed_count" -eq 0 ]]; then
    echo "90日超 deprecated として物理削除される id: なし"
  else
    echo "90日超 deprecated として物理削除される id（${removed_count}件）: $removed_ids"
  fi
  echo ""
  echo "--apply を付けて再実行すると上記の圧縮・削除が反映されます（現時点では無変更）。"
  exit 0
fi

# ---- --apply: 実書き換え（tmp → mv 原子的置換。ロックは取得済みのまま維持する） ----
tmp_file="$(mktemp "${knowledge_dir}/.lessons.jsonl.XXXXXX")"
printf '%s' "$compact_summary" | jq -c '.[] | select(.remove | not) | .last' > "$tmp_file"
mv "$tmp_file" "$lessons_jsonl"
tmp_file=""

echo "=== knowledge-prune.sh --compact --apply ==="
echo "lessons.jsonl: $lessons_jsonl"
echo "圧縮前の行数: $total_lines → 圧縮後の行数: $kept_count"
if [[ "$removed_count" -eq 0 ]]; then
  echo "90日超 deprecated として物理削除した id: なし"
else
  echo "90日超 deprecated として物理削除した id（${removed_count}件）: $removed_ids"
fi
echo ""
echo "lessons.md は自動更新されません。knowledge-digest.sh を再実行してダイジェストを再生成してください。"
