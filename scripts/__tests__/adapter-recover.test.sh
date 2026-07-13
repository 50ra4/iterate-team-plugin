#!/usr/bin/env bash
# adapter-recover.sh の単体テスト
#
# 実行環境前提: Linux / GNU coreutils + git（dev container・メイン checkout）。
# bash 3.2 / macOS 互換は目標外。
#
# 仕様の正本: <plugin_root>/operations/adapter-policy.md §7
#
# Usage:
#   bash scripts/__tests__/adapter-recover.test.sh
#
# Exit code:
#   0 = 全ケース pass
#   1 = いずれか fail

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${SCRIPT_DIR}/../adapter-recover.sh"

if [[ ! -f "$TARGET" ]]; then
  echo "adapter-recover.sh not found at: $TARGET" >&2
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
  git -C "$tmpdir" config user.email "test@example.com"
  git -C "$tmpdir" config user.name "Test"
  echo "$tmpdir"
}

SESSION_ID="test-session-001"

# ========== A1 [fresh repo] 全ファイル untracked のまま commit 失敗を再現 ==========
run_case "A1: fresh repo + untracked project-profile.md/command-map.md/rules/global.md — 旧手順の pathspec エラーを再現した上で adapter-recover.sh が全て退避して clean にする"

A1_REPO="$(make_isolated_repo)"
# HEAD は存在するが .agent-os/ は一度も commit されていない
# 「fresh リポジトリ」を再現する（/iterate-adapt 初回実行で team-profiler が
# .agent-os/ 一式を書き出した直後に commit が失敗するシナリオ）。
git -C "$A1_REPO" commit -q --allow-empty -m "init"
mkdir -p "$A1_REPO/.agent-os/rules"
echo "# project profile" > "$A1_REPO/.agent-os/project-profile.md"
echo "# command map" > "$A1_REPO/.agent-os/command-map.md"
echo "# global rules" > "$A1_REPO/.agent-os/rules/global.md"

# 旧手順（ガード無し）が fresh repo で pathspec エラーになることを確認し、
# 「旧手順が壊れていた」ことを文書化する（このリポジトリでは .agent-os/ が index にも
# HEAD にも存在しない）。
set +e
old_stderr=$(git -C "$A1_REPO" restore --staged --worktree -- .agent-os/ 2>&1 1>/dev/null)
old_exit=$?
set -e
if [[ "$old_exit" -ne 0 ]]; then
  echo "  PASS: 旧手順 (git restore 単独) は fresh repo で非ゼロ終了する（pathspec エラーの再現。exit=$old_exit）"
  pass_count=$((pass_count + 1))
else
  echo "  FAIL: 旧手順 (git restore 単独) が fresh repo で成功してしまった（再現できていない）" >&2
  fail_count=$((fail_count + 1))
fi
assert_contains "旧手順の stderr は pathspec 不一致エラー" "did not match any" "$old_stderr"

# adapter-recover.sh 本体の検証
set +e
stdout=$(CLAUDE_PROJECT_DIR="$A1_REPO" bash "$TARGET" "$SESSION_ID" 2>"$TMPDIR_GLOBAL/a1-err")
exit_code=$?
set -e
stderr="$(cat "$TMPDIR_GLOBAL/a1-err" 2>/dev/null || true)"

assert_eq "exit code 0" "0" "$exit_code"

A1_EVAC="$A1_REPO/.iterate-team/state/$SESSION_ID/failed-adapter"
assert_path_exists "project-profile.md が退避される" "$A1_EVAC/project-profile.md"
assert_path_exists "command-map.md が退避される" "$A1_EVAC/command-map.md"
assert_path_exists "rules/global.md が構造を保持して退避される" "$A1_EVAC/rules/global.md"

A1_PORCELAIN="$(git -C "$A1_REPO" status --porcelain -- .agent-os/ 2>/dev/null)"
assert_eq "git status --porcelain（.agent-os/ 限定）が空" "" "$A1_PORCELAIN"

assert_eq "stdout は退避先の repo-root 相対パス1行" ".iterate-team/state/$SESSION_ID/failed-adapter/" "$stdout"

rm -rf "$A1_REPO"

