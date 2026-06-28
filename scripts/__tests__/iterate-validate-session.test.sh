#!/usr/bin/env bash
# scripts/iterate-validate-session.sh の単体テスト。依存ゼロ（bats / shunit2 等不要）。
#
# 7 ケース:
#   1. next_step 数値 6, review phase     → exit 0, pass 出力
#   2. next_step 文字列 "6", review phase → exit 0, pass 出力
#   3. build 完了 checkpoint も all_tasks_completed も無し, review → exit 5, build phase not completed
#   4. next_step 数値 4.5, build phase   → exit 0, pass 出力
#   5. next_step 文字列 "4.5", build phase → exit 0, pass 出力
#   6. plan 完了シグナル無し, build phase → exit 4, plan phase not completed
#   7. all_tasks_completed あり（next_step 不在）, review → exit 0（後方互換）
#
# Usage: bash scripts/__tests__/iterate-validate-session.test.sh
# Exit: 0 = 全 PASS / 1 = 1 件以上 FAIL
#
# 合成 runlog fixture は mktemp -d で作成した一時 git リポジトリ（対象プロジェクト相当）
# 配下に書き出す。実 .iterate-team/state/ は一切改変しない。
# iterate-validate-session.sh は repo_root を CLAUDE_PROJECT_DIR 優先で解決するため、
# スクリプトのコピーは「対象リポ外のプラグイン配置」を模した別の一時 git リポジトリへ置き、
# 実行時に CLAUDE_PROJECT_DIR を対象リポへ向ける。これによりプラグインを対象リポ外へ
# 配布（npm/global install・別 checkout）しても state を取り違えない回帰を検証する。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE_SCRIPT_SRC="$SCRIPT_DIR/../iterate-validate-session.sh"

if [[ ! -f "$VALIDATE_SCRIPT_SRC" ]]; then
  echo "iterate-validate-session.sh not found at: $VALIDATE_SCRIPT_SRC" >&2
  exit 1
fi

pass_count=0
fail_count=0
case_count=0

# ---------- assertion helpers ----------

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
    echo "  FAIL: $label (needle='$needle' haystack='${haystack:0:300}')" >&2
    fail_count=$((fail_count + 1))
  fi
}

# ---------- 一時 git リポジトリのセットアップ ----------
# iterate-validate-session.sh は CLAUDE_PROJECT_DIR（未注入時は CWD の git root）から
# repo_root を特定し、<repo_root>/.iterate-team/state/<sid>/runlog.jsonl を参照する。
# 対象リポ（TMP_ROOT）と、スクリプト配置先のプラグイン repo（PLUGIN_ROOT）を別々に作り、
# 実行時に CLAUDE_PROJECT_DIR=TMP_ROOT を渡して対象リポ側の state を解決させる。

TMP_ROOT=""
PLUGIN_ROOT=""
VALIDATE_SCRIPT_COPY=""
TMP_OUT_FILE=""
TMP_ERR_FILE=""

cleanup() {
  [[ -n "${TMP_ROOT:-}" && -d "${TMP_ROOT}" ]] && rm -rf "$TMP_ROOT"
  [[ -n "${PLUGIN_ROOT:-}" && -d "${PLUGIN_ROOT}" ]] && rm -rf "$PLUGIN_ROOT"
  [[ -n "${TMP_OUT_FILE:-}" && -f "${TMP_OUT_FILE}" ]] && rm -f "$TMP_OUT_FILE"
  [[ -n "${TMP_ERR_FILE:-}" && -f "${TMP_ERR_FILE}" ]] && rm -f "$TMP_ERR_FILE"
}
trap cleanup EXIT

setup_tmp_repo() {
  # 対象プロジェクト（runlog state はここに置く）
  TMP_ROOT="$(mktemp -d)"
  # git user を一時設定して init & commit を通す
  git init --quiet "$TMP_ROOT"
  git -C "$TMP_ROOT" config user.email "test@example.com"
  git -C "$TMP_ROOT" config user.name "Test"
  git -C "$TMP_ROOT" commit --allow-empty --quiet -m "init"

  # スクリプト配置先（対象リポ外のプラグインを模した別の git repo）。
  # ここに置くことで、repo_root を script の場所から解決すると対象リポを見失う
  # （旧実装のバグ条件）。CLAUDE_PROJECT_DIR 経由なら正しく TMP_ROOT を解決する。
  PLUGIN_ROOT="$(mktemp -d)"
  git init --quiet "$PLUGIN_ROOT"
  local scripts_dir="${PLUGIN_ROOT}/scripts"
  mkdir -p "$scripts_dir"
  cp "$VALIDATE_SCRIPT_SRC" "$scripts_dir/iterate-validate-session.sh"
  chmod +x "$scripts_dir/iterate-validate-session.sh"
  VALIDATE_SCRIPT_COPY="${scripts_dir}/iterate-validate-session.sh"

  TMP_OUT_FILE="$(mktemp)"
  TMP_ERR_FILE="$(mktemp)"
}

# 合成 runlog を tmp repo 内の state/<sid>/runlog.jsonl に書き出す。
write_runlog() {
  local sid="$1"
  local content="$2"
  local state_dir="${TMP_ROOT}/.iterate-team/state/${sid}"
  mkdir -p "$state_dir"
  printf '%s' "$content" > "${state_dir}/runlog.jsonl"
}

