#!/usr/bin/env bash
# scripts/team-compute-waves.sh の単体テスト。
# 6 ケース（単一 / 並列 / 線形 / 菱形 / サイクル / 存在しない依存）を網羅。
#
# Usage:
#   bash scripts/__tests__/team-compute-waves.test.sh
#
# Exit code:
#   0 = 全ケース pass
#   1 = いずれか fail

set -euo pipefail

script_dir="$(cd "$(dirname "$0")/.." && pwd)"
target="${script_dir}/team-compute-waves.sh"

if [[ ! -x "$target" ]]; then
  echo "target not found or not executable: $target" >&2
  exit 1
fi

fail_count=0
pass_count=0

# 共通: テストケース実行ヘルパ
# args: <case-num> <description> <expected-exit> <fixture-content> [expected-stdout-grep] [expected-stderr-grep]
run_case() {
  local n="$1"
  local desc="$2"
  local expected_exit="$3"
  local fixture="$4"
  local stdout_pattern="${5:-}"
  local stderr_pattern="${6:-}"

  local fixture_path="/tmp/team-compute-waves-test-${n}.json"
  local stdout_file="/tmp/team-compute-waves-test-${n}.stdout"
  local stderr_file="/tmp/team-compute-waves-test-${n}.stderr"

  echo "$fixture" > "$fixture_path"

  set +e
  bash "$target" "$fixture_path" >"$stdout_file" 2>"$stderr_file"
  local actual_exit=$?
  set -e

  local result="OK"

  if [[ "$actual_exit" != "$expected_exit" ]]; then
    result="FAIL: exit code mismatch (expected=${expected_exit}, actual=${actual_exit})"
  elif [[ -n "$stdout_pattern" ]] && ! grep -qE "$stdout_pattern" "$stdout_file"; then
    result="FAIL: stdout does not match pattern: $stdout_pattern"
  elif [[ -n "$stderr_pattern" ]] && ! grep -qE "$stderr_pattern" "$stderr_file"; then
    result="FAIL: stderr does not match pattern: $stderr_pattern"
  fi

  if [[ "$result" == "OK" ]]; then
    echo "[OK] case ${n}: ${desc}"
    pass_count=$((pass_count + 1))
  else
    echo "[FAIL] case ${n}: ${desc}"
    echo "        ${result}"
    echo "        stdout: $(cat "$stdout_file")"
    echo "        stderr: $(cat "$stderr_file")"
    fail_count=$((fail_count + 1))
  fi

  rm -f "$fixture_path" "$stdout_file" "$stderr_file"
}

# ケース 1: 単一タスク
run_case 1 "単一タスク (depends_on=[])" 0 \
  '{"tasks":[{"id":"task-1_1_1","depends_on":[]}]}' \
  '"wave":0.*task-1_1_1'

# ケース 2: 4 タスク並列
run_case 2 "4 タスク並列 (depends_on=[] のみ)" 0 \
  '{"tasks":[{"id":"task-1_1_1","depends_on":[]},{"id":"task-1_1_2","depends_on":[]},{"id":"task-1_1_3","depends_on":[]},{"id":"task-1_1_4","depends_on":[]}]}' \
  '"wave":0.*task-1_1_1.*task-1_1_4'

# ケース 3: 線形依存 (A→B→C→D)
run_case 3 "線形依存 (4 wave)" 0 \
  '{"tasks":[{"id":"a","depends_on":[]},{"id":"b","depends_on":["a"]},{"id":"c","depends_on":["b"]},{"id":"d","depends_on":["c"]}]}' \
  '"wave":3.*"d"'

# ケース 4: 菱形依存 (A → {B,C} → D)
run_case 4 "菱形依存 (3 wave)" 0 \
  '{"tasks":[{"id":"a","depends_on":[]},{"id":"b","depends_on":["a"]},{"id":"c","depends_on":["a"]},{"id":"d","depends_on":["b","c"]}]}' \
  '"wave":2.*"d"'

# ケース 5: サイクル
run_case 5 "サイクル検出 (A→B→A)" 1 \
  '{"tasks":[{"id":"a","depends_on":["b"]},{"id":"b","depends_on":["a"]}]}' \
  "" \
  '^CYCLE:'

# ケース 6: 存在しない依存
run_case 6 "存在しない依存先" 1 \
  '{"tasks":[{"id":"a","depends_on":["nonexistent"]}]}' \
  "" \
  '^UNKNOWN_DEPENDENCY:'

echo ""
echo "==============================================="
echo "Test summary: ${pass_count} passed, ${fail_count} failed"
echo "==============================================="

if [[ "$fail_count" -gt 0 ]]; then
  exit 1
fi

exit 0
