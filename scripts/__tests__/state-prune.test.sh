#!/usr/bin/env bash
# state-prune.sh の単体テスト
#
# 実行環境前提: Linux / GNU coreutils（dev container・メイン checkout）。
# bash 3.2 / macOS 互換は目標外。
#
# prune 対象は --state-root（未指定時は git toplevel 配下の .iterate-team/state）で解決する。
# T11 は隔離 git リポジトリ内で既定パス解決を検証する。
#
# Usage:
#   bash scripts/__tests__/state-prune.test.sh
#
# Exit code:
#   0 = 全ケース pass
#   1 = いずれか fail

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${SCRIPT_DIR}/../state-prune.sh"

if [[ ! -f "$TARGET" ]]; then
  echo "state-prune.sh not found at: $TARGET" >&2
  exit 1
fi

pass_count=0
fail_count=0
case_count=0

# ---- 保持基準定数（state-retention-policy.md 確定値） ----
RETENTION_DAYS=30         # ハーネスセッション保持日数
SESSIONS_KEEP_COUNT=20    # sessions/<uuid>/ 最新保持件数
GRACE_PERIOD_DAYS=30      # sessions/<uuid>/ grace period（日数）

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

assert_matches_regex() {
  local label="$1" pattern="$2" haystack="$3"
  if echo "$haystack" | grep -qE "$pattern"; then
    echo "  PASS: $label (matches /$pattern/)"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL: $label (pattern=/$pattern/ not found in haystack='${haystack:0:300}')" >&2
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

# ---- フィクスチャヘルパー: 超過日数を秒単位で計算 ----
# 「現在 - (RETENTION_DAYS + 1) 日」前の epoch
past_epoch_over_retention() {
  echo $(( $(date +%s) - (RETENTION_DAYS + 1) * 86400 ))
}

# 「現在 - 1 日」前の epoch（保持期間内）
past_epoch_within_retention() {
  echo $(( $(date +%s) - 1 * 86400 ))
}

# 「現在 - (GRACE_PERIOD_DAYS + 1) 日」前（grace period 外）の ISO8601 文字列
iso8601_over_grace() {
  date -d "@$(( $(date +%s) - (GRACE_PERIOD_DAYS + 1) * 86400 ))" --utc +%Y-%m-%dT%H:%M:%SZ
}

# 「現在 - 1 日」前（grace period 内）の ISO8601 文字列
iso8601_within_grace() {
  date -d "@$(( $(date +%s) - 1 * 86400 ))" --utc +%Y-%m-%dT%H:%M:%SZ
}

# touch -d "@epoch" でファイルの mtime を epoch に設定する
set_mtime() {
  local path="$1" epoch="$2"
  touch -d "@${epoch}" "$path"
}

# ---- state-root フィクスチャ共通生成: escalation-template.md を含む空 state root ----
make_state_root() {
  local dir="$1"
  mkdir -p "$dir"
  touch "$dir/escalation-template.md"
}

# ---- 隔離 git リポジトリ生成ヘルパー ----
# 隔離リポジトリを作成し、リポジトリルートパスを echo する。
make_isolated_repo() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  git init -q "$tmpdir"
  echo "$tmpdir"
}

# ========== T1: dry-run が削除対象を列挙し実削除しない ==========
run_case "T1: dry-run（--state-root 付き）が削除対象を列挙し実削除しない"

T1_DIR="$(mktemp -d)"
make_state_root "$T1_DIR"
# 保持期間超過のセッションディレクトリ（runlog.jsonl なし → dir mtime で判定）
OLD_SESSION="$T1_DIR/team_old_session"
mkdir -p "$OLD_SESSION"
set_mtime "$OLD_SESSION" "$(past_epoch_over_retention)"

