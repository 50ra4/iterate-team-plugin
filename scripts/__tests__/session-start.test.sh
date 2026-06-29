#!/usr/bin/env bash
# session-start.sh の単体テスト（runtime state の git 無視登録）。
#
# 実行環境前提: Linux / GNU coreutils + jq + git（dev container・メイン checkout）。
# bash 3.2 / macOS 互換は目標外。
#
# 検証対象: SessionStart hook が .iterate-team/state/ を seed する前に
# .git/info/exclude へ無視登録し、初回インストールのクリーン checkout で
# `/iterate-team` step 0.1 の `git status --porcelain` dirty check を誤発火させないこと。
#
# Usage:
#   bash scripts/__tests__/session-start.test.sh
#
# Exit code:
#   0 = 全ケース pass
#   1 = いずれか fail

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${SCRIPT_DIR}/../session-start.sh"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if [[ ! -f "$TARGET" ]]; then
  echo "session-start.sh not found at: $TARGET" >&2
  exit 1
fi

# 依存コマンド前提（無ければ fail closed: テストを通過させない）
for cmd in jq git; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "required command not found: $cmd" >&2
    exit 1
  fi
done

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
    echo "  PASS: $label (correctly absent: $path)"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL: $label (expected to be absent but exists: $path)" >&2
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

# ---- フィクスチャ: hook 実行ヘルパー ----
# stdin に hook 入力 JSON を渡し、CLAUDE_PROJECT_DIR を project_dir に設定して hook を実行する。
# stdout（hook の additionalContext JSON）は捨て、副作用（exclude / seed）のみ検証する。
# CLAUDE_CONFIG_DIR は host プロファイル固定（dev container 判定を避ける）。
run_hook() {
  local project_dir="$1" session_id="${2:-test-session-0001}" model="${3:-claude-sonnet-4-6}"
  local input
  input="$(jq -nc --arg s "$session_id" --arg m "$model" \
    '{session_id:$s, model:$m, source:"startup"}')"
  printf '%s' "$input" \
    | CLAUDE_PROJECT_DIR="$project_dir" \
      CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
      CLAUDE_CONFIG_DIR="" \
      bash "$TARGET" >/dev/null 2>&1
}

STATE_PATTERN="/.iterate-team/state/"

# ========== T1: クリーン初回 checkout で state が無視登録され dirty check が誤発火しない ==========
run_case "T1: クリーン git checkout で seed 後も git status が clean（codex P1 回帰）"

T1_REPO="$(make_isolated_repo)"
run_hook "$T1_REPO" "team-session-t1"

T1_EXCLUDE="$T1_REPO/.git/info/exclude"
assert_path_exists "exclude ファイルが存在" "$T1_EXCLUDE"
assert_contains "exclude に state 無視パターンが追記される" "$STATE_PATTERN" "$(cat "$T1_EXCLUDE" 2>/dev/null)"
assert_path_exists "init.json が seed される" "$T1_REPO/.iterate-team/state/sessions/team-session-t1/init.json"
assert_path_exists "escalation-template.md が seed される" "$T1_REPO/.iterate-team/state/escalation-template.md"

T1_STATUS="$(git -C "$T1_REPO" status --porcelain)"
assert_not_contains "git status --porcelain に .iterate-team が現れない（dirty 誤発火なし）" ".iterate-team" "$T1_STATUS"
# git status check-ignore でも seed ファイルが無視されることを確認
git -C "$T1_REPO" check-ignore -q .iterate-team/state/escalation-template.md
assert_eq "check-ignore が state seed を無視と判定" "0" "$?"

# ========== T2: 冪等（複数セッションで二重追記しない） ==========
run_case "T2: hook を 2 回実行しても exclude パターンは 1 行のみ（冪等）"

T2_REPO="$(make_isolated_repo)"
run_hook "$T2_REPO" "team-session-t2a"
run_hook "$T2_REPO" "team-session-t2b"

T2_COUNT="$(grep -cxF "$STATE_PATTERN" "$T2_REPO/.git/info/exclude" 2>/dev/null || echo 0)"
assert_eq "exclude の state パターンは 1 行" "1" "$T2_COUNT"
assert_path_exists "後発セッションの init.json も独立して seed" "$T2_REPO/.iterate-team/state/sessions/team-session-t2b/init.json"

# ========== T3: 既に .gitignore で無視済みなら exclude へ追記しない ==========
run_case "T3: .gitignore で .iterate-team/ 無視済みなら exclude を変更しない（no-op）"

T3_REPO="$(make_isolated_repo)"
printf '.iterate-team/\n' > "$T3_REPO/.gitignore"
run_hook "$T3_REPO" "team-session-t3"

T3_EXCLUDE_BODY="$(cat "$T3_REPO/.git/info/exclude" 2>/dev/null || true)"
assert_not_contains "既に無視済みなら exclude に追記されない" "$STATE_PATTERN" "$T3_EXCLUDE_BODY"
assert_path_exists "no-op でも init.json は seed される" "$T3_REPO/.iterate-team/state/sessions/team-session-t3/init.json"

# ========== T4: project_dir がサブディレクトリでも toplevel 相対で anchor される ==========
run_case "T4: project_dir がリポジトリのサブディレクトリでも正しく anchor + clean"

T4_REPO="$(make_isolated_repo)"
mkdir -p "$T4_REPO/sub/dir"
run_hook "$T4_REPO/sub/dir" "team-session-t4"

T4_EXCLUDE_BODY="$(cat "$T4_REPO/.git/info/exclude" 2>/dev/null || true)"
assert_contains "exclude が prefix 付きで anchor される" "/sub/dir/.iterate-team/state/" "$T4_EXCLUDE_BODY"
T4_STATUS="$(git -C "$T4_REPO" status --porcelain)"
assert_not_contains "サブディレクトリ seed もルートの git status に現れない" ".iterate-team" "$T4_STATUS"

# ========== T5: 非 git ディレクトリでも graceful（init.json は seed） ==========
run_case "T5: git 管理外ディレクトリでも hook は失敗せず init.json を seed する"

T5_DIR="$(mktemp -d "$TMPDIR_GLOBAL/plain.XXXXXX")"
run_hook "$T5_DIR" "team-session-t5"

assert_path_exists "非 git でも init.json が seed される" "$T5_DIR/.iterate-team/state/sessions/team-session-t5/init.json"
assert_path_not_exists "非 git ディレクトリに .git を作らない" "$T5_DIR/.git"

# ========== T6: 末尾改行の無い既存 exclude を壊さず追記する ==========
run_case "T6: 末尾改行なしの既存 exclude でも直前パターンと連結しない"

T6_REPO="$(make_isolated_repo)"
# 末尾改行を意図的に欠いた既存パターンを書く（printf に \n を付けない）
printf '*.log' > "$T6_REPO/.git/info/exclude"
run_hook "$T6_REPO" "team-session-t6"

T6_EXCLUDE_BODY="$(cat "$T6_REPO/.git/info/exclude" 2>/dev/null || true)"
assert_contains "既存パターン *.log が保持される" "*.log" "$T6_EXCLUDE_BODY"
assert_contains "state パターンも独立行として追記される" "$STATE_PATTERN" "$T6_EXCLUDE_BODY"
# 連結事故（*.log/.iterate-team/state/）が起きていないことを確認
assert_not_contains "直前パターンと連結していない" "*.log/.iterate-team" "$T6_EXCLUDE_BODY"

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
