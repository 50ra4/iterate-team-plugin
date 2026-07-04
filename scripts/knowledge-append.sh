#!/usr/bin/env bash
# knowledge（クロスセッション自己学習）機構のレッスンレコード追記用スクリプト。
# team-retrospector agent が本スクリプトを 1 行で呼び出すことで、
# Write ツール経由の JSON 構築を context から排除する（runlog-append.sh と同じ狙い）。
#
# Usage:
#   <plugin_root>/scripts/knowledge-append.sh <lesson-record-json>
#
# Example:
#   <plugin_root>/scripts/knowledge-append.sh '{"category":"review","target_agents":["team-planner"],"trigger":"...","lesson":"...","evidence":[{"session_id":"s1","event":"..."}],"status":"active","source":"auto-retrospective"}'
#
# 動作:
#   - 必須キー / enum を jq で検証し、不正なら非 0 終了 + stderr に理由を出力する
#       - lesson は 200 字以内（knowledge-policy.md §3）
#       - target_agents の各要素は "*" / team-planner / team-generator / team-evaluator /
#         team-interviewer / team-test-coder のいずれか（knowledge-digest.sh の
#         AGENT_SECTIONS と二重定義。typo は「記録されるが digest に出ない」罠になるため）
#       - evidence の各要素は session_id / event を持つオブジェクト
#       - lesson / trigger に "<!-- manual:" を含めることは禁止（digest の manual ブロック
#         抽出を壊すため）
#   - 全検証成功後、$REPO_ROOT/.iterate-team/knowledge/ を冪等 seed する（検証前に seed
#     すると、拒否レコードが untracked な .gitattributes 等を残し fail-open 後も作業ツリーが
#     dirty のままになるため、seed は検証の後段に置く）
#       - knowledge/ , knowledge/proposals/ を mkdir -p
#       - knowledge/.gitattributes に "lessons.jsonl merge=union" 行を（無ければ）追記
#       - knowledge/.gitignore に "lessons.md" 行を（無ければ）追記（lessons.md を
#         git 管理外にする。設計判断参照）
#   - id / confidence / applied_count / merged_into / last_applied_ts を補完する。
#     ts は補完ではなく常にスクリプト側の現在時刻で上書きする（呼び出し元が指定した
#     ts は常に無視する。拒否ではなく上書き。理由は「設計判断: ts 上書き」参照）
#   - $REPO_ROOT/.iterate-team/knowledge/lessons.jsonl へ 1 行 JSON（compact）で
#     flock append する（runlog-append.sh のロック節を踏襲。macOS は mkdir ロック fallback）
#   - ロックは git-tracked の knowledge/ を汚染しないよう state/ 配下に置く
#     （残置された .lock が untracked 差分としてステップ 6.7 の差分判定を誤発火させるため）
#   - 標準出力に最終的な id（生成分含む）を出力する（呼び出し元が受け取る）
#
# 設計判断: ts は呼び出し元指定を常に無視し、スクリプト側の現在時刻で上書きする
#   （Codex レビュー第6ラウンド P1 指摘）。knowledge-digest.sh / knowledge-prune.sh は
#   同一 id が複数行存在する場合の勝者選定を「物理行順」から「最新 ts 勝ち
#   （max_by(.ts // "")）」に変更済み（knowledge-prune.sh 修正5）。この規則の下で
#   旧実装（`.ts = (.ts // $ts_now)`）が呼び出し元指定の ts を温存すると、
#   retrospector が既存レコードを更新（applied_count 加算・status=deprecated 化等）
#   する際に旧 ts をそのまま再掲した更新後レコードを append した場合、旧レコードと
#   新レコードが同一 ts の「タイ」になる。jq の max_by はタイ時に入力順で後の要素を
#   返す仕様だが、prune の merge=union 統合後は複数ブランチの物理結合順が保証されず、
#   タイの場合に古い（更新前の）レコードが「後の要素」として勝ち残り得る
#   （deprecated 化の復活・applied_count 更新の喪失）。ts を常にスクリプト側で
#   採番することで、同一内容の再 append でも ts が必ず単調に新しくなり、
#   「最新 ts 勝ち」規則が意図通り機能する。拒否ではなく上書きなのは、
#   retrospector 側の「既存レコードの全フィールドを再構築して append する」更新
#   フロー自体を壊さないため（呼び出し元が ts を省略する必要がなくなる）。
#   なお id の `.id = (.id // $id_candidate)` は更新時に呼び出し元が指定した既存 id を
#   温存する必要があるため（同一レコードの更新であることを示す唯一の鍵）、現行のまま
#   変更しない。
#
# 設計判断: lessons.md を git 管理外にする（Codex レビュー第7ラウンド P1 指摘・実機再現済み）。
#   同一 base から並走した 2 セッションがそれぞれ append + digest + commit すると、
#   lessons.jsonl は .gitattributes の `merge=union` により無競合で統合できるが、
#   決定的に再生成される派生物である lessons.md は両ブランチが独立に新規生成するため
#   マージ時に add/add 競合（新規ファイルの衝突は union merge driver が効かない）を起こし、
#   ハーネスの自動マージを構造的に塞いでいた。lessons.jsonl を正本、lessons.md をその
#   決定的な派生ビュー（knowledge-digest.sh がいつでも再生成可能）と位置づけ、派生物を
#   git 追跡から外すことで並走マージの競合点そのものを除去する。merge=union は
#   lessons.jsonl のみに効く設定であり、lessons.md 側の競合は解決しないため、
#   「管理しない」以外の対策では並走セッション数が増えるほど衝突頻度が増す構造的問題を
#   解消できない。
#
# 仕様の正本: <plugin_root>/operations/knowledge-policy.md（§3・§11）

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <lesson-record-json>" >&2
  exit 1
