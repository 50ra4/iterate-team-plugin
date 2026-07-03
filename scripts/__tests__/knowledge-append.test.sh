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
WITH_ID='{"id":"L-manual-fixed","category":"impl","target_agents":["team-generator"],"trigger":"t","lesson":"l","evidence":[{"session_id":"s","event":"e"}],"status":"active","source":"manual"}'

set +e
stdout=$(CLAUDE_PROJECT_DIR="$T8_REPO" bash "$TARGET" "$WITH_ID" 2>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 0" "0" "$exit_code"
assert_eq "stdout は指定した id" "L-manual-fixed" "$stdout"
assert_eq "lessons.jsonl の id も指定値のまま" "L-manual-fixed" "$(jq -r '.id' "$T8_REPO/.iterate-team/knowledge/lessons.jsonl")"

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
