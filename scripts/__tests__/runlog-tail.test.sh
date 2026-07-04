#!/usr/bin/env bash
# runlog-tail.sh の単体テスト
#
# 実行環境前提: Linux / GNU coreutils + git（dev container・メイン checkout）。
# bash 3.2 / macOS 互換は目標外。
#
# 仕様の正本: <plugin_root>/commands/iterate-retrospect.md ステップ3
#
# Usage:
#   bash scripts/__tests__/runlog-tail.test.sh
#
# Exit code:
#   0 = 全ケース pass
#   1 = いずれか fail

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${SCRIPT_DIR}/../runlog-tail.sh"

if [[ ! -f "$TARGET" ]]; then
  echo "runlog-tail.sh not found at: $TARGET" >&2
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

SESSION_ID="test-session-001"

make_repo_with_runlog() {
  local tmpdir n_lines
  tmpdir="$(mktemp -d "$TMPDIR_GLOBAL/repo.XXXXXX")"
  n_lines="${1:-10}"
  mkdir -p "$tmpdir/.iterate-team/state/$SESSION_ID"
  for i in $(seq 1 "$n_lines"); do
    echo "{\"n\":$i}" >> "$tmpdir/.iterate-team/state/$SESSION_ID/runlog.jsonl"
  done
  echo "$tmpdir"
}

# ========== U1: 正常 tail（lines 省略。全10行が既定400以下なので全件出力） ==========
run_case "U1: lines 省略時は既定 400 行で tail され、10行しかない runlog は全件出力される"

U1_REPO="$(make_repo_with_runlog 10)"

set +e
stdout=$(CLAUDE_PROJECT_DIR="$U1_REPO" bash "$TARGET" "$SESSION_ID" 2>"$TMPDIR_GLOBAL/u1-err")
exit_code=$?
set -e
u1_stderr="$(cat "$TMPDIR_GLOBAL/u1-err" 2>/dev/null || true)"

assert_eq "exit code 0" "0" "$exit_code"
assert_eq "stderr は空" "" "$u1_stderr"
assert_eq "出力行数は10" "10" "$(echo "$stdout" | wc -l | tr -d ' ')"
assert_eq "先頭行は1件目" '{"n":1}' "$(echo "$stdout" | head -n1)"
assert_eq "末尾行は10件目" '{"n":10}' "$(echo "$stdout" | tail -n1)"

rm -rf "$U1_REPO"

# ========== U2: 正常 tail（lines 指定あり） ==========
run_case "U2: lines=3 を指定すると末尾3行のみが出力される"

U2_REPO="$(make_repo_with_runlog 10)"

set +e
stdout=$(CLAUDE_PROJECT_DIR="$U2_REPO" bash "$TARGET" "$SESSION_ID" 3 2>"$TMPDIR_GLOBAL/u2-err")
exit_code=$?
set -e

assert_eq "exit code 0" "0" "$exit_code"
assert_eq "出力は末尾3行" '{"n":8}
{"n":9}
{"n":10}' "$stdout"

rm -rf "$U2_REPO"

# ========== U3: runlog.jsonl が存在しない → exit 1 ==========
run_case "U3: 対象 session-id の runlog.jsonl が存在しない場合、診断を stderr に出して exit 1"

U3_REPO="$(mktemp -d "$TMPDIR_GLOBAL/repo.XXXXXX")"