# ========== A2: .agent-os/ が存在しない ==========
run_case "A2: .agent-os/ が存在しない場合、exit 0・stdout 空・stderr 空・退避ディレクトリ作成なし"

A2_REPO="$(make_isolated_repo)"

set +e
stdout=$(CLAUDE_PROJECT_DIR="$A2_REPO" bash "$TARGET" "$SESSION_ID" 2>"$TMPDIR_GLOBAL/a2-err")
exit_code=$?
set -e
stderr="$(cat "$TMPDIR_GLOBAL/a2-err" 2>/dev/null || true)"

assert_eq "exit code 0" "0" "$exit_code"
assert_eq "stdout は空" "" "$stdout"
assert_eq "stderr は空（no-op 経路で git の無害 warning を出さない）" "" "$stderr"
assert_path_not_exists "退避ディレクトリは作成されない" "$A2_REPO/.iterate-team/state/$SESSION_ID/failed-adapter"

rm -rf "$A2_REPO"

# ========== A3: tracked ファイルに staged 変更 + worktree 変更のみ ==========
run_case "A3: tracked (コミット済み) learned-rules.md に staged 変更 + worktree 変更 → HEAD へ復元、tree clean、stdout 空"

A3_REPO="$(make_isolated_repo)"
mkdir -p "$A3_REPO/.agent-os"
echo "# Rule: orig" > "$A3_REPO/.agent-os/learned-rules.md"
git -C "$A3_REPO" add .agent-os/learned-rules.md
git -C "$A3_REPO" commit -q -m "seed learned-rules.md"

# staged 変更
echo "# Rule: staged" >> "$A3_REPO/.agent-os/learned-rules.md"
git -C "$A3_REPO" add .agent-os/learned-rules.md
# worktree 変更（未 add）
echo "# Rule: worktree" >> "$A3_REPO/.agent-os/learned-rules.md"

set +e
stdout=$(CLAUDE_PROJECT_DIR="$A3_REPO" bash "$TARGET" "$SESSION_ID" 2>"$TMPDIR_GLOBAL/a3-err")
exit_code=$?
set -e

assert_eq "exit code 0" "0" "$exit_code"
assert_eq "stdout は空（退避なし）" "" "$stdout"
A3_PORCELAIN="$(git -C "$A3_REPO" status --porcelain -- .agent-os/)"
assert_eq "git status --porcelain が空" "" "$A3_PORCELAIN"
A3_CONTENT="$(cat "$A3_REPO/.agent-os/learned-rules.md")"
assert_eq "learned-rules.md の内容が HEAD (orig のみ) に復元される" "# Rule: orig" "$A3_CONTENT"

rm -rf "$A3_REPO"

# ========== A4: tracked + 新規 untracked 混在 ==========
run_case "A4: tracked ファイルの変更 + 新規 untracked ファイルが混在 → 復元と退避の両方が行われる"

A4_REPO="$(make_isolated_repo)"
mkdir -p "$A4_REPO/.agent-os"
echo "# Rule: orig" > "$A4_REPO/.agent-os/learned-rules.md"
git -C "$A4_REPO" add .agent-os/learned-rules.md
git -C "$A4_REPO" commit -q -m "seed learned-rules.md"

echo "# Rule: dirty" >> "$A4_REPO/.agent-os/learned-rules.md"
echo "# new failure" > "$A4_REPO/.agent-os/failure-log.md"
mkdir -p "$A4_REPO/.agent-os/rules"
echo "# nested rule" > "$A4_REPO/.agent-os/rules/project.md"

set +e
stdout=$(CLAUDE_PROJECT_DIR="$A4_REPO" bash "$TARGET" "$SESSION_ID" 2>"$TMPDIR_GLOBAL/a4-err")
exit_code=$?
set -e

assert_eq "exit code 0" "0" "$exit_code"
A4_CONTENT="$(cat "$A4_REPO/.agent-os/learned-rules.md")"
assert_eq "tracked learned-rules.md は HEAD に復元される" "# Rule: orig" "$A4_CONTENT"

