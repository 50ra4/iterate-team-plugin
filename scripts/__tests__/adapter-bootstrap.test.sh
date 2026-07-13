#!/usr/bin/env bash
# adapter-bootstrap.sh の単体テスト
#
# 実行環境前提: Linux / GNU coreutils + git（dev container・メイン checkout）。
# bash 3.2 / macOS 互換は目標外。オフラインで完結する（vendor/agent-os/ 配下の
# ファイルをローカルコピーするのみでネットワークアクセスを行わない）。
#
# 仕様の正本: <plugin_root>/operations/adapter-policy.md（§2・§9）
#
# Usage:
#   bash scripts/__tests__/adapter-bootstrap.test.sh
#
# Exit code:
#   0 = 全ケース pass
#   1 = いずれか fail

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${SCRIPT_DIR}/../adapter-bootstrap.sh"
PLUGIN_ROOT="${SCRIPT_DIR}/../.."

if [[ ! -f "$TARGET" ]]; then
  echo "adapter-bootstrap.sh not found at: $TARGET" >&2
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

assert_path_not_exists() {
  local label="$1" path="$2"
  if [[ ! -e "$path" ]]; then
    echo "  PASS: $label (does not exist: $path)"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL: $label (unexpectedly exists: $path)" >&2
    fail_count=$((fail_count + 1))
  fi
}

