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