A4_EVAC="$A4_REPO/.iterate-team/state/$SESSION_ID/failed-adapter"
assert_path_exists "untracked failure-log.md が退避される" "$A4_EVAC/failure-log.md"
assert_path_exists "untracked rules/project.md が退避される" "$A4_EVAC/rules/project.md"
assert_eq "stdout は退避先パス1行" ".iterate-team/state/$SESSION_ID/failed-adapter/" "$stdout"

A4_PORCELAIN="$(git -C "$A4_REPO" status --porcelain -- .agent-os/)"
assert_eq "git status --porcelain が空" "" "$A4_PORCELAIN"

rm -rf "$A4_REPO"

# ========== A5: 2回連続の失敗 → 連番サフィックスで衝突回避 ==========
run_case "A5: 2回連続の失敗（同名 untracked 再生成）→ 連番サフィックスで衝突回避され exit 0"

A5_REPO="$(make_isolated_repo)"
mkdir -p "$A5_REPO/.agent-os"
echo "# risk" > "$A5_REPO/.agent-os/risk-map.md"

set +e
stdout1=$(CLAUDE_PROJECT_DIR="$A5_REPO" bash "$TARGET" "$SESSION_ID" 2>"$TMPDIR_GLOBAL/a5a-err")
exit1=$?
set -e
assert_eq "1回目 exit code 0" "0" "$exit1"

A5_EVAC="$A5_REPO/.iterate-team/state/$SESSION_ID/failed-adapter"
assert_path_exists "1回目退避: risk-map.md" "$A5_EVAC/risk-map.md"

# 同名 untracked を再生成して2回目実行
mkdir -p "$A5_REPO/.agent-os"
echo "# risk (second failure)" > "$A5_REPO/.agent-os/risk-map.md"

set +e
stdout2=$(CLAUDE_PROJECT_DIR="$A5_REPO" bash "$TARGET" "$SESSION_ID" 2>"$TMPDIR_GLOBAL/a5b-err")
exit2=$?
set -e
assert_eq "2回目 exit code 0" "0" "$exit2"

assert_path_exists "2回目退避は連番サフィックス risk-map.md.1 で衝突回避される" "$A5_EVAC/risk-map.md.1"
A5_ORIG_CONTENT="$(cat "$A5_EVAC/risk-map.md")"
A5_SUFFIXED_CONTENT="$(cat "$A5_EVAC/risk-map.md.1")"
assert_eq "1回目退避ファイルの内容は書き換わっていない" "# risk" "$A5_ORIG_CONTENT"
assert_eq "2回目退避ファイルの内容は新しい方" "# risk (second failure)" "$A5_SUFFIXED_CONTENT"

rm -rf "$A5_REPO"

# ========== A6: スペース入りファイル名 ==========
run_case "A6: スペース入りファイル名の untracked ファイルが正しく退避される"

A6_REPO="$(make_isolated_repo)"
mkdir -p "$A6_REPO/.agent-os"
echo "spaced content" > "$A6_REPO/.agent-os/file with spaces.md"

set +e
stdout=$(CLAUDE_PROJECT_DIR="$A6_REPO" bash "$TARGET" "$SESSION_ID" 2>"$TMPDIR_GLOBAL/a6-err")
exit_code=$?
set -e

assert_eq "exit code 0" "0" "$exit_code"
A6_EVAC="$A6_REPO/.iterate-team/state/$SESSION_ID/failed-adapter"
assert_path_exists "スペース入りファイル名が退避される" "$A6_EVAC/file with spaces.md"
assert_eq "退避ファイルの内容が保持される" "spaced content" "$(cat "$A6_EVAC/file with spaces.md")"

rm -rf "$A6_REPO"

# ========== A7: ネストした untracked ディレクトリ ==========
run_case "A7: ネストした untracked ディレクトリ (rules/sub/deep.md) が構造を保持して退避され、退避後に空になった .agent-os/ 自体が削除される"

A7_REPO="$(make_isolated_repo)"
mkdir -p "$A7_REPO/.agent-os/rules/sub"
echo "deep content" > "$A7_REPO/.agent-os/rules/sub/deep.md"

