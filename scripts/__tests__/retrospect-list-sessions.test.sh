#!/usr/bin/env bash
# retrospect-list-sessions.sh の単体テスト
#
# 実行環境前提: Linux / GNU coreutils + git（dev container・メイン checkout）。
# bash 3.2 / macOS 互換は目標外。
#
# 仕様の正本: <plugin_root>/commands/iterate-retrospect.md ステップ1
#
# Usage:
#   bash scripts/__tests__/retrospect-list-sessions.test.sh
#
# Exit code:
#   0 = 全ケース pass
#   1 = いずれか fail

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${SCRIPT_DIR}/../retrospect-list-sessions.sh"

if [[ ! -f "$TARGET" ]]; then
  echo "retrospect-list-sessions.sh not found at: $TARGET" >&2
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

# ---- フィクスチャ: 隔離 git リポジトリ生成（mtime 制御用に touch -d を使う） ----
make_isolated_repo() {
  local tmpdir
  tmpdir="$(mktemp -d "$TMPDIR_GLOBAL/repo.XXXXXX")"
  git init -q "$tmpdir"
  git -C "$tmpdir" config user.email "test@example.com"
  git -C "$tmpdir" config user.name "Test"
  git -C "$tmpdir" commit -q --allow-empty -m "init"
  echo "$tmpdir"
}

# ========== T1: runlog.jsonl の mtime 降順で並び、retro_* は除外され、N 件に切り出される ==========
run_case "T1: 通常セッション3件 + retro_* 1件 → runlog.jsonl の mtime 降順で N=2 件が取得され retro_* は含まれない"

T1_REPO="$(make_isolated_repo)"
mkdir -p "$T1_REPO/.iterate-team/state/sess-old" \
         "$T1_REPO/.iterate-team/state/sess-mid" \
         "$T1_REPO/.iterate-team/state/sess-new" \
         "$T1_REPO/.iterate-team/state/retro_20260101"
: > "$T1_REPO/.iterate-team/state/sess-old/runlog.jsonl"
: > "$T1_REPO/.iterate-team/state/sess-mid/runlog.jsonl"
: > "$T1_REPO/.iterate-team/state/sess-new/runlog.jsonl"
: > "$T1_REPO/.iterate-team/state/retro_20260101/runlog.jsonl"
# ディレクトリ自体の mtime は意図的に runlog.jsonl と逆順にし、判定基準が
# runlog.jsonl の mtime であることを検証する（ディレクトリ mtime 基準だと FAIL する）。
touch -d '2022-01-01 00:00:00' "$T1_REPO/.iterate-team/state/sess-old"
touch -d '2021-01-01 00:00:00' "$T1_REPO/.iterate-team/state/sess-mid"
touch -d '2020-01-01 00:00:00' "$T1_REPO/.iterate-team/state/sess-new"
touch -d '2020-01-01 00:00:00' "$T1_REPO/.iterate-team/state/sess-old/runlog.jsonl"
touch -d '2021-01-01 00:00:00' "$T1_REPO/.iterate-team/state/sess-mid/runlog.jsonl"
touch -d '2022-01-01 00:00:00' "$T1_REPO/.iterate-team/state/sess-new/runlog.jsonl"
touch -d '2026-01-01 00:00:00' "$T1_REPO/.iterate-team/state/retro_20260101/runlog.jsonl"

set +e
stdout=$(CLAUDE_PROJECT_DIR="$T1_REPO" bash "$TARGET" 2 2>"$TMPDIR_GLOBAL/t1-err")
exit_code=$?
set -e
t1_stderr="$(cat "$TMPDIR_GLOBAL/t1-err" 2>/dev/null || true)"

assert_eq "exit code 0" "0" "$exit_code"
assert_eq "stderr は空" "" "$t1_stderr"
assert_eq "N=2 は runlog.jsonl mtime 降順で sess-new, sess-mid の2件" "sess-new
sess-mid" "$stdout"

rm -rf "$T1_REPO"

# ========== T2: N がディレクトリ数を超える場合、全件が runlog.jsonl mtime 降順で出力される ==========
run_case "T2: N が実件数を超える → retro_* を除いた全件が runlog.jsonl mtime 降順で出力される"

T2_REPO="$(make_isolated_repo)"
mkdir -p "$T2_REPO/.iterate-team/state/sess-a" "$T2_REPO/.iterate-team/state/sess-b"
: > "$T2_REPO/.iterate-team/state/sess-a/runlog.jsonl"
: > "$T2_REPO/.iterate-team/state/sess-b/runlog.jsonl"
touch -d '2020-01-01 00:00:00' "$T2_REPO/.iterate-team/state/sess-a/runlog.jsonl"
touch -d '2023-01-01 00:00:00' "$T2_REPO/.iterate-team/state/sess-b/runlog.jsonl"

set +e
stdout=$(CLAUDE_PROJECT_DIR="$T2_REPO" bash "$TARGET" 100 2>"$TMPDIR_GLOBAL/t2-err")
exit_code=$?
set -e

