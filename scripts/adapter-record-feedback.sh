#!/usr/bin/env bash
# adapter（プロジェクト適応レイヤ）の review-feedback-log.md 追記用スクリプト。
# team-adapter agent が本スクリプトを 1 行で呼び出すことで、逐語フィードバックの
# 記録を Write ツール経由の手書きではなく、flock 安全な単一経路に統一する
# （runlog-append.sh / knowledge-append.sh と同じ狙い）。
#
# Usage:
#   <plugin_root>/scripts/adapter-record-feedback.sh \
#     --adapter <adapter_dir> --category <cat> [--context <task-context>] \
#     [--session <session-id>]
#   （逐語フィードバック本文は引数ではなく **stdin** から読む。改行や引用符を含む
#     任意のテキストを、シェルの引数クォート事故なく安全に受け渡すため）
#
# Example:
#   printf '%s\n' 'controller に業務ロジックを書かないでほしい。service 層に置く。' \
#     | <plugin_root>/scripts/adapter-record-feedback.sh \
#         --adapter /path/to/project/.agent-os --category architecture \
#         --context "PR #42 レビュー" --session 20260713_login-fix
#
# category は fable learn-from-feedback skill の 7 分類のいずれか:
#   convention / architecture / testing / security / workflow / communication /
#   forbidden-action
#
# 動作:
#   - `.agent-os/` は team-profiler / team-adapter のみが書き込む単一書き手領域
#     （operations/adapter-policy.md §6）。本スクリプトはその書き手隔離を実装する
#     並行実行に露出した adapter 書き込み経路の一つであり（直列 interviewer ループ
#     等から呼ばれうる）、flock 安全でなければならない。
#   - ロックファイルは `.iterate-team/state/adapter-agent-os.lock` であり、
#     `adapter-recover.sh`（§7 fail-open の `.agent-os/` 復旧）が使う **同一の**
#     共有ロックである。cross-session に `adapter-recover.sh` の git restore/evacuate
#     と本スクリプトの追記が競合して `.agent-os/` を破損・欠落させないよう、
#     両者を同じロックで相互排他する（ロック名を分けない）。
#   - ロック実体は git-tracked の `.agent-os/` を汚さないよう、対象リポの
#     `.iterate-team/state/` 配下に置く（knowledge-append.sh のロック配置規律と同じ
#     理由: 残置ロックが untracked 差分として git status を汚染しないため）。
#   - repo_root は `--adapter` で渡された adapter_dir の**親ディレクトリ**から解決
#     する（adapter_dir は通常 `<project_dir>/.agent-os` であり、呼び出し元が
#     明示的に絶対/相対パスを渡してくる前提のため、他スクリプトのような
#     `CLAUDE_PROJECT_DIR` フォールバックに頼るより正確）。
#   - 検証成功後にのみ、`<adapter_dir>/review-feedback-log.md` が存在しなければ
#     fable テンプレート相当の最小ヘッダから新規作成する（知識-append.sh の
#     「拒否呼び出しは副作用ゼロで残す」規律を踏襲: 検証失敗時は何も書かない）。
#   - 1 エントリは次の形式で追記する:
#
#       <!-- adapter-feedback-entry:begin id=<8hex nonce> -->
#       Timestamp: <UTC ISO8601>
#       Category: <category>
#       Context: <task context, or "(none)">
#       Session: <session-id, or "(none)">
#
#       Feedback (verbatim):
#       <body: stdin をそのまま、末尾の空白/改行のみ trim。内部の改行・逆引用符・
#        見出し様の行はいっさい変更しない>
#
#       <!-- adapter-feedback-entry:end id=<8hex nonce> -->
#
#     区切り偽造対策: begin/end はどちらも呼び出しごとに新規生成する 8 桁 hex の
#     nonce を含む。逐語本文はユーザー入力であり、`## 2026-01-15 — Feedback` の
#     ような見出し行や `<!-- adapter-feedback-entry:end ... -->` を模倣する行を
#     含みうるが、呼び出し前に nonce を知ることはできないため、本文中の模倣行が
#     実際の境界（id が一致する begin/end 対）を偽造することはできない
#     （knowledge-append.sh が「改行/manual マーカーを禁止して行フォーマット偽造
#     を防ぐ」のと同じ動機を、逐語性を保ったまま nonce で満たす設計）。
#   - `--context` / `--session` は 1 行メタデータとして直接埋め込むため、
#     knowledge-append.sh の lesson/trigger と同じ理由で改行を禁止する
#     （複数行を許すと偽の Category:/Session: 行を注入できてしまうため）。
#   - 標準出力に「どのファイルに・どの category で記録したか」を短く出力する。
#   - git は一切実行しない（コミットは呼び出し元 Orchestrator の責務。
#     operations/adapter-policy.md §7）。
#   - runlog `feedback_recorded` イベント自体は本スクリプトが記録しない
#     （呼び出し元が operations/adapter-policy.md §8 の規約に従い別途記録する）。
#
# 仕様の正本: <plugin_root>/operations/adapter-policy.md（§6・§7・§8）
#
# 実行環境前提: Linux / GNU coreutils + git（dev container・メイン checkout）。
# flock が無い macOS ホストでは mkdir の原子性を用いたポータブルロックに
# フォールバックする（runlog-append.sh と同一方式）。