set +e
stderr=$(CLAUDE_PROJECT_DIR="$U3_REPO" bash "$TARGET" "$SESSION_ID" 2>&1 1>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 非ゼロ" "1" "$exit_code"
assert_contains "stderr に runlog not found が出力される" "runlog not found" "$stderr"

rm -rf "$U3_REPO"

# ========== U4: session-id が不正（../evil）→ exit 1 ==========
run_case "U4: session-id が '../evil' のようなパス逸脱値だと非ゼロ終了で拒否される"

U4_REPO="$(mktemp -d "$TMPDIR_GLOBAL/repo.XXXXXX")"

set +e
stderr=$(CLAUDE_PROJECT_DIR="$U4_REPO" bash "$TARGET" "../evil" 2>&1 1>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 非ゼロ" "1" "$exit_code"
assert_contains "stderr に invalid session-id の理由が出力される" "invalid session-id" "$stderr"

# 空文字
set +e
stderr_empty=$(CLAUDE_PROJECT_DIR="$U4_REPO" bash "$TARGET" "" 2>&1 1>/dev/null)
exit_empty=$?
set -e
assert_eq "session-id 空文字: exit code 非ゼロ" "1" "$exit_empty"
assert_contains "session-id 空文字: stderr に invalid session-id が出力される" "invalid session-id" "$stderr_empty"

# '/' を含む
set +e
stderr_slash=$(CLAUDE_PROJECT_DIR="$U4_REPO" bash "$TARGET" "a/b" 2>&1 1>/dev/null)
exit_slash=$?
set -e
assert_eq "session-id '/' 含み: exit code 非ゼロ" "1" "$exit_slash"

# 許容文字集合外
set +e
stderr_bad_char=$(CLAUDE_PROJECT_DIR="$U4_REPO" bash "$TARGET" 'sess;rm' 2>&1 1>/dev/null)
exit_bad_char=$?
set -e
assert_eq "session-id 不正文字: exit code 非ゼロ" "1" "$exit_bad_char"

rm -rf "$U4_REPO"

# ========== U5: lines が不正（0 / 負数 / 非数値） → exit 1 ==========
run_case "U5: lines が不正な値（0, -1, abc, 1.5）の場合、いずれも非ゼロ終了しstderrにメッセージが出る"

U5_REPO="$(make_repo_with_runlog 5)"

for bad_lines in 0 -1 abc "1.5" "01"; do
  set +e
  stderr=$(CLAUDE_PROJECT_DIR="$U5_REPO" bash "$TARGET" "$SESSION_ID" "$bad_lines" 2>&1 1>/dev/null)
  exit_code=$?
  set -e
  assert_eq "lines='$bad_lines': exit code 非ゼロ" "1" "$exit_code"
  assert_contains "lines='$bad_lines': stderr に invalid lines が出力される" "invalid lines" "$stderr"
done

rm -rf "$U5_REPO"

# ========== U6: lines が上限 (10000) を超える場合はクランプされエラーにならない ==========
run_case "U6: lines が上限を超える巨大な値でも拒否されず、上限にクランプされて成功する"

U6_REPO="$(make_repo_with_runlog 5)"

set +e
stdout=$(CLAUDE_PROJECT_DIR="$U6_REPO" bash "$TARGET" "$SESSION_ID" 999999999 2>"$TMPDIR_GLOBAL/u6-err")
exit_code=$?
set -e
u6_stderr="$(cat "$TMPDIR_GLOBAL/u6-err" 2>/dev/null || true)"

assert_eq "exit code 0（拒否せずクランプされる）" "0" "$exit_code"
assert_eq "stderr は空" "" "$u6_stderr"
assert_eq "出力行数は runlog の全5行（クランプ上限に達していないため全件）" "5" "$(echo "$stdout" | wc -l | tr -d ' ')"

rm -rf "$U6_REPO"

# ========== U7: 引数個数不正（0個 / 3個以上） → exit 1 ==========
run_case "U7: 引数が0個または3個以上の場合、Usage を stderr に出して exit 1"

U7_REPO="$(mktemp -d "$TMPDIR_GLOBAL/repo.XXXXXX")"

set +e
stderr_noargs=$(CLAUDE_PROJECT_DIR="$U7_REPO" bash "$TARGET" 2>&1 1>/dev/null)
exit_noargs=$?
set -e
assert_eq "引数0個: exit code 非ゼロ" "1" "$exit_noargs"
assert_contains "引数0個: Usage が stderr に出力される" "Usage" "$stderr_noargs"

set +e
stderr_toomany=$(CLAUDE_PROJECT_DIR="$U7_REPO" bash "$TARGET" "$SESSION_ID" 10 20 2>&1 1>/dev/null)
exit_toomany=$?
set -e
assert_eq "引数3個: exit code 非ゼロ" "1" "$exit_toomany"
assert_contains "引数3個: Usage が stderr に出力される" "Usage" "$stderr_toomany"

rm -rf "$U7_REPO"

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
