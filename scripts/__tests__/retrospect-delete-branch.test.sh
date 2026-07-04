#!/usr/bin/env bash
# retrospect-delete-branch.sh の単体テスト
#
# 実行環境前提: Linux / GNU coreutils + git（dev container・メイン checkout）。
# bash 3.2 / macOS 互換は目標外。
#
# 仕様の正本: <plugin_root>/scripts/retrospect-delete-branch.sh（ヘッダコメント）
#
# Usage:
#   bash scripts/__tests__/retrospect-delete-branch.test.sh
#
# Exit code:
#   0 = 全ケース pass
#   1 = いずれか fail

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${SCRIPT_DIR}/../retrospect-delete-branch.sh"

if [[ ! -f "$TARGET" ]]; then
  echo "retrospect-delete-branch.sh not found at: $TARGET" >&2
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

assert_not_eq() {
  local label="$1" unexpected="$2" actual="$3"
  if [[ "$unexpected" != "$actual" ]]; then
    echo "  PASS: $label (=$actual, unexpected='$unexpected')"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL: $label (unexpectedly equals '$unexpected')" >&2
    fail_count=$((fail_count + 1))
  fi
}

branch_exists() {
  local repo="$1" branch="$2"
  git -C "$repo" show-ref --verify --quiet "refs/heads/${branch}"
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

# ---- フィクスチャ: 隔離 git リポジトリ生成（main + 各種ブランチ） ----
make_isolated_repo() {
  local tmpdir
  tmpdir="$(mktemp -d "$TMPDIR_GLOBAL/repo.XXXXXX")"
  git init -q -b main "$tmpdir"
  git -C "$tmpdir" config user.email "test@example.com"
  git -C "$tmpdir" config user.name "Test"
  git -C "$tmpdir" commit -q --allow-empty -m "init"
  git -C "$tmpdir" branch claude/knowledge-retrospect-x
  git -C "$tmpdir" branch claude/other
  echo "$tmpdir"
}

# ========== T1: 正常削除 ==========
run_case "T1: claude/knowledge-retrospect-x は正常に削除される"

T1_REPO="$(make_isolated_repo)"

set +e
CLAUDE_PROJECT_DIR="$T1_REPO" bash "$TARGET" "claude/knowledge-retrospect-x" >"$TMPDIR_GLOBAL/t1-out" 2>"$TMPDIR_GLOBAL/t1-err"
exit_code=$?
set -e

assert_eq "exit code 0" "0" "$exit_code"
if branch_exists "$T1_REPO" "claude/knowledge-retrospect-x"; then
  echo "  FAIL: claude/knowledge-retrospect-x が削除されていない" >&2
  fail_count=$((fail_count + 1))
else
  echo "  PASS: claude/knowledge-retrospect-x が削除されている"
  pass_count=$((pass_count + 1))
fi

rm -rf "$T1_REPO"

# ========== T2: パターン外ブランチ名は拒否される ==========
run_case "T2: main / claude/other など retro 命名規則外のブランチ名は非ゼロ終了で拒否され削除もされない"

T2_REPO="$(make_isolated_repo)"

for bad_branch in "main" "claude/other" "claude/knowledge-retrospect-" "knowledge-retrospect-x" "claude/knowledge-retrospectx"; do
  set +e
  stderr=$(CLAUDE_PROJECT_DIR="$T2_REPO" bash "$TARGET" "$bad_branch" 2>&1 1>/dev/null)
  exit_code=$?
  set -e
  assert_eq "ブランチ '$bad_branch': exit code 非ゼロ" "1" "$exit_code"
  assert_contains "ブランチ '$bad_branch': stderr に invalid branch が出力される" "invalid branch" "$stderr"
done

if branch_exists "$T2_REPO" "main"; then
  echo "  PASS: main は削除されずに残っている"
  pass_count=$((pass_count + 1))
else
  echo "  FAIL: main が削除されてしまった" >&2
  fail_count=$((fail_count + 1))
fi
if branch_exists "$T2_REPO" "claude/other"; then
  echo "  PASS: claude/other は削除されずに残っている"
  pass_count=$((pass_count + 1))
else
  echo "  FAIL: claude/other が削除されてしまった" >&2
  fail_count=$((fail_count + 1))
fi

rm -rf "$T2_REPO"

# ========== T3: 2引数（余剰引数注入）は拒否される ==========
run_case "T3: 'claude/knowledge-retrospect-x main' のような2引数は非ゼロ終了で拒否され、いずれのブランチも削除されない（余剰引数注入対策）"

T3_REPO="$(make_isolated_repo)"

set +e
stderr=$(CLAUDE_PROJECT_DIR="$T3_REPO" bash "$TARGET" "claude/knowledge-retrospect-x" "main" 2>&1 1>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 非ゼロ" "1" "$exit_code"
assert_contains "stderr に Usage が出力される" "Usage" "$stderr"

if branch_exists "$T3_REPO" "main"; then
  echo "  PASS: main は削除されずに残っている（余剰引数注入は成立しない）"
  pass_count=$((pass_count + 1))
else
  echo "  FAIL: main が余剰引数注入で削除されてしまった" >&2
  fail_count=$((fail_count + 1))
fi
if branch_exists "$T3_REPO" "claude/knowledge-retrospect-x"; then
  echo "  PASS: claude/knowledge-retrospect-x も削除されずに残っている（2引数は丸ごと拒否）"
  pass_count=$((pass_count + 1))
else
  echo "  FAIL: claude/knowledge-retrospect-x が削除されてしまった" >&2
  fail_count=$((fail_count + 1))
fi

rm -rf "$T3_REPO"

# ========== T4: 引数0個は拒否される ==========
run_case "T4: 引数0個は非ゼロ終了で Usage が出力される"

T4_REPO="$(make_isolated_repo)"

set +e
stderr=$(CLAUDE_PROJECT_DIR="$T4_REPO" bash "$TARGET" 2>&1 1>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 非ゼロ" "1" "$exit_code"
assert_contains "stderr に Usage が出力される" "Usage" "$stderr"

rm -rf "$T4_REPO"

# ========== T5: 未存在ブランチはエラーを伝播する ==========
run_case "T5: 命名規則には一致するが未存在のブランチを指定すると git のエラーが伝播し exit 非ゼロ"

T5_REPO="$(make_isolated_repo)"

set +e
stderr=$(CLAUDE_PROJECT_DIR="$T5_REPO" bash "$TARGET" "claude/knowledge-retrospect-no-such-branch" 2>&1 1>/dev/null)
exit_code=$?
set -e

assert_not_eq "exit code は 0 ではない（git branch -D 自体の失敗が伝播する）" "0" "$exit_code"

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
