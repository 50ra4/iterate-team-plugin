#!/usr/bin/env bash
# knowledge-digest.sh の単体テスト
#
# 実行環境前提: Linux / GNU coreutils + jq + git（dev container・メイン checkout）。
# bash 3.2 / macOS 互換は目標外。
#
# 仕様の正本: <plugin_root>/operations/knowledge-policy.md（§4）
#
# Usage:
#   bash scripts/__tests__/knowledge-digest.test.sh
#
# Exit code:
#   0 = 全ケース pass
#   1 = いずれか fail

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${SCRIPT_DIR}/../knowledge-digest.sh"

if [[ ! -f "$TARGET" ]]; then
  echo "knowledge-digest.sh not found at: $TARGET" >&2
  exit 1
fi

pass_count=0
fail_count=0
case_count=0

# ---- アサーション helpers ----

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $label (=$actual)"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL: $label (expected='$expected' actual='$actual')" >&2
    fail_count=$((fail_count + 1))
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  PASS: $label (contains '$needle')"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL: $label (needle='$needle' haystack='${haystack:0:500}...')" >&2
    fail_count=$((fail_count + 1))
  fi
}

assert_not_contains() {
  local label="$1" needle="$2" haystack="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "  PASS: $label (does not contain '$needle')"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL: $label (unexpectedly contains '$needle')" >&2
    fail_count=$((fail_count + 1))
  fi
}

# ---- ケース実行ヘルパー ----
run_case() {
  local label="$1"
  case_count=$((case_count + 1))
  echo ""
  echo "[Case $case_count] $label"
}

# ---- グローバルクリーンアップ ----
TMPDIR_GLOBAL=""
cleanup_global() {
  if [[ -n "${TMPDIR_GLOBAL:-}" && -d "${TMPDIR_GLOBAL:-}" ]]; then
    rm -rf "$TMPDIR_GLOBAL"
  fi
}
trap cleanup_global EXIT
TMPDIR_GLOBAL="$(mktemp -d)"

# ---- フィクスチャ: 隔離 git リポジトリ生成 ----
make_isolated_repo() {
  local tmpdir
  tmpdir="$(mktemp -d "$TMPDIR_GLOBAL/repo.XXXXXX")"
  git init -q "$tmpdir"
  echo "$tmpdir"
}

# ---- フィクスチャ: 1 レコードを jsonl 形式で組み立てる ----
make_record() {
  local id="$1" confidence="$2" applied_count="$3" ts="$4" status="$5" \
        target_agents_json="$6" lesson="$7"
  jq -nc \
    --arg id "$id" \
    --arg confidence "$confidence" \
    --argjson applied_count "$applied_count" \
    --arg ts "$ts" \
    --arg status "$status" \
    --argjson target_agents "$target_agents_json" \
    --arg lesson "$lesson" \
    '{
      id: $id, ts: $ts, session_id: "s1", source: "manual", category: "impl",
      target_agents: $target_agents, trigger: "t", lesson: $lesson,
      evidence: [{session_id:"s1", event:"e"}], status: $status,
      merged_into: null, confidence: $confidence, applied_count: $applied_count,
      last_applied_ts: null
    }'
}

# ========== T1: lessons.jsonl 不在時に空セクションの骨格を生成する ==========
run_case "T1: lessons.jsonl 不在時にも lessons.md の骨格（全セクション見出し + manual ブロック）が生成される"

T1_REPO="$(make_isolated_repo)"

set +e
CLAUDE_PROJECT_DIR="$T1_REPO" bash "$TARGET" >/dev/null 2>&1
exit_code=$?
set -e

T1_MD="$T1_REPO/.iterate-team/knowledge/lessons.md"
assert_eq "exit code 0" "0" "$exit_code"
if [[ -f "$T1_MD" ]]; then
  echo "  PASS: lessons.md が生成される"
  pass_count=$((pass_count + 1))
else
  echo "  FAIL: lessons.md が生成されない" >&2
  fail_count=$((fail_count + 1))
