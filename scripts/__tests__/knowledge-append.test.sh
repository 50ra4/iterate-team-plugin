#!/usr/bin/env bash
# knowledge-append.sh の単体テスト
#
# 実行環境前提: Linux / GNU coreutils + jq + git（dev container・メイン checkout）。
# bash 3.2 / macOS 互換は目標外。
#
# 仕様の正本: <plugin_root>/operations/knowledge-policy.md（§3・§11）
#
# Usage:
#   bash scripts/__tests__/knowledge-append.test.sh
#
# Exit code:
#   0 = 全ケース pass
#   1 = いずれか fail

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${SCRIPT_DIR}/../knowledge-append.sh"

if [[ ! -f "$TARGET" ]]; then
  echo "knowledge-append.sh not found at: $TARGET" >&2
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
    echo "  FAIL: $label (needle='$needle' haystack='${haystack:0:300}...')" >&2
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

assert_matches_regex() {
  local label="$1" pattern="$2" haystack="$3"
  if echo "$haystack" | grep -qE "$pattern"; then
    echo "  PASS: $label (matches /$pattern/)"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL: $label (pattern=/$pattern/ not found in haystack='${haystack:0:300}')" >&2
    fail_count=$((fail_count + 1))
  fi
}

assert_path_exists() {
  local label="$1" path="$2"
  if [[ -e "$path" ]]; then
    echo "  PASS: $label (exists: $path)"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL: $label (expected to exist but missing: $path)" >&2
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

VALID_RECORD='{"category":"review","target_agents":["team-planner"],"trigger":"レビューで差し戻し","lesson":"レビュー観点Xを先に確認する","evidence":[{"session_id":"s1","event":"e1"}],"status":"active","source":"auto-retrospective"}'

# ========== T1: 正常 append で全キーが補完される ==========
run_case "T1: 正常な最小レコードを append すると id/ts/confidence/applied_count/merged_into/last_applied_ts が補完される"

T1_REPO="$(make_isolated_repo)"
T1_ERR_FILE="$(mktemp "$TMPDIR_GLOBAL/t1-err.XXXXXX")"

set +e
stdout=$(CLAUDE_PROJECT_DIR="$T1_REPO" bash "$TARGET" "$VALID_RECORD" 2>"$T1_ERR_FILE")
exit_code=$?
set -e
stderr="$(cat "$T1_ERR_FILE" 2>/dev/null || true)"

T1_LESSONS="$T1_REPO/.iterate-team/knowledge/lessons.jsonl"
assert_eq "exit code 0" "0" "$exit_code"
assert_matches_regex "stdout に生成 id 形式が出力される" "^L-[0-9]{8}T[0-9]{4}-[0-9a-f]{4}$" "$stdout"

line="$(cat "$T1_LESSONS")"
assert_eq "書き込まれた行数は1" "1" "$(wc -l < "$T1_LESSONS" | tr -d ' ')"
assert_eq "書き込まれた id は stdout の id と一致" "$stdout" "$(echo "$line" | jq -r '.id')"
assert_matches_regex "ts が ISO8601 UTC 形式" "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$" "$(echo "$line" | jq -r '.ts')"
assert_eq "confidence 未指定は low が補完される" "low" "$(echo "$line" | jq -r '.confidence')"
assert_eq "applied_count 未指定は 0 が補完される" "0" "$(echo "$line" | jq -r '.applied_count')"
assert_eq "merged_into 未指定は null が補完される" "null" "$(echo "$line" | jq -r '.merged_into')"
assert_eq "last_applied_ts 未指定は null が補完される" "null" "$(echo "$line" | jq -r '.last_applied_ts')"
assert_eq "1行 JSON として valid" "0" "$(echo "$line" | jq empty >/dev/null 2>&1; echo $?)"

rm -rf "$T1_REPO"

# ========== T2: 必須キー欠落は拒否される ==========
run_case "T2: 必須キー（category）欠落は非ゼロ終了 + stderr に理由が出力される"

T2_REPO="$(make_isolated_repo)"
MISSING_CATEGORY='{"target_agents":["team-planner"],"trigger":"t","lesson":"l","evidence":[{"session_id":"s","event":"e"}],"status":"active","source":"manual"}'

set +e
stderr=$(CLAUDE_PROJECT_DIR="$T2_REPO" bash "$TARGET" "$MISSING_CATEGORY" 2>&1 1>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 非ゼロ" "1" "$exit_code"
assert_contains "stderr に category 欠落の理由が出力される" "category" "$stderr"
assert_eq "lessons.jsonl は生成されない" "" "$(cat "$T2_REPO/.iterate-team/knowledge/lessons.jsonl" 2>/dev/null || true)"

rm -rf "$T2_REPO"

# ========== T3: 不正 enum（category）は拒否される ==========
run_case "T3: 不正な category enum は非ゼロ終了で拒否される"

T3_REPO="$(make_isolated_repo)"
BAD_CATEGORY='{"category":"bogus","target_agents":["team-planner"],"trigger":"t","lesson":"l","evidence":[{"session_id":"s","event":"e"}],"status":"active","source":"manual"}'

set +e
stderr=$(CLAUDE_PROJECT_DIR="$T3_REPO" bash "$TARGET" "$BAD_CATEGORY" 2>&1 1>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 非ゼロ" "1" "$exit_code"
assert_contains "stderr に category enum 違反の理由が出力される" "category" "$stderr"

rm -rf "$T3_REPO"

# ========== T4: 必須キー（evidence）が空配列は拒否される ==========
run_case "T4: evidence が空配列だと非ゼロ終了で拒否される"

T4_REPO="$(make_isolated_repo)"
EMPTY_EVIDENCE='{"category":"impl","target_agents":["team-generator"],"trigger":"t","lesson":"l","evidence":[],"status":"active","source":"manual"}'

set +e
stderr=$(CLAUDE_PROJECT_DIR="$T4_REPO" bash "$TARGET" "$EMPTY_EVIDENCE" 2>&1 1>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 非ゼロ" "1" "$exit_code"
assert_contains "stderr に evidence 違反の理由が出力される" "evidence" "$stderr"

rm -rf "$T4_REPO"

# ========== T5: 不正 enum（status/source/confidence）は個別に拒否される ==========
run_case "T5: 不正な status / source / confidence enum はそれぞれ拒否される"

T5_REPO="$(make_isolated_repo)"

BAD_STATUS='{"category":"impl","target_agents":["team-generator"],"trigger":"t","lesson":"l","evidence":[{"session_id":"s","event":"e"}],"status":"bogus","source":"manual"}'
set +e
stderr=$(CLAUDE_PROJECT_DIR="$T5_REPO" bash "$TARGET" "$BAD_STATUS" 2>&1 1>/dev/null)
exit_code=$?
set -e
assert_eq "status enum 違反: exit code 非ゼロ" "1" "$exit_code"
assert_contains "status enum 違反の理由が出力される" "status" "$stderr"

BAD_SOURCE='{"category":"impl","target_agents":["team-generator"],"trigger":"t","lesson":"l","evidence":[{"session_id":"s","event":"e"}],"status":"active","source":"bogus"}'
set +e
stderr=$(CLAUDE_PROJECT_DIR="$T5_REPO" bash "$TARGET" "$BAD_SOURCE" 2>&1 1>/dev/null)
exit_code=$?
set -e
assert_eq "source enum 違反: exit code 非ゼロ" "1" "$exit_code"
assert_contains "source enum 違反の理由が出力される" "source" "$stderr"

BAD_CONFIDENCE='{"category":"impl","target_agents":["team-generator"],"trigger":"t","lesson":"l","evidence":[{"session_id":"s","event":"e"}],"status":"active","source":"manual","confidence":"bogus"}'
set +e
stderr=$(CLAUDE_PROJECT_DIR="$T5_REPO" bash "$TARGET" "$BAD_CONFIDENCE" 2>&1 1>/dev/null)
exit_code=$?
set -e
assert_eq "confidence enum 違反: exit code 非ゼロ" "1" "$exit_code"
assert_contains "confidence enum 違反の理由が出力される" "confidence" "$stderr"

rm -rf "$T5_REPO"

# ========== T6: target_agents 空配列は拒否される ==========
run_case "T6: target_agents が空配列だと非ゼロ終了で拒否される"

T6_REPO="$(make_isolated_repo)"
EMPTY_TARGETS='{"category":"impl","target_agents":[],"trigger":"t","lesson":"l","evidence":[{"session_id":"s","event":"e"}],"status":"active","source":"manual"}'

set +e
stderr=$(CLAUDE_PROJECT_DIR="$T6_REPO" bash "$TARGET" "$EMPTY_TARGETS" 2>&1 1>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 非ゼロ" "1" "$exit_code"
assert_contains "stderr に target_agents 違反の理由が出力される" "target_agents" "$stderr"

rm -rf "$T6_REPO"

# ========== T7: id 未指定時の自動生成と stdout 出力 ==========
run_case "T7: id 未指定時に L-<YYYYMMDDTHHmm>-<4hex> 形式の id が生成され stdout に出力される"

T7_REPO="$(make_isolated_repo)"

set +e
id1=$(CLAUDE_PROJECT_DIR="$T7_REPO" bash "$TARGET" "$VALID_RECORD" 2>/dev/null)
id2=$(CLAUDE_PROJECT_DIR="$T7_REPO" bash "$TARGET" "$VALID_RECORD" 2>/dev/null)
set -e

assert_matches_regex "id1 が仕様の形式に一致する" "^L-[0-9]{8}T[0-9]{4}-[0-9a-f]{4}$" "$id1"
assert_matches_regex "id2 が仕様の形式に一致する" "^L-[0-9]{8}T[0-9]{4}-[0-9a-f]{4}$" "$id2"
if [[ "$id1" != "$id2" ]]; then
  echo "  PASS: 連続 2 回の呼び出しで id が重複しない (id1=$id1 id2=$id2)"
  pass_count=$((pass_count + 1))
else
  echo "  FAIL: id が重複した (id1=$id1 id2=$id2)" >&2
  fail_count=$((fail_count + 1))
fi

rm -rf "$T7_REPO"

# ========== T8: id 指定時はその id がそのまま使われ stdout にも出力される ==========
run_case "T8: id 指定時は補完されず、指定した id がそのまま lessons.jsonl と stdout に反映される"

T8_REPO="$(make_isolated_repo)"
WITH_ID='{"id":"L-20260101T0000-abcd","category":"impl","target_agents":["team-generator"],"trigger":"t","lesson":"l","evidence":[{"session_id":"s","event":"e"}],"status":"active","source":"manual"}'

set +e
stdout=$(CLAUDE_PROJECT_DIR="$T8_REPO" bash "$TARGET" "$WITH_ID" 2>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 0" "0" "$exit_code"
assert_eq "stdout は指定した id" "L-20260101T0000-abcd" "$stdout"
assert_eq "lessons.jsonl の id も指定値のまま" "L-20260101T0000-abcd" "$(jq -r '.id' "$T8_REPO/.iterate-team/knowledge/lessons.jsonl")"

rm -rf "$T8_REPO"

# ========== T9: 並列 append 10 プロセスで行数 10・全行 valid JSON（行破損なし） ==========
run_case "T9: 並列 append 10 プロセスでも lessons.jsonl は 10 行・全行 valid JSON（flock による排他制御）"

T9_REPO="$(make_isolated_repo)"

pids=()
for i in $(seq 1 10); do
  (
    record="{\"category\":\"impl\",\"target_agents\":[\"team-generator\"],\"trigger\":\"t${i}\",\"lesson\":\"lesson ${i}\",\"evidence\":[{\"session_id\":\"s${i}\",\"event\":\"e${i}\"}],\"status\":\"active\",\"source\":\"manual\"}"
    CLAUDE_PROJECT_DIR="$T9_REPO" bash "$TARGET" "$record" >/dev/null 2>&1
  ) &
  pids+=($!)
done
for p in "${pids[@]}"; do
  wait "$p"
done

T9_LESSONS="$T9_REPO/.iterate-team/knowledge/lessons.jsonl"
T9_LINE_COUNT="$(wc -l < "$T9_LESSONS" | tr -d ' ')"
assert_eq "行数は 10（並列 append で行破損・欠落なし）" "10" "$T9_LINE_COUNT"

T9_INVALID=0
while IFS= read -r line; do
  echo "$line" | jq empty >/dev/null 2>&1 || T9_INVALID=$((T9_INVALID + 1))
done < "$T9_LESSONS"
assert_eq "全行が valid JSON（破損 0 行）" "0" "$T9_INVALID"

T9_UNIQUE_IDS="$(jq -r '.id' "$T9_LESSONS" | sort -u | wc -l | tr -d ' ')"
assert_eq "10 行それぞれ異なる id を持つ（衝突なし）" "10" "$T9_UNIQUE_IDS"

rm -rf "$T9_REPO"

# ========== T10: .gitattributes 冪等（2回実行しても1行のまま） ==========
run_case "T10: .gitattributes の merge=union 行は 2 回実行しても 1 行のまま（冪等 seed）"

T10_REPO="$(make_isolated_repo)"

CLAUDE_PROJECT_DIR="$T10_REPO" bash "$TARGET" "$VALID_RECORD" >/dev/null 2>&1
CLAUDE_PROJECT_DIR="$T10_REPO" bash "$TARGET" "$VALID_RECORD" >/dev/null 2>&1

T10_GITATTR="$T10_REPO/.iterate-team/knowledge/.gitattributes"
assert_contains "gitattributes に merge=union 行が含まれる" "lessons.jsonl merge=union" "$(cat "$T10_GITATTR" 2>/dev/null)"

T10_LINE_COUNT="$(grep -cxF "lessons.jsonl merge=union" "$T10_GITATTR" 2>/dev/null || echo 0)"
assert_eq "merge=union 行は 1 行のみ（2 回実行後も重複しない）" "1" "$T10_LINE_COUNT"

T10_LESSONS_COUNT="$(wc -l < "$T10_REPO/.iterate-team/knowledge/lessons.jsonl" | tr -d ' ')"
assert_eq "lessons.jsonl は 2 回分の append で 2 行になる（append 自体は独立）" "2" "$T10_LESSONS_COUNT"

T10_PROPOSALS_DIR="$T10_REPO/.iterate-team/knowledge/proposals"
if [[ -d "$T10_PROPOSALS_DIR" ]]; then
  echo "  PASS: knowledge/proposals/ ディレクトリが seed される"
  pass_count=$((pass_count + 1))
else
  echo "  FAIL: knowledge/proposals/ ディレクトリが seed されない" >&2
  fail_count=$((fail_count + 1))
fi

# ロックは state/ 配下に置く規約（git-tracked の knowledge/ を汚染しない）の回帰確認:
# knowledge/ 内に .lock / .lock.d が残置されず、ロック実体は state/ 側に作られる。
T10_LOCK_IN_KNOWLEDGE="$(find "$T10_REPO/.iterate-team/knowledge" -name '*.lock*' | wc -l | tr -d ' ')"
assert_eq "knowledge/ 配下にロックファイルが残置されない" "0" "$T10_LOCK_IN_KNOWLEDGE"
assert_path_exists "ロック実体は state/ 配下に作られる" "$T10_REPO/.iterate-team/state/knowledge-lessons.lock"

rm -rf "$T10_REPO"

# ========== T11: lesson が201字だと拒否される ==========
run_case "T11: lesson が201字（200字超過）だと非ゼロ終了で拒否される"

T11_REPO="$(make_isolated_repo)"
T11_LESSON_201="$(printf 'a%.0s' $(seq 1 201))"
T11_RECORD="$(jq -nc --arg l "$T11_LESSON_201" '{category:"impl",target_agents:["team-generator"],trigger:"t",lesson:$l,evidence:[{session_id:"s",event:"e"}],status:"active",source:"manual"}')"

set +e
stderr=$(CLAUDE_PROJECT_DIR="$T11_REPO" bash "$TARGET" "$T11_RECORD" 2>&1 1>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 非ゼロ" "1" "$exit_code"
assert_contains "stderr に lesson 文字数超過の理由が出力される" "lesson" "$stderr"

rm -rf "$T11_REPO"

# ========== T12: lesson がちょうど200字は受理される ==========
run_case "T12: lesson がちょうど200字は受理される（境界値）"

T12_REPO="$(make_isolated_repo)"
T12_LESSON_200="$(printf 'a%.0s' $(seq 1 200))"
T12_RECORD="$(jq -nc --arg l "$T12_LESSON_200" '{category:"impl",target_agents:["team-generator"],trigger:"t",lesson:$l,evidence:[{session_id:"s",event:"e"}],status:"active",source:"manual"}')"

set +e
stdout=$(CLAUDE_PROJECT_DIR="$T12_REPO" bash "$TARGET" "$T12_RECORD" 2>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 0（200字ちょうどは境界内）" "0" "$exit_code"
assert_matches_regex "id が正しく発行される" "^L-[0-9]{8}T[0-9]{4}-[0-9a-f]{4}$" "$stdout"

rm -rf "$T12_REPO"

# ========== T13: target_agents の typo は拒否される ==========
run_case "T13: target_agents に typo（team-plannr）を含むと非ゼロ終了で拒否される"

T13_REPO="$(make_isolated_repo)"
TYPO_TARGET='{"category":"impl","target_agents":["team-plannr"],"trigger":"t","lesson":"l","evidence":[{"session_id":"s","event":"e"}],"status":"active","source":"manual"}'

set +e
stderr=$(CLAUDE_PROJECT_DIR="$T13_REPO" bash "$TARGET" "$TYPO_TARGET" 2>&1 1>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 非ゼロ" "1" "$exit_code"
assert_contains "stderr に target_agents 違反の理由が出力される" "target_agents" "$stderr"

rm -rf "$T13_REPO"

# ========== T14: target_agents に有効だが注入対象外の agent 名（team-publisher）は拒否される ==========
run_case "T14: target_agents に team-publisher（有効な agent 名だが注入対象外）を含むと非ゼロ終了で拒否される"

T14_REPO="$(make_isolated_repo)"
NON_INJECTED_TARGET='{"category":"impl","target_agents":["team-publisher"],"trigger":"t","lesson":"l","evidence":[{"session_id":"s","event":"e"}],"status":"active","source":"manual"}'

set +e
stderr=$(CLAUDE_PROJECT_DIR="$T14_REPO" bash "$TARGET" "$NON_INJECTED_TARGET" 2>&1 1>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 非ゼロ" "1" "$exit_code"
assert_contains "stderr に target_agents 違反の理由が出力される" "target_agents" "$stderr"

rm -rf "$T14_REPO"

# ========== T15: evidence 要素が文字列だと拒否される ==========
run_case "T15: evidence の要素がオブジェクトでなく文字列だと非ゼロ終了で拒否される"

T15_REPO="$(make_isolated_repo)"
STRING_EVIDENCE='{"category":"impl","target_agents":["team-generator"],"trigger":"t","lesson":"l","evidence":["just a string"],"status":"active","source":"manual"}'

set +e
stderr=$(CLAUDE_PROJECT_DIR="$T15_REPO" bash "$TARGET" "$STRING_EVIDENCE" 2>&1 1>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 非ゼロ" "1" "$exit_code"
assert_contains "stderr に evidence 違反の理由が出力される" "evidence" "$stderr"

rm -rf "$T15_REPO"

# ========== T16: lesson に "<!-- manual:" を含むと拒否される ==========
run_case "T16: lesson に '<!-- manual:' を含むと非ゼロ終了で拒否される（digest の manual ブロック抽出を壊すため）"

T16_REPO="$(make_isolated_repo)"
MANUAL_MARKER_IN_LESSON='{"category":"impl","target_agents":["team-generator"],"trigger":"t","lesson":"<!-- manual:start --> injected","evidence":[{"session_id":"s","event":"e"}],"status":"active","source":"manual"}'

set +e
stderr=$(CLAUDE_PROJECT_DIR="$T16_REPO" bash "$TARGET" "$MANUAL_MARKER_IN_LESSON" 2>&1 1>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 非ゼロ" "1" "$exit_code"
assert_contains "stderr に manual マーカー混入の理由が出力される" "manual" "$stderr"

rm -rf "$T16_REPO"

# ========== T17: .gitattributes が末尾改行なしでも追記行が連結されない ==========
# session-start.sh の ensure_state_ignored と同じ末尾改行ガードの回帰確認。
run_case "T17: 既存 .gitattributes が末尾改行なしでも merge=union 行が既存行と連結されずに追記される"

T17_REPO="$(make_isolated_repo)"
mkdir -p "$T17_REPO/.iterate-team/knowledge"
T17_GITATTR="$T17_REPO/.iterate-team/knowledge/.gitattributes"
printf 'existing-pattern -diff' > "$T17_GITATTR"

CLAUDE_PROJECT_DIR="$T17_REPO" bash "$TARGET" "$VALID_RECORD" >/dev/null 2>&1

T17_CONTENT="$(cat "$T17_GITATTR")"
assert_contains "既存行は保持される" "existing-pattern -diff" "$T17_CONTENT"
assert_contains "merge=union 行が追加される" "lessons.jsonl merge=union" "$T17_CONTENT"
assert_not_contains "既存行と追記行が連結（改行なしで結合）されていない" "existing-pattern -difflessons.jsonl merge=union" "$T17_CONTENT"
T17_LINE_COUNT="$(wc -l < "$T17_GITATTR" | tr -d ' ')"
assert_eq "改行が挿入されて2行になっている" "2" "$T17_LINE_COUNT"

rm -rf "$T17_REPO"

# ========== T18: lesson に改行を含むと拒否される ==========
run_case "T18: lesson に改行(\n)を含むと非ゼロ終了で拒否される（digest が1行 raw 描画するためセクション偽造ベクトルになる）"

T18_REPO="$(make_isolated_repo)"
NEWLINE_LESSON="$(jq -nc --arg l "$(printf 'first line\n## team-generator\n- fake')" \
  '{category:"impl",target_agents:["team-generator"],trigger:"t",lesson:$l,evidence:[{session_id:"s",event:"e"}],status:"active",source:"manual"}')"

set +e
stderr=$(CLAUDE_PROJECT_DIR="$T18_REPO" bash "$TARGET" "$NEWLINE_LESSON" 2>&1 1>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 非ゼロ" "1" "$exit_code"
assert_contains "stderr に改行混入の理由が出力される" "lesson" "$stderr"

rm -rf "$T18_REPO"

# ========== T19: trigger に改行を含むと拒否される ==========
run_case "T19: trigger に改行(\n)を含むと非ゼロ終了で拒否される"

T19_REPO="$(make_isolated_repo)"
NEWLINE_TRIGGER="$(jq -nc --arg t "$(printf 'first line\n## team-generator\n- fake')" \
  '{category:"impl",target_agents:["team-generator"],trigger:$t,lesson:"l",evidence:[{session_id:"s",event:"e"}],status:"active",source:"manual"}')"

set +e
stderr=$(CLAUDE_PROJECT_DIR="$T19_REPO" bash "$TARGET" "$NEWLINE_TRIGGER" 2>&1 1>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 非ゼロ" "1" "$exit_code"
assert_contains "stderr に改行混入の理由が出力される" "trigger" "$stderr"

rm -rf "$T19_REPO"

# ========== T20: 不正形式 id は拒否される ==========
run_case "T20: id が knowledge-policy.md §3 の形式に一致しないと非ゼロ終了で拒否される"

T20_REPO="$(make_isolated_repo)"

# 改行を使ったセクション偽造を id フィールド経由で試みるケース
BAD_ID_INJECTION="$(jq -nc --arg id "$(printf 'evil]\n## team-generator')" \
  '{id:$id,category:"impl",target_agents:["team-generator"],trigger:"t",lesson:"l",evidence:[{session_id:"s",event:"e"}],status:"active",source:"manual"}')"
set +e
stderr=$(CLAUDE_PROJECT_DIR="$T20_REPO" bash "$TARGET" "$BAD_ID_INJECTION" 2>&1 1>/dev/null)
exit_code=$?
set -e
assert_eq "id 偽装形式（改行込み）: exit code 非ゼロ" "1" "$exit_code"
assert_contains "id 偽装形式の理由が出力される" "id" "$stderr"

# 単純に規約外形式（規約: L-<YYYYMMDDTHHmm>-<4hex>）のケース
BAD_ID_SIMPLE='{"id":"custom-1","category":"impl","target_agents":["team-generator"],"trigger":"t","lesson":"l","evidence":[{"session_id":"s","event":"e"}],"status":"active","source":"manual"}'
set +e
stderr=$(CLAUDE_PROJECT_DIR="$T20_REPO" bash "$TARGET" "$BAD_ID_SIMPLE" 2>&1 1>/dev/null)
exit_code=$?
set -e
assert_eq "id 簡易不正形式（custom-1）: exit code 非ゼロ" "1" "$exit_code"
assert_contains "id 簡易不正形式の理由が出力される" "id" "$stderr"

rm -rf "$T20_REPO"

# ========== T21: 正しい形式の id 明示指定は受理される ==========
run_case "T21: 正しい形式（L-YYYYMMDDTHHmm-4hex）の id を明示指定すると受理される"

T21_REPO="$(make_isolated_repo)"
GOOD_ID_RECORD='{"id":"L-20260101T0000-abcd","category":"impl","target_agents":["team-generator"],"trigger":"t","lesson":"l","evidence":[{"session_id":"s","event":"e"}],"status":"active","source":"manual"}'

set +e
stdout=$(CLAUDE_PROJECT_DIR="$T21_REPO" bash "$TARGET" "$GOOD_ID_RECORD" 2>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 0" "0" "$exit_code"
assert_eq "stdout は指定した id" "L-20260101T0000-abcd" "$stdout"

rm -rf "$T21_REPO"

# ========== T22: 不正形式 merged_into は拒否される ==========
run_case "T22: merged_into が非 null かつ id 形式に一致しないと非ゼロ終了で拒否される"

T22_REPO="$(make_isolated_repo)"
BAD_MERGED_INTO='{"category":"impl","target_agents":["team-generator"],"trigger":"t","lesson":"l","evidence":[{"session_id":"s","event":"e"}],"status":"merged","source":"manual","merged_into":"not-an-id"}'

set +e
stderr=$(CLAUDE_PROJECT_DIR="$T22_REPO" bash "$TARGET" "$BAD_MERGED_INTO" 2>&1 1>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 非ゼロ" "1" "$exit_code"
assert_contains "stderr に merged_into 違反の理由が出力される" "merged_into" "$stderr"

rm -rf "$T22_REPO"

# ========== T23: fresh リポジトリで不正 payload は副作用ゼロで拒否される ==========
# PR レビュー指摘（Codex P1）: seed（mkdir -p / .gitattributes 追記）が検証より前に走ると、
# fresh リポジトリで不正レコードが拒否されても untracked な .gitattributes 等が残り、
# fail-open 後も作業ツリーが dirty のままになって次回 preflight の clean-tree ガードを
# 汚染する。seed は全 check 成功後に移動したため、拒否時は knowledge/ 配下に一切
# ファイルが生成されず、git status --porcelain も空であることを確認する。
run_case "T23: fresh リポジトリで不正 payload（不正 category）を append すると knowledge/ 配下に一切ファイルが生成されず git status も空のまま"

T23_REPO="$(make_isolated_repo)"
BAD_CATEGORY_FRESH='{"category":"bogus","target_agents":["team-planner"],"trigger":"t","lesson":"l","evidence":[{"session_id":"s","event":"e"}],"status":"active","source":"manual"}'

set +e
stderr=$(CLAUDE_PROJECT_DIR="$T23_REPO" bash "$TARGET" "$BAD_CATEGORY_FRESH" 2>&1 1>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 非ゼロ" "1" "$exit_code"

T23_KNOWLEDGE_DIR="$T23_REPO/.iterate-team/knowledge"
if [[ -e "$T23_KNOWLEDGE_DIR" ]]; then
  echo "  FAIL: knowledge/ が生成されてしまっている（seed が検証前に走っている疑い）: $T23_KNOWLEDGE_DIR" >&2
  fail_count=$((fail_count + 1))
else
  echo "  PASS: knowledge/ が一切生成されない（.gitattributes 含め副作用ゼロ）"
  pass_count=$((pass_count + 1))
fi

T23_PORCELAIN="$(cd "$T23_REPO" && git status --porcelain)"
assert_eq "git status --porcelain が空（作業ツリーに dirty な差分が残らない）" "" "$T23_PORCELAIN"

rm -rf "$T23_REPO"

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
