#!/usr/bin/env bash
# team-worktree-merge.sh の単体テスト（dirty task worktree のマージ拒否ガード）。
#
# 実行環境前提: Linux / GNU coreutils + git。bash 3.2 / macOS 互換は目標外。
#
# 検証対象: generator が必須ファイルを未コミット（未 stage / untracked）のまま残した
# dirty な task worktree を、merge スクリプトが exit 3 で拒否し、未コミットファイルを
# 温存すること（codex P1: 承認挙動の取りこぼし + cleanup --force による消失の防止）。
#
# Usage:
#   bash scripts/__tests__/team-worktree-merge.test.sh
#
# Exit code:
#   0 = 全ケース pass
#   1 = いずれか fail

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MERGE="${SCRIPT_DIR}/../team-worktree-merge.sh"
SETUP="${SCRIPT_DIR}/../team-worktree-setup.sh"

for f in "$MERGE" "$SETUP"; do
  if [[ ! -f "$f" ]]; then
    echo "script not found: $f" >&2
    exit 1
  fi
done
if ! command -v git >/dev/null 2>&1; then
  echo "required command not found: git" >&2
  exit 1
fi

pass_count=0
fail_count=0
case_count=0

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

run_case() {
  local label="$1"
  case_count=$((case_count + 1))
  echo ""
  echo "[Case $case_count] $label"
}

TMPDIR_GLOBAL=""
cleanup_global() {
  if [[ -n "${TMPDIR_GLOBAL:-}" && -d "${TMPDIR_GLOBAL:-}" ]]; then
    rm -rf "$TMPDIR_GLOBAL"
  fi
}
trap cleanup_global EXIT
TMPDIR_GLOBAL="$(mktemp -d)"

INTEGRATION="claude/itg"

# ---- フィクスチャ: integration ブランチを HEAD に持つ隔離リポジトリ ----
make_repo() {
  local repo
  repo="$(mktemp -d "$TMPDIR_GLOBAL/repo.XXXXXX")"
  git init -q "$repo"
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "test"
  printf 'seed\n' > "$repo/seed.txt"
  git -C "$repo" add seed.txt
  git -C "$repo" commit -q -m "init"
  # integration ブランチ (claude/*) を作成して HEAD にする
  git -C "$repo" switch -q -c "$INTEGRATION"
  echo "$repo"
}

# ---- フィクスチャ: node_modules を gitignore しないリポジトリ ----
# team-worktree-setup.sh が無条件で張る node_modules symlink（ルート + ネスト）が
# dirty ガードを誤発火させないことを検証するための最悪ケース構成。
make_repo_with_nm() {
  local repo
  repo="$(mktemp -d "$TMPDIR_GLOBAL/repo.XXXXXX")"
  git init -q "$repo"
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "test"
  printf 'seed\n' > "$repo/seed.txt"
  mkdir -p "$repo/packages/foo"
  printf 'export const x = 1\n' > "$repo/packages/foo/index.js"
  git -C "$repo" add seed.txt packages/foo/index.js
  git -C "$repo" commit -q -m "init"
  # node_modules を gitignore せず実ディレクトリとして用意（setup が symlink を張る材料）
  mkdir -p "$repo/node_modules" "$repo/packages/foo/node_modules"
  printf 'dep\n' > "$repo/node_modules/dep.js"
  printf 'dep\n' > "$repo/packages/foo/node_modules/dep.js"
  git -C "$repo" switch -q -c "$INTEGRATION"
  echo "$repo"
}

# worktree を作成し絶対パスを echo する（stderr は捨てる）
setup_worktree() {
  local repo="$1" sid="$2" tid="$3"
  ( cd "$repo" && bash "$SETUP" "$sid" "$tid" "$INTEGRATION" 2>/dev/null )
}

# merge を実行し "<exit_code>\n<stderr>" を返す
run_merge() {
  local repo="$1" sid="$2" tid="$3"
  local err rc
  err="$( cd "$repo" && bash "$MERGE" "$sid" "$tid" "$INTEGRATION" 2>&1 1>/dev/null )"
  rc=$?
  printf '%s\n%s' "$rc" "$err"
}

# ========== T1: clean な worktree は正常にマージされる ==========
run_case "T1: コミット済みでクリーンな task worktree は exit 0 でマージされる"

T1_REPO="$(make_repo)"
T1_WT="$(setup_worktree "$T1_REPO" sess1 task1)"
printf 'feature\n' > "$T1_WT/feature.txt"
git -C "$T1_WT" add feature.txt
git -C "$T1_WT" commit -q -m "feat: add feature

Refs: task1"

T1_OUT="$(run_merge "$T1_REPO" sess1 task1)"
T1_RC="$(printf '%s' "$T1_OUT" | head -n1)"
assert_eq "clean worktree は exit 0" "0" "$T1_RC"
# task_branch が integration に取り込まれている
if git -C "$T1_REPO" merge-base --is-ancestor "team-task/sess1/task1" "$INTEGRATION" 2>/dev/null; then
  merged="yes"; else merged="no"; fi
assert_eq "task_branch が integration にマージ済み" "yes" "$merged"