fi
T1_CONTENT="$(cat "$T1_MD" 2>/dev/null || true)"
assert_contains "見出しが含まれる" "# 知見ダイジェスト（自動生成）" "$T1_CONTENT"
assert_contains "共通セクション見出しが含まれる" "## 共通（全 agent）" "$T1_CONTENT"
assert_contains "team-planner セクション見出しが含まれる" "## team-planner" "$T1_CONTENT"
assert_contains "team-test-coder セクション見出しが含まれる" "## team-test-coder" "$T1_CONTENT"
assert_contains "manual ブロックが含まれる" "<!-- manual:start -->" "$T1_CONTENT"
assert_contains "空セクションは (なし) と表示される" "(なし)" "$T1_CONTENT"

rm -rf "$T1_REPO"

# ========== T2: 全体最大 20 件（21件入れて20件になる） ==========
# セクション上限（8件）に引っかからないよう 3 セクション（team-planner/team-generator/
# team-evaluator）に分散させ、各セクション最大 7 件（<=8）に収める。confidence を 1 件だけ
# "low" にして必ずソート最下位（confidence desc の主キーで確実に最下位）にすることで、
# 全体 20 件上限により当該 1 件だけが digest から落ちることを検証する。
run_case "T2: active レコードが 21 件（各セクション <=8 件に分散）あっても全体の掲載件数は 20 件に切られる"

T2_REPO="$(make_isolated_repo)"
T2_KNOWLEDGE="$T2_REPO/.iterate-team/knowledge"
mkdir -p "$T2_KNOWLEDGE"
T2_JSONL="$T2_KNOWLEDGE/lessons.jsonl"
: > "$T2_JSONL"

for i in $(seq -w 1 7); do
  make_record "L-t2-planner-$i" "high" "0" "2026-01-01T00:00:00Z" "active" '["team-planner"]' "planner lesson $i" >> "$T2_JSONL"
done
for i in $(seq -w 1 7); do
  make_record "L-t2-generator-$i" "high" "0" "2026-01-01T00:00:00Z" "active" '["team-generator"]' "generator lesson $i" >> "$T2_JSONL"
done
for i in $(seq -w 1 6); do
  make_record "L-t2-evaluator-$i" "high" "0" "2026-01-01T00:00:00Z" "active" '["team-evaluator"]' "evaluator lesson $i" >> "$T2_JSONL"
done
# 21 件目: confidence=low で確実にソート最下位（全体 20 件上限で唯一落ちる 1 件）
make_record "L-t2-lowest" "low" "0" "2026-01-01T00:00:00Z" "active" '["team-evaluator"]' "lowest lesson" >> "$T2_JSONL"

set +e
CLAUDE_PROJECT_DIR="$T2_REPO" bash "$TARGET" >/dev/null 2>&1
exit_code=$?
set -e

T2_MD="$T2_KNOWLEDGE/lessons.md"
assert_eq "exit code 0" "0" "$exit_code"
T2_LISTED_COUNT="$(grep -cE '^- \[L-t2-' "$T2_MD" 2>/dev/null || echo 0)"
assert_eq "掲載件数は全体最大 20 件に切られる（21件中1件が落ちる）" "20" "$T2_LISTED_COUNT"
assert_not_contains "confidence=low の最下位レコードが全体上限で落ちる" "L-t2-lowest" "$(cat "$T2_MD")"

rm -rf "$T2_REPO"

# ========== T3: セクションあたり最大 8 件 ==========
run_case "T3: 同一 agent 向けレコードが 10 件あってもそのセクションの掲載は 8 件に切られる"

T3_REPO="$(make_isolated_repo)"
T3_KNOWLEDGE="$T3_REPO/.iterate-team/knowledge"
mkdir -p "$T3_KNOWLEDGE"
T3_JSONL="$T3_KNOWLEDGE/lessons.jsonl"
: > "$T3_JSONL"

for i in $(seq -w 1 10); do
  ts="2026-02-$(printf '%02d' $(( (10#$i % 28) + 1 )))T00:00:00Z"
  make_record "L-t3-$i" "medium" "0" "$ts" "active" '["team-generator"]' "generator lesson $i" >> "$T3_JSONL"
done