assert_nonzero() {
  local label="$1" code="$2"
  if [[ "$code" -ne 0 ]]; then
    echo "  PASS: $label (exit code $code)"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL: $label (expected non-zero exit code, got 0)" >&2
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

ADAPTER_STATE_FILES=(project-profile learned-rules failure-log review-feedback-log evals command-map architecture-map risk-map)

# ========== T1: --target が存在しないディレクトリだと明確に拒否される ==========
run_case "T1: --target が存在しないディレクトリだと非ゼロ終了 + stderr にエラーが出力される"

T1_NONEXISTENT="$TMPDIR_GLOBAL/does-not-exist-$$"

set +e
stderr=$(bash "$TARGET" --target "$T1_NONEXISTENT" 2>&1 1>/dev/null)
exit_code=$?
set -e

assert_nonzero "exit code 非ゼロ" "$exit_code"
assert_contains "stderr に target 不在の理由が出力される" "does not exist" "$stderr"
assert_path_not_exists "存在しない target 配下には何も作られない" "$T1_NONEXISTENT/.agent-os"

# ========== T2: fresh target で --adapter-only の既定インストール ==========
run_case "T2: fresh target に既定 --adapter-only を実行すると 8 スキャフォールド + GLOBAL_AGENTS.md が作られる"

T2_REPO="$(make_isolated_repo)"

set +e
stdout=$(bash "$TARGET" --target "$T2_REPO" 2>&1)
exit_code=$?
set -e

assert_eq "exit code 0" "0" "$exit_code"
assert_path_exists "$T2_REPO/.agent-os/ が作られる" "$T2_REPO/.agent-os"

for f in "${ADAPTER_STATE_FILES[@]}"; do
  assert_path_exists "$f.md が設置される" "$T2_REPO/.agent-os/$f.md"
done
assert_path_exists "GLOBAL_AGENTS.md が設置される" "$T2_REPO/.agent-os/GLOBAL_AGENTS.md"

assert_path_not_exists ".claude/skills は adapter-only では設置されない" "$T2_REPO/.claude/skills"
assert_path_not_exists ".claude/agents は adapter-only では設置されない" "$T2_REPO/.claude/agents"
assert_path_not_exists "root CLAUDE.md は adapter-only では設置されない" "$T2_REPO/CLAUDE.md"
assert_path_not_exists "root AGENTS.md は adapter-only では設置されない" "$T2_REPO/AGENTS.md"
assert_path_not_exists ".agent-os/skills/ は adapter-only では設置されない" "$T2_REPO/.agent-os/skills"

assert_contains "summary に Installed 件数が出力される" "Installed:" "$stdout"

rm -rf "$T2_REPO"

# ========== T3: 冪等性 / 保護 — 既存の 8 ファイルは再実行しても上書きされない ==========
run_case "T3: 既存の learned-rules.md（sentinel 入り）は再実行しても PROTECTED として保持される"

T3_REPO="$(make_isolated_repo)"
mkdir -p "$T3_REPO/.agent-os"
SENTINEL="## Rule: sentinel-do-not-overwrite-me"
printf '%s\n' "$SENTINEL" > "$T3_REPO/.agent-os/learned-rules.md"

set +e
stdout=$(bash "$TARGET" --target "$T3_REPO" 2>&1)
exit_code=$?
set -e

assert_eq "exit code 0" "0" "$exit_code"
assert_contains "stdout に PROTECTED: 行が出力される" "PROTECTED:" "$stdout"
assert_contains "stdout の PROTECTED 行が learned-rules.md を指す" "learned-rules.md" "$stdout"

T3_CONTENT="$(cat "$T3_REPO/.agent-os/learned-rules.md")"
assert_eq "sentinel が上書きされずそのまま残る" "$SENTINEL" "$T3_CONTENT"

# 他の 7 ファイル + GLOBAL_AGENTS.md は fresh install されている（保護されるのは
# 既存だった learned-rules.md のみ）ことも確認する。
for f in project-profile failure-log review-feedback-log evals command-map architecture-map risk-map; do
  assert_path_exists "$f.md は新規設置される" "$T3_REPO/.agent-os/$f.md"
done
assert_path_exists "GLOBAL_AGENTS.md は新規設置される" "$T3_REPO/.agent-os/GLOBAL_AGENTS.md"

rm -rf "$T3_REPO"

# ========== T4: symlink 拒否 — .agent-os が target 外を指す symlink だと安全に拒否される ==========
run_case "T4: <target>/.agent-os が target 外を指す symlink だと非ゼロ終了で拒否され、symlink 経由で何も書き込まれない"

T4_REPO="$(make_isolated_repo)"
T4_OUTSIDE="$(mktemp -d "$TMPDIR_GLOBAL/outside.XXXXXX")"
ln -s "$T4_OUTSIDE" "$T4_REPO/.agent-os"

set +e
stderr=$(bash "$TARGET" --target "$T4_REPO" 2>&1 1>/dev/null)
exit_code=$?
set -e

assert_nonzero "exit code 非ゼロ" "$exit_code"
assert_contains "stderr に symlink 拒否の理由が出力される" "symlink" "$stderr"

# symlink 経由で外部ディレクトリへ何も書かれていないこと（何も作られていない）。
T4_OUTSIDE_ENTRIES="$(find "$T4_OUTSIDE" -mindepth 1 | wc -l | tr -d ' ')"
assert_eq "symlink 先の外部ディレクトリには何も書き込まれない" "0" "$T4_OUTSIDE_ENTRIES"

# .agent-os 自体は symlink のまま変更されていないこと。
if [[ -L "$T4_REPO/.agent-os" ]]; then
  echo "  PASS: .agent-os の symlink 自体はそのまま残っている（置き換えられていない）"
  pass_count=$((pass_count + 1))
else
  echo "  FAIL: .agent-os の symlink が失われている（何らかの書込みが発生した疑い）" >&2
  fail_count=$((fail_count + 1))
fi

rm -f "$T4_REPO/.agent-os"
rm -rf "$T4_OUTSIDE"
rm -rf "$T4_REPO"

# ========== T5: GLOBAL_AGENTS.md は --force 指定時のみ上書きされる ==========
run_case "T5: 既存 GLOBAL_AGENTS.md は --force なしでは保持され、--force 指定時のみ上書きされる"

T5_REPO="$(make_isolated_repo)"
mkdir -p "$T5_REPO/.agent-os"
printf 'stale content\n' > "$T5_REPO/.agent-os/GLOBAL_AGENTS.md"

set +e
stdout_no_force=$(bash "$TARGET" --target "$T5_REPO" 2>&1)
exit_code_no_force=$?
set -e

assert_eq "--force なし: exit code 0" "0" "$exit_code_no_force"
assert_eq "--force なし: 既存の GLOBAL_AGENTS.md は変更されない" "stale content" "$(cat "$T5_REPO/.agent-os/GLOBAL_AGENTS.md")"
assert_contains "--force なし: SKIPPED として報告される" "SKIPPED" "$stdout_no_force"

UPSTREAM_CONTENT="$(cat "$PLUGIN_ROOT/vendor/agent-os/GLOBAL_AGENTS.md")"

set +e
stdout_force=$(bash "$TARGET" --target "$T5_REPO" --force 2>&1)
exit_code_force=$?
set -e

assert_eq "--force あり: exit code 0" "0" "$exit_code_force"
assert_eq "--force あり: GLOBAL_AGENTS.md が upstream 内容で上書きされる" "$UPSTREAM_CONTENT" "$(cat "$T5_REPO/.agent-os/GLOBAL_AGENTS.md")"
assert_contains "--force あり: stdout に Installed: が出力される" "Installed:" "$stdout_force"

rm -rf "$T5_REPO"

# ========== T6: --reset-adapter は既存の保護ファイルをバックアップしてから再設置する ==========
run_case "T6: --reset-adapter は既存 learned-rules.md を backup-<timestamp>/ へ退避してから新規スキャフォールドを設置する"

T6_REPO="$(make_isolated_repo)"
mkdir -p "$T6_REPO/.agent-os"
T6_SENTINEL="## Rule: to-be-backed-up"
printf '%s\n' "$T6_SENTINEL" > "$T6_REPO/.agent-os/learned-rules.md"

set +e
stdout=$(bash "$TARGET" --target "$T6_REPO" --reset-adapter 2>&1)
exit_code=$?
set -e

assert_eq "exit code 0" "0" "$exit_code"
assert_contains "stdout に Backed up: が出力される" "Backed up:" "$stdout"

T6_BACKUP_DIRS=("$T6_REPO"/.agent-os/backup-*)
if [[ -d "${T6_BACKUP_DIRS[0]:-}" ]]; then
  echo "  PASS: backup-<timestamp>/ ディレクトリが作られる"
  pass_count=$((pass_count + 1))
  T6_BACKUP_FILE="${T6_BACKUP_DIRS[0]}/learned-rules.md"
  assert_path_exists "sentinel 入り learned-rules.md がバックアップされる" "$T6_BACKUP_FILE"
  assert_eq "バックアップされた内容が sentinel と一致する" "$T6_SENTINEL" "$(cat "$T6_BACKUP_FILE" 2>/dev/null)"
else
  echo "  FAIL: backup-<timestamp>/ ディレクトリが作られていない" >&2
  fail_count=$((fail_count + 1))
fi

# 新しい learned-rules.md が設置され、もう sentinel ではないこと。
T6_NEW_CONTENT="$(cat "$T6_REPO/.agent-os/learned-rules.md" 2>/dev/null || true)"
if [[ "$T6_NEW_CONTENT" != "$T6_SENTINEL" ]]; then
  echo "  PASS: 再設置後の learned-rules.md は sentinel ではなく新規スキャフォールド内容"
  pass_count=$((pass_count + 1))
else
  echo "  FAIL: 再設置後も learned-rules.md が sentinel のままになっている" >&2
  fail_count=$((fail_count + 1))
fi

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