set -euo pipefail

VALID_CATEGORIES=(convention architecture testing security workflow communication forbidden-action)

usage() {
  cat <<'EOF'
Usage: adapter-record-feedback.sh --adapter <adapter_dir> --category <cat>
                                   [--context <task-context>] [--session <session-id>]

Reads the verbatim feedback text from stdin and appends one entry to
<adapter_dir>/review-feedback-log.md under an exclusive lock.

Options:
  --adapter <dir>     Path to the target repo's .agent-os/ directory (must
                       already exist).
  --category <cat>    One of: convention, architecture, testing, security,
                       workflow, communication, forbidden-action.
  --context <text>    Optional single-line task context (no newlines).
  --session <id>      Optional single-line session id (no newlines).
  --help              Show this help text and exit.
EOF
}

# ---- 引数解析 ----
adapter_dir=""
category=""
context=""
session=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --adapter)
      [[ $# -ge 2 ]] || { echo "ERROR: --adapter requires a value" >&2; exit 2; }
      adapter_dir="$2"
      shift 2
      ;;
    --category)
      [[ $# -ge 2 ]] || { echo "ERROR: --category requires a value" >&2; exit 2; }
      category="$2"
      shift 2
      ;;
    --context)
      [[ $# -ge 2 ]] || { echo "ERROR: --context requires a value" >&2; exit 2; }
      context="$2"
      shift 2
      ;;
    --session)
      [[ $# -ge 2 ]] || { echo "ERROR: --session requires a value" >&2; exit 2; }
      session="$2"
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

# ---- 必須引数検証 ----
if [[ -z "$adapter_dir" ]]; then
  echo "ERROR: --adapter is required" >&2
  exit 2
fi

if [[ ! -d "$adapter_dir" ]]; then
  echo "ERROR: --adapter directory does not exist: $adapter_dir" >&2
  exit 1
fi

if [[ -z "$category" ]]; then
  echo "ERROR: --category is required" >&2
  exit 2
fi

category_valid=0
for c in "${VALID_CATEGORIES[@]}"; do
  if [[ "$category" == "$c" ]]; then
    category_valid=1
    break
  fi
done
if [[ "$category_valid" -ne 1 ]]; then
  echo "ERROR: invalid --category '$category'; must be one of: ${VALID_CATEGORIES[*]}" >&2
  exit 1
fi

# context/session は 1 行メタデータとしてエントリへ直接埋め込むため、改行混入で
# Category:/Session: 等の後続行を偽造できてしまわないよう禁止する
# （knowledge-append.sh の lesson/trigger 改行禁止と同じ理由）。
if [[ "$context" =~ [$'\n\r'] ]]; then
  echo "ERROR: --context must not contain newline characters" >&2
  exit 1
fi
if [[ "$session" =~ [$'\n\r'] ]]; then
  echo "ERROR: --session must not contain newline characters" >&2
  exit 1
fi

# ---- stdin から逐語本文を読む ----
# コマンド置換は末尾改行を自動的に trim するのみで内部の改行・空白は保持する
# ("末尾の空白のみ trim" の要件をそのまま満たす)。
body="$(cat)"

if [[ -z "$body" ]]; then
  echo "ERROR: verbatim feedback text on stdin must not be empty" >&2
  exit 1
fi

# ---- adapter_dir 解決 & repo_root 導出 ----
adapter_dir_abs="$(cd "$adapter_dir" && pwd)"
# repo_root は adapter_dir の親ディレクトリから解決する（adapter_dir は通常
# <project_dir>/.agent-os。呼び出し元が明示的に adapter_dir を渡してくるため、
# CLAUDE_PROJECT_DIR 経由の推測より確実）。
repo_root="$(cd "$adapter_dir_abs/.." && pwd)"

log_file="${adapter_dir_abs}/review-feedback-log.md"

# ロックは git-tracked の .agent-os/ を汚染しないよう state/ 配下に置く
# （knowledge-append.sh のロック配置規律と同一の理由）。
lock_base_dir="${repo_root}/.iterate-team/state"
mkdir -p "$lock_base_dir"
lock_file="${lock_base_dir}/adapter-agent-os.lock"

ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# 呼び出しごとに新規生成する 8 桁 hex nonce（gen id）。knowledge-append.sh の
# gen_hex4 と同じ方式（/dev/urandom 優先、無ければ $RANDOM フォールバック）を
# 8 桁に拡張したもの。
gen_nonce() {
  if [[ -r /dev/urandom ]]; then
    head -c4 /dev/urandom | od -An -tx1 | tr -d ' \n'
  else
    printf '%04x%04x' "$((RANDOM % 65536))" "$((RANDOM % 65536))"
  fi
}
nonce="$(gen_nonce)"

context_display="${context:-(none)}"
session_display="${session:-(none)}"

MINIMAL_HEADER='<!--
Role: verbatim record of user corrections and review comments for this
project -- raw material for the Learning Layer (operations/adapter-policy.md
Section 6). Written by: team-adapter only. Read by team-adapter (repeat /
conflict detection) and team-profiler.
-->

# Review Feedback Log
'

# ---- 排他ロック配下での追記本体 ----
_locked_append() {
  if [[ ! -f "$log_file" ]]; then
    printf '%s\n' "$MINIMAL_HEADER" > "$log_file"
  fi
  {
    printf '\n'
    printf '<!-- adapter-feedback-entry:begin id=%s -->\n' "$nonce"
    printf 'Timestamp: %s\n' "$ts"
    printf 'Category: %s\n' "$category"
    printf 'Context: %s\n' "$context_display"
    printf 'Session: %s\n' "$session_display"
    printf '\n'
    printf 'Feedback (verbatim):\n'
    printf '%s\n' "$body"
    printf '\n'
    printf '<!-- adapter-feedback-entry:end id=%s -->\n' "$nonce"
  } >> "$log_file"
}

# 並列 append 安全化: flock（Linux）または mkdir（macOS ホスト）で排他ロックを取得後に追記する。
# review-feedback-log.md は直列 interviewer ループ等から並行して呼ばれうる adapter
# 書き込み経路であり、かつ adapter-recover.sh と同一ロック（adapter-agent-os.lock）を
# 共有するため、この節は runlog-append.sh のロック節と同一方式で実装する（片方だけ
# 実装して整合を崩さないこと）。
if command -v flock >/dev/null 2>&1; then
  exec 9>>"$lock_file"
  if ! flock -x -w 5 9; then
    echo "flock timeout: $log_file" >&2
    exit 1
  fi
  _locked_append
  flock -u 9
  exec 9>&-
else
  # flock 非搭載（macOS ホスト）: mkdir の原子性を利用したポータブルな排他制御。
  lock_dir="${lock_file}.d"
  waited=0
  until mkdir "$lock_dir" 2>/dev/null; do
    if [[ "$waited" -ge 50 ]]; then
      echo "lock timeout: $log_file" >&2
      exit 1
    fi
    sleep 0.1
    waited=$((waited + 1))
  done
  trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT
  _locked_append
  rmdir "$lock_dir" 2>/dev/null || true
  trap - EXIT
fi

echo "recorded feedback entry in $log_file (category: $category)"