set +e
CLAUDE_PROJECT_DIR="$T3_REPO" bash "$TARGET" >/dev/null 2>&1
exit_code=$?
set -e

T3_MD="$T3_KNOWLEDGE/lessons.md"
assert_eq "exit code 0" "0" "$exit_code"
T3_LISTED_COUNT="$(grep -cE '^- \[L-t3-' "$T3_MD" 2>/dev/null || echo 0)"
assert_eq "team-generator セクションの掲載は 8 件に切られる" "8" "$T3_LISTED_COUNT"

rm -rf "$T3_REPO"

# ========== T4: 同一 id は最終行勝ち（status を deprecated に上書き→digest から消える） ==========
run_case "T4: 同一 id の更新レコード（status=deprecated への上書き）が append された場合、最終行が優先され digest から消える"

T4_REPO="$(make_isolated_repo)"
T4_KNOWLEDGE="$T4_REPO/.iterate-team/knowledge"
mkdir -p "$T4_KNOWLEDGE"
T4_JSONL="$T4_KNOWLEDGE/lessons.jsonl"
: > "$T4_JSONL"

make_record "L-t4-dup" "high" "0" "2026-03-01T00:00:00Z" "active" '["team-evaluator"]' "original lesson" >> "$T4_JSONL"
make_record "L-t4-dup" "high" "0" "2026-03-02T00:00:00Z" "deprecated" '["team-evaluator"]' "original lesson" >> "$T4_JSONL"
make_record "L-t4-keep" "high" "0" "2026-03-01T00:00:00Z" "active" '["team-evaluator"]' "kept lesson" >> "$T4_JSONL"

set +e
CLAUDE_PROJECT_DIR="$T4_REPO" bash "$TARGET" >/dev/null 2>&1
exit_code=$?
set -e

T4_MD="$T4_KNOWLEDGE/lessons.md"
assert_eq "exit code 0" "0" "$exit_code"
T4_CONTENT="$(cat "$T4_MD")"
assert_not_contains "deprecated に上書きされた id は掲載されない" "L-t4-dup" "$T4_CONTENT"
assert_contains "active のままの id は掲載される" "L-t4-keep" "$T4_CONTENT"

rm -rf "$T4_REPO"

# ========== T5: manual ブロックの温存 ==========
run_case "T5: 既存 lessons.md の manual ブロックが再生成後も温存される"

T5_REPO="$(make_isolated_repo)"
T5_KNOWLEDGE="$T5_REPO/.iterate-team/knowledge"
mkdir -p "$T5_KNOWLEDGE"
T5_JSONL="$T5_KNOWLEDGE/lessons.jsonl"
make_record "L-t5-1" "high" "0" "2026-04-01T00:00:00Z" "active" '["team-interviewer"]' "interview lesson" > "$T5_JSONL"

cat > "$T5_KNOWLEDGE/lessons.md" <<'EOF'
# 知見ダイジェスト（自動生成）

古い内容（再生成で消えるはず）。

<!-- manual:start -->
運用者が書いた手編集メモ：これは温存されるべき。
<!-- manual:end -->
EOF

set +e
CLAUDE_PROJECT_DIR="$T5_REPO" bash "$TARGET" >/dev/null 2>&1
exit_code=$?
set -e

T5_CONTENT="$(cat "$T5_KNOWLEDGE/lessons.md")"
assert_eq "exit code 0" "0" "$exit_code"
assert_contains "manual ブロックの内容が温存される" "運用者が書いた手編集メモ" "$T5_CONTENT"
assert_not_contains "manual ブロック外の古い内容は消える" "古い内容（再生成で消えるはず）" "$T5_CONTENT"
assert_contains "新しい active レコードが掲載される" "L-t5-1" "$T5_CONTENT"

rm -rf "$T5_REPO"

# ========== T6: "*" は共通セクションのみに掲載し agent 別セクションに重複掲載しない ==========
run_case 'T6: target_agents に "*" を含むレコードは共通セクションのみに掲載され、agent 別セクションに重複掲載されない'