assert_eq "exit code 0" "0" "$exit_code"
assert_eq "全2件が runlog.jsonl mtime 降順" "sess-b
sess-a" "$stdout"

rm -rf "$T2_REPO"

# ========== T2b: runlog.jsonl を持たないディレクトリは除外される ==========
run_case "T2b: runlog.jsonl を持たないディレクトリは session_list から除外される（後段 runlog-tail.sh の exit 1 を防ぐ）"

T2B_REPO="$(make_isolated_repo)"
mkdir -p "$T2B_REPO/.iterate-team/state/sess-with-runlog" \
         "$T2B_REPO/.iterate-team/state/sess-no-runlog"
: > "$T2B_REPO/.iterate-team/state/sess-with-runlog/runlog.jsonl"
touch -d '2020-01-01 00:00:00' "$T2B_REPO/.iterate-team/state/sess-with-runlog/runlog.jsonl"
# sess-no-runlog はディレクトリのみ存在し runlog.jsonl を持たない（例: mkdir 直後や
# 異常終了などで runlog が一度も追記されなかったセッション）。ディレクトリ自体の
# mtime は sess-with-runlog より新しくして、除外が runlog.jsonl の有無で判定される
# ことを確認する。
touch -d '2026-01-01 00:00:00' "$T2B_REPO/.iterate-team/state/sess-no-runlog"

set +e
stdout=$(CLAUDE_PROJECT_DIR="$T2B_REPO" bash "$TARGET" 10 2>"$TMPDIR_GLOBAL/t2b-err")
exit_code=$?
set -e
t2b_stderr="$(cat "$TMPDIR_GLOBAL/t2b-err" 2>/dev/null || true)"

assert_eq "exit code 0" "0" "$exit_code"
assert_eq "stderr は空" "" "$t2b_stderr"
assert_eq "runlog.jsonl を持つ sess-with-runlog のみが出力される" "sess-with-runlog" "$stdout"

rm -rf "$T2B_REPO"

# ========== T3: .iterate-team/state/ が存在しない → 空出力・exit 0 ==========
run_case "T3: .iterate-team/state/ が存在しない場合、空出力で exit 0"

T3_REPO="$(make_isolated_repo)"

set +e
stdout=$(CLAUDE_PROJECT_DIR="$T3_REPO" bash "$TARGET" 5 2>"$TMPDIR_GLOBAL/t3-err")
exit_code=$?
set -e
t3_stderr="$(cat "$TMPDIR_GLOBAL/t3-err" 2>/dev/null || true)"

assert_eq "exit code 0" "0" "$exit_code"
assert_eq "stdout は空" "" "$stdout"
assert_eq "stderr は空" "" "$t3_stderr"

rm -rf "$T3_REPO"

# ========== T4: state/ 配下が retro_* のみ（0 件） → 空出力・exit 0 ==========
run_case "T4: state/ 配下が retro_* ディレクトリのみ → 空出力で exit 0"

T4_REPO="$(make_isolated_repo)"
mkdir -p "$T4_REPO/.iterate-team/state/retro_20260101"

set +e
stdout=$(CLAUDE_PROJECT_DIR="$T4_REPO" bash "$TARGET" 5 2>"$TMPDIR_GLOBAL/t4-err")
exit_code=$?
set -e

assert_eq "exit code 0" "0" "$exit_code"
assert_eq "stdout は空（retro_* のみは対象外）" "" "$stdout"

rm -rf "$T4_REPO"

# ========== T5: N が不正（0 / 負数 / 非数値） → Usage を stderr に出して exit 1 ==========
run_case "T5: N が不正な値（0, -1, abc, 空文字, 引数無し, 引数2個）の場合、いずれも非ゼロ終了しstderrにメッセージが出る"

T5_REPO="$(make_isolated_repo)"

for bad_n in 0 -1 abc "" "1.5" "01"; do
  set +e
  stderr=$(CLAUDE_PROJECT_DIR="$T5_REPO" bash "$TARGET" "$bad_n" 2>&1 1>/dev/null)
  exit_code=$?
  set -e
  assert_eq "N='$bad_n': exit code 非ゼロ" "1" "$exit_code"
  assert_contains "N='$bad_n': stderr に Usage/invalid が出力される" "Usage" "$stderr"
done

# 引数無し
set +e
stderr_noargs=$(CLAUDE_PROJECT_DIR="$T5_REPO" bash "$TARGET" 2>&1 1>/dev/null)
exit_noargs=$?
set -e
assert_eq "引数無し: exit code 非ゼロ" "1" "$exit_noargs"
assert_contains "引数無し: Usage が stderr に出力される" "Usage" "$stderr_noargs"

# 引数2個（多すぎ）
set +e
stderr_toomany=$(CLAUDE_PROJECT_DIR="$T5_REPO" bash "$TARGET" 5 10 2>&1 1>/dev/null)
exit_toomany=$?
set -e
assert_eq "引数2個: exit code 非ゼロ" "1" "$exit_toomany"
assert_contains "引数2個: Usage が stderr に出力される" "Usage" "$stderr_toomany"

rm -rf "$T5_REPO"

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
