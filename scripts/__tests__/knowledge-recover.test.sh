#!/usr/bin/env bash
# knowledge-recover.sh の単体テスト
#
# 実行環境前提: Linux / GNU coreutils + jq + git（dev container・メイン checkout）。
# bash 3.2 / macOS 互換は目標外。
#
# 仕様の正本: <plugin_root>/operations/iterate-team-runbook.md §6.7.5
#
# Usage:
#   bash scripts/__tests__/knowledge-recover.test.sh
#
# Exit code:
#   0 = 全ケース pass
#   1 = いずれか fail

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${SCRIPT_DIR}/../knowledge-recover.sh"

if [[ ! -f "$TARGET" ]]; then
  echo "knowledge-recover.sh not found at: $TARGET" >&2
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

# ========== R1 [R5 再現・回帰の核心] ==========
run_case "R1: fresh repo + untracked lessons.jsonl/.gitattributes/proposals/x.md — 旧手順の pathspec エラーを再現した上で knowledge-recover.sh が全て退避して clean にする"

R1_REPO="$(make_isolated_repo)"
# HEAD は存在するが .iterate-team/knowledge/ は一度も commit されていない
# 「fresh リポジトリ」を再現する（PR レビュー指摘 P1 の実際のシナリオ:
# knowledge/ が index にも HEAD にも存在しない状態で初回のレトロスペクティブが走る）。
git -C "$R1_REPO" commit -q --allow-empty -m "init"
mkdir -p "$R1_REPO/.iterate-team/knowledge/proposals"
echo '{"id":"L-1"}' > "$R1_REPO/.iterate-team/knowledge/lessons.jsonl"
echo "lessons.jsonl merge=union" > "$R1_REPO/.iterate-team/knowledge/.gitattributes"
echo "# proposal" > "$R1_REPO/.iterate-team/knowledge/proposals/x.md"

# 旧手順（ガード無し）が fresh repo で pathspec エラーになることを確認し、
# 「旧手順が壊れていた」ことを文書化する（このリポジトリでは knowledge/ が index にも
# HEAD にも存在しない）。
set +e
old_stderr=$(git -C "$R1_REPO" restore --staged --worktree -- .iterate-team/knowledge/ 2>&1 1>/dev/null)
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

# knowledge-recover.sh 本体の検証
set +e
stdout=$(CLAUDE_PROJECT_DIR="$R1_REPO" bash "$TARGET" "$SESSION_ID" 2>"$TMPDIR_GLOBAL/r1-err")
exit_code=$?
set -e
stderr="$(cat "$TMPDIR_GLOBAL/r1-err" 2>/dev/null || true)"

assert_eq "exit code 0" "0" "$exit_code"

R1_EVAC="$R1_REPO/.iterate-team/state/$SESSION_ID/failed-retrospective"
assert_path_exists "lessons.jsonl が退避される" "$R1_EVAC/lessons.jsonl"
assert_path_exists "ドットファイル .gitattributes も退避される" "$R1_EVAC/.gitattributes"
assert_path_exists "proposals/x.md が構造を保持して退避される" "$R1_EVAC/proposals/x.md"

R1_PORCELAIN="$(git -C "$R1_REPO" status --porcelain -- .iterate-team/knowledge/ 2>/dev/null)"
assert_eq "git status --porcelain（knowledge/ 限定）が空" "" "$R1_PORCELAIN"

assert_eq "stdout は退避先の repo-root 相対パス1行" ".iterate-team/state/$SESSION_ID/failed-retrospective/" "$stdout"

rm -rf "$R1_REPO"

# ========== R2: knowledge/ が存在しない ==========
run_case "R2: .iterate-team/knowledge/ が存在しない場合、exit 0・stdout 空・退避ディレクトリ作成なし"

R2_REPO="$(make_isolated_repo)"

set +e
stdout=$(CLAUDE_PROJECT_DIR="$R2_REPO" bash "$TARGET" "$SESSION_ID" 2>"$TMPDIR_GLOBAL/r2-err")
exit_code=$?
set -e
stderr="$(cat "$TMPDIR_GLOBAL/r2-err" 2>/dev/null || true)"