# ========== T2: untracked ファイルが残る dirty worktree は拒否される ==========
run_case "T2: untracked の取りこぼしがある worktree は exit 3 で拒否され未コミットファイルが温存される"

T2_REPO="$(make_repo)"
T2_WT="$(setup_worktree "$T2_REPO" sess2 task2)"
printf 'main change\n' > "$T2_WT/impl.txt"
git -C "$T2_WT" add impl.txt
git -C "$T2_WT" commit -q -m "feat: impl

Refs: task2"
# generator が git add し忘れた生成物を再現（untracked）
printf 'generated but forgotten\n' > "$T2_WT/generated.txt"

T2_OUT="$(run_merge "$T2_REPO" sess2 task2)"
T2_RC="$(printf '%s' "$T2_OUT" | head -n1)"
T2_ERR="$(printf '%s' "$T2_OUT" | tail -n +2)"
assert_eq "dirty(untracked) worktree は exit 3" "3" "$T2_RC"
assert_contains "stderr に DIRTY_TASK_WORKTREE マーカー" "DIRTY_TASK_WORKTREE: task2" "$T2_ERR"
assert_contains "stderr に取りこぼしファイルが列挙される" "generated.txt" "$T2_ERR"
assert_path_exists "未コミットファイルが温存される（merge 拒否でクリーンアップ未実行）" "$T2_WT/generated.txt"
# integration に取り込まれていない（部分マージしない）
if git -C "$T2_REPO" merge-base --is-ancestor "team-task/sess2/task2" "$INTEGRATION" 2>/dev/null; then
  merged2="yes"; else merged2="no"; fi
assert_eq "拒否時は integration へ部分マージしない" "no" "$merged2"

# ========== T3: tracked ファイルの未 stage 変更がある dirty worktree も拒否される ==========
run_case "T3: tracked ファイルの未 stage 変更がある worktree も exit 3 で拒否される"

T3_REPO="$(make_repo)"
T3_WT="$(setup_worktree "$T3_REPO" sess3 task3)"
printf 'v1\n' > "$T3_WT/impl.txt"
git -C "$T3_WT" add impl.txt
git -C "$T3_WT" commit -q -m "feat: impl v1

Refs: task3"
# コミット後に tracked ファイルを stage せず変更
printf 'v2-uncommitted\n' >> "$T3_WT/impl.txt"

T3_OUT="$(run_merge "$T3_REPO" sess3 task3)"
T3_RC="$(printf '%s' "$T3_OUT" | head -n1)"
assert_eq "dirty(unstaged) worktree は exit 3" "3" "$T3_RC"

# ========== T4: 既マージは冪等（再実行で exit 0） ==========
run_case "T4: clean マージ後の再実行は ALREADY_MERGED で exit 0（冪等）"

T4_OUT="$(run_merge "$T1_REPO" sess1 task1)"
T4_RC="$(printf '%s' "$T4_OUT" | head -n1)"
assert_eq "再マージは exit 0" "0" "$T4_RC"

# ========== T5: setup の node_modules symlink は clean マージを妨げない（誤検知回帰） ==========
run_case "T5: node_modules を gitignore しないリポジトリでも setup の symlink で誤検知しない"

T5_REPO="$(make_repo_with_nm)"
T5_WT="$(setup_worktree "$T5_REPO" sess5 task5)"
assert_path_exists "setup がルート node_modules symlink を張る" "$T5_WT/node_modules"
assert_path_exists "setup がネスト node_modules symlink を張る" "$T5_WT/packages/foo/node_modules"
printf 'feature\n' > "$T5_WT/feature.txt"
git -C "$T5_WT" add feature.txt
git -C "$T5_WT" commit -q -m "feat: add feature

Refs: task5"

T5_OUT="$(run_merge "$T5_REPO" sess5 task5)"
T5_RC="$(printf '%s' "$T5_OUT" | head -n1)"
assert_eq "node_modules symlink があっても clean なら exit 0" "0" "$T5_RC"

# ========== T6: node_modules symlink 併存下でも真の取りこぼしは検出する ==========
run_case "T6: node_modules symlink があっても未コミットの取りこぼしは exit 3（node_modules は列挙しない）"

T6_REPO="$(make_repo_with_nm)"
T6_WT="$(setup_worktree "$T6_REPO" sess6 task6)"
printf 'impl\n' > "$T6_WT/impl.txt"
git -C "$T6_WT" add impl.txt
git -C "$T6_WT" commit -q -m "feat: impl

Refs: task6"
printf 'generated but forgotten\n' > "$T6_WT/generated.txt"

T6_OUT="$(run_merge "$T6_REPO" sess6 task6)"
T6_RC="$(printf '%s' "$T6_OUT" | head -n1)"
T6_ERR="$(printf '%s' "$T6_OUT" | tail -n +2)"
assert_eq "node_modules symlink 併存でも取りこぼしは exit 3" "3" "$T6_RC"
assert_contains "stderr に取りこぼしファイル" "generated.txt" "$T6_ERR"
assert_not_contains "stderr に node_modules を列挙しない（除外済み）" "node_modules" "$T6_ERR"

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
