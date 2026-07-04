#!/usr/bin/env bash
# knowledge-prune.sh の単体テスト
#
# 実行環境前提: Linux / GNU coreutils + jq + git（dev container・メイン checkout）。
# bash 3.2 / macOS 互換は目標外。
#
# 仕様の正本: <plugin_root>/operations/knowledge-policy.md（§6「物理削除」）
#
# Usage:
#   bash scripts/__tests__/knowledge-prune.test.sh
#
# Exit code:
#   0 = 全ケース pass
#   1 = いずれか fail

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${SCRIPT_DIR}/../knowledge-prune.sh"

if [[ ! -f "$TARGET" ]]; then
  echo "knowledge-prune.sh not found at: $TARGET" >&2
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
    echo "  FAIL: $label (needle='$needle' haystack='${haystack:0:500}...')" >&2
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

# ---- フィクスチャ: 1 レコードを組み立てる ----
make_record() {
  local id="$1" ts="$2" status="$3" lesson="${4:-lesson}"
  jq -nc \
    --arg id "$id" --arg ts "$ts" --arg status "$status" --arg lesson "$lesson" \
    '{
      id: $id, ts: $ts, session_id: "s1", source: "manual", category: "impl",
      target_agents: ["team-generator"], trigger: "t", lesson: $lesson,
      evidence: [{session_id:"s1", event:"e"}], status: $status,
      merged_into: null, confidence: "low", applied_count: 0, last_applied_ts: null
    }'
}

# 「現在 - N 日」前の ISO8601 UTC 文字列
iso_days_ago() {
  local days="$1"
  date -u -d "-${days} days" +%Y-%m-%dT%H:%M:%SZ
}

# ========== T1: lessons.jsonl 不在はエラー終了 ==========
run_case "T1: lessons.jsonl が存在しない場合は非ゼロ終了で拒否される"

T1_REPO="$(make_isolated_repo)"