fi

payload="$1"

# JSON 妥当性チェック
if ! echo "$payload" | jq empty >/dev/null 2>&1; then
  echo "invalid JSON payload: $payload" >&2
  exit 1
fi

# repo_root は対象プロジェクト基準で解決する（プラグイン自身の git root は見ない）。
# CLAUDE_PROJECT_DIR を優先し、未注入時は CWD の git root → pwd の順でフォールバックする。
# runlog-append.sh / session-start.sh と同一規約で state 先の分裂を防ぐ。
repo_root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
knowledge_dir="${repo_root}/.iterate-team/knowledge"
lessons_file="${knowledge_dir}/lessons.jsonl"
gitattributes_file="${knowledge_dir}/.gitattributes"
gitignore_file="${knowledge_dir}/.gitignore"

# ---- 検証ヘルパー ----
# 与えた jq 式が真を返さない場合、理由を stderr に出して非 0 終了する。
fail() {
  echo "knowledge-append: invalid lesson record: $1" >&2
  exit 1
}

check() {
  local expr="$1" msg="$2"
  if ! printf '%s' "$payload" | jq -e "$expr" >/dev/null 2>&1; then
    fail "$msg"
  fi
}

# 必須キー検証
check 'has("category")' "category is required"
check '.category as $c | ["plan","impl","test","review","acceptance","env","process"] | index($c) != null' \
  "category must be one of plan/impl/test/review/acceptance/env/process"

check 'has("target_agents") and (.target_agents | type == "array") and (.target_agents | length > 0)' \
  "target_agents must be a non-empty array"

# target_agents の各要素は "*" または注入対象 5 agent のいずれかに限定する。
# 相互参照: この許容集合は knowledge-digest.sh の AGENT_SECTIONS と二重定義になっている
# （knowledge-policy.md §7 の注入対象 5 agent + 共通 "*"）。typo した値は検証をすり抜けると
# 「記録はされるが digest に永遠に表示されない」罠になるため、ここで enum 検証する。
check '(.target_agents | all(. as $a | ["*","team-planner","team-generator","team-evaluator","team-interviewer","team-test-coder"] | index($a) != null))' \
  'target_agents elements must each be one of "*"/team-planner/team-generator/team-evaluator/team-interviewer/team-test-coder'

check 'has("trigger") and (.trigger | type == "string") and (.trigger | length > 0)' \
  "trigger is required (non-empty string)"

check 'has("lesson") and (.lesson | type == "string") and (.lesson | length > 0)' \
  "lesson is required (non-empty string)"

# lesson は命令形の教訓文 200 字以内（knowledge-policy.md §3）。jq の length は
# 文字列に対しコードポイント数（=字数）を返す。
check '(.lesson | length) <= 200' \
  "lesson must be 200 characters or fewer"

check 'has("evidence") and (.evidence | type == "array") and (.evidence | length > 0)' \
  "evidence must be a non-empty array"

