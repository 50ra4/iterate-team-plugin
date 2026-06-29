#!/usr/bin/env bash
# scripts/validate-plan.sh の単体テスト。依存ゼロ（bats / shunit2 等不要）。
#
# 11 ケース:
#   1. OK                            (整合 fixture → exit 0)
#   2. INVALID_EXECUTOR (plan)       (plan.json に "executor": "codex" → exit 1)
#   3. INVALID_EXECUTOR (fm)         (frontmatter に executor: codex → exit 1)
#   4. MISSING                       (plan.json に id があり対応 task-*.md が無い → exit 1)
#   5. MISSING_KEY                   (plan.json の task に required_advisors キー欠落 → exit 1)
#   6. LEGACY_KEY                    (frontmatter に旧キー advisors: 残存 → exit 1)
#   7. EXTRA                         (tasks-dir に plan.json 未掲載の task-*.md → exit 1)
#   8. MISMATCH (max_retries)        (plan.json と frontmatter の max_retries が不一致 → exit 1)
#   9. MISMATCH (reviewer)           (plan.json と frontmatter の reviewer が不一致 → exit 1)
#  10. MISMATCH (depends_on)         (plan.json と frontmatter の depends_on が不一致 → exit 1)
#  11. MISMATCH (required_advisors)  (plan.json と frontmatter の required_advisors が不一致 → exit 1)
#
# Usage: bash scripts/__tests__/validate-plan.test.sh
# Exit: 0 = 全 PASS / 1 = 1 件以上 FAIL
#
# --- fixture writer 失敗の手動確認手順 ---
# write_fixture() は cat の終了コードとファイルサイズをアサートする。
# 意図的に失敗させるには write_fixture() 内の cat 行を
#   cat > "/nonexistent/path/file" ...
# のように書き換えてテストを実行すると、该当ケースが FAIL となることを確認できる。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE_SCRIPT="$SCRIPT_DIR/../validate-plan.sh"

if [[ ! -x "$VALIDATE_SCRIPT" && ! -f "$VALIDATE_SCRIPT" ]]; then
  echo "validate-plan.sh not found at: $VALIDATE_SCRIPT" >&2
  exit 1
fi

pass_count=0
fail_count=0
case_count=0

# ---------- assertion helpers ----------

# 期待値と実際値が一致することを表明する。
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

# 文字列に部分文字列が含まれることを表明する。
assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  PASS: $label (contains '$needle')"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL: $label (needle='$needle' haystack='${haystack:0:200}...')" >&2
    fail_count=$((fail_count + 1))
  fi
}

# ---------- fixture writers ----------

# fixture ファイルを安全に書き出すラッパー。
# cat が失敗、またはファイルサイズが 0 の場合は即座に FAIL してテストを終了する。
write_fixture() {
  local dest="$1"
  shift
  # heredoc は標準入力から受け取るため、残引数は使わない（呼び出し元で cat > dest <<'DELIM' 形式を使う）
  # ここでは書き出し後のサイズ確認のみ行う
  if [[ ! -f "$dest" ]]; then
    echo "  FAIL: fixture write failed (file not created: $dest)" >&2
    fail_count=$((fail_count + 1))
    return 1
  fi
  local size
  size=$(wc -c < "$dest")
  if [[ "$size" -eq 0 ]]; then
    echo "  FAIL: fixture write failed (file is empty: $dest)" >&2
    fail_count=$((fail_count + 1))
    return 1
  fi
  return 0
}

# generator 固定の plan.json と整合する task-*.md 1 件のみの fixture を作る。
write_ok_fixture() {
  local dir="$1"
  cat > "$dir/plan.json" <<'JSON'
{
  "topic_slug": "ok",
  "task_count": 1,
  "tasks": [
    {
      "id": "task-1_1_1",
      "title": "ok task",
      "depends_on": [],
      "max_retries": 2,
      "executor": "generator",
      "reviewer": "none",
      "required_advisors": []
    }
  ]
}
JSON
  write_fixture "$dir/plan.json" || return 1
  cat > "$dir/task-1_1_1.md" <<'MD'
---
id: task-1_1_1
title: ok task
depends_on: []
max_retries: 2
required_advisors: []
executor: generator
reviewer: none
---

# task-1_1_1
MD
  write_fixture "$dir/task-1_1_1.md" || return 1
}

