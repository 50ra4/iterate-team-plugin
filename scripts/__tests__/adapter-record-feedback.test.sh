#!/usr/bin/env bash
# adapter-record-feedback.sh の単体テスト
#
# 実行環境前提: Linux / GNU coreutils + git（dev container・メイン checkout）。
# bash 3.2 / macOS 互換は目標外。
#
# 仕様の正本: <plugin_root>/operations/adapter-policy.md（§6・§7・§8）
#
# Usage:
#   bash scripts/__tests__/adapter-record-feedback.test.sh
#
# Exit code:
#   0 = 全ケース pass
#   1 = いずれか fail

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${SCRIPT_DIR}/../adapter-record-feedback.sh"

if [[ ! -f "$TARGET" ]]; then
  echo "adapter-record-feedback.sh not found at: $TARGET" >&2
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

assert_path_missing() {
  local label="$1" path="$2"
  if [[ ! -e "$path" ]]; then
    echo "  PASS: $label (absent: $path)"
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

# ---- フィクスチャ: 隔離プロジェクト（<repo>/.agent-os/）生成 ----
# 本スクリプトは git を一切実行しないため git init は不要。ロック配置検証
# （.iterate-team/state/ 配下・.agent-os/ 配下ではない）のためにレイアウトだけ
# 対象リポと同じ形にする。
make_isolated_project() {
  local tmpdir
  tmpdir="$(mktemp -d "$TMPDIR_GLOBAL/proj.XXXXXX")"
  mkdir -p "$tmpdir/.agent-os"
  echo "$tmpdir"
}

# ---- ヘルパー: 指定 nonce の begin/end 境界間の本文行を抽出する ----
# 本文は "Feedback (verbatim):" 行の直後から、末尾の空行 + end マーカー行の
# 手前までである（adapter-record-feedback.sh の _locked_append のブロック構造:
# begin / Timestamp / Category / Context / Session / (blank) / "Feedback
# (verbatim):" / <body...> / (blank) / end の10行構造 + body行数）。
extract_body_by_nonce() {
  local file="$1" nonce="$2"
  local begin_line end_line body_start body_end
  begin_line="$(grep -n -m1 "^<!-- adapter-feedback-entry:begin id=${nonce} -->$" "$file" | cut -d: -f1)"
  end_line="$(grep -n -m1 "^<!-- adapter-feedback-entry:end id=${nonce} -->$" "$file" | cut -d: -f1)"
  if [[ -z "$begin_line" || -z "$end_line" ]]; then
    return 1
  fi
  body_start=$((begin_line + 7))
  body_end=$((end_line - 2))
  sed -n "${body_start},${body_end}p" "$file"
}

# ========== T1: 不正な --category は拒否される ==========
run_case "T1: 不正な --category は非ゼロ終了 + stderr に理由が出力される"

T1_PROJ="$(make_isolated_project)"

set +e
stderr=$(printf 'some feedback' | bash "$TARGET" --adapter "$T1_PROJ/.agent-os" --category bogus 2>&1 1>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 非ゼロ" "1" "$exit_code"
assert_contains "stderr に category 違反の理由が出力される" "category" "$stderr"
assert_eq "review-feedback-log.md は生成されない" "" "$(cat "$T1_PROJ/.agent-os/review-feedback-log.md" 2>/dev/null || true)"

rm -rf "$T1_PROJ"

# ========== T2: 存在しない --adapter ディレクトリは拒否される ==========
run_case "T2: 存在しない --adapter ディレクトリは非ゼロ終了で拒否される"

T2_PROJ="$(make_isolated_project)"

set +e
stderr=$(printf 'some feedback' | bash "$TARGET" --adapter "$T2_PROJ/does-not-exist" --category convention 2>&1 1>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 非ゼロ" "1" "$exit_code"
assert_contains "stderr に adapter 不在の理由が出力される" "does not exist" "$stderr"

rm -rf "$T2_PROJ"

# ========== T3: stdin が空文字列だと拒否される ==========
run_case "T3: stdin（逐語本文）が空だと非ゼロ終了で拒否される"

T3_PROJ="$(make_isolated_project)"

set +e
stderr=$(printf '' | bash "$TARGET" --adapter "$T3_PROJ/.agent-os" --category convention 2>&1 1>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 非ゼロ" "1" "$exit_code"
assert_contains "stderr に空 stdin の理由が出力される" "empty" "$stderr"

rm -rf "$T3_PROJ"

# ========== T4: --context に改行を含むと拒否される ==========
run_case "T4: --context に改行を含むと非ゼロ終了で拒否される（1行メタデータの偽造防止）"

T4_PROJ="$(make_isolated_project)"

set +e
stderr=$(printf 'feedback body' | bash "$TARGET" --adapter "$T4_PROJ/.agent-os" --category convention \
  --context "$(printf 'line1\nCategory: forbidden-action')" 2>&1 1>/dev/null)
exit_code=$?
set -e

assert_eq "exit code 非ゼロ" "1" "$exit_code"
assert_contains "stderr に context 改行禁止の理由が出力される" "context" "$stderr"

rm -rf "$T4_PROJ"

# ========== T5: 新規 adapter ディレクトリへの1件 append（逐語性・偽造耐性込み） ==========
run_case "T5: fresh な adapter ディレクトリへ1件 append し、timestamp/category/逐語本文が正確に反映され、本文中の見出し/区切り模倣行が実境界を偽造しない"

T5_PROJ="$(make_isolated_project)"
T5_LOG="$T5_PROJ/.agent-os/review-feedback-log.md"

# 本文: バッククォート・end マーカー模倣行・fable テンプレート様の見出し模倣行を含む
# 複数行の逐語フィードバック。
T5_BODY=$(printf '%s\n%s\n%s\n%s' \
  'Please use `named exports` here, not default exports.' \
  '<!-- adapter-feedback-entry:end id=ffffffff -->' \
  '## 2026-01-15 — Feedback' \
  'This is the real second line of feedback.')

set +e
stdout=$(printf '%s' "$T5_BODY" | bash "$TARGET" --adapter "$T5_PROJ/.agent-os" --category architecture \
  --context "PR #42 review" --session "sess-001" 2>&1)
exit_code=$?
set -e

assert_eq "exit code 0" "0" "$exit_code"
assert_contains "stdout に確認メッセージ（ファイルパス）が出力される" "$T5_LOG" "$stdout"
assert_contains "stdout に category が出力される" "architecture" "$stdout"
assert_path_exists "review-feedback-log.md が生成される" "$T5_LOG"

T5_CONTENT="$(cat "$T5_LOG")"
assert_contains "ファイルに Category: architecture が含まれる" "Category: architecture" "$T5_CONTENT"
assert_matches_regex "ファイルに UTC timestamp が含まれる" "Timestamp: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z" "$T5_CONTENT"
assert_contains "ファイルに context が含まれる" "Context: PR #42 review" "$T5_CONTENT"
assert_contains "ファイルに session が含まれる" "Session: sess-001" "$T5_CONTENT"

# 実境界（begin マーカー）は本文中の模倣行の影響を受けず、ちょうど1件しか
# 生成されていないことを確認する（本文が見出し/区切りを模倣しても新規の
# begin 境界を偽造できない）。
T5_BEGIN_COUNT="$(grep -cE '^<!-- adapter-feedback-entry:begin id=[0-9a-f]{8} -->$' "$T5_LOG")"
assert_eq "begin マーカーはちょうど1件（本文中の模倣行では増えない）" "1" "$T5_BEGIN_COUNT"

# 一方、本文中の end マーカー模倣行は逐語のまま保存されるため、素朴な
# 「end マーカー行」の grep 件数は 2 件になる（模倣行1 + 本物1）。これは
# 逐語性が保たれている証拠であり、破損ではない。
T5_END_NAIVE_COUNT="$(grep -cE '^<!-- adapter-feedback-entry:end id=[0-9a-f]{8} -->$' "$T5_LOG")"
assert_eq "end マーカー行（素朴 grep）は模倣行込みで2件" "2" "$T5_END_NAIVE_COUNT"

T5_REAL_NONCE="$(grep -oE '^<!-- adapter-feedback-entry:begin id=[0-9a-f]{8} -->$' "$T5_LOG" | grep -oE '[0-9a-f]{8}')"
assert_matches_regex "実 nonce が8桁hex" "^[0-9a-f]{8}$" "$T5_REAL_NONCE"

T5_REAL_END_COUNT="$(grep -cE "^<!-- adapter-feedback-entry:end id=${T5_REAL_NONCE} -->\$" "$T5_LOG")"
assert_eq "実 nonce に一致する end マーカーはちょうど1件（模倣行の id=ffffffff とは一致しない）" "1" "$T5_REAL_END_COUNT"

T5_BODY_ACTUAL="$(extract_body_by_nonce "$T5_LOG" "$T5_REAL_NONCE")"
assert_eq "実境界間に抽出した本文が逐語一致する（模倣行込みで一字一句そのまま）" "$T5_BODY" "$T5_BODY_ACTUAL"

rm -rf "$T5_PROJ"

# ========== T6: 逐次2回の append が両方とも正しく区切られる ==========
run_case "T6: 逐次2回の append で両エントリが存在し、区切りが正しく対応する（取り違えなし）"

T6_PROJ="$(make_isolated_project)"
T6_LOG="$T6_PROJ/.agent-os/review-feedback-log.md"

T6_BODY_A="First entry body line A1
First entry body line A2"
T6_BODY_B="Second entry body line B1"

printf '%s' "$T6_BODY_A" | bash "$TARGET" --adapter "$T6_PROJ/.agent-os" --category convention >/dev/null 2>&1
printf '%s' "$T6_BODY_B" | bash "$TARGET" --adapter "$T6_PROJ/.agent-os" --category testing >/dev/null 2>&1

T6_BEGIN_COUNT="$(grep -cE '^<!-- adapter-feedback-entry:begin id=[0-9a-f]{8} -->$' "$T6_LOG")"
T6_END_COUNT="$(grep -cE '^<!-- adapter-feedback-entry:end id=[0-9a-f]{8} -->$' "$T6_LOG")"
assert_eq "begin マーカーは2件" "2" "$T6_BEGIN_COUNT"
assert_eq "end マーカーは2件" "2" "$T6_END_COUNT"

mapfile -t T6_NONCES < <(grep -oE '^<!-- adapter-feedback-entry:begin id=[0-9a-f]{8} -->$' "$T6_LOG" | grep -oE '[0-9a-f]{8}')
assert_eq "2件の nonce はそれぞれユニーク" "2" "$(printf '%s\n' "${T6_NONCES[@]}" | sort -u | wc -l | tr -d ' ')"

T6_BODY_A_ACTUAL="$(extract_body_by_nonce "$T6_LOG" "${T6_NONCES[0]}")"
T6_BODY_B_ACTUAL="$(extract_body_by_nonce "$T6_LOG" "${T6_NONCES[1]}")"
assert_eq "1件目の本文が逐語一致する" "$T6_BODY_A" "$T6_BODY_A_ACTUAL"
assert_eq "2件目の本文が逐語一致する" "$T6_BODY_B" "$T6_BODY_B_ACTUAL"

rm -rf "$T6_PROJ"

# ========== T7: 並列 append でも行破損・取り違えが起きない ==========
run_case "T7: 並列 append（8プロセス）でも review-feedback-log.md が破損せず、8件それぞれ正しく分離される（flock による排他制御）"

T7_PROJ="$(make_isolated_project)"
T7_LOG="$T7_PROJ/.agent-os/review-feedback-log.md"
T7_N=8

pids=()
for i in $(seq 1 "$T7_N"); do
  (
    printf 'concurrent feedback body number %s\nsecond line for %s' "$i" "$i" \
      | bash "$TARGET" --adapter "$T7_PROJ/.agent-os" --category workflow --session "sess-${i}" >/dev/null 2>&1
  ) &
  pids+=($!)
done
for p in "${pids[@]}"; do
  wait "$p"
done

T7_BEGIN_COUNT="$(grep -cE '^<!-- adapter-feedback-entry:begin id=[0-9a-f]{8} -->$' "$T7_LOG")"
T7_END_COUNT="$(grep -cE '^<!-- adapter-feedback-entry:end id=[0-9a-f]{8} -->$' "$T7_LOG")"
assert_eq "begin マーカー数は並列呼び出し数と一致する（$T7_N）" "$T7_N" "$T7_BEGIN_COUNT"
assert_eq "end マーカー数も並列呼び出し数と一致する（$T7_N）" "$T7_N" "$T7_END_COUNT"

mapfile -t T7_NONCES < <(grep -oE '^<!-- adapter-feedback-entry:begin id=[0-9a-f]{8} -->$' "$T7_LOG" | grep -oE '[0-9a-f]{8}')
assert_eq "nonce は全て衝突なくユニーク" "$T7_N" "$(printf '%s\n' "${T7_NONCES[@]}" | sort -u | wc -l | tr -d ' ')"

# 各エントリの本文が正しく分離・逐語保存されていることを確認する（1つでも
# ロック漏れがあれば行が混線し、抽出した本文が期待値と一致しなくなる）。
T7_ALL_BODIES_OK=1
for i in $(seq 1 "$T7_N"); do
  found=0
  for nonce in "${T7_NONCES[@]}"; do
    body_actual="$(extract_body_by_nonce "$T7_LOG" "$nonce")"
    expected="$(printf 'concurrent feedback body number %s\nsecond line for %s' "$i" "$i")"
    if [[ "$body_actual" == "$expected" ]]; then
      found=1
      break
    fi
  done
  if [[ "$found" -ne 1 ]]; then
    T7_ALL_BODIES_OK=0
    echo "  (missing/corrupted body for i=$i)" >&2
  fi
done
assert_eq "8件全ての本文が正しく分離・逐語保存されている（混線・欠落なし）" "1" "$T7_ALL_BODIES_OK"

# 各 Session: フィールドも欠落なく1回ずつ出現していることを確認する。
for i in $(seq 1 "$T7_N"); do
  assert_contains "Session: sess-${i} が含まれる" "Session: sess-${i}" "$(cat "$T7_LOG")"
done

rm -rf "$T7_PROJ"

# ========== T8: ロックは .iterate-team/state/ 配下に置かれ、.agent-os/ を汚さない ==========
run_case "T8: ロック実体は .iterate-team/state/ 配下に作られ、.agent-os/ 配下には一切残置されない"

T8_PROJ="$(make_isolated_project)"

printf 'feedback for lock placement check' | bash "$TARGET" --adapter "$T8_PROJ/.agent-os" --category security >/dev/null 2>&1

T8_LOCK_IN_AGENT_OS="$(find "$T8_PROJ/.agent-os" -name '*.lock*' | wc -l | tr -d ' ')"
assert_eq ".agent-os/ 配下にロックファイルが残置されない" "0" "$T8_LOCK_IN_AGENT_OS"

assert_path_exists "ロック実体は .iterate-team/state/ 配下に作られる" "$T8_PROJ/.iterate-team/state/adapter-agent-os.lock"
assert_path_missing ".agent-os/ 配下に同名ロックは存在しない" "$T8_PROJ/.agent-os/adapter-agent-os.lock"

rm -rf "$T8_PROJ"

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