assert_eq "exit code 0" "0" "$exit_code"
assert_eq "stdout は空" "" "$stdout"
assert_eq "stderr は空（no-op 経路で git の無害 warning を出さない。修正2回帰）" "" "$stderr"
assert_path_not_exists "退避ディレクトリは作成されない" "$R2_REPO/.iterate-team/state/$SESSION_ID/failed-retrospective"

rm -rf "$R2_REPO"

# ========== R3: tracked ファイルに staged + worktree 変更のみ ==========
run_case "R3: tracked (コミット済み) lessons.jsonl に staged 変更 + worktree 変更 → HEAD へ復元、tree clean、stdout 空"

R3_REPO="$(make_isolated_repo)"
mkdir -p "$R3_REPO/.iterate-team/knowledge"
echo '{"id":"L-orig"}' > "$R3_REPO/.iterate-team/knowledge/lessons.jsonl"
git -C "$R3_REPO" add .iterate-team/knowledge/lessons.jsonl
git -C "$R3_REPO" commit -q -m "seed lessons.jsonl"

# staged 変更
echo '{"id":"L-staged"}' >> "$R3_REPO/.iterate-team/knowledge/lessons.jsonl"
git -C "$R3_REPO" add .iterate-team/knowledge/lessons.jsonl
# worktree 変更（未 add）
echo '{"id":"L-worktree"}' >> "$R3_REPO/.iterate-team/knowledge/lessons.jsonl"

set +e
stdout=$(CLAUDE_PROJECT_DIR="$R3_REPO" bash "$TARGET" "$SESSION_ID" 2>"$TMPDIR_GLOBAL/r3-err")
exit_code=$?
set -e

assert_eq "exit code 0" "0" "$exit_code"
assert_eq "stdout は空（退避なし）" "" "$stdout"
R3_PORCELAIN="$(git -C "$R3_REPO" status --porcelain -- .iterate-team/knowledge/)"
assert_eq "git status --porcelain が空" "" "$R3_PORCELAIN"
R3_CONTENT="$(cat "$R3_REPO/.iterate-team/knowledge/lessons.jsonl")"
assert_eq "lessons.jsonl の内容が HEAD (L-orig のみ) に復元される" '{"id":"L-orig"}' "$R3_CONTENT"

rm -rf "$R3_REPO"

# ========== R4: tracked + 新規 untracked 混在 ==========
run_case "R4: tracked ファイルの変更 + 新規 untracked ファイルが混在 → 復元と退避の両方が行われる"

R4_REPO="$(make_isolated_repo)"
mkdir -p "$R4_REPO/.iterate-team/knowledge"
echo '{"id":"L-orig"}' > "$R4_REPO/.iterate-team/knowledge/lessons.jsonl"
git -C "$R4_REPO" add .iterate-team/knowledge/lessons.jsonl
git -C "$R4_REPO" commit -q -m "seed lessons.jsonl"

echo '{"id":"L-dirty"}' >> "$R4_REPO/.iterate-team/knowledge/lessons.jsonl"
echo "# new proposal" > "$R4_REPO/.iterate-team/knowledge/proposals-new.md"
mkdir -p "$R4_REPO/.iterate-team/knowledge/proposals"
echo "# nested proposal" > "$R4_REPO/.iterate-team/knowledge/proposals/new.md"

set +e
stdout=$(CLAUDE_PROJECT_DIR="$R4_REPO" bash "$TARGET" "$SESSION_ID" 2>"$TMPDIR_GLOBAL/r4-err")
exit_code=$?
set -e

assert_eq "exit code 0" "0" "$exit_code"
R4_CONTENT="$(cat "$R4_REPO/.iterate-team/knowledge/lessons.jsonl")"
assert_eq "tracked lessons.jsonl は HEAD に復元される" '{"id":"L-orig"}' "$R4_CONTENT"