# dry-run は git リポジトリ内であれば任意 cwd で実行できる
set +e
stdout=$(cd "$SCRIPT_DIR" && bash "$TARGET" --state-root "$T1_DIR" 2>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 0（dry-run 成功）" "0" "$exit_code"
assert_contains "stdout に削除対象セッションが列挙される" "team_old_session" "$stdout"
assert_path_exists "dry-run 後にセッションディレクトリが残存する" "$OLD_SESSION"

rm -rf "$T1_DIR"

# ========== T2: dry-run 出力に件数・合計サイズ（整数バイト形式）が含まれる ==========
run_case "T2: dry-run 出力に削除対象件数と合計サイズ（整数バイト形式）が含まれる"

T2_DIR="$(mktemp -d)"
make_state_root "$T2_DIR"
OLD_SESSION2="$T2_DIR/team_old_clean"
mkdir -p "$OLD_SESSION2"
# ファイルを置いてサイズをゼロ以外にする
echo "dummy" > "$OLD_SESSION2/dummy.txt"
set_mtime "$OLD_SESSION2" "$(past_epoch_over_retention)"
set_mtime "$OLD_SESSION2/dummy.txt" "$(past_epoch_over_retention)"

set +e
stdout=$(cd "$SCRIPT_DIR" && bash "$TARGET" --state-root "$T2_DIR" 2>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 0" "0" "$exit_code"
# 整数バイト形式の数値が出力に含まれること（例: "1 directories" "12345 bytes" など）
assert_matches_regex "stdout に削除件数が含まれる（数値 + directories）" "[0-9]+ director" "$stdout"
assert_matches_regex "stdout に合計サイズが含まれる（整数バイト形式）" "[0-9]+ bytes" "$stdout"
# 人間可読形式（K/M/G 等）が出力されていないこと（整数バイト形式のみ）
assert_not_contains "stdout に人間可読サイズ（K/M/G）が含まれない" " KB" "$stdout"
assert_not_contains "stdout に人間可読サイズ（K/M/G）が含まれない(M)" " MB" "$stdout"

rm -rf "$T2_DIR"

# ========== T3: escalation-template.md と保持期間内セッションが除外される ==========
run_case "T3: escalation-template.md と保持期間内セッション（runlog.jsonl mtime が期間内）が除外される"

T3_DIR="$(mktemp -d)"
make_state_root "$T3_DIR"

# 期間内セッション（runlog.jsonl の mtime が RETENTION_DAYS 以内）
RECENT_SESSION="$T3_DIR/team_recent"
mkdir -p "$RECENT_SESSION"
echo "log" > "$RECENT_SESSION/runlog.jsonl"
set_mtime "$RECENT_SESSION/runlog.jsonl" "$(past_epoch_within_retention)"

# 期間超過セッション（runlog.jsonl の mtime が超過）
OLD_SESSION3="$T3_DIR/team_old_with_runlog"
mkdir -p "$OLD_SESSION3"
echo "log" > "$OLD_SESSION3/runlog.jsonl"
set_mtime "$OLD_SESSION3/runlog.jsonl" "$(past_epoch_over_retention)"
set_mtime "$OLD_SESSION3" "$(past_epoch_over_retention)"

set +e
stdout=$(cd "$SCRIPT_DIR" && bash "$TARGET" --state-root "$T3_DIR" 2>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 0" "0" "$exit_code"
assert_not_contains "escalation-template.md が削除対象に含まれない" "escalation-template.md" "$stdout"
assert_not_contains "期間内セッションが削除対象に含まれない" "team_recent" "$stdout"
assert_contains "期間超過セッションが削除対象に含まれる" "team_old_with_runlog" "$stdout"
assert_path_exists "escalation-template.md が残存する" "$T3_DIR/escalation-template.md"

rm -rf "$T3_DIR"

# ========== T4: runlog.jsonl なしセッション → dir mtime フォールバック ==========
run_case "T4: runlog.jsonl 欠落セッションで dir mtime フォールバックが効く（期間内=除外・期間外=削除対象）"

T4_DIR="$(mktemp -d)"
make_state_root "$T4_DIR"

# runlog.jsonl なし・dir mtime が期間内
FALLBACK_RECENT="$T4_DIR/team_fallback_recent"
mkdir -p "$FALLBACK_RECENT"
set_mtime "$FALLBACK_RECENT" "$(past_epoch_within_retention)"

# runlog.jsonl なし・dir mtime が期間超過
FALLBACK_OLD="$T4_DIR/team_fallback_old"
mkdir -p "$FALLBACK_OLD"
set_mtime "$FALLBACK_OLD" "$(past_epoch_over_retention)"

set +e
stdout=$(cd "$SCRIPT_DIR" && bash "$TARGET" --state-root "$T4_DIR" 2>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 0" "0" "$exit_code"
assert_not_contains "dir mtime 期間内セッションが削除対象に含まれない" "team_fallback_recent" "$stdout"
assert_contains "dir mtime 期間外セッションが削除対象に含まれる" "team_fallback_old" "$stdout"
assert_path_exists "dir mtime 期間内セッションが残存する" "$FALLBACK_RECENT"

rm -rf "$T4_DIR"

# ========== T5: sessions/<uuid>/ grace period 内/外 のエントリ保護 ==========
# フィクスチャ構成:
#   grace_in         : grace period 内（1日前）、件数外（21番目） → grace period 保護
#   grace_out_1〜19  : grace period 外（GRACE_PERIOD_DAYS+1日前以上）、最新 20 件以内 → 件数保護
#   grace_out_oldest : grace period 外、件数外（21番目相当の最古） → AND 条件で削除対象
# SESSIONS_KEEP_COUNT=20 のため、21 件生成して件数外（最古）を 1 件作る。
# EARS 5 の AND 条件「N件外 かつ grace period 外」のみが削除対象になることを検証する。
run_case "T5: sessions/<uuid>/ の grace period 内エントリが除外され、期間外かつ件数外が削除対象になる"

T5_DIR="$(mktemp -d)"
make_state_root "$T5_DIR"
SESSIONS_DIR="$T5_DIR/sessions/test-uuid-t5"
mkdir -p "$SESSIONS_DIR"

# grace period 外エントリを 19 件生成（grace_out_01〜grace_out_19）
# これら 19 件は grace period 外だが、件数内（最新 20 件以内）になるため件数保護される。
# 各エントリの created_at: 現在 - (GRACE_PERIOD_DAYS + 21 - i) 日（i=1が最古、i=19が最新）
for i in $(seq 1 19); do
  entry_dir="$SESSIONS_DIR/grace_out_$(printf '%02d' $i)"
  mkdir -p "$entry_dir"
  age_days=$(( GRACE_PERIOD_DAYS + 21 - i ))
  ts_epoch=$(( $(date +%s) - age_days * 86400 ))
  ts_iso=$(date -d "@${ts_epoch}" --utc +%Y-%m-%dT%H:%M:%SZ)
  echo "{\"created_at\": \"${ts_iso}\"}" > "$entry_dir/init.json"
  set_mtime "$entry_dir/init.json" "$ts_epoch"
  set_mtime "$entry_dir" "$ts_epoch"
done

# grace period 外かつ件数外（最古 = 21番目以降）の最古エントリ → 削除対象
# created_at: 現在 - (GRACE_PERIOD_DAYS + 21) 日（19件の中で最古より更に古い）
GRACE_OUT_OLDEST="$SESSIONS_DIR/grace_out_oldest"
mkdir -p "$GRACE_OUT_OLDEST"
oldest_age_days=$(( GRACE_PERIOD_DAYS + 21 ))
oldest_epoch=$(( $(date +%s) - oldest_age_days * 86400 ))
oldest_iso=$(date -d "@${oldest_epoch}" --utc +%Y-%m-%dT%H:%M:%SZ)
echo "{\"created_at\": \"${oldest_iso}\"}" > "$GRACE_OUT_OLDEST/init.json"
set_mtime "$GRACE_OUT_OLDEST/init.json" "$oldest_epoch"
set_mtime "$GRACE_OUT_OLDEST" "$oldest_epoch"

# grace period 内（1日前）、件数外（21番目相当の最新） → grace period 保護
# created_at が最新（1日前）なので件数内にも入るが、ここでは grace period 保護を主に確認
GRACE_IN="$SESSIONS_DIR/grace_in"
mkdir -p "$GRACE_IN"
echo "{\"created_at\": \"$(iso8601_within_grace)\"}" > "$GRACE_IN/init.json"

# 合計: grace_out_01〜grace_out_19 (19件) + grace_out_oldest (1件) + grace_in (1件) = 21件
# 最新 20 件は grace_in + grace_out_01〜grace_out_19 が件数保護される
# grace_out_oldest のみが「件数外 AND grace period 外」で削除対象

set +e
stdout=$(cd "$SCRIPT_DIR" && bash "$TARGET" --state-root "$T5_DIR" 2>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 0" "0" "$exit_code"
# grace period 内エントリは保護（件数内に入るため件数保護でもある）
assert_not_contains "grace period 内エントリが削除対象に含まれない" "grace_in" "$stdout"
# grace period 外かつ件数内エントリは件数保護される（AND 条件の OR 側：件数保護）
assert_not_contains "件数保護エントリが削除対象に含まれない（grace_out_19）" "grace_out_19" "$stdout"
# grace period 外かつ件数外（最古）のエントリのみが削除対象になる
assert_contains "grace period 外かつ件数外エントリが削除対象に含まれる" "grace_out_oldest" "$stdout"
assert_path_exists "grace period 内エントリが残存する" "$GRACE_IN"
assert_path_exists "件数保護エントリが残存する" "$SESSIONS_DIR/grace_out_19"

rm -rf "$T5_DIR"

# ========== T6: sessions/<uuid>/ の件数保持（最新 N 件保護・古い件数外が削除対象） ==========
run_case "T6: sessions/<uuid>/ が SESSIONS_KEEP_COUNT を超える場合、最新N件が保持されN件外の古いエントリが削除対象になる"

T6_DIR="$(mktemp -d)"
make_state_root "$T6_DIR"
SESSIONS_DIR6="$T6_DIR/sessions/test-uuid-t6"
mkdir -p "$SESSIONS_DIR6"

# SESSIONS_KEEP_COUNT+1 件生成（最新 N 件は保護、最古の 1 件は削除対象）
N=$SESSIONS_KEEP_COUNT  # =20
OLDEST_GRACE_OUT_DIR=""

for i in $(seq 1 $((N + 1))); do
  entry_dir="$SESSIONS_DIR6/session_$(printf '%03d' $i)"
  mkdir -p "$entry_dir"
  # 古い順から並べ: i=1 が最古（grace period 外）、i=N+1 が最新
  # epoch: 現在 - (GRACE_PERIOD_DAYS + N + 1 - i) * 86400
  age_days=$(( GRACE_PERIOD_DAYS + N + 2 - i ))
  ts_epoch=$(( $(date +%s) - age_days * 86400 ))
  ts_iso=$(date -d "@${ts_epoch}" --utc +%Y-%m-%dT%H:%M:%SZ)
  echo "{\"created_at\": \"${ts_iso}\"}" > "$entry_dir/init.json"
  set_mtime "$entry_dir/init.json" "$ts_epoch"
  set_mtime "$entry_dir" "$ts_epoch"
  if [[ $i -eq 1 ]]; then
    OLDEST_GRACE_OUT_DIR="$entry_dir"
  fi
done

set +e
stdout=$(cd "$SCRIPT_DIR" && bash "$TARGET" --state-root "$T6_DIR" 2>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 0" "0" "$exit_code"
# 最古エントリ（件数外 + grace period 外）が削除対象
assert_contains "最古エントリ（件数外）が削除対象に含まれる" "session_001" "$stdout"
# 最新エントリ（件数内）が削除対象外
assert_not_contains "最新エントリ（件数内）が削除対象に含まれない" "session_$(printf '%03d' $((N+1)))" "$stdout"
assert_path_exists "最古エントリが dry-run 後に残存する" "$OLDEST_GRACE_OUT_DIR"

rm -rf "$T6_DIR"

# ========== T7: worktree 文脈での --apply 拒否 ==========
run_case "T7: メイン checkout 以外（worktree 文脈）での --apply が非ゼロ終了で拒否される"

T7_REPO="$(mktemp -d)"
T7_STATE="$(mktemp -d)"
git init -q "$T7_REPO"
# 最初のコミットが必要（git worktree add には最低1コミット）
git -C "$T7_REPO" config user.email "test@test.com"
git -C "$T7_REPO" config user.name "Test"
git -C "$T7_REPO" commit --allow-empty -q -m "init"
# linked worktree を追加
T7_WORKTREE="$(mktemp -d)"
rmdir "$T7_WORKTREE"  # git worktree add が自動作成するため事前削除
git -C "$T7_REPO" worktree add -q "$T7_WORKTREE"

make_state_root "$T7_STATE"

set +e
stderr=$(cd "$T7_WORKTREE" && bash "$TARGET" --state-root "$T7_STATE" --apply 2>&1 1>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 非ゼロ（worktree での --apply 拒否）" "1" "$exit_code"
assert_contains "stderr に拒否メッセージが含まれる" "worktree" "$stderr"

# クリーンアップ
git -C "$T7_REPO" worktree remove --force "$T7_WORKTREE" 2>/dev/null || true
git -C "$T7_REPO" worktree prune 2>/dev/null || true
rm -rf "$T7_REPO" "$T7_STATE"

# ========== T8: --apply でセッションが実削除される（隔離リポジトリ内・メイン checkout） ==========
run_case "T8: --apply 時に保持基準超過セッションが実削除される（隔離リポジトリ内のメイン checkout）"

# --apply は checkout 配下の .iterate-team/state に固定されるため、state を repo 内に配置する
T8_REPO="$(make_isolated_repo)"
T8_STATE="$T8_REPO/.iterate-team/state"
make_state_root "$T8_STATE"

OLD_SESSION8="$T8_STATE/team_to_delete"
mkdir -p "$OLD_SESSION8"
set_mtime "$OLD_SESSION8" "$(past_epoch_over_retention)"

KEEP_SESSION8="$T8_STATE/team_to_keep"
mkdir -p "$KEEP_SESSION8"
set_mtime "$KEEP_SESSION8" "$(past_epoch_within_retention)"

set +e
stdout=$(cd "$T8_REPO" && bash "$TARGET" --state-root "$T8_STATE" --apply 2>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 0（--apply 成功）" "0" "$exit_code"
assert_path_not_exists "超過セッションが削除されている" "$OLD_SESSION8"
assert_path_exists "保持期間内セッションが残存する" "$KEEP_SESSION8"
assert_path_exists "escalation-template.md が残存する" "$T8_STATE/escalation-template.md"

rm -rf "$T8_REPO"

# ========== T9: symlink は辿らず除外して残す（fail-closed） ==========
run_case "T9: state root 配下の symlink は辿らず削除対象から除外して残る（配下外実体も残存）"

T9_DIR="$(mktemp -d)"
make_state_root "$T9_DIR"

# 配下外実体
T9_OUTSIDE="$(mktemp -d)"
mkdir -p "$T9_OUTSIDE/secret"
echo "secret" > "$T9_OUTSIDE/secret/data.txt"

# state root 配下に配下外を指す symlink を置く
ln -s "$T9_OUTSIDE" "$T9_DIR/symlink_to_outside"

# 同じ state root 内に保持期間超過の通常ディレクトリも置く（処理継続確認用）
OLD_SESSION9="$T9_DIR/team_old_for_t9"
mkdir -p "$OLD_SESSION9"
set_mtime "$OLD_SESSION9" "$(past_epoch_over_retention)"

set +e
stdout=$(cd "$SCRIPT_DIR" && bash "$TARGET" --state-root "$T9_DIR" 2>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 0（symlink 検出でエラー終了しない）" "0" "$exit_code"
# symlink 自体が削除対象に含まれない
assert_not_contains "symlink が削除対象に含まれない" "symlink_to_outside" "$stdout"
# symlink 自体が残存する
assert_path_exists "symlink が残存する" "$T9_DIR/symlink_to_outside"
# 配下外の実体が残存する
assert_path_exists "配下外実体が残存する" "$T9_OUTSIDE/secret/data.txt"
# 処理が継続し、通常ディレクトリは削除対象として列挙される
assert_contains "通常超過セッションが削除対象に含まれる（処理継続）" "team_old_for_t9" "$stdout"

rm -rf "$T9_DIR" "$T9_OUTSIDE"

# ========== T10: パス逸脱エントリが削除対象から除外され処理継続 ==========
run_case "T10: symlink 解決後パスが state root 配下外となるエントリが削除対象から除外され、配下内通常ディレクトリは削除対象になる"

T10_DIR="$(mktemp -d)"
make_state_root "$T10_DIR"

# 配下外実体（兄弟ディレクトリ相当）
T10_OUTSIDE="$(mktemp -d)"
echo "outside" > "$T10_OUTSIDE/outside.txt"

# state-backup 等の兄弟ディレクトリ名誤マッチ防止（security CRITICAL）:
# state_root_real=/x/state の場合に /x/state-backup が前方一致誤判定されないことを確認
T10_PARENT="$(dirname "$T10_DIR")"
T10_SIBLING="${T10_PARENT}/$(basename "$T10_DIR")-backup"
mkdir -p "$T10_SIBLING"
echo "backup" > "$T10_SIBLING/backup.txt"

# state root 配下外を指す symlink（解決後パスが配下外）
ln -s "$T10_OUTSIDE" "$T10_DIR/escaped_symlink"

# 配下内の保持期間超過通常ディレクトリ
OLD_SESSION10="$T10_DIR/team_old_for_t10"
mkdir -p "$OLD_SESSION10"
set_mtime "$OLD_SESSION10" "$(past_epoch_over_retention)"

set +e
stdout=$(cd "$SCRIPT_DIR" && bash "$TARGET" --state-root "$T10_DIR" 2>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 0（逸脱エントリでエラー終了しない）" "0" "$exit_code"
assert_not_contains "逸脱 symlink が削除対象に含まれない" "escaped_symlink" "$stdout"
assert_path_exists "配下外実体が残存する" "$T10_OUTSIDE/outside.txt"
assert_path_exists "兄弟ディレクトリが誤削除されない（sibling 残存）" "$T10_SIBLING/backup.txt"
assert_contains "配下内超過セッションが削除対象になる（処理継続）" "team_old_for_t10" "$stdout"

rm -rf "$T10_DIR" "$T10_OUTSIDE" "$T10_SIBLING"

# ========== T11: no-arg の既定パス解決（隔離 git リポジトリ内で検証） ==========
run_case "T11: no-arg 実行で既定 state root が隔離リポジトリの .iterate-team/state に解決される"

T11_REPO="$(make_isolated_repo)"
T11_STATE_DIR="$T11_REPO/.iterate-team/state"
mkdir -p "$T11_STATE_DIR"
touch "$T11_STATE_DIR/escalation-template.md"

# 保持期間超過セッションをフィクスチャとして配置
OLD_SESSION11="$T11_STATE_DIR/team_old_no_arg"
mkdir -p "$OLD_SESSION11"
set_mtime "$OLD_SESSION11" "$(past_epoch_over_retention)"

# no-arg 実行（隔離リポジトリ内 cd）
set +e
stdout=$(cd "$T11_REPO" && bash "$TARGET" 2>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 0（no-arg dry-run 成功）" "0" "$exit_code"
# 既定 state root（.iterate-team/state 配下）のフィクスチャが列挙される
assert_contains "no-arg で隔離リポジトリの超過セッションが列挙される" "team_old_no_arg" "$stdout"

rm -rf "$T11_REPO"

# ========== T13: メイン checkout のサブディレクトリからの --apply が成功する ==========
# git rev-parse --git-dir はサブディレクトリから実行すると CWD 基準の相対パスを返す。
# --git-common-dir と形式がずれても、絶対パス正規化により worktree 誤判定せず削除できることを検証。
run_case "T13: メイン checkout のサブディレクトリから --apply してもメイン checkout と判定され実削除される"

# --apply は checkout 配下の .iterate-team/state に固定されるため、state を repo 内に配置する
T13_REPO="$(make_isolated_repo)"
T13_SUBDIR="$T13_REPO/sub/nested/dir"
mkdir -p "$T13_SUBDIR"
T13_STATE="$T13_REPO/.iterate-team/state"
make_state_root "$T13_STATE"

OLD_SESSION13="$T13_STATE/team_to_delete_subdir"
mkdir -p "$OLD_SESSION13"
set_mtime "$OLD_SESSION13" "$(past_epoch_over_retention)"

set +e
stdout=$(cd "$T13_SUBDIR" && bash "$TARGET" --state-root "$T13_STATE" --apply 2>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 0（サブディレクトリからの --apply 成功）" "0" "$exit_code"
assert_path_not_exists "超過セッションが削除されている" "$OLD_SESSION13"
assert_path_exists "escalation-template.md が残存する" "$T13_STATE/escalation-template.md"

rm -rf "$T13_REPO"

# ========== T14: --apply で checkout 外の state root（同名マーカー付き）が拒否される ==========
# escalation-template.md マーカーを持つ別ディレクトリを通常 checkout から --apply に渡しても、
# checkout 配下の .iterate-team/state と一致しない限り実削除を拒否することを検証（誤削除防止）。
run_case "T14: --apply で checkout 外の state root（同名マーカー付き）が非ゼロ終了で拒否され実削除されない"

T14_REPO="$(make_isolated_repo)"
mkdir -p "$T14_REPO/.iterate-team/state"
touch "$T14_REPO/.iterate-team/state/escalation-template.md"

# checkout 外の「偽 state root」（マーカーは持つが checkout の state ではない）
T14_FAKE="$(mktemp -d)"
make_state_root "$T14_FAKE"
VICTIM14="$T14_FAKE/team_should_survive"
mkdir -p "$VICTIM14"
set_mtime "$VICTIM14" "$(past_epoch_over_retention)"

set +e
stderr=$(cd "$T14_REPO" && bash "$TARGET" --state-root "$T14_FAKE" --apply 2>&1 1>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 非ゼロ（checkout 外 state root の --apply 拒否）" "1" "$exit_code"
assert_contains "stderr に state root 限定の拒否メッセージが含まれる" ".iterate-team/state" "$stderr"
assert_path_exists "checkout 外の超過ディレクトリが誤削除されず残存する" "$VICTIM14"

rm -rf "$T14_REPO" "$T14_FAKE"

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