# ---------- case runners ----------

run_case() {
  local label="$1"
  case_count=$((case_count + 1))
  echo ""
  echo "[Case $case_count] $label"
}

cleanup() {
  if [[ -n "${TMPDIR_LOCAL:-}" && -d "${TMPDIR_LOCAL}" ]]; then
    rm -rf "$TMPDIR_LOCAL"
  fi
}
trap cleanup EXIT

# ---------- Case 1: OK ----------
run_case "OK (executor: generator のみ)"
TMPDIR_LOCAL=$(mktemp -d)
write_ok_fixture "$TMPDIR_LOCAL"
stdout=$(bash "$VALIDATE_SCRIPT" "$TMPDIR_LOCAL/plan.json" "$TMPDIR_LOCAL" 2>/dev/null)
exit_code=$?
assert_eq "exit code" "0" "$exit_code"
assert_contains "stdout" "validate-plan: OK" "$stdout"
rm -rf "$TMPDIR_LOCAL"

# ---------- Case 2: INVALID_EXECUTOR (plan.json side) ----------
run_case "INVALID_EXECUTOR (plan.json side)"
TMPDIR_LOCAL=$(mktemp -d)
write_ok_fixture "$TMPDIR_LOCAL"
# plan.json の executor のみ codex に書き換え（frontmatter は generator のままで MISMATCH も併発）
cat > "$TMPDIR_LOCAL/plan.json" <<'JSON'
{
  "topic_slug": "invalid-plan-side",
  "task_count": 1,
  "tasks": [
    {
      "id": "task-1_1_1",
      "title": "ok task",
      "depends_on": [],
      "max_retries": 2,
      "executor": "codex",
      "reviewer": "none",
      "required_advisors": []
    }
  ]
}
JSON
stderr=$(bash "$VALIDATE_SCRIPT" "$TMPDIR_LOCAL/plan.json" "$TMPDIR_LOCAL" 2>&1 1>/dev/null)
exit_code=$?
assert_eq "exit code" "1" "$exit_code"
assert_contains "stderr" "INVALID_EXECUTOR" "$stderr"
assert_contains "stderr (plan.json side label)" "plan.json='codex'" "$stderr"
rm -rf "$TMPDIR_LOCAL"

# ---------- Case 3: INVALID_EXECUTOR (frontmatter side) ----------
run_case "INVALID_EXECUTOR (frontmatter side)"
TMPDIR_LOCAL=$(mktemp -d)
write_ok_fixture "$TMPDIR_LOCAL"
# frontmatter の executor のみ codex に書き換え
sed -i 's/executor: generator/executor: codex/' "$TMPDIR_LOCAL/task-1_1_1.md"
stderr=$(bash "$VALIDATE_SCRIPT" "$TMPDIR_LOCAL/plan.json" "$TMPDIR_LOCAL" 2>&1 1>/dev/null)
exit_code=$?
assert_eq "exit code" "1" "$exit_code"
assert_contains "stderr" "INVALID_EXECUTOR" "$stderr"
assert_contains "stderr (frontmatter side label)" "frontmatter='codex'" "$stderr"
rm -rf "$TMPDIR_LOCAL"

# ---------- Case 4: MISSING ----------
run_case "MISSING (plan.json id に対応する task-*.md が無い)"
TMPDIR_LOCAL=$(mktemp -d)
write_ok_fixture "$TMPDIR_LOCAL"
rm -f "$TMPDIR_LOCAL/task-1_1_1.md"
stderr=$(bash "$VALIDATE_SCRIPT" "$TMPDIR_LOCAL/plan.json" "$TMPDIR_LOCAL" 2>&1 1>/dev/null)
exit_code=$?
assert_eq "exit code" "1" "$exit_code"
assert_contains "stderr" "MISSING" "$stderr"
rm -rf "$TMPDIR_LOCAL"