R4_EVAC="$R4_REPO/.iterate-team/state/$SESSION_ID/failed-retrospective"
assert_path_exists "untracked proposals-new.md が退避される" "$R4_EVAC/proposals-new.md"
assert_path_exists "untracked proposals/new.md が退避される" "$R4_EVAC/proposals/new.md"
assert_eq "stdout は退避先パス1行" ".iterate-team/state/$SESSION_ID/failed-retrospective/" "$stdout"

R4_PORCELAIN="$(git -C "$R4_REPO" status --porcelain -- .iterate-team/knowledge/)"
assert_eq "git status --porcelain が空" "" "$R4_PORCELAIN"

rm -rf "$R4_REPO"

# ========== R5: 2回連続の失敗 → 連番サフィックスで衝突回避 ==========
run_case "R5: 2回連続の失敗（同名 untracked 再生成）→ 連番サフィックスで衝突回避され exit 0"

R5_REPO="$(make_isolated_repo)"
mkdir -p "$R5_REPO/.iterate-team/knowledge"
echo "# proposal" > "$R5_REPO/.iterate-team/knowledge/dup.md"

set +e
stdout1=$(CLAUDE_PROJECT_DIR="$R5_REPO" bash "$TARGET" "$SESSION_ID" 2>"$TMPDIR_GLOBAL/r5a-err")
exit1=$?
set -e
assert_eq "1回目 exit code 0" "0" "$exit1"

R5_EVAC="$R5_REPO/.iterate-team/state/$SESSION_ID/failed-retrospective"
assert_path_exists "1回目退避: dup.md" "$R5_EVAC/dup.md"

# 同名 untracked を再生成して2回目実行
mkdir -p "$R5_REPO/.iterate-team/knowledge"
echo "# proposal (second failure)" > "$R5_REPO/.iterate-team/knowledge/dup.md"

set +e
stdout2=$(CLAUDE_PROJECT_DIR="$R5_REPO" bash "$TARGET" "$SESSION_ID" 2>"$TMPDIR_GLOBAL/r5b-err")
exit2=$?
set -e
assert_eq "2回目 exit code 0" "0" "$exit2"

assert_path_exists "2回目退避は連番サフィックス dup.md.1 で衝突回避される" "$R5_EVAC/dup.md.1"
R5_ORIG_CONTENT="$(cat "$R5_EVAC/dup.md")"
R5_SUFFIXED_CONTENT="$(cat "$R5_EVAC/dup.md.1")"
assert_eq "1回目退避ファイルの内容は書き換わっていない" "# proposal" "$R5_ORIG_CONTENT"
assert_eq "2回目退避ファイルの内容は新しい方" "# proposal (second failure)" "$R5_SUFFIXED_CONTENT"

rm -rf "$R5_REPO"

# ========== R6: スペース入りファイル名 ==========
run_case "R6: スペース入りファイル名の untracked ファイルが正しく退避される"

R6_REPO="$(make_isolated_repo)"
mkdir -p "$R6_REPO/.iterate-team/knowledge"
echo "spaced content" > "$R6_REPO/.iterate-team/knowledge/file with spaces.md"

set +e
stdout=$(CLAUDE_PROJECT_DIR="$R6_REPO" bash "$TARGET" "$SESSION_ID" 2>"$TMPDIR_GLOBAL/r6-err")
exit_code=$?
set -e

assert_eq "exit code 0" "0" "$exit_code"
R6_EVAC="$R6_REPO/.iterate-team/state/$SESSION_ID/failed-retrospective"
assert_path_exists "スペース入りファイル名が退避される" "$R6_EVAC/file with spaces.md"
assert_eq "退避ファイルの内容が保持される" "spaced content" "$(cat "$R6_EVAC/file with spaces.md")"

rm -rf "$R6_REPO"

# ========== R7: ネストした untracked ディレクトリ ==========
run_case "R7: ネストした untracked ディレクトリ (proposals/sub/deep.md) が構造を保持して退避される"

