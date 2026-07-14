#!/usr/bin/env bash
# adapter-check-staleness.sh の単体テスト
#
# 実行環境前提: Linux / GNU coreutils + git（dev container・メイン checkout）。
# bash 3.2 / macOS 互換は目標外。オフラインで完結する（vendor/agent-os/ 配下の
# ファイルをローカルコピーするのみでネットワークアクセスを行わない）。
#
# 仕様の正本: <plugin_root>/operations/adapter-policy.md（§2）・
#   <plugin_root>/scripts/adapter-check-staleness.sh のヘッダコメント。
#
# Usage:
#   bash scripts/__tests__/adapter-check-staleness.test.sh
#
# Exit code:
#   0 = 全ケース pass
#   1 = いずれか fail

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${SCRIPT_DIR}/../adapter-check-staleness.sh"
PLUGIN_ROOT="${SCRIPT_DIR}/../.."
BOOTSTRAP="${SCRIPT_DIR}/../adapter-bootstrap.sh"

if [[ ! -f "$TARGET" ]]; then
  echo "adapter-check-staleness.sh not found at: $TARGET" >&2
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

assert_starts_with() {
  local label="$1" prefix="$2" haystack="$3"
  if [[ "$haystack" == "$prefix"* ]]; then
    echo "  PASS: $label (starts with '$prefix')"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL: $label (expected prefix='$prefix' actual='${haystack:0:300}...')" >&2
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

# ========== T1: .agent-os ディレクトリ自体が存在しない ==========
run_case "T1: <adapter_dir> が存在しない場合、1 行目が absent: で始まり exit code 2"

T1_REPO="$(make_isolated_repo)"
T1_ADAPTER="$T1_REPO/.agent-os"

set +e
stdout=$(bash "$TARGET" --adapter "$T1_ADAPTER" 2>&1)
exit_code=$?
set -e

first_line="${stdout%%$'\n'*}"
assert_starts_with "1 行目が absent: で始まる" "absent:" "$first_line"
assert_eq "exit code 2" "2" "$exit_code"

rm -rf "$T1_REPO"

# ========== T2: .agent-os は存在するが project-profile.md が無い ==========
run_case "T2: .agent-os は存在するが project-profile.md が無い場合、absent: exit code 2"

T2_REPO="$(make_isolated_repo)"
T2_ADAPTER="$T2_REPO/.agent-os"
mkdir -p "$T2_ADAPTER"
# project-profile.md 以外の何か無関係なファイルだけ置いておく（ディレクトリ自体は
# 存在することを保証しつつ project-profile.md 不在の分岐を踏ませる）。
printf 'irrelevant\n' > "$T2_ADAPTER/README-not-a-real-adapter-file.md"

set +e
stdout=$(bash "$TARGET" --adapter "$T2_ADAPTER" 2>&1)
exit_code=$?
set -e

first_line="${stdout%%$'\n'*}"
assert_starts_with "1 行目が absent: で始まる" "absent:" "$first_line"
assert_contains "理由に project-profile.md が言及される" "project-profile.md" "$stdout"
assert_eq "exit code 2" "2" "$exit_code"

rm -rf "$T2_REPO"

# ========== T3: adapter-bootstrap.sh 直後（未観測スキャフォールドそのまま）は stale ==========
run_case "T3: adapter-bootstrap.sh 直後の未観測スキャフォールドは stale: exit code 3"

T3_REPO="$(make_isolated_repo)"

set +e
bootstrap_out=$(bash "$BOOTSTRAP" --target "$T3_REPO" 2>&1)
bootstrap_exit=$?
set -e
assert_eq "前提: adapter-bootstrap.sh 自体は成功する" "0" "$bootstrap_exit"

set +e
stdout=$(bash "$TARGET" --adapter "$T3_REPO/.agent-os" 2>&1)
exit_code=$?
set -e

first_line="${stdout%%$'\n'*}"
assert_starts_with "1 行目が stale: で始まる" "stale:" "$first_line"
assert_eq "exit code 3" "3" "$exit_code"
assert_contains "理由に project-profile.md への言及がある" "project-profile.md" "$stdout"
assert_contains "理由に command-map.md への言及がある" "command-map.md" "$stdout"

rm -rf "$T3_REPO"

# ========== T4: vendor/agent-os/project-adapter/.agent-os/*.md を直接コピーしても stale (cp 経由フィクスチャ) ==========
run_case "T4: vendored scaffold を cp で複製しただけの .agent-os は stale: exit code 3"

T4_REPO="$(make_isolated_repo)"
T4_ADAPTER="$T4_REPO/.agent-os"
mkdir -p "$T4_ADAPTER"
cp "$PLUGIN_ROOT/vendor/agent-os/project-adapter/.agent-os/"*.md "$T4_ADAPTER/"
cp "$PLUGIN_ROOT/vendor/agent-os/GLOBAL_AGENTS.md" "$T4_ADAPTER/GLOBAL_AGENTS.md"

set +e
stdout=$(bash "$TARGET" --adapter "$T4_ADAPTER" 2>&1)
exit_code=$?
set -e

first_line="${stdout%%$'\n'*}"
assert_starts_with "1 行目が stale: で始まる" "stale:" "$first_line"
assert_eq "exit code 3" "3" "$exit_code"

rm -rf "$T4_REPO"

# ========== T5: 実観測内容が project-profile.md と command-map.md 両方にある場合は fresh ==========
run_case "T5: project-profile.md と command-map.md に実観測内容がある場合、fresh: exit code 0"

T5_REPO="$(make_isolated_repo)"
T5_ADAPTER="$T5_REPO/.agent-os"
mkdir -p "$T5_ADAPTER"

cat > "$T5_ADAPTER/project-profile.md" <<'EOF'
# Project Profile: widget-cli

## Project overview

widget-cli is a Node.js CLI tool for managing widgets. Observed from
package.json (name: widget-cli) and README.md.

## Tech stack (observed)

- Node.js 20, TypeScript 5.4 (tsconfig.json, observed directly)
- npm workspaces (package.json "workspaces" field)
EOF

cat > "$T5_ADAPTER/command-map.md" <<'EOF'
# Command Map: widget-cli

## Test

| Command | What it does | Evidence | Last verified |
|---|---|---|---|
| `npm test` | Runs the Jest test suite | package.json scripts."test" | 2026-07-14 |

## Lint

| Command | What it does | Evidence | Last verified |
|---|---|---|---|
| `npm run lint` | Runs eslint | package.json scripts."lint" | 2026-07-14 |
EOF

set +e
stdout=$(bash "$TARGET" --adapter "$T5_ADAPTER" 2>&1)
exit_code=$?
set -e

assert_eq "stdout が fresh ちょうど 1 語" "fresh" "$stdout"
assert_eq "exit code 0" "0" "$exit_code"

rm -rf "$T5_REPO"

# ========== T6: project-profile.md は観測済みだが command-map.md が未観測(0 件)なら stale ==========
run_case "T6: project-profile.md は観測済みだが command-map.md が検証済みコマンド 0 件のままなら stale"

T6_REPO="$(make_isolated_repo)"
T6_ADAPTER="$T6_REPO/.agent-os"
mkdir -p "$T6_ADAPTER"

cat > "$T6_ADAPTER/project-profile.md" <<'EOF'
# Project Profile: widget-cli

## Project overview

widget-cli is a Node.js CLI tool for managing widgets. Observed from
package.json (name: widget-cli) and README.md.
EOF

cat > "$T6_ADAPTER/command-map.md" <<'EOF'
# Command Map: widget-cli

## Test

Still investigating; no command verified yet.
EOF

set +e
stdout=$(bash "$TARGET" --adapter "$T6_ADAPTER" 2>&1)
exit_code=$?
set -e

first_line="${stdout%%$'\n'*}"
assert_starts_with "1 行目が stale: で始まる" "stale:" "$first_line"
assert_eq "exit code 3" "3" "$exit_code"
assert_contains "理由に検証済みコマンド 0 件への言及がある" "0 件" "$stdout"

rm -rf "$T6_REPO"

# ========== T7: --adapter 未指定は usage error ==========
run_case "T7: --adapter を省略すると usage error (exit code >= 10)、stdout に fresh/absent/stale いずれのキーワードも出さない"

set +e
stdout=$(bash "$TARGET" 2>/dev/null)
stderr=$(bash "$TARGET" 2>&1 1>/dev/null)
exit_code=$?
set -e

if [[ "$exit_code" -ge 10 ]]; then
  echo "  PASS: usage error は exit code >= 10 (=$exit_code)"
  pass_count=$((pass_count + 1))
else
  echo "  FAIL: usage error の exit code が 10 未満 (=$exit_code)" >&2
  fail_count=$((fail_count + 1))
fi
assert_contains "stderr に --adapter が必須である旨のエラーが出る" "--adapter" "$stderr"
assert_eq "usage error 時、stdout に判定キーワードを出さない" "" "$stdout"

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