T6_REPO="$(make_isolated_repo)"
T6_KNOWLEDGE="$T6_REPO/.iterate-team/knowledge"
mkdir -p "$T6_KNOWLEDGE"
T6_JSONL="$T6_KNOWLEDGE/lessons.jsonl"
make_record "L-t6-star" "high" "0" "2026-05-01T00:00:00Z" "active" '["*"]' "common lesson" > "$T6_JSONL"
make_record "L-t6-planner" "high" "0" "2026-05-01T00:00:00Z" "active" '["team-planner"]' "planner only lesson" >> "$T6_JSONL"

set +e
CLAUDE_PROJECT_DIR="$T6_REPO" bash "$TARGET" >/dev/null 2>&1
exit_code=$?
set -e

T6_MD="$T6_KNOWLEDGE/lessons.md"
assert_eq "exit code 0" "0" "$exit_code"

# 共通セクションから次の "## " 見出しまでを抜き出して "*" レコードの掲載を確認
T6_COMMON_SECTION="$(awk '/^## 共通（全 agent）$/{flag=1; next} /^## /{flag=0} flag' "$T6_MD")"
assert_contains "共通セクションに \"*\" レコードが掲載される" "L-t6-star" "$T6_COMMON_SECTION"

T6_PLANNER_SECTION="$(awk '/^## team-planner$/{flag=1; next} /^## /{flag=0} flag' "$T6_MD")"
assert_not_contains "team-planner セクションに \"*\" レコードは重複掲載されない" "L-t6-star" "$T6_PLANNER_SECTION"
assert_contains "team-planner セクションには専用レコードが掲載される" "L-t6-planner" "$T6_PLANNER_SECTION"

rm -rf "$T6_REPO"

# ========== T7: 決定的再生成（同一入力なら同一出力） ==========
run_case "T7: 同一 lessons.jsonl に対して 2 回再生成しても lessons.md の内容は同一（決定的）"

T7_REPO="$(make_isolated_repo)"
T7_KNOWLEDGE="$T7_REPO/.iterate-team/knowledge"
mkdir -p "$T7_KNOWLEDGE"
T7_JSONL="$T7_KNOWLEDGE/lessons.jsonl"
make_record "L-t7-1" "medium" "1" "2026-06-01T00:00:00Z" "active" '["team-test-coder"]' "coder lesson" > "$T7_JSONL"

CLAUDE_PROJECT_DIR="$T7_REPO" bash "$TARGET" >/dev/null 2>&1
T7_FIRST="$(cat "$T7_KNOWLEDGE/lessons.md")"
CLAUDE_PROJECT_DIR="$T7_REPO" bash "$TARGET" >/dev/null 2>&1
T7_SECOND="$(cat "$T7_KNOWLEDGE/lessons.md")"

assert_eq "2 回の再生成結果が同一" "$T7_FIRST" "$T7_SECOND"

rm -rf "$T7_REPO"

# ========== T8: 不正 JSON 行が1行混入していても、正常な行だけで digest 生成される ==========
# 修正前は `jq -s '...' lessons.jsonl 2>/dev/null || echo '[]'` のため、jsonl 内に
# 不正な行が1行あるだけで jq -s 全体が失敗し、プール全体が `[]` に化けて正常な既存レコード
# の digest まで空になってしまっていた（PR レビュー指摘）。tolerant パースにより、不正行
# だけをスキップし残りの正常行から digest が生成されることを検証する。
run_case "T8: 正常2行+不正1行の jsonl から、正常2行分のダイジェストが生成される（不正1行はスキップ）"

T8_REPO="$(make_isolated_repo)"
T8_KNOWLEDGE="$T8_REPO/.iterate-team/knowledge"
mkdir -p "$T8_KNOWLEDGE"
T8_JSONL="$T8_KNOWLEDGE/lessons.jsonl"

make_record "L-t8-a" "high" "0" "2026-07-01T00:00:00Z" "active" '["team-planner"]' "valid lesson a" > "$T8_JSONL"
echo 'this is not valid json {{{' >> "$T8_JSONL"
make_record "L-t8-b" "high" "0" "2026-07-02T00:00:00Z" "active" '["team-planner"]' "valid lesson b" >> "$T8_JSONL"