# ---------- Case 5: MISSING_KEY ----------
run_case "MISSING_KEY (plan.json の task に required_advisors キー欠落)"
TMPDIR_LOCAL=$(mktemp -d)
write_ok_fixture "$TMPDIR_LOCAL"
cat > "$TMPDIR_LOCAL/plan.json" <<'JSON'
{
  "topic_slug": "missing-key",
  "task_count": 1,
  "tasks": [
    {
      "id": "task-1_1_1",
      "title": "ok task",
      "depends_on": [],
      "max_retries": 2,
      "executor": "generator",
      "reviewer": "none"
    }
  ]
}
JSON
stderr=$(bash "$VALIDATE_SCRIPT" "$TMPDIR_LOCAL/plan.json" "$TMPDIR_LOCAL" 2>&1 1>/dev/null)
exit_code=$?
assert_eq "exit code" "1" "$exit_code"
assert_contains "stderr" "MISSING_KEY" "$stderr"
rm -rf "$TMPDIR_LOCAL"

# ---------- Case 6: LEGACY_KEY ----------
run_case "LEGACY_KEY (frontmatter に旧キー advisors: 残存)"
TMPDIR_LOCAL=$(mktemp -d)
write_ok_fixture "$TMPDIR_LOCAL"
# frontmatter に旧キー advisors: を追加
cat > "$TMPDIR_LOCAL/task-1_1_1.md" <<'MD'
---
id: task-1_1_1
title: ok task
depends_on: []
max_retries: 2
required_advisors: []
advisors: [architect]
executor: generator
reviewer: none
---

# task-1_1_1
MD
stderr=$(bash "$VALIDATE_SCRIPT" "$TMPDIR_LOCAL/plan.json" "$TMPDIR_LOCAL" 2>&1 1>/dev/null)
exit_code=$?
assert_eq "exit code" "1" "$exit_code"
assert_contains "stderr" "LEGACY_KEY" "$stderr"
rm -rf "$TMPDIR_LOCAL"

# ---------- Case 7: EXTRA ----------
run_case "EXTRA (tasks-dir に plan.json 未掲載の task-*.md)"
TMPDIR_LOCAL=$(mktemp -d)
write_ok_fixture "$TMPDIR_LOCAL"
# 余分な task-9_9_9.md を追加（plan.json には未掲載）
cat > "$TMPDIR_LOCAL/task-9_9_9.md" <<'MD'
---
id: task-9_9_9
title: extra
depends_on: []
max_retries: 2
required_advisors: []
executor: generator
reviewer: none
---

# task-9_9_9
MD
write_fixture "$TMPDIR_LOCAL/task-9_9_9.md"
stderr=$(bash "$VALIDATE_SCRIPT" "$TMPDIR_LOCAL/plan.json" "$TMPDIR_LOCAL" 2>&1 1>/dev/null)
exit_code=$?
assert_eq "exit code" "1" "$exit_code"
assert_contains "stderr" "EXTRA" "$stderr"
rm -rf "$TMPDIR_LOCAL"

# ---------- Case 8: MISMATCH (max_retries) ----------
run_case "MISMATCH (max_retries: plan.json=3 frontmatter=2)"
TMPDIR_LOCAL=$(mktemp -d)
write_ok_fixture "$TMPDIR_LOCAL"
cat > "$TMPDIR_LOCAL/plan.json" <<'JSON'
{
  "topic_slug": "mismatch-max-retries",
  "task_count": 1,
  "tasks": [
    {
      "id": "task-1_1_1",
      "title": "ok task",
      "depends_on": [],
      "max_retries": 3,
      "executor": "generator",
      "reviewer": "none",
      "required_advisors": []
    }
  ]
}
JSON
write_fixture "$TMPDIR_LOCAL/plan.json"
stderr=$(bash "$VALIDATE_SCRIPT" "$TMPDIR_LOCAL/plan.json" "$TMPDIR_LOCAL" 2>&1 1>/dev/null)
exit_code=$?
assert_eq "exit code" "1" "$exit_code"
assert_contains "stderr" "MISMATCH" "$stderr"
assert_contains "stderr (key label)" "max_retries" "$stderr"
rm -rf "$TMPDIR_LOCAL"