# iterate-validate-session.sh（コピー版）を実行し、
# 結果を TMP_OUT_FILE / TMP_ERR_FILE に書き込む。
# 呼び出し後は LAST_EXIT_CODE / LAST_STDOUT / LAST_STDERR を参照する。
LAST_EXIT_CODE=0
LAST_STDOUT=""
LAST_STDERR=""

run_validate() {
  local sid="$1"
  local phase="$2"

  : > "$TMP_OUT_FILE"
  : > "$TMP_ERR_FILE"

  # CLAUDE_PROJECT_DIR を対象リポ（TMP_ROOT）へ向ける。スクリプト本体は PLUGIN_ROOT
  # 配下にあるが、repo_root が対象リポ側へ解決されることを検証する。
  CLAUDE_PROJECT_DIR="$TMP_ROOT" bash "$VALIDATE_SCRIPT_COPY" "$sid" "$phase" \
    >"$TMP_OUT_FILE" 2>"$TMP_ERR_FILE"
  LAST_EXIT_CODE=$?
  true  # set -e を持つ親スコープがあっても継続させる
  LAST_STDOUT="$(cat "$TMP_OUT_FILE")"
  LAST_STDERR="$(cat "$TMP_ERR_FILE")"
}

# ---------- case runner ----------

run_case() {
  local label="$1"
  case_count=$((case_count + 1))
  echo ""
  echo "[Case $case_count] $label"
}

# ---------- テスト開始 ----------

setup_tmp_repo

SID_BASE="synthetic-sess-test1111"

# ---------- Case 1: next_step 数値 6, review → exit 0 ----------
run_case "next_step 数値 6, review phase → exit 0 & pass 出力"
SID="${SID_BASE}-c1"
write_runlog "$SID" '{"event":"step_checkpoint","next_step":6}
'
run_validate "$SID" "review"
assert_eq      "exit code" "0" "$LAST_EXIT_CODE"
assert_contains "stdout contains session_id" "session_id" "$LAST_STDOUT"

# ---------- Case 2: next_step 文字列 "6", review → exit 0 ----------
run_case 'next_step 文字列 "6", review phase → exit 0 & pass 出力'
SID="${SID_BASE}-c2"
write_runlog "$SID" '{"event":"step_checkpoint","next_step":"6"}
'
run_validate "$SID" "review"
assert_eq      "exit code" "0" "$LAST_EXIT_CODE"
assert_contains "stdout contains session_id" "session_id" "$LAST_STDOUT"

# ---------- Case 3: build 完了シグナル無し, review → exit 5 ----------
run_case "build 完了シグナル無し, review phase → exit 5 & build phase not completed"
SID="${SID_BASE}-c3"
write_runlog "$SID" '{"event":"plan_approved"}
'
run_validate "$SID" "review"
assert_eq      "exit code" "5" "$LAST_EXIT_CODE"
assert_contains "stderr contains build phase not completed" "build phase not completed" "$LAST_STDERR"

# ---------- Case 4: next_step 数値 4.5, build → exit 0 ----------
run_case "next_step 数値 4.5, build phase → exit 0 & pass 出力"
SID="${SID_BASE}-c4"
write_runlog "$SID" '{"event":"step_checkpoint","next_step":4.5}
'
run_validate "$SID" "build"
assert_eq      "exit code" "0" "$LAST_EXIT_CODE"
assert_contains "stdout contains session_id" "session_id" "$LAST_STDOUT"

# ---------- Case 5: next_step 文字列 "4.5", build → exit 0 ----------
run_case 'next_step 文字列 "4.5", build phase → exit 0 & pass 出力'
SID="${SID_BASE}-c5"
write_runlog "$SID" '{"event":"step_checkpoint","next_step":"4.5"}
'
run_validate "$SID" "build"
assert_eq      "exit code" "0" "$LAST_EXIT_CODE"
assert_contains "stdout contains session_id" "session_id" "$LAST_STDOUT"

# ---------- Case 6: plan 完了シグナル無し, build → exit 4 ----------
run_case "plan 完了シグナル無し, build phase → exit 4 & plan phase not completed"
SID="${SID_BASE}-c6"
write_runlog "$SID" '{"event":"step_checkpoint","next_step":6}
'
run_validate "$SID" "build"
assert_eq      "exit code" "4" "$LAST_EXIT_CODE"
assert_contains "stderr contains plan phase not completed" "plan phase not completed" "$LAST_STDERR"

# ---------- Case 7: all_tasks_completed あり（next_step 不在）, review → exit 0 ----------
run_case "all_tasks_completed あり（next_step 不在）, review → exit 0（後方互換）"
SID="${SID_BASE}-c7"
write_runlog "$SID" '{"event":"all_tasks_completed"}
'
run_validate "$SID" "review"
assert_eq      "exit code" "0" "$LAST_EXIT_CODE"
assert_contains "stdout contains session_id" "session_id" "$LAST_STDOUT"

# ---------- Summary ----------
echo ""
echo "===================="
echo "  Cases: $case_count"
echo "  PASS:  $pass_count"
echo "  FAIL:  $fail_count"
echo "===================="

if [[ $fail_count -gt 0 ]]; then
  exit 1
fi
exit 0