set +e
T8_STDERR=$(CLAUDE_PROJECT_DIR="$T8_REPO" bash "$TARGET" 2>&1 1>/dev/null)
exit_code=$?
set -e

T8_MD="$T8_KNOWLEDGE/lessons.md"
assert_eq "exit code 0（不正行があっても異常終了しない）" "0" "$exit_code"
T8_CONTENT="$(cat "$T8_MD" 2>/dev/null || true)"
assert_contains "正常な1件目(L-t8-a)は掲載される" "L-t8-a" "$T8_CONTENT"
assert_contains "正常な2件目(L-t8-b)は掲載される" "L-t8-b" "$T8_CONTENT"
assert_contains "stderr に malformed line skipped 警告が出力される" "malformed line" "$T8_STDERR"

rm -rf "$T8_REPO"

# ========== T9: manual ブロックが2個ある場合は最初のみ温存される ==========
run_case "T9: 既存 lessons.md に manual ブロックが2個ある場合、再生成後も最初のブロックのみ温存される"

T9_REPO="$(make_isolated_repo)"
T9_KNOWLEDGE="$T9_REPO/.iterate-team/knowledge"
mkdir -p "$T9_KNOWLEDGE"
T9_JSONL="$T9_KNOWLEDGE/lessons.jsonl"
make_record "L-t9-1" "high" "0" "2026-07-01T00:00:00Z" "active" '["team-planner"]' "lesson" > "$T9_JSONL"

cat > "$T9_KNOWLEDGE/lessons.md" <<'EOF'
# 知見ダイジェスト（自動生成）

<!-- manual:start -->
最初のブロック（これだけが温存されるべき）。
<!-- manual:end -->

以下は誤って残った2個目の manual ブロック（無視されるべき）。

<!-- manual:start -->
2個目のブロック（無視されるべき）。
<!-- manual:end -->
EOF

set +e
CLAUDE_PROJECT_DIR="$T9_REPO" bash "$TARGET" >/dev/null 2>&1
exit_code=$?
set -e

T9_CONTENT="$(cat "$T9_KNOWLEDGE/lessons.md")"
assert_eq "exit code 0" "0" "$exit_code"
assert_contains "最初の manual ブロックの内容が温存される" "最初のブロック（これだけが温存されるべき）" "$T9_CONTENT"
assert_not_contains "2個目の manual ブロックの内容は温存されない" "2個目のブロック（無視されるべき）" "$T9_CONTENT"

rm -rf "$T9_REPO"

# ========== T10: manual:end マーカー欠落時は空ブロックへフォールバック + 警告 ==========
run_case "T10: manual:start はあるが manual:end が無い場合、空の manual ブロックへフォールバックし stderr に警告が出る"

T10_REPO="$(make_isolated_repo)"
T10_KNOWLEDGE="$T10_REPO/.iterate-team/knowledge"
mkdir -p "$T10_KNOWLEDGE"
T10_JSONL="$T10_KNOWLEDGE/lessons.jsonl"
make_record "L-t10-1" "high" "0" "2026-07-01T00:00:00Z" "active" '["team-planner"]' "lesson" > "$T10_JSONL"

cat > "$T10_KNOWLEDGE/lessons.md" <<'EOF'
# 知見ダイジェスト（自動生成）

<!-- manual:start -->
end マーカーが無いまま EOF まで続くブロック（本文はここに含まれるべきではない）。
EOF

set +e
T10_STDERR=$(CLAUDE_PROJECT_DIR="$T10_REPO" bash "$TARGET" 2>&1 1>/dev/null)
exit_code=$?
set -e

T10_CONTENT="$(cat "$T10_KNOWLEDGE/lessons.md")"
assert_eq "exit code 0" "0" "$exit_code"
assert_contains "end マーカー欠落時は空の manual ブロックにフォールバックする" $'<!-- manual:start -->\n<!-- manual:end -->' "$T10_CONTENT"
assert_not_contains "end マーカーが無い旧本文は取り込まれない" "end マーカーが無いまま EOF まで続くブロック" "$T10_CONTENT"
assert_contains "stderr に manual:end 欠落の警告が出力される" "manual:end" "$T10_STDERR"