R7_REPO="$(make_isolated_repo)"
mkdir -p "$R7_REPO/.iterate-team/knowledge/proposals/sub"
echo "deep content" > "$R7_REPO/.iterate-team/knowledge/proposals/sub/deep.md"

set +e
stdout=$(CLAUDE_PROJECT_DIR="$R7_REPO" bash "$TARGET" "$SESSION_ID" 2>"$TMPDIR_GLOBAL/r7-err")
exit_code=$?
set -e

assert_eq "exit code 0" "0" "$exit_code"
R7_EVAC="$R7_REPO/.iterate-team/state/$SESSION_ID/failed-retrospective"
assert_path_exists "ネスト構造 proposals/sub/deep.md が保持されて退避される" "$R7_EVAC/proposals/sub/deep.md"
assert_eq "退避ファイルの内容が保持される" "deep content" "$(cat "$R7_EVAC/proposals/sub/deep.md")"

# 退避後、knowledge/ 配下の空ディレクトリ（proposals/sub, proposals, knowledge 自体）は削除される
assert_path_not_exists "退避後に空になった knowledge/ 自体が削除される" "$R7_REPO/.iterate-team/knowledge"

rm -rf "$R7_REPO"

# ========== R8: session-id パス安全性ガード（拒否ケース） ==========
run_case "R8: session-id が '../evil' のようなパス逸脱値だと非ゼロ終了で拒否される"

R8_REPO="$(make_isolated_repo)"