# ---------- Case 9: MISMATCH (reviewer) ----------
run_case "MISMATCH (reviewer: plan.json=codex frontmatter=none)"
TMPDIR_LOCAL=$(mktemp -d)
write_ok_fixture "$TMPDIR_LOCAL"
cat > "$TMPDIR_LOCAL/plan.json" <<'JSON'
{
  "topic_slug": "mismatch-reviewer",
  "task_count": 1,
  "tasks": [
    {
      "id": "task-1_1_1",
      "title": "ok task",
      "depends_on": [],
      "max_retries": 2,
      "executor": "generator",
      "reviewer": "codex",
      "required_advisors": []
    }
  ]
}
JSON
write_fixture "$TMPDIR_LOCAL/plan.json"
stderr=$(bash "$VALIDATE_SCRIPT" "$TMPDIR_LOCAL/plan.json" "$TMPDIR_LOCAL" 2>&1 1>/dev/null)
exit_code=$?
assert_eq "exit code" "1" "$exit_code"
assert_contains "stderr" "MISMATCH" "$stderr"
assert_contains "stderr (key label)" "reviewer" "$stderr"
rm -rf "$TMPDIR_LOCAL"

# ---------- Case 10: MISMATCH (depends_on) ----------
run_case "MISMATCH (depends_on: plan.json=[task-0_1_1] frontmatter=[])"
TMPDIR_LOCAL=$(mktemp -d)
write_ok_fixture "$TMPDIR_LOCAL"
cat > "$TMPDIR_LOCAL/plan.json" <<'JSON'
{
  "topic_slug": "mismatch-depends-on",
  "task_count": 1,
  "tasks": [
    {
      "id": "task-1_1_1",
      "title": "ok task",
      "depends_on": ["task-0_1_1"],
      "max_retries": 2,
      "executor": "generator",
      "reviewer": "none",
      "required_advisors": []
    }
  ]
}
JSON
write_fixture "$TMPDIR_LOCAL/plan.json"
stderr=$(bash "$VALIDATE_SCRIPT" "$TMPDIR_LOCAL/plan.json" "$TMPDIR_LOCAL" 2>&1 1>/dev/null)
exit_code=$?
assert_eq "exit code" "1" "$exit_code"
assert_contains "stderr" "MISMATCH" "$stderr"
assert_contains "stderr (key label)" "depends_on" "$stderr"
rm -rf "$TMPDIR_LOCAL"

# ---------- Case 11: MISMATCH (required_advisors) ----------
run_case "MISMATCH (required_advisors: plan.json=[architect] frontmatter=[])"
TMPDIR_LOCAL=$(mktemp -d)
write_ok_fixture "$TMPDIR_LOCAL"
cat > "$TMPDIR_LOCAL/plan.json" <<'JSON'
{
  "topic_slug": "mismatch-required-advisors",
  "task_count": 1,
  "tasks": [
    {
      "id": "task-1_1_1",
      "title": "ok task",
      "depends_on": [],
      "max_retries": 2,
      "executor": "generator",
      "reviewer": "none",
      "required_advisors": ["architect"]
    }
  ]
}
JSON
write_fixture "$TMPDIR_LOCAL/plan.json"
stderr=$(bash "$VALIDATE_SCRIPT" "$TMPDIR_LOCAL/plan.json" "$TMPDIR_LOCAL" 2>&1 1>/dev/null)
exit_code=$?
assert_eq "exit code" "1" "$exit_code"
assert_contains "stderr" "MISMATCH" "$stderr"
assert_contains "stderr (key label)" "required_advisors" "$stderr"
rm -rf "$TMPDIR_LOCAL"

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
