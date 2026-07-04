#!/usr/bin/env bash
# git-switch-branch.sh の単体テスト
#
# 実行環境前提: Linux / GNU coreutils + git（dev container・メイン checkout）。
# bash 3.2 / macOS 互換は目標外。
#
# 仕様の正本: <plugin_root>/scripts/git-switch-branch.sh（ヘッダコメント）
#
# Usage:
#   bash scripts/__tests__/git-switch-branch.test.sh
#
# Exit code:
#   0 = 全ケース pass
#   1 = いずれか fail

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${SCRIPT_DIR}/../git-switch-branch.sh"

if [[ ! -f "$TARGET" ]]; then
  echo "git-switch-branch.sh not found at: $TARGET" >&2
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

# ---- フィクスチャ: 隔離 git リポジトリ生成（main + feature ブランチ） ----
make_isolated_repo() {
  local tmpdir
  tmpdir="$(mktemp -d "$TMPDIR_GLOBAL/repo.XXXXXX")"
  git init -q -b main "$tmpdir"
  git -C "$tmpdir" config user.email "test@example.com"
  git -C "$tmpdir" config user.name "Test"
  git -C "$tmpdir" commit -q --allow-empty -m "init"
  git -C "$tmpdir" branch feature
  echo "$tmpdir"
}

# ========== T1: 正常切替 ==========
run_case "T1: main -> feature へ正常に切り替わる"

T1_REPO="$(make_isolated_repo)"

set +e
stdout=$(CLAUDE_PROJECT_DIR="$T1_REPO" bash "$TARGET" "feature" 2>"$TMPDIR_GLOBAL/t1-err")
exit_code=$?
set -e
t1_stderr="$(cat "$TMPDIR_GLOBAL/t1-err" 2>/dev/null || true)"

assert_eq "exit code 0" "0" "$exit_code"
T1_CURRENT="$(git -C "$T1_REPO" branch --show-current)"
assert_eq "現在のブランチが feature に切り替わっている" "feature" "$T1_CURRENT"

rm -rf "$T1_REPO"

# ========== T2: 引数0個は拒否される ==========
run_case "T2: 引数0個は非ゼロ終了で Usage が出力される"

T2_REPO="$(make_isolated_repo)"

set +e
stderr=$(CLAUDE_PROJECT_DIR="$T2_REPO" bash "$TARGET" 2>&1 1>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 非ゼロ" "1" "$exit_code"
assert_contains "stderr に Usage が出力される" "Usage" "$stderr"

rm -rf "$T2_REPO"

# ========== T3: 引数2個は拒否される ==========
run_case "T3: 引数2個は非ゼロ終了で Usage が出力される（余剰引数注入対策）"

T3_REPO="$(make_isolated_repo)"

set +e
stderr=$(CLAUDE_PROJECT_DIR="$T3_REPO" bash "$TARGET" "feature" "main" 2>&1 1>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 非ゼロ" "1" "$exit_code"
assert_contains "stderr に Usage が出力される" "Usage" "$stderr"
T3_CURRENT="$(git -C "$T3_REPO" branch --show-current)"
assert_eq "ブランチは切り替わらず main のまま" "main" "$T3_CURRENT"

rm -rf "$T3_REPO"

# ========== T4: 先頭が '-' の引数（フラグ形）は拒否される ==========
run_case "T4: '-f' や '--discard-changes' など先頭が '-' の引数は非ゼロ終了で拒否され、dirty worktree も破棄されない"

T4_REPO="$(make_isolated_repo)"
echo "dirty content" > "$T4_REPO/dirty.txt"
git -C "$T4_REPO" add dirty.txt
echo "more dirty (unstaged)" >> "$T4_REPO/dirty.txt"

for flag in "-f" "--discard-changes" "-C"; do
  set +e
  stderr=$(CLAUDE_PROJECT_DIR="$T4_REPO" bash "$TARGET" "$flag" 2>&1 1>/dev/null)
  exit_code=$?
  set -e
  assert_eq "フラグ '$flag': exit code 非ゼロ" "1" "$exit_code"
  assert_contains "フラグ '$flag': stderr に拒否理由が出力される" "invalid branch" "$stderr"
done

T4_DIRTY_CONTENT="$(cat "$T4_REPO/dirty.txt")"
assert_contains "dirty worktree の内容が破棄されず保持されている" "more dirty (unstaged)" "$T4_DIRTY_CONTENT"
T4_CURRENT="$(git -C "$T4_REPO" branch --show-current)"
assert_eq "ブランチは切り替わらず main のまま" "main" "$T4_CURRENT"

rm -rf "$T4_REPO"

# ========== T5: 不正な ref 名は拒否される ==========
run_case "T5: check-ref-format に反する ref 名は非ゼロ終了で拒否される"

T5_REPO="$(make_isolated_repo)"

for bad_ref in "" "feature..x" "feature~1" "feature^" "feature:x" "feature x"; do
  set +e
  stderr=$(CLAUDE_PROJECT_DIR="$T5_REPO" bash "$TARGET" "$bad_ref" 2>&1 1>/dev/null)
  exit_code=$?
  set -e
  assert_eq "不正 ref '$bad_ref': exit code 非ゼロ" "1" "$exit_code"
done

rm -rf "$T5_REPO"

# ========== T6: 未存在ブランチはエラーを伝播する ==========
run_case "T6: 未存在ブランチ（それ自体は妥当な ref 名）を指定すると git のエラーが伝播し exit 非ゼロ"

T6_REPO="$(make_isolated_repo)"

set +e
stderr=$(CLAUDE_PROJECT_DIR="$T6_REPO" bash "$TARGET" "no-such-branch" 2>&1 1>/dev/null)
exit_code=$?
set -e

assert_not_eq "exit code は 0 ではない（git switch 自体の失敗が伝播する）" "0" "$exit_code"
T6_CURRENT="$(git -C "$T6_REPO" branch --show-current)"
assert_eq "ブランチは切り替わらず main のまま" "main" "$T6_CURRENT"

rm -rf "$T6_REPO"

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