# evidence の各要素は {"session_id":"...","event":"..."} 形式のオブジェクトに限定する
# （knowledge-policy.md §3。文字列や配列など他の型は digest 側の想定外構造になるため拒否）。
check '(.evidence | all(. as $e | ($e | type) == "object" and ($e | has("session_id")) and ($e | has("event"))))' \
  "evidence elements must be objects with session_id and event keys"

# lesson / trigger に manual ブロックのマーカー文字列を混入させることを禁止する。
# knowledge-digest.sh の manual ブロック抽出は <!-- manual:start --> 〜 <!-- manual:end -->
# をテキスト全体から検索するため、レコード側にこの文字列が混入すると抽出ロジックを
# 壊す（意図しない範囲を manual ブロックとして温存/破棄してしまう）。
check '((.lesson | test("<!-- manual:") | not) and (.trigger | test("<!-- manual:") | not))' \
  'lesson/trigger must not contain the literal string "<!-- manual:" (would break digest manual-block extraction)'

# lesson / trigger に改行(\n / \r)を含めることを禁止する。knowledge-digest.sh の
# format_section は `jq -r '"- [" + .id + "] " + .lesson'` で 1 行 raw 出力するため、
# lesson/trigger に改行を含むレコードが受理されると、改行以降の文字列が独立した行として
# 描画されてしまい "## team-generator" 等の別 agent セクション見出しを偽造できる
# （PR レビュー指摘: セクション偽造による対象外 agent への永続注入）。
check '((.lesson | test("[\\r\\n]") | not) and (.trigger | test("[\\r\\n]") | not))' \
  'lesson/trigger must not contain newline characters (\n or \r): digest renders them raw on a single line, so a newline is a section-forgery vector'

check 'has("status")' "status is required"
check '.status as $s | ["active","deprecated","merged"] | index($s) != null' \
  "status must be one of active/deprecated/merged"

check 'has("source")' "source is required"
check '.source as $s | ["auto-retrospective","deep-retrospect","manual"] | index($s) != null' \
  "source must be one of auto-retrospective/deep-retrospect/manual"

# confidence は任意。指定時のみ enum 検証（未指定時は "low" を補完する）。
check '(has("confidence") | not) or (.confidence as $c | ["low","medium","high"] | index($c) != null)' \
  "confidence must be one of low/medium/high when specified"

# id を呼び出し元が指定した場合、knowledge-policy.md §3 の id 形式
# L-<YYYYMMDDTHHmm>-<4hex> を強制する（不一致は拒否）。id も digest の
# "- [" + .id + "] " 描画にそのまま使われるため、不正な id（改行や "]" 等を含む文字列）は
# lesson/trigger と同じセクション偽造・行フォーマット破壊のベクトルになる
# （PR レビュー指摘: 入口側での多層防御）。
check '(has("id") | not) or (.id | test("^L-[0-9]{8}T[0-9]{4}-[0-9a-f]{4}$"))' \
  'id, when specified by the caller, must match ^L-<YYYYMMDDTHHmm>-<4hex>$ (knowledge-policy.md §3)'

# merged_into が非 null で指定された場合も、id と同一形式を強制する
# （status=merged 時の統合先 id。knowledge-policy.md §3）。
check '((has("merged_into") | not) or (.merged_into == null) or (.merged_into | test("^L-[0-9]{8}T[0-9]{4}-[0-9a-f]{4}$")))' \
  'merged_into, when non-null, must match the same id format ^L-<YYYYMMDDTHHmm>-<4hex>$'

# ---- 冪等 seed（knowledge/・proposals/・.gitattributes） ----
# seed は全 check 検証成功後に行う。検証拒否されたレコードが untracked の .gitattributes
# 等を残すと、fresh リポジトリで fail-open 後も作業ツリーが dirty のままになり後続
# preflight（clean-tree ガード）を汚染するため（不正入力は副作用ゼロで拒否する）。
# knowledge/ は git-tracked 資産（state/ と異なり exclude しない。knowledge-policy.md §2）。
mkdir -p "$knowledge_dir" "${knowledge_dir}/proposals"