set +e
stderr=$(CLAUDE_PROJECT_DIR="$T1_REPO" bash "$TARGET" --compact 2>&1 1>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 非ゼロ" "1" "$exit_code"
assert_contains "stderr に lessons.jsonl 不在の理由が出力される" "lessons.jsonl" "$stderr"

rm -rf "$T1_REPO"

# ========== T2: dry-run 既定ではファイル無変更 ==========
run_case "T2: --apply なし（dry-run 既定）ではファイルが一切変更されない"

T2_REPO="$(make_isolated_repo)"
T2_KNOWLEDGE="$T2_REPO/.iterate-team/knowledge"
mkdir -p "$T2_KNOWLEDGE"
T2_JSONL="$T2_KNOWLEDGE/lessons.jsonl"

make_record "L-t2-a" "2026-01-01T00:00:00Z" "active" "lesson a" > "$T2_JSONL"
make_record "L-t2-a" "2026-01-02T00:00:00Z" "active" "lesson a updated" >> "$T2_JSONL"
make_record "L-t2-b" "$(iso_days_ago 91)" "deprecated" "old lesson" >> "$T2_JSONL"

T2_BEFORE_HASH="$(sha256sum "$T2_JSONL" | awk '{print $1}')"

set +e
stdout=$(CLAUDE_PROJECT_DIR="$T2_REPO" bash "$TARGET" --compact 2>/dev/null)
exit_code=$?
set -e

T2_AFTER_HASH="$(sha256sum "$T2_JSONL" | awk '{print $1}')"

assert_eq "exit code 0" "0" "$exit_code"
assert_eq "dry-run 前後でファイル内容（ハッシュ）が変化しない" "$T2_BEFORE_HASH" "$T2_AFTER_HASH"
assert_contains "dry-run 出力に重複圧縮対象の行数が含まれる" "重複" "$stdout"
assert_contains "dry-run 出力に90日超 deprecated 対象 id が含まれる" "L-t2-b" "$stdout"
assert_contains "dry-run である旨が出力される（無変更）" "現時点では無変更" "$stdout"

rm -rf "$T2_REPO"

# ========== T3: --apply で同一 id の中間レコードが圧縮される ==========
run_case "T3: --apply で同一 id の中間レコードが物理削除され最終レコードのみ残る"

T3_REPO="$(make_isolated_repo)"
T3_KNOWLEDGE="$T3_REPO/.iterate-team/knowledge"
mkdir -p "$T3_KNOWLEDGE"
T3_JSONL="$T3_KNOWLEDGE/lessons.jsonl"

make_record "L-t3-dup" "2026-01-01T00:00:00Z" "active" "first version" > "$T3_JSONL"
make_record "L-t3-dup" "2026-01-02T00:00:00Z" "active" "second version" >> "$T3_JSONL"
make_record "L-t3-dup" "2026-01-03T00:00:00Z" "active" "final version" >> "$T3_JSONL"
make_record "L-t3-other" "2026-01-01T00:00:00Z" "active" "other lesson" >> "$T3_JSONL"

set +e
stdout=$(CLAUDE_PROJECT_DIR="$T3_REPO" bash "$TARGET" --compact --apply 2>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 0" "0" "$exit_code"
T3_LINE_COUNT="$(wc -l < "$T3_JSONL" | tr -d ' ')"
assert_eq "圧縮後の行数は id 種類数（2件）と一致する" "2" "$T3_LINE_COUNT"

T3_DUP_LESSON="$(jq -r 'select(.id=="L-t3-dup") | .lesson' "$T3_JSONL")"
assert_eq "L-t3-dup は最終レコード（final version）のみ残る" "final version" "$T3_DUP_LESSON"
assert_contains "L-t3-other のレコードも残る" "L-t3-other" "$(cat "$T3_JSONL")"
assert_contains "--apply 後にダイジェスト再生成を促すメッセージが出力される" "knowledge-digest.sh" "$stdout"

# ロックは state/ 配下に置く規約（git-tracked の knowledge/ を汚染しない）の回帰確認:
# --apply 後も knowledge/ 内にロックファイル・tmp ファイルが残置されない。
T3_LEFTOVER_IN_KNOWLEDGE="$(find "$T3_KNOWLEDGE" -name '*.lock*' -o -name '.lessons.jsonl.*' | wc -l | tr -d ' ')"
assert_eq "--apply 後も knowledge/ 配下にロック/tmp ファイルが残置されない" "0" "$T3_LEFTOVER_IN_KNOWLEDGE"

rm -rf "$T3_REPO"

# ========== T4: 90日超 deprecated のみ削除、89日は残る ==========
run_case "T4: 90日超 deprecated のレコードのみ削除され、89日の deprecated レコードは残る"

T4_REPO="$(make_isolated_repo)"
T4_KNOWLEDGE="$T4_REPO/.iterate-team/knowledge"
mkdir -p "$T4_KNOWLEDGE"
T4_JSONL="$T4_KNOWLEDGE/lessons.jsonl"

# 初回記録（first_ts）が 91 日前 → 90日超で削除対象
make_record "L-t4-old" "$(iso_days_ago 91)" "deprecated" "very old lesson" > "$T4_JSONL"
# 初回記録が 89 日前 → 90日以内のため残る
make_record "L-t4-recent" "$(iso_days_ago 89)" "deprecated" "recent deprecated lesson" >> "$T4_JSONL"
# active はそもそも削除対象外（何日前でも残る）
make_record "L-t4-active-old" "$(iso_days_ago 200)" "active" "old but active lesson" >> "$T4_JSONL"

set +e
stdout=$(CLAUDE_PROJECT_DIR="$T4_REPO" bash "$TARGET" --compact --apply 2>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 0" "0" "$exit_code"
T4_CONTENT="$(cat "$T4_JSONL")"
assert_not_contains "90日超 deprecated（L-t4-old）は削除される" "L-t4-old" "$T4_CONTENT"
assert_contains "89日の deprecated（L-t4-recent）は残る" "L-t4-recent" "$T4_CONTENT"
assert_contains "200日前でも active（L-t4-active-old）は残る" "L-t4-active-old" "$T4_CONTENT"
assert_contains "stdout に削除した id（L-t4-old）が報告される" "L-t4-old" "$stdout"

rm -rf "$T4_REPO"

# ========== T5: 初回記録（最初のレコードの ts）基準で 90 日判定する ==========
# 同一 id の最終レコードの ts が新しくても、初回記録（同一 id の最初のレコード）が
# 90 日超なら削除対象になることを検証する（knowledge-policy.md §6 の「初回記録から」の定義）。
run_case "T5: 同一 id の最終レコード ts が新しくても、初回記録の ts が90日超なら削除される"

T5_REPO="$(make_isolated_repo)"
T5_KNOWLEDGE="$T5_REPO/.iterate-team/knowledge"
mkdir -p "$T5_KNOWLEDGE"
T5_JSONL="$T5_KNOWLEDGE/lessons.jsonl"

# 初回記録は 100 日前（active）。直近の上書きで deprecated 化（ts は 1 日前=新しい）。
make_record "L-t5-dup" "$(iso_days_ago 100)" "active" "first" > "$T5_JSONL"
make_record "L-t5-dup" "$(iso_days_ago 1)" "deprecated" "final (deprecated)" >> "$T5_JSONL"

set +e
stdout=$(CLAUDE_PROJECT_DIR="$T5_REPO" bash "$TARGET" --compact --apply 2>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 0" "0" "$exit_code"
assert_not_contains "初回記録が90日超のため最終レコードの ts が新しくても削除される" "L-t5-dup" "$(cat "$T5_JSONL")"
assert_contains "stdout に削除した id が報告される" "L-t5-dup" "$stdout"

rm -rf "$T5_REPO"

# ========== T6: TOCTOU 回帰防止 ==========
# --compact の圧縮結果算出（jq 読み取り）がロック取得より前に行われていると、
# 「外部プロセスがロックを保持している間に別プロセスが追記した行」が、ロック解放後に
# 実行される --apply の mv によって消失してしまう（読み取り時点のスナップショットに
# その追記行が反映されていないため）。
#
# ここでは flock を用いて外部プロセス（このテスト自身）が先にロックを握り、その状態で
# prune --apply をバックグラウンド起動する。ロック保持中に lessons.jsonl へ新規 id の
# 行を直接追記し、その後ロックを解放する。
#   - 修正後（読み取りがロック取得後）: prune はロック解放を待ってから読み取るため、
#     追記された行を含めて圧縮結果が算出され、mv 後も追記行が残る。
#   - 修正前（読み取りがロック取得前）: prune はロック取得を待たずに即座に（数百ms未満で）
#     読み取りを終えてしまうため、追記された行を含まないスナップショットで mv され、
#     追記行が失われる。
# タイミングに依存せず決定的に判定できるよう、「ロックを外部が保持している間だけ」
# 追記を行い、それ以降に prune のロック取得・書き込みが起きる順序を固定している。
run_case "T6: 外部プロセスがロック保持中に追記した行が、ロック解放後の prune --apply でも失われない（TOCTOU 回帰防止）"

T6_REPO="$(make_isolated_repo)"
T6_KNOWLEDGE="$T6_REPO/.iterate-team/knowledge"
mkdir -p "$T6_KNOWLEDGE"
T6_JSONL="$T6_KNOWLEDGE/lessons.jsonl"
T6_STATE="$T6_REPO/.iterate-team/state"
mkdir -p "$T6_STATE"
T6_LOCK="$T6_STATE/knowledge-lessons.lock"

make_record "L-t6-dup" "2026-01-01T00:00:00Z" "active" "first" > "$T6_JSONL"
make_record "L-t6-dup" "2026-01-02T00:00:00Z" "active" "second" >> "$T6_JSONL"

# 外部プロセス（このテストシェル自身）が先にロックを握る
# （knowledge-append.sh / knowledge-prune.sh と同一のロックファイルパスを使う）。
exec 8>"$T6_LOCK"
flock -x 8

T6_STDOUT_FILE="$TMPDIR_GLOBAL/t6-prune-stdout.txt"
(CLAUDE_PROJECT_DIR="$T6_REPO" bash "$TARGET" --compact --apply > "$T6_STDOUT_FILE" 2>&1) &
prune_pid=$!

# prune がロック待ちに入るための猶予（このテストの正しさ自体はタイミングに依存しない。
# 修正前の実装で読み取りが即座に終わってしまうことを再現するための待機であり、
# 修正後の実装ではロックを保持している限り prune は読み取りにすら進めない）。
sleep 0.3

# ロックを外部が握ったまま、新規 id の行を直接追記する
# （この行が prune の圧縮結果に反映されるかどうかが TOCTOU 修正の検証点）。
make_record "L-t6-concurrent" "2026-01-03T00:00:00Z" "active" "concurrent lesson" >> "$T6_JSONL"

# ロックを解放し、prune --apply の完了を待つ
flock -u 8
exec 8>&-

wait "$prune_pid"
prune_exit=$?

T6_STDOUT="$(cat "$T6_STDOUT_FILE" 2>/dev/null || true)"
T6_CONTENT="$(cat "$T6_JSONL")"

assert_eq "prune --apply は exit 0" "0" "$prune_exit"
assert_contains "ロック保持中に追記された行(L-t6-concurrent)が prune 後も残る" "L-t6-concurrent" "$T6_CONTENT"
assert_eq "L-t6-dup は圧縮されて最終レコード(second)のみ残る" "second" "$(jq -r 'select(.id=="L-t6-dup") | .lesson' "$T6_JSONL")"

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
