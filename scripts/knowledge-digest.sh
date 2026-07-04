#!/usr/bin/env bash
# knowledge（クロスセッション自己学習）機構の lessons.md 決定的再生成スクリプト。
#
# Usage:
#   <plugin_root>/scripts/knowledge-digest.sh
#
# 動作:
#   - $REPO_ROOT/.iterate-team/knowledge/lessons.jsonl を読み、lessons.md を
#     決定的に再生成する（掲載規則は knowledge-policy.md §4 の確定値）。
#       - 同一 id は最新 ts 勝ち（物理行順非依存。max_by(.ts // "")。
#         .gitattributes の `lessons.jsonl merge=union` はブランチ統合時に同一 id の
#         行順を保証しないため、「最終行勝ち」は統合後に古いレコードを正として
#         採用してしまう実バグがあった。ts 欠落は最劣位、同一 ts はタイブレークで
#         物理順が優先される）
#       - status=active のみ掲載
#       - 選定順: confidence desc（high > medium > low） → applied_count desc → ts desc
#       - 全体最大 20 件・セクションあたり最大 8 件（全体上位 20 件を先に確定し、
#         その中からセクション振り分け後に各セクション 8 件で切る）
#       - target_agents に "*" を含むレコードは「共通（全 agent）」のみに掲載し、
#         agent 別セクションには重複掲載しない
#   - 既存 lessons.md があれば <!-- manual:start -->〜<!-- manual:end --> ブロックを
#     抽出して末尾に温存する（無ければ空の manual ブロックを生成する）
#   - lessons.jsonl が無い/空でも空セクションの骨格を生成する
#   - tmp ファイルに書いて mv で原子的に置換する
#
# 仕様の正本: <plugin_root>/operations/knowledge-policy.md（§4）

set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo "Usage: $0" >&2
  exit 1
fi

# repo_root は対象プロジェクト基準で解決する（runlog-append.sh と同一規約）。
repo_root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
knowledge_dir="${repo_root}/.iterate-team/knowledge"
lessons_jsonl="${knowledge_dir}/lessons.jsonl"
lessons_md="${knowledge_dir}/lessons.md"

mkdir -p "$knowledge_dir"

# agent 別セクションの表示順（knowledge-policy.md §4 の確定順）
# 相互参照: この5 agent 名の許容集合は knowledge-append.sh の target_agents enum 検証
# （"*" / team-planner / team-generator / team-evaluator / team-interviewer /
# team-test-coder）と二重定義になっている。追加・変更時は両スクリプトを同時に直すこと。
AGENT_SECTIONS=(team-planner team-generator team-evaluator team-interviewer team-test-coder)

# ---- 既存 manual ブロックの抽出（温存対象） ----
# 最初の <!-- manual:start --> から、その後最初に現れる <!-- manual:end --> までのみを
# 抽出する（2 個目以降の manual ブロックは無視する）。end マーカーが見つからない場合は
# 「壊れた/閉じていないブロック」とみなし、EOF までを取り込まずに空ブロックへフォール
# バックした上で stderr に警告を出す（誤って本文全体を manual 扱いにして再生成不能に
# なるのを防ぐため）。
extract_manual_block() {
  if [[ ! -f "$lessons_md" ]]; then
    return 0
  fi

  if ! grep -q '<!-- manual:start -->' "$lessons_md"; then
    return 0
  fi

  local start_line end_line
  start_line="$(grep -n -m1 '<!-- manual:start -->' "$lessons_md" | cut -d: -f1)"
  end_line="$(awk -v s="$start_line" 'NR > s && /<!-- manual:end -->/ { print NR; exit }' "$lessons_md")"

  if [[ -z "$end_line" ]]; then
    echo "knowledge-digest.sh: warning: manual:start はあるが manual:end が見つかりません。manual ブロックを空にフォールバックします。" >&2
    return 0
  fi

  sed -n "${start_line},${end_line}p" "$lessons_md"
}

manual_block="$(extract_manual_block)"
if [[ -z "$manual_block" ]]; then
  manual_block=$'<!-- manual:start -->\n<!-- manual:end -->'
fi