rm -rf "$T10_REPO"

# ========== T11: digest 実行中の並走 append で lessons.jsonl が壊れず digest も正常終了する ==========
run_case "T11: digest 実行中に append を並走させても lessons.jsonl は壊れず、digest は正常終了する"

T11_REPO="$(make_isolated_repo)"
T11_KNOWLEDGE="$T11_REPO/.iterate-team/knowledge"
mkdir -p "$T11_KNOWLEDGE"
T11_JSONL="$T11_KNOWLEDGE/lessons.jsonl"
for i in $(seq -w 1 20); do
  make_record "L-t11-$i" "medium" "0" "2026-07-01T00:00:00Z" "active" '["team-generator"]' "lesson $i" >> "$T11_JSONL"
done

APPEND_TARGET="${SCRIPT_DIR}/../knowledge-append.sh"
pids=()
for i in $(seq 1 5); do
  (
    record="{\"category\":\"impl\",\"target_agents\":[\"team-generator\"],\"trigger\":\"concurrent t${i}\",\"lesson\":\"concurrent lesson ${i}\",\"evidence\":[{\"session_id\":\"s${i}\",\"event\":\"e${i}\"}],\"status\":\"active\",\"source\":\"manual\"}"
    CLAUDE_PROJECT_DIR="$T11_REPO" bash "$APPEND_TARGET" "$record" >/dev/null 2>&1
  ) &
  pids+=($!)
done

set +e
CLAUDE_PROJECT_DIR="$T11_REPO" bash "$TARGET" >/dev/null 2>&1
digest_exit=$?
set -e

for p in "${pids[@]}"; do
  wait "$p"
done

assert_eq "digest 実行時点で exit code 0" "0" "$digest_exit"

T11_INVALID=0
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  echo "$line" | jq empty >/dev/null 2>&1 || T11_INVALID=$((T11_INVALID + 1))
done < "$T11_JSONL"
assert_eq "並走後も lessons.jsonl の全行が valid JSON（破損なし）" "0" "$T11_INVALID"

T11_LINE_COUNT="$(wc -l < "$T11_JSONL" | tr -d ' ')"
assert_eq "並走 append 5件分がすべて追記されている（20+5=25行）" "25" "$T11_LINE_COUNT"

rm -rf "$T11_REPO"

# ========== T12: 複数 agent 宛レッスンは両セクションに掲載されるが、全体プールの計上は1回のみ ==========
run_case 'T12: target_agents に複数 agent を含むレッスンは両セクションに掲載されるが、全体20件プールへの計上は1回のみ'

T12_REPO="$(make_isolated_repo)"
T12_KNOWLEDGE="$T12_REPO/.iterate-team/knowledge"
mkdir -p "$T12_KNOWLEDGE"
T12_JSONL="$T12_KNOWLEDGE/lessons.jsonl"
make_record "L-t12-dual" "high" "0" "2026-07-01T00:00:00Z" "active" '["team-planner","team-generator"]' "dual target lesson" > "$T12_JSONL"
make_record "L-t12-single" "high" "0" "2026-07-01T00:00:00Z" "active" '["team-evaluator"]' "single target lesson" >> "$T12_JSONL"

set +e
CLAUDE_PROJECT_DIR="$T12_REPO" bash "$TARGET" >/dev/null 2>&1
exit_code=$?
set -e

T12_MD="$T12_KNOWLEDGE/lessons.md"
assert_eq "exit code 0" "0" "$exit_code"

T12_PLANNER_SECTION="$(awk '/^## team-planner$/{flag=1; next} /^## /{flag=0} flag' "$T12_MD")"
T12_GENERATOR_SECTION="$(awk '/^## team-generator$/{flag=1; next} /^## /{flag=0} flag' "$T12_MD")"
assert_contains "team-planner セクションに dual レッスンが掲載される" "L-t12-dual" "$T12_PLANNER_SECTION"
assert_contains "team-generator セクションに dual レッスンが掲載される" "L-t12-dual" "$T12_GENERATOR_SECTION"