GITATTR_LINE="lessons.jsonl merge=union"
if [[ ! -f "$gitattributes_file" ]] || ! grep -qxF "$GITATTR_LINE" "$gitattributes_file" 2>/dev/null; then
  # 既存ファイルが改行で終わっていない場合、追記行が直前の行と連結されてしまわないよう
  # 先に改行を足す（session-start.sh の ensure_state_ignored と同じ末尾改行ガード）。
  if [[ -s "$gitattributes_file" ]] && [[ -n "$(tail -c1 "$gitattributes_file" 2>/dev/null)" ]]; then
    printf '\n' >> "$gitattributes_file"
  fi
  echo "$GITATTR_LINE" >> "$gitattributes_file"
fi

# lessons.md（knowledge-digest.sh が決定的に再生成する派生物）を git 管理外にする。
# 並走セッションの digest add/add 競合を構造的に防止するための設計判断（ヘッダの
# 「設計判断: lessons.md を git 管理外にする」参照）。merge=union は lessons.jsonl
# のみに効くため、lessons.md 自体を untracked にする以外に競合を解消する手段がない。
GITIGNORE_LINE="lessons.md"
if [[ ! -f "$gitignore_file" ]] || ! grep -qxF "$GITIGNORE_LINE" "$gitignore_file" 2>/dev/null; then
  # .gitattributes と同じ末尾改行ガード。
  if [[ -s "$gitignore_file" ]] && [[ -n "$(tail -c1 "$gitignore_file" 2>/dev/null)" ]]; then
    printf '\n' >> "$gitignore_file"
  fi
  echo "$GITIGNORE_LINE" >> "$gitignore_file"
fi

# ---- フィールド補完 ----
# id 未指定なら L-<YYYYMMDDTHHmm(UTC)>-<4hex乱数> を生成する（並走セッション衝突回避のため
# 時刻 + 乱数 4hex を用いる。knowledge-policy.md §3 の id 形式に準拠）。
gen_hex4() {
  if [[ -r /dev/urandom ]]; then
    head -c2 /dev/urandom | od -An -tx1 | tr -d ' \n'
  else
    printf '%04x' "$((RANDOM % 65536))"
  fi
}

id_candidate="L-$(date -u +%Y%m%dT%H%M)-$(gen_hex4)"
ts_now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

final_record="$(printf '%s' "$payload" | jq -c \
  --arg id_candidate "$id_candidate" \
  --arg ts_now "$ts_now" \
  '
    .id = (.id // $id_candidate)
  | .ts = $ts_now
  | .confidence = (.confidence // "low")
  | .applied_count = (.applied_count // 0)
  | .merged_into = (.merged_into // null)
  | .last_applied_ts = (.last_applied_ts // null)
  '
)"

final_id="$(printf '%s' "$final_record" | jq -r '.id')"

# ---- 排他ロック付き追記（runlog-append.sh のロック節と同一方式） ----
_locked_append() {
  printf '%s\n' "$final_record" >> "$lessons_file"
}

# ロックパスは git 除外領域の state/ 配下に置く（knowledge/ 内に .lock を残置すると
# untracked 差分として git status を汚染し誤コミットのリスクがあるため）。
# knowledge-prune.sh と同一パスを共有し、append と prune の相互排他を成立させる。
lock_base_dir="${repo_root}/.iterate-team/state"
mkdir -p "$lock_base_dir"

# 並列 append 安全化: flock（Linux）または mkdir（macOS ホスト）で排他ロックを取得後に追記する。
if command -v flock >/dev/null 2>&1; then
  lock_file="${lock_base_dir}/knowledge-lessons.lock"
  exec 9>>"$lock_file"
  if ! flock -x -w 5 9; then
    echo "flock timeout: $lessons_file" >&2
    exit 1
  fi
  _locked_append
  flock -u 9
  exec 9>&-
else
  # flock 非搭載（macOS ホスト）: mkdir の原子性を利用したポータブルな排他制御。
  lock_dir="${lock_base_dir}/knowledge-lessons.lock.d"
  waited=0
  until mkdir "$lock_dir" 2>/dev/null; do
    if [[ "$waited" -ge 50 ]]; then
      echo "lock timeout: $lessons_file" >&2
      exit 1
    fi
    sleep 0.1
    waited=$((waited + 1))
  done
  trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT
  _locked_append
  rmdir "$lock_dir" 2>/dev/null || true
  trap - EXIT
fi

# 生成/確定した id を呼び出し元へ返す
echo "$final_id"