# ---- 全体上位 20 件プール算出（status=active、同一 id は最新 ts 勝ち） ----
# lessons.jsonl が無い/空なら空プール。
# 不正 JSON 行が混入していても、その行だけをスキップし残りは正常にダイジェスト化する
# （tolerant パース）。全体を `[]` にフォールバックすると、正常な既存レコードの digest
# までもが不正 1 行のせいで消え失せてしまうため（PR レビュー指摘）。
# tolerant パース段では `select(type == "object")` も課す。構文的に妥当な JSON だが
# object でない行（例: `42` 単体の行）は、fromjson 自体は成功してしまうため
# `fromjson? // empty` だけでは弾けず、後段の group_by(.id) 等が「オブジェクトの
# フィールドを非オブジェクトに対して参照しようとして型エラーで失敗」→
# `|| echo '[]'` により正常レコードまで含めてプール全体が空に化ける、という実バグが
# あった（実機確認済み）。select(type == "object") を通過しない行は構文エラー行と
# 同じ「malformed line」として下記の警告カウントに含める。
#
# 同一 id が複数行ある場合、`ts` が最新のレコードを採用する（`max_by(.ts // "")`）。
# 物理行順（group_by の安定ソートによる出現順）に依存する「最終行勝ち」は採用しない。
# .gitattributes の `lessons.jsonl merge=union` はブランチ統合時に同一 id の物理行順を
# 保証しないため、統合後に古いレコードが物理的に最終行へ来ることがあり、その場合
# 「最終行勝ち」だと古いレコードを誤って正として採用してしまう（実機再現済み）。
# jq の max_by はタイ時に入力順で後の要素を返すため、同一 ts の場合は物理順が自然な
# タイブレークになる。ts 欠落レコードは `.ts // ""` で最劣位になる。
if [[ -s "$lessons_jsonl" ]]; then
  total_line_count="$(wc -l < "$lessons_jsonl" | tr -d ' ')"
  valid_json_lines="$(jq -R -c '(fromjson? // empty) | select(type == "object")' "$lessons_jsonl" 2>/dev/null)"
  valid_line_count="$(printf '%s\n' "$valid_json_lines" | grep -c '.' || true)"
  valid_line_count="${valid_line_count:-0}"

  if [[ "$valid_line_count" -lt "$total_line_count" ]]; then
    echo "knowledge-digest.sh: warning: malformed line(s) skipped ($(( total_line_count - valid_line_count )) of ${total_line_count} lines in lessons.jsonl)" >&2
  fi

  pool="$(printf '%s\n' "$valid_json_lines" | jq -s '
    group_by(.id)
    | map(max_by(.ts // ""))
    | map(select(.status == "active"))
    | map(. + {_rank: (if .confidence == "high" then 3
                        elif .confidence == "medium" then 2
                        else 1 end)})
    | sort_by(._rank, (.applied_count // 0), .ts)
    | reverse
    | .[0:20]
  ' 2>/dev/null || echo '[]')"
else
  pool='[]'
fi

# ---- セクション整形ヘルパー ----
# 引数: フィルタ済み JSON 配列（jq）。1 件 1 行 "- [id] lesson" を出力する。
# 空配列なら "(なし)" の 1 行を出力する。
#
# .id / .lesson はともに gsub("[\r\n]+"; " ") で改行を空白へ潰してから連結する。
# knowledge-append.sh の入口検証（lesson/trigger の改行禁止・id の形式強制）を経由しない
# 手編集や過去データ由来の不正行が lessons.jsonl に混入していても、ここで改行を潰すことで
# セクション見出し（"## team-generator" 等）の偽造を防ぐ（append 側検証との多層防御）。
format_section() {
  local json="$1"
  local count
  count="$(printf '%s' "$json" | jq 'length')"
  if [[ "$count" -eq 0 ]]; then
    echo "(なし)"
  else
    printf '%s' "$json" | jq -r '.[] | "- [" + (.id | gsub("[\r\n]+"; " ")) + "] " + (.lesson | gsub("[\r\n]+"; " "))'
  fi
}

# 共通（"*" を含む）: セクションあたり最大 8 件
common_json="$(printf '%s' "$pool" | jq '
  [.[] | select(.target_agents | index("*") != null)] | .[0:8]
')"

# ---- tmp ファイルへ書き出し、mv で原子的置換 ----
tmp_file="$(mktemp "${knowledge_dir}/.lessons.md.XXXXXX")"
cleanup_tmp() {
  [[ -f "$tmp_file" ]] && rm -f "$tmp_file"
}
trap cleanup_tmp EXIT

{
  echo "# 知見ダイジェスト（自動生成）"
  echo ""
  echo "knowledge-digest.sh が再生成する。手編集は manual ブロック内のみ。"
  echo ""
  echo "## 共通（全 agent）"
  format_section "$common_json"
  echo ""

  for agent in "${AGENT_SECTIONS[@]}"; do
    agent_json="$(printf '%s' "$pool" | jq --arg a "$agent" '
      [.[] | select((.target_agents | index("*") == null) and (.target_agents | index($a) != null))] | .[0:8]
    ')"
    echo "## ${agent}"
    format_section "$agent_json"
    echo ""
  done

  printf '%s\n' "$manual_block"
} > "$tmp_file"

mv "$tmp_file" "$lessons_md"
trap - EXIT

echo "knowledge-digest.sh: regenerated $lessons_md"