set +e
stderr=$(CLAUDE_PROJECT_DIR="$R8_REPO" bash "$TARGET" "../evil" 2>&1 1>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 非ゼロ" "1" "$exit_code"
assert_contains "stderr に invalid session-id の理由が出力される" "invalid session-id" "$stderr"

# 引数無し（Usage エラー）
set +e
stderr_noargs=$(CLAUDE_PROJECT_DIR="$R8_REPO" bash "$TARGET" 2>&1 1>/dev/null)
exit_noargs=$?
set -e
assert_eq "引数無し: exit code 非ゼロ" "1" "$exit_noargs"
assert_contains "引数無し: Usage が stderr に出力される" "Usage" "$stderr_noargs"

rm -rf "$R8_REPO"

# ========== R9: ロック実体は state/ 配下、knowledge/ には残置しない ==========
run_case "R9: ロック実体は .iterate-team/state/ 配下に作られ、knowledge/ 配下には残置しない（append/prune と同一パス共有の回帰確認）"

R9_REPO="$(make_isolated_repo)"
mkdir -p "$R9_REPO/.iterate-team/knowledge"
echo "# proposal" > "$R9_REPO/.iterate-team/knowledge/x.md"

set +e
CLAUDE_PROJECT_DIR="$R9_REPO" bash "$TARGET" "$SESSION_ID" >/dev/null 2>"$TMPDIR_GLOBAL/r9-err"
exit_code=$?
set -e

assert_eq "exit code 0" "0" "$exit_code"
# knowledge/ 自体が空退避で削除済みの場合、find は非ゼロ終了しうる（pipefail 対策で
# 「|| true」を付け、set -e 下でも意図せず script が中断しないようにする）。
R9_LOCK_IN_KNOWLEDGE="$( (find "$R9_REPO/.iterate-team/knowledge" -name '*.lock*' 2>/dev/null | wc -l | tr -d ' ') || true)"
assert_eq "knowledge/ 配下にロックファイルが残置されない（knowledge/ 自体は空退避で削除済みのため 0 件になるのも正）" "0" "$R9_LOCK_IN_KNOWLEDGE"

rm -rf "$R9_REPO"

# ========== R10 [修正1 回帰] 6.7.2 正規フロー再現 ==========
# ステップ 6.7.2 の正規フロー（team-retrospector が個別ファイルを git add した後、
# git commit が失敗する）を再現する: tracked lessons.jsonl への staged 変更 +
# staged 新規 proposals/x.md（git add 済み・未コミット）。旧実装
# （`git restore --staged --worktree` 単発呼び出し）はこの staged 新規ファイルを
# worktree からも削除して完全消失させていた（実機確認済みの P0 バグ）。
run_case "R10: 6.7.2 正規フロー再現（tracked staged 変更 + staged 新規 proposals/x.md）→ tracked は HEAD 復元、staged 新規は削除されず退避先に存在、tree clean"

R10_REPO="$(make_isolated_repo)"
mkdir -p "$R10_REPO/.iterate-team/knowledge"
echo '{"id":"L-orig"}' > "$R10_REPO/.iterate-team/knowledge/lessons.jsonl"
git -C "$R10_REPO" add .iterate-team/knowledge/lessons.jsonl
git -C "$R10_REPO" commit -q -m "seed lessons.jsonl"

# tracked ファイルへの staged 変更（コミット済みファイルの更新分を add）
echo '{"id":"L-new"}' >> "$R10_REPO/.iterate-team/knowledge/lessons.jsonl"
git -C "$R10_REPO" add .iterate-team/knowledge/lessons.jsonl

# staged 新規ファイル（HEAD には存在しない。git add 済み・未コミット）
mkdir -p "$R10_REPO/.iterate-team/knowledge/proposals"
echo "# new proposal from retrospective" > "$R10_REPO/.iterate-team/knowledge/proposals/x.md"
git -C "$R10_REPO" add .iterate-team/knowledge/proposals/x.md

set +e
stdout=$(CLAUDE_PROJECT_DIR="$R10_REPO" bash "$TARGET" "$SESSION_ID" 2>"$TMPDIR_GLOBAL/r10-err")
exit_code=$?
set -e
r10_stderr="$(cat "$TMPDIR_GLOBAL/r10-err" 2>/dev/null || true)"

assert_eq "exit code 0" "0" "$exit_code"

R10_CONTENT="$(cat "$R10_REPO/.iterate-team/knowledge/lessons.jsonl")"
assert_eq "tracked lessons.jsonl は HEAD (L-orig のみ) に復元される" '{"id":"L-orig"}' "$R10_CONTENT"

R10_EVAC="$R10_REPO/.iterate-team/state/$SESSION_ID/failed-retrospective"
assert_path_exists "staged 新規 proposals/x.md は削除されず退避先に存在する" "$R10_EVAC/proposals/x.md"
assert_eq "退避された proposals/x.md の内容が保持される" "# new proposal from retrospective" "$(cat "$R10_EVAC/proposals/x.md" 2>/dev/null)"

R10_PORCELAIN="$(git -C "$R10_REPO" status --porcelain -- .iterate-team/knowledge/)"
assert_eq "git status --porcelain（knowledge/ 限定）が空" "" "$R10_PORCELAIN"
assert_eq "stdout は退避先の repo-root 相対パス1行" ".iterate-team/state/$SESSION_ID/failed-retrospective/" "$stdout"

rm -rf "$R10_REPO"

# ========== R11 [修正1 回帰] 初回実行で全ファイル staged のまま commit 失敗 ==========
run_case "R11: 初回実行（fresh repo）で全ファイルが git add 済み・未コミットのまま commit が失敗する再現 → 全件退避・tree clean"

R11_REPO="$(make_isolated_repo)"
git -C "$R11_REPO" commit -q --allow-empty -m "init"
mkdir -p "$R11_REPO/.iterate-team/knowledge/proposals"
echo '{"id":"L-1"}' > "$R11_REPO/.iterate-team/knowledge/lessons.jsonl"
echo "# proposal" > "$R11_REPO/.iterate-team/knowledge/proposals/x.md"
git -C "$R11_REPO" add .iterate-team/knowledge/

set +e
stdout=$(CLAUDE_PROJECT_DIR="$R11_REPO" bash "$TARGET" "$SESSION_ID" 2>"$TMPDIR_GLOBAL/r11-err")
exit_code=$?
set -e
r11_stderr="$(cat "$TMPDIR_GLOBAL/r11-err" 2>/dev/null || true)"

assert_eq "exit code 0" "0" "$exit_code"

R11_EVAC="$R11_REPO/.iterate-team/state/$SESSION_ID/failed-retrospective"
assert_path_exists "全 staged 新規 lessons.jsonl が退避される" "$R11_EVAC/lessons.jsonl"
assert_path_exists "全 staged 新規 proposals/x.md が退避される" "$R11_EVAC/proposals/x.md"

R11_PORCELAIN="$(git -C "$R11_REPO" status --porcelain -- .iterate-team/knowledge/)"
assert_eq "git status --porcelain（knowledge/ 限定）が空" "" "$R11_PORCELAIN"

# 全件退避により knowledge/ 自体が空になって削除され、tracked も存在しないため、
# 事後検証の git status 呼び出し自体がスキップされ、`warning: could not open
# directory` が stderr に出ないことを確認する（修正3の回帰確認）。
assert_eq "stderr は空（knowledge/ 削除後の事後検証スキップにより無害 warning が出ない。修正3回帰）" "" "$r11_stderr"

rm -rf "$R11_REPO"

# ========== R12 [修正2 回帰] git 障害時に成功を偽装しない ==========
run_case "R12: CLAUDE_PROJECT_DIR が git リポジトリでないディレクトリを指す場合 → exit 1、残置ファイルは消えない（git 障害時の成功偽装防止）"

R12_DIR="$(mktemp -d "$TMPDIR_GLOBAL/notgit.XXXXXX")"
mkdir -p "$R12_DIR/.iterate-team/knowledge"
echo "leftover content" > "$R12_DIR/.iterate-team/knowledge/leftover.md"

set +e
stdout=$(CLAUDE_PROJECT_DIR="$R12_DIR" bash "$TARGET" "$SESSION_ID" 2>"$TMPDIR_GLOBAL/r12-err")
exit_code=$?
set -e
r12_stderr="$(cat "$TMPDIR_GLOBAL/r12-err" 2>/dev/null || true)"

assert_eq "exit code 非ゼロ（git 障害を成功として偽装しない）" "1" "$exit_code"
assert_path_exists "残置ファイル leftover.md は消えない" "$R12_DIR/.iterate-team/knowledge/leftover.md"
assert_eq "残置ファイルの内容は書き換わっていない" "leftover content" "$(cat "$R12_DIR/.iterate-team/knowledge/leftover.md" 2>/dev/null)"

rm -rf "$R12_DIR"

# ========== R13 [修正2 回帰] no-op 経路の stderr は空 ==========
# R2 ケース（.iterate-team/knowledge/ が存在しない）で stderr が完全に空であることを
# 確認する。修正前は knowledge_dir が存在しないディレクトリへの `git status` 呼び出し
# のせいで `warning: could not open directory` が stderr に出ていた。
run_case "R13: R2 相当の no-op 経路（.iterate-team/knowledge/ が存在しない）で stderr が完全に空である"

R13_REPO="$(make_isolated_repo)"

set +e
stdout=$(CLAUDE_PROJECT_DIR="$R13_REPO" bash "$TARGET" "$SESSION_ID" 2>"$TMPDIR_GLOBAL/r13-err")
exit_code=$?
set -e
r13_stderr="$(cat "$TMPDIR_GLOBAL/r13-err" 2>/dev/null || true)"

assert_eq "exit code 0" "0" "$exit_code"
assert_eq "stdout は空" "" "$stdout"
assert_eq "stderr は空（no-op 経路で git の無害 warning を出さない）" "" "$r13_stderr"

# 2回目実行でも stderr が空であることを確認する（no-op が繰り返し実行されるケース）。
set +e
stdout2=$(CLAUDE_PROJECT_DIR="$R13_REPO" bash "$TARGET" "$SESSION_ID" 2>"$TMPDIR_GLOBAL/r13b-err")
exit_code2=$?
set -e
r13b_stderr="$(cat "$TMPDIR_GLOBAL/r13b-err" 2>/dev/null || true)"

assert_eq "2回目 exit code 0" "0" "$exit_code2"
assert_eq "2回目も stderr は空" "" "$r13b_stderr"

rm -rf "$R13_REPO"

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