T12_LISTED_LINES="$(grep -cE '^- \[L-' "$T12_MD" 2>/dev/null || echo 0)"
T12_UNIQUE_IDS="$(grep -oE '\[L-[^]]+\]' "$T12_MD" | sort -u | wc -l | tr -d ' ')"
assert_eq "掲載行数は3（dual レッスンが2セクションに重複掲載されるため）" "3" "$T12_LISTED_LINES"
assert_eq "ユニーク id 数は2（全体プールへの計上は dual レッスンにつき1回のみ）" "2" "$T12_UNIQUE_IDS"

rm -rf "$T12_REPO"

# ========== T13: 改行入り lesson が lessons.jsonl に直接混入していてもセクション偽造されない ==========
# knowledge-append.sh は改行入り lesson/trigger を拒否するが、それは入口側の防御に過ぎない。
# 手編集や過去データ由来で lessons.jsonl に改行を含む不正行が既に存在するケースに備え、
# knowledge-digest.sh 側（出口）でも改行をサニタイズする多層防御が入っているはず。
# ここでは append をバイパスして lessons.jsonl に直接、改行(JSON 文字列内 \n)を含む
# lesson のレコードを書き込み、digest 出力で当該レッスンが 1 行に潰され、
# "## team-generator" 見出しが偽造されていない（見出し数が期待どおり）ことを検証する。
run_case 'T13: lessons.jsonl に直接書き込まれた改行入り lesson は digest で1行に潰され、"## team-generator" 見出しが偽造されない'

T13_REPO="$(make_isolated_repo)"
T13_KNOWLEDGE="$T13_REPO/.iterate-team/knowledge"
mkdir -p "$T13_KNOWLEDGE"
T13_JSONL="$T13_KNOWLEDGE/lessons.jsonl"

INJECTED_LESSON="$(printf 'normal lesson text\n## team-generator\n- [L-fake-0001] forged lesson')"
jq -nc --arg lesson "$INJECTED_LESSON" '{
  id: "L-t13-1", ts: "2026-07-01T00:00:00Z", session_id: "s1", source: "manual", category: "impl",
  target_agents: ["team-planner"], trigger: "t", lesson: $lesson,
  evidence: [{session_id:"s1", event:"e"}], status: "active",
  merged_into: null, confidence: "high", applied_count: 0,
  last_applied_ts: null
}' > "$T13_JSONL"

set +e
CLAUDE_PROJECT_DIR="$T13_REPO" bash "$TARGET" >/dev/null 2>&1
exit_code=$?
set -e

T13_MD="$T13_KNOWLEDGE/lessons.md"
assert_eq "exit code 0" "0" "$exit_code"

T13_HEADING_COUNT="$(grep -cE '^## team-generator$' "$T13_MD" 2>/dev/null || echo 0)"
assert_eq '"## team-generator" 見出しは1個のみ（偽造されず、通常のセクション見出しのみ）' "1" "$T13_HEADING_COUNT"

T13_LESSON_LINE_COUNT="$(grep -cE '^- \[L-t13-1\]' "$T13_MD" 2>/dev/null || echo 0)"
assert_eq "改行入りレッスンが1行に潰されて掲載される" "1" "$T13_LESSON_LINE_COUNT"

T13_FAKE_LINE_COUNT="$(grep -cE '^- \[L-fake-0001\]' "$T13_MD" 2>/dev/null || true)"
T13_FAKE_LINE_COUNT="${T13_FAKE_LINE_COUNT:-0}"
assert_eq "偽造しようとした行が独立した箇条書き行として解釈されない" "0" "$T13_FAKE_LINE_COUNT"

rm -rf "$T13_REPO"

# ========== T14 [修正3 回帰] 非 object の JSON 行（構文的に妥当だが object でない） ==========
# 修正前は `echo '42' >> lessons.jsonl` のような「構文的に妥当な JSON だが object でない」
# 行が1行あるだけで、tolerant パース（fromjson? // empty）は通過してしまい、後段の
# group_by(.id)/map(last) 等が数値に対してオブジェクトのフィールドを参照しようとして
# jq 型エラーで失敗 → `|| echo '[]'` により正常レコードまで含めてプール全体が空に化け、
# lessons.md から正常レッスンが警告なしで全消失していた（実機確認済みの P0 バグ）。
run_case "T14: 非 object の JSON 行（42 単体）が混入していても、正常レッスンは lessons.md に残存し malformed 警告が出る"