set +e
stdout=$(CLAUDE_PROJECT_DIR="$A7_REPO" bash "$TARGET" "$SESSION_ID" 2>"$TMPDIR_GLOBAL/a7-err")
exit_code=$?
set -e

assert_eq "exit code 0" "0" "$exit_code"
A7_EVAC="$A7_REPO/.iterate-team/state/$SESSION_ID/failed-adapter"
assert_path_exists "ネスト構造 rules/sub/deep.md が保持されて退避される" "$A7_EVAC/rules/sub/deep.md"
assert_eq "退避ファイルの内容が保持される" "deep content" "$(cat "$A7_EVAC/rules/sub/deep.md")"

# 退避後、.agent-os/ 配下の空ディレクトリ（rules/sub, rules, .agent-os 自体）は削除される
assert_path_not_exists "退避後に空になった .agent-os/ 自体が削除される" "$A7_REPO/.agent-os"

rm -rf "$A7_REPO"

# ========== A8: session-id パス安全性ガード（拒否ケース） ==========
run_case "A8: session-id が '../evil' のようなパス逸脱値だと非ゼロ終了で拒否される"

A8_REPO="$(make_isolated_repo)"

set +e
stderr=$(CLAUDE_PROJECT_DIR="$A8_REPO" bash "$TARGET" "../evil" 2>&1 1>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 非ゼロ" "1" "$exit_code"
assert_contains "stderr に invalid session-id の理由が出力される" "invalid session-id" "$stderr"

# 引数無し（Usage エラー）
set +e
stderr_noargs=$(CLAUDE_PROJECT_DIR="$A8_REPO" bash "$TARGET" 2>&1 1>/dev/null)
exit_noargs=$?
set -e
assert_eq "引数無し: exit code 非ゼロ" "1" "$exit_noargs"
assert_contains "引数無し: Usage が stderr に出力される" "Usage" "$stderr_noargs"

rm -rf "$A8_REPO"

# ========== A9: ロック実体は state/ 配下、.agent-os/ には残置しない ==========
run_case "A9: ロック実体は .iterate-team/state/ 配下に作られ、.agent-os/ 配下には残置しない"

A9_REPO="$(make_isolated_repo)"
mkdir -p "$A9_REPO/.agent-os"
echo "# x" > "$A9_REPO/.agent-os/x.md"

set +e
CLAUDE_PROJECT_DIR="$A9_REPO" bash "$TARGET" "$SESSION_ID" >/dev/null 2>"$TMPDIR_GLOBAL/a9-err"
exit_code=$?
set -e

assert_eq "exit code 0" "0" "$exit_code"
# .agent-os/ 自体が空退避で削除済みの場合、find は非ゼロ終了しうる（pipefail 対策で
# 「|| true」を付け、set -e 下でも意図せず script が中断しないようにする）。
A9_LOCK_IN_AGENT_OS="$( (find "$A9_REPO/.agent-os" -name '*.lock*' 2>/dev/null | wc -l | tr -d ' ') || true)"
assert_eq ".agent-os/ 配下にロックファイルが残置されない（.agent-os/ 自体は空退避で削除済みのため 0 件になるのも正）" "0" "$A9_LOCK_IN_AGENT_OS"

rm -rf "$A9_REPO"

# ========== A10 §7 正規フロー再現 ==========
# §7 の正規フロー（Orchestrator が .agent-os/ 配下の各ファイルを個別 git add した後、
# git commit が失敗する）を再現する: tracked learned-rules.md への staged 変更 +
# staged 新規 rules/project.md（git add 済み・未コミット）。単一コマンド
# `git restore --staged --worktree` はこの staged 新規ファイルを worktree からも
# 削除して完全消失させる（knowledge-recover.sh と同型の実機確認済みバグ）。
run_case "A10: §7 正規フロー再現（tracked staged 変更 + staged 新規 rules/project.md）→ tracked は HEAD 復元、staged 新規は削除されず退避先に存在、tree clean"

A10_REPO="$(make_isolated_repo)"
mkdir -p "$A10_REPO/.agent-os"
echo "# Rule: orig" > "$A10_REPO/.agent-os/learned-rules.md"
git -C "$A10_REPO" add .agent-os/learned-rules.md
git -C "$A10_REPO" commit -q -m "seed learned-rules.md"

# tracked ファイルへの staged 変更（コミット済みファイルの更新分を add）
echo "# Rule: new" >> "$A10_REPO/.agent-os/learned-rules.md"
git -C "$A10_REPO" add .agent-os/learned-rules.md

# staged 新規ファイル（HEAD には存在しない。git add 済み・未コミット）
mkdir -p "$A10_REPO/.agent-os/rules"
echo "# Rule: project scope" > "$A10_REPO/.agent-os/rules/project.md"
git -C "$A10_REPO" add .agent-os/rules/project.md

set +e
stdout=$(CLAUDE_PROJECT_DIR="$A10_REPO" bash "$TARGET" "$SESSION_ID" 2>"$TMPDIR_GLOBAL/a10-err")
exit_code=$?
set -e
a10_stderr="$(cat "$TMPDIR_GLOBAL/a10-err" 2>/dev/null || true)"

assert_eq "exit code 0" "0" "$exit_code"

A10_CONTENT="$(cat "$A10_REPO/.agent-os/learned-rules.md")"
assert_eq "tracked learned-rules.md は HEAD (orig のみ) に復元される" "# Rule: orig" "$A10_CONTENT"

A10_EVAC="$A10_REPO/.iterate-team/state/$SESSION_ID/failed-adapter"
assert_path_exists "staged 新規 rules/project.md は削除されず退避先に存在する" "$A10_EVAC/rules/project.md"
assert_eq "退避された rules/project.md の内容が保持される" "# Rule: project scope" "$(cat "$A10_EVAC/rules/project.md" 2>/dev/null)"

A10_PORCELAIN="$(git -C "$A10_REPO" status --porcelain -- .agent-os/)"
assert_eq "git status --porcelain（.agent-os/ 限定）が空" "" "$A10_PORCELAIN"
assert_eq "stdout は退避先の repo-root 相対パス1行" ".iterate-team/state/$SESSION_ID/failed-adapter/" "$stdout"

rm -rf "$A10_REPO"

# ========== A11 初回実行で全ファイル staged のまま commit 失敗 ==========
run_case "A11: 初回実行（fresh repo）で全ファイルが git add 済み・未コミットのまま commit が失敗する再現 → 全件退避・tree clean・stderr 空"

A11_REPO="$(make_isolated_repo)"
git -C "$A11_REPO" commit -q --allow-empty -m "init"
mkdir -p "$A11_REPO/.agent-os/rules"
echo "# profile" > "$A11_REPO/.agent-os/project-profile.md"
echo "# rule" > "$A11_REPO/.agent-os/rules/global.md"
git -C "$A11_REPO" add .agent-os/

set +e
stdout=$(CLAUDE_PROJECT_DIR="$A11_REPO" bash "$TARGET" "$SESSION_ID" 2>"$TMPDIR_GLOBAL/a11-err")
exit_code=$?
set -e
a11_stderr="$(cat "$TMPDIR_GLOBAL/a11-err" 2>/dev/null || true)"

assert_eq "exit code 0" "0" "$exit_code"

A11_EVAC="$A11_REPO/.iterate-team/state/$SESSION_ID/failed-adapter"
assert_path_exists "全 staged 新規 project-profile.md が退避される" "$A11_EVAC/project-profile.md"
assert_path_exists "全 staged 新規 rules/global.md が退避される" "$A11_EVAC/rules/global.md"

A11_PORCELAIN="$(git -C "$A11_REPO" status --porcelain -- .agent-os/)"
assert_eq "git status --porcelain（.agent-os/ 限定）が空" "" "$A11_PORCELAIN"

# 全件退避により .agent-os/ 自体が空になって削除され、tracked も存在しないため、
# 事後検証の git status 呼び出し自体がスキップされ、`warning: could not open
# directory` が stderr に出ないことを確認する。
assert_eq "stderr は空（.agent-os/ 削除後の事後検証スキップにより無害 warning が出ない）" "" "$a11_stderr"

rm -rf "$A11_REPO"

# ========== A12 git 障害時に成功を偽装しない ==========
run_case "A12: CLAUDE_PROJECT_DIR が git リポジトリでないディレクトリを指す場合 → exit 1、残置ファイルは消えない（git 障害時の成功偽装防止）"

A12_DIR="$(mktemp -d "$TMPDIR_GLOBAL/notgit.XXXXXX")"
mkdir -p "$A12_DIR/.agent-os"
echo "leftover content" > "$A12_DIR/.agent-os/leftover.md"

set +e
stdout=$(CLAUDE_PROJECT_DIR="$A12_DIR" bash "$TARGET" "$SESSION_ID" 2>"$TMPDIR_GLOBAL/a12-err")
exit_code=$?
set -e
a12_stderr="$(cat "$TMPDIR_GLOBAL/a12-err" 2>/dev/null || true)"

assert_eq "exit code 非ゼロ（git 障害を成功として偽装しない）" "1" "$exit_code"
assert_path_exists "残置ファイル leftover.md は消えない" "$A12_DIR/.agent-os/leftover.md"
assert_eq "残置ファイルの内容は書き換わっていない" "leftover content" "$(cat "$A12_DIR/.agent-os/leftover.md" 2>/dev/null)"

rm -rf "$A12_DIR"

# ========== A13 no-op 経路の stderr は空（2回連続） ==========
# A2 ケース（.agent-os/ が存在しない）で stderr が完全に空であることを確認する。
run_case "A13: A2 相当の no-op 経路（.agent-os/ が存在しない）で stderr が完全に空である（2回連続）"

A13_REPO="$(make_isolated_repo)"

set +e
stdout=$(CLAUDE_PROJECT_DIR="$A13_REPO" bash "$TARGET" "$SESSION_ID" 2>"$TMPDIR_GLOBAL/a13-err")
exit_code=$?
set -e
a13_stderr="$(cat "$TMPDIR_GLOBAL/a13-err" 2>/dev/null || true)"

assert_eq "exit code 0" "0" "$exit_code"
assert_eq "stdout は空" "" "$stdout"
assert_eq "stderr は空（no-op 経路で git の無害 warning を出さない）" "" "$a13_stderr"

# 2回目実行でも stderr が空であることを確認する（no-op が繰り返し実行されるケース）。
set +e
stdout2=$(CLAUDE_PROJECT_DIR="$A13_REPO" bash "$TARGET" "$SESSION_ID" 2>"$TMPDIR_GLOBAL/a13b-err")
exit_code2=$?
set -e
a13b_stderr="$(cat "$TMPDIR_GLOBAL/a13b-err" 2>/dev/null || true)"

assert_eq "2回目 exit code 0" "0" "$exit_code2"
assert_eq "2回目も stderr は空" "" "$a13b_stderr"

rm -rf "$A13_REPO"

# ========== A14 tracked .agent-os/ + 新規 untracked の混在（2回目以降のセッション相当） ==========
# .agent-os/ が既にコミット済みの通常運用（2回目以降のセッション）で、tracked
# learned-rules.md への staged 変更と、team-profiler が再生成した新規 untracked
# command-map.md（実際には既存ファイルの上書きだが、ここでは新規ファイルの追加で
# 「再観測により新しいファイルが増える」ケースを模す）が同時に残ったケース。
# restore（tracked 復元）と untracked 退避の両方が行われ tree clean になることを確認する。
run_case "A14: tracked .agent-os/ + staged 変更 + 新規 untracked evals.md の混在 → restore と untracked 退避の両方が行われ tree clean"

A14_REPO="$(make_isolated_repo)"
mkdir -p "$A14_REPO/.agent-os"
echo "# Rule: orig" > "$A14_REPO/.agent-os/learned-rules.md"
echo "# architecture" > "$A14_REPO/.agent-os/architecture-map.md"
git -C "$A14_REPO" add .agent-os/
git -C "$A14_REPO" commit -q -m "seed tracked .agent-os/"

# tracked learned-rules.md への staged 変更
echo "# Rule: new" >> "$A14_REPO/.agent-os/learned-rules.md"
git -C "$A14_REPO" add .agent-os/learned-rules.md

# 新規 untracked evals.md（team-adapter が今回書き出したが未コミットのまま失敗）
echo "# evals" > "$A14_REPO/.agent-os/evals.md"

A14_PRE_STATUS="$(git -C "$A14_REPO" status --porcelain -- .agent-os/)"
assert_contains "前提: learned-rules.md は staged 変更 (M) として現れる" "M  .agent-os/learned-rules.md" "$A14_PRE_STATUS"
assert_contains "前提: evals.md は untracked (??) として現れる" "?? .agent-os/evals.md" "$A14_PRE_STATUS"

set +e
stdout=$(CLAUDE_PROJECT_DIR="$A14_REPO" bash "$TARGET" "$SESSION_ID" 2>"$TMPDIR_GLOBAL/a14-err")
exit_code=$?
set -e
a14_stderr="$(cat "$TMPDIR_GLOBAL/a14-err" 2>/dev/null || true)"

assert_eq "exit code 0" "0" "$exit_code"

A14_CONTENT="$(cat "$A14_REPO/.agent-os/learned-rules.md")"
assert_eq "tracked learned-rules.md は HEAD (orig のみ) に復元される" "# Rule: orig" "$A14_CONTENT"

A14_EVAC="$A14_REPO/.iterate-team/state/$SESSION_ID/failed-adapter"
assert_path_exists "新規 untracked evals.md が退避される" "$A14_EVAC/evals.md"

A14_PORCELAIN="$(git -C "$A14_REPO" status --porcelain -- .agent-os/)"
assert_eq "git status --porcelain（.agent-os/ 限定）が空" "" "$A14_PORCELAIN"
assert_eq "stderr は空" "" "$a14_stderr"

rm -rf "$A14_REPO"

# ========== A15 [.agent-os/ 以外は一切触らない] ==========
run_case "A15: .agent-os/ 以外の untracked/staged/tracked ファイルは一切変更・退避されない"

A15_REPO="$(make_isolated_repo)"
echo "# readme" > "$A15_REPO/README.md"
git -C "$A15_REPO" add README.md
git -C "$A15_REPO" commit -q -m "seed README"

mkdir -p "$A15_REPO/.agent-os"
echo "# leftover" > "$A15_REPO/.agent-os/leftover.md"

# .agent-os/ 以外の tracked ファイルへの staged 変更
echo "# readme updated" >> "$A15_REPO/README.md"
git -C "$A15_REPO" add README.md

# .agent-os/ 以外の untracked ファイル
echo "scratch" > "$A15_REPO/scratch.txt"
mkdir -p "$A15_REPO/.iterate-team/knowledge"
echo '{"id":"L-1"}' > "$A15_REPO/.iterate-team/knowledge/lessons.jsonl"

set +e
stdout=$(CLAUDE_PROJECT_DIR="$A15_REPO" bash "$TARGET" "$SESSION_ID" 2>"$TMPDIR_GLOBAL/a15-err")
exit_code=$?
set -e

assert_eq "exit code 0" "0" "$exit_code"

A15_README_STATUS="$(git -C "$A15_REPO" status --porcelain -- README.md)"
assert_eq "README.md への staged 変更は手つかずのまま残る（.agent-os/ 以外は不可侵）" "M  README.md" "$A15_README_STATUS"

assert_path_exists ".agent-os/ 以外の untracked scratch.txt は移動されずそのまま残る" "$A15_REPO/scratch.txt"
assert_path_exists ".iterate-team/knowledge/ 配下の untracked ファイルは移動されずそのまま残る" "$A15_REPO/.iterate-team/knowledge/lessons.jsonl"

A15_EVAC="$A15_REPO/.iterate-team/state/$SESSION_ID/failed-adapter"
assert_path_exists ".agent-os/ 配下の untracked leftover.md のみ退避される" "$A15_EVAC/leftover.md"
assert_path_not_exists "退避先に README.md は含まれない" "$A15_EVAC/README.md"
assert_path_not_exists "退避先に scratch.txt は含まれない" "$A15_EVAC/scratch.txt"
assert_path_not_exists "退避先に lessons.jsonl は含まれない" "$A15_EVAC/lessons.jsonl"

rm -rf "$A15_REPO"

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