T14_REPO="$(make_isolated_repo)"
T14_KNOWLEDGE="$T14_REPO/.iterate-team/knowledge"
mkdir -p "$T14_KNOWLEDGE"
T14_JSONL="$T14_KNOWLEDGE/lessons.jsonl"

make_record "L-t14-a" "high" "0" "2026-07-01T00:00:00Z" "active" '["team-planner"]' "valid lesson a" > "$T14_JSONL"
echo '42' >> "$T14_JSONL"
make_record "L-t14-b" "high" "0" "2026-07-02T00:00:00Z" "active" '["team-planner"]' "valid lesson b" >> "$T14_JSONL"

set +e
T14_STDERR=$(CLAUDE_PROJECT_DIR="$T14_REPO" bash "$TARGET" 2>&1 1>/dev/null)
exit_code=$?
set -e

T14_MD="$T14_KNOWLEDGE/lessons.md"
assert_eq "exit code 0（非 object 行があっても異常終了しない）" "0" "$exit_code"
T14_CONTENT="$(cat "$T14_MD" 2>/dev/null || true)"
assert_contains "正常な1件目(L-t14-a)は掲載される" "L-t14-a" "$T14_CONTENT"
assert_contains "正常な2件目(L-t14-b)は掲載される" "L-t14-b" "$T14_CONTENT"
assert_contains "stderr に malformed line 警告が出力される（非 object 行も同じ malformed カウントに含まれる）" "malformed line" "$T14_STDERR"

rm -rf "$T14_REPO"

# ========== T15 [修正5 回帰] merge=union による物理行順の破壊への耐性（新しい ts 勝ち） ==========
# .gitattributes の `lessons.jsonl merge=union` はブランチ統合時に同一 id の物理行順を
# 保証しない。そのため「新しい ts のレコードが物理的に先、古い ts が後」という
# merge=union 再現の並びを直接組み立て、digest が「物理最終行」ではなく「最新 ts」を
# 採用することを検証する。
run_case "T15: 同一 id で新しい ts のレコードが物理的に先・古い ts が後（merge=union 再現）でも digest は新しい ts 側を採用する"

T15_REPO="$(make_isolated_repo)"
T15_KNOWLEDGE="$T15_REPO/.iterate-team/knowledge"
mkdir -p "$T15_KNOWLEDGE"
T15_JSONL="$T15_KNOWLEDGE/lessons.jsonl"

# 物理的に先: ts が新しい（2026-06-01）。物理的に後: ts が古い（2026-01-05）。
make_record "L-t15-dup" "high" "0" "2026-06-01T00:00:00Z" "active" '["team-planner"]' "newer-ts-lesson-physically-first" > "$T15_JSONL"
make_record "L-t15-dup" "high" "0" "2026-01-05T00:00:00Z" "active" '["team-planner"]' "older-ts-lesson-physically-last" >> "$T15_JSONL"

set +e
CLAUDE_PROJECT_DIR="$T15_REPO" bash "$TARGET" >/dev/null 2>&1
exit_code=$?
set -e

T15_MD="$T15_KNOWLEDGE/lessons.md"
assert_eq "exit code 0" "0" "$exit_code"
T15_CONTENT="$(cat "$T15_MD" 2>/dev/null || true)"
assert_contains "新しい ts 側のレッスン本文が採用される" "newer-ts-lesson-physically-first" "$T15_CONTENT"
assert_not_contains "古い ts 側のレッスン本文（物理最終行）は採用されない" "older-ts-lesson-physically-last" "$T15_CONTENT"

rm -rf "$T15_REPO"

# ========== Summary ==========
echo ""
echo "======================================"
echo "  Cases: $case_count"
echo "  PASS:  $pass_count"
echo "  FAIL:  $fail_count"
echo "======================================"

if [[ $fail_count -gt 0 ]]; then
  exit 1
fi
exit 0
