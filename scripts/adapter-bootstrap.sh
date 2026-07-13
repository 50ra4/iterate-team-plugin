#!/usr/bin/env bash
# Agent OS プロジェクトアダプタ（`.agent-os/`）を対象リポジトリへ設置する wrapper。
#
# Usage:
#   <plugin_root>/scripts/adapter-bootstrap.sh [--target <dir>] [--adapter-only|--full]
#                                               [--force] [--reset-adapter]
#
# 既定は --adapter-only（iterate-team の中立設計における最小構成）:
#   vendor/agent-os/project-adapter/.agent-os/*.md の 8 ファイル（project-owned
#   な学習状態。既存ファイルは決して上書きしない）+ vendor/agent-os/GLOBAL_AGENTS.md
#   （OS-owned。--force 指定時のみ上書き）のみを <target>/.agent-os/ へ複製する。
#   .claude/skills・.claude/agents・root CLAUDE.md/AGENTS.md・.agent-os/skills/ は
#   本モードでは一切設置しない（中立設計維持。operations/adapter-policy.md §2・§9）。
#
# --full は vendor/agent-os/scripts/bootstrap-project.sh --target <dir> --for claude
#   （+ 透過した --force/--reset-adapter）へ完全委譲するエスケープハッチ。
#   fable 本体のフルインストール（.claude/skills 等も含む）が要る場合のみ使う。
#
# target 解決: 明示 --target を優先。省略時は CLAUDE_PROJECT_DIR、それも無ければ
#   カレントの git root（無ければ pwd）へフォールバックする（knowledge-append.sh /
#   session-start.sh と同一の repo-root 解決 idiom）。プラグイン自身のルート
#   ディレクトリを target に解決することは拒否する（アダプタを誤ってプラグイン
#   自身へ設置してしまう事故を防ぐ）。
#
# symlink 安全性（vendor/agent-os/scripts/bootstrap-project.sh のヘッダの原則を
#   --adapter-only の直接実装側でも踏襲する）: <target>/.agent-os、またはそこへ至る
#   既存のパス構成要素のいずれかが symlink である場合、あるいはその物理解決
#   （pwd -P）が <target> の外へ出る場合は、一切の書込み/mkdir/move を行わずに
#   明確なエラーで拒否する。planted symlink による target 外への書込みを防ぐ。
#
# 本スクリプトは git を一切実行しない（add/commit/push は呼び出し元コマンドの
#   責務。operations/adapter-policy.md §7）。ファイルコピーのみを行う。
#
# 仕様の正本: <plugin_root>/operations/adapter-policy.md（§2・§9）
#
# 実行環境前提: Linux / GNU coreutils + git（dev container・メイン checkout）。
# bash 3.2 / macOS 互換は目標外。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: adapter-bootstrap.sh [--target <dir>] [--adapter-only|--full] [--force] [--reset-adapter]

Install the Agent OS project adapter (.agent-os/) into a target repository.

Options:
  --target <dir>    Target repository root (must already exist). Defaults to
                     CLAUDE_PROJECT_DIR, then the current git repo's toplevel,
                     then the current directory.
  --adapter-only     (default) Install only the 8 project-owned .agent-os/*.md
                     scaffold files (never overwritten if already present) and
                     GLOBAL_AGENTS.md (OS-owned; overwritten only with --force).
                     Does not install .claude/skills, .claude/agents, root
                     CLAUDE.md/AGENTS.md, or .agent-os/skills/.
  --full             Delegate entirely to
                     vendor/agent-os/scripts/bootstrap-project.sh --for claude
                     (the full fable install; escape hatch, not the default).
  --force            Pass through to --full; for --adapter-only, allows
                     overwriting GLOBAL_AGENTS.md if it already exists (the 8
                     protected scaffold files are never overwritten by --force
                     in either mode -- use --reset-adapter to replace them).
  --reset-adapter    Back up existing protected .agent-os/*.md scaffold files
                     to .agent-os/backup-<UTC timestamp>/ before re-installing
                     fresh copies. Pass-through for --full.
  --help             Show this help text and exit.
EOF
}

# ---- 引数解析 ----
MODE="adapter-only"
TARGET=""
FORCE=0
RESET_ADAPTER=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --target)
      [[ $# -ge 2 ]] || { echo "ERROR: --target requires a value" >&2; exit 2; }
      TARGET="$2"
      shift 2
      ;;
    --adapter-only)
      MODE="adapter-only"
      shift
      ;;
    --full)
      MODE="full"
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --reset-adapter)
      RESET_ADAPTER=1
      shift
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

# ---- target 解決 ----
if [[ -z "$TARGET" ]]; then
  TARGET="${CLAUDE_PROJECT_DIR:-$(git -C . rev-parse --show-toplevel 2>/dev/null || pwd)}"
fi

if [[ ! -d "$TARGET" ]]; then
  echo "ERROR: target directory does not exist: $TARGET" >&2
  exit 1
fi

TARGET_ABS="$(cd "$TARGET" && pwd)"

# プラグイン自身のルートを target に解決することは拒否する（誤ってプラグイン
# 自身の .agent-os/ を書き換えてしまう事故を防ぐ）。
if [[ "$TARGET_ABS" == "$ROOT" ]]; then
  echo "ERROR: refusing to use the plugin's own root directory as --target: $TARGET_ABS" >&2
  exit 1
fi

# 物理（symlink 解決済み）パス。symlink された中間ディレクトリ経由で target 外へ
# 書込みが逃げていないかの containment チェックに用いる
# （vendor/agent-os/scripts/bootstrap-project.sh の TARGET_PHYS と同じ用途）。
TARGET_PHYS="$(cd "$TARGET_ABS" && pwd -P)"

# ---- --full: 完全委譲 ----
if [[ "$MODE" == "full" ]]; then
  args=(--target "$TARGET_ABS" --for claude)
  [[ "$FORCE" -eq 1 ]] && args+=(--force)
  [[ "$RESET_ADAPTER" -eq 1 ]] && args+=(--reset-adapter)
  exec bash "$ROOT/vendor/agent-os/scripts/bootstrap-project.sh" "${args[@]}"
fi

# ---- --adapter-only: 最小構成の直接実装 ----

AO_DIR="$TARGET_ABS/.agent-os"

# 8 つの project-owned アダプタ状態ファイル。project-adapter/.agent-os/*.md および
# vendor/agent-os/scripts/validate-agent-os.sh の ADAPTER_FILES と一致させる。
ADAPTER_STATE_FILES=(project-profile learned-rules failure-log review-feedback-log evals command-map architecture-map risk-map)

# ---- symlink 安全性: 起動時ゲート（defense layer 1） ----
# 一切の書込み/mkdir より前に、.agent-os 自体が symlink なら拒否する。これが無いと
# copy_file() や reset のバックアップ先解決がリンク越しに target 外へ書込みを
# リダイレクトしてしまう（vendor/agent-os/scripts/bootstrap-project.sh の同名ゲート
# と同じ原則）。
if [[ -L "$AO_DIR" ]]; then
  echo "ERROR: $AO_DIR is a symlink; refusing to operate on a target whose .agent-os is symlinked (remove the symlink manually if you want a regular directory installed there)" >&2
  exit 1
fi

# ---- symlink 安全性: パス構成要素ウォーク（defense layer 2） ----
# $1（TARGET_ABS 自身かその配下のパス）を、TARGET_ABS から 1 構成要素ずつ辿って
# 作成する。既存の構成要素のいずれかが symlink であれば即座に拒否する。
# `mkdir -p` は全構成要素を一括で辿り作成してしまうため、途中の symlink を検知する
# 前に target 外へディレクトリを作ってしまいうる。1 要素ずつ検査することで、
# 拒否時に target 外へは何も残さないことを保証する
# （vendor/agent-os/scripts/bootstrap-project.sh の safe_mkdir_within_target() と
# 同一のロジック）。
SAFE_MKDIR_FAIL_PATH=""
safe_mkdir_within_target() {
  local dir="$1"
  SAFE_MKDIR_FAIL_PATH=""

  local rel="${dir#"$TARGET_ABS"}"
  rel="${rel#/}"

  local cur="$TARGET_ABS"
  if [[ -n "$rel" ]]; then
    local part
    local IFS=/
    for part in $rel; do
      [[ -z "$part" ]] && continue
      cur="$cur/$part"
      if [[ -L "$cur" ]]; then
        SAFE_MKDIR_FAIL_PATH="$cur"
        return 1
      fi
      if [[ ! -e "$cur" ]]; then
        mkdir "$cur" || { SAFE_MKDIR_FAIL_PATH="$cur"; return 1; }
      fi
    done
  fi

  # 仕上げの二重チェック: 構成要素ウォーク後も、最終的な物理パスが target 自身か
  # その配下であることを確認する。
  local phys
  phys="$(cd "$dir" && pwd -P)" || { SAFE_MKDIR_FAIL_PATH="$dir"; return 1; }
  if [[ "$phys" != "$TARGET_PHYS" && "$phys" != "$TARGET_PHYS"/* ]]; then
    SAFE_MKDIR_FAIL_PATH="$phys"
    return 1
  fi
  return 0
}

if ! safe_mkdir_within_target "$AO_DIR"; then
  echo "ERROR: refusing to create/use $AO_DIR safely (blocked at: $SAFE_MKDIR_FAIL_PATH); a symlinked path component would redirect writes outside the target; nothing written" >&2
  exit 1
fi

# ---- 集計 ----
INSTALLED_COUNT=0
SKIPPED_COUNT=0
PROTECTED_COUNT=0
BLOCKED_COUNT=0
BACKED_UP_COUNT=0
INSTALLED_LIST=()
SKIPPED_LIST=()
PROTECTED_LIST=()
BLOCKED_LIST=()
BACKED_UP_LIST=()
BACKUP_DIR=""

# 1 ファイルを複製する。protected=1 の場合、既存ファイルは（--force の有無に
# 関わらず）決して上書きせず PROTECTED: 行を出して skip する（project-owned な
# 学習状態を保護する。置き換えるには --reset-adapter を使う）。protected=0
# （GLOBAL_AGENTS.md）の場合は、既存かつ --force 未指定なら skip、--force
# 指定時のみ上書きする。
#
# symlink 安全性: dest 自体が symlink なら書込みを拒否する（cp がリンク先へ
# 追従して target 外を書き換えてしまうことを防ぐ）。dest の親ディレクトリの
# 構成要素に symlink がある場合も safe_mkdir_within_target() が拒否する。
copy_file() {
  local src="$1"
  local dest="$2"
  local protected="${3:-0}"

  if [[ ! -f "$src" ]]; then
    echo "WARN: source file missing, skipping: $src" >&2
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    SKIPPED_LIST+=("$dest (source missing)")
    return
  fi

  if [[ -L "$dest" ]]; then
    echo "BLOCKED (symlink): destination is a symlink; refusing to write through or replace it: $dest"
    BLOCKED_COUNT=$((BLOCKED_COUNT + 1))
    BLOCKED_LIST+=("$dest (destination is a symlink)")
    return
  fi

  if [[ -e "$dest" ]]; then
    if [[ "$protected" -eq 1 ]]; then
      echo "PROTECTED: $dest (project-owned state, not overwritten; use --reset-adapter to replace it)"
      PROTECTED_COUNT=$((PROTECTED_COUNT + 1))
      PROTECTED_LIST+=("$dest")
      return
    fi
    if [[ "$FORCE" -ne 1 ]]; then
      echo "SKIPPED: already exists (use --force to overwrite): $dest"
      SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
      SKIPPED_LIST+=("$dest")
      return
    fi
    # protected=0 かつ --force: 下に落ちて上書きする。
  fi

  if ! safe_mkdir_within_target "$(dirname "$dest")"; then
    echo "BLOCKED (symlink): a symlinked parent directory redirected this write outside the target project: $dest (blocked at: $SAFE_MKDIR_FAIL_PATH)"
    BLOCKED_COUNT=$((BLOCKED_COUNT + 1))
    BLOCKED_LIST+=("$dest (symlinked parent directory escapes target)")
    return
  fi

  cp "$src" "$dest"
  INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
  INSTALLED_LIST+=("$dest")
}

# --reset-adapter: 既存の 8 保護ファイルを .agent-os/backup-<UTC timestamp>/ へ
# 退避してから、この後の copy_file 呼び出しで新規スキャフォールドを設置させる。
# ここでの UTC タイムスタンプは date -u +%Y%m%dT%H%M%S で採番する（JS ワークフロー
# と違い、シェルスクリプトでの Date.now() 相当は問題ない）。
reset_adapter_backup() {
  local ts backup_dir candidate suffix f src any
  ts="$(date -u +%Y%m%dT%H%M%S)"
  backup_dir="$AO_DIR/backup-$ts"

  # defense layer 2: バックアップ実行直前に .agent-os 自体を再検証する（起動時
  # ゲートを通過した後に安全でない状態へ変わっていないことを確認する）。
  if [[ -e "$AO_DIR" ]]; then
    if [[ -L "$AO_DIR" ]]; then
      echo "ERROR: refusing --reset-adapter: $AO_DIR is a symlink; nothing moved" >&2
      exit 1
    fi
    local ao_phys
    ao_phys="$(cd "$AO_DIR" && pwd -P)"
    if [[ "$ao_phys" != "$TARGET_PHYS/.agent-os" ]]; then
      echo "ERROR: refusing --reset-adapter: $AO_DIR resolves to $ao_phys, outside $TARGET_PHYS/.agent-os; nothing moved" >&2
      exit 1
    fi
  fi

  # バックアップ先候補が symlink でなく、かつ未使用であることを確認する
  # （既存の非 symlink ディレクトリへは mv しない。同名衝突を避けるため -2, -3 ...
  # を付番する）。
  candidate="$backup_dir"
  suffix=1
  while :; do
    if [[ -L "$candidate" ]]; then
      echo "ERROR: refusing --reset-adapter: $candidate is a symlink; nothing moved" >&2
      exit 1
    fi
    if [[ -e "$candidate" ]]; then
      suffix=$((suffix + 1))
      candidate="${backup_dir}-${suffix}"
      continue
    fi
    break
  done
  backup_dir="$candidate"

  if ! safe_mkdir_within_target "$backup_dir"; then
    echo "ERROR: refusing --reset-adapter: could not safely create backup directory $backup_dir (blocked at: $SAFE_MKDIR_FAIL_PATH); nothing moved" >&2
    exit 1
  fi

  any=0
  for f in "${ADAPTER_STATE_FILES[@]}"; do
    src="$AO_DIR/$f.md"
    if [[ -f "$src" || -L "$src" ]]; then
      mv "$src" "$backup_dir/$f.md"
      any=1
      BACKED_UP_COUNT=$((BACKED_UP_COUNT + 1))
      BACKED_UP_LIST+=("$backup_dir/$f.md (was .agent-os/$f.md)")
    fi
  done

  if [[ "$any" -eq 1 ]]; then
    BACKUP_DIR="$backup_dir"
    echo "INFO: reset-adapter: backed up existing protected file(s) to $backup_dir"
  else
    echo "INFO: reset-adapter: no existing protected files found, nothing to back up"
  fi
}

if [[ "$RESET_ADAPTER" -eq 1 ]]; then
  reset_adapter_backup
fi

# ---- 1. 8 つの project-owned スキャフォールドファイル ----
for f in "${ADAPTER_STATE_FILES[@]}"; do
  copy_file "$ROOT/vendor/agent-os/project-adapter/.agent-os/$f.md" "$AO_DIR/$f.md" 1
done

# ---- 2. GLOBAL_AGENTS.md（OS-owned） ----
copy_file "$ROOT/vendor/agent-os/GLOBAL_AGENTS.md" "$AO_DIR/GLOBAL_AGENTS.md" 0

# ---- Summary ----
echo
echo "===== adapter-bootstrap (--adapter-only) summary ====="
echo "Target:      $TARGET_ABS"
echo "Adapter dir: $AO_DIR"
echo "Installed:   $INSTALLED_COUNT file(s)"
for f in "${INSTALLED_LIST[@]:-}"; do
  [[ -n "$f" ]] && echo "  + $f"
done
echo "Skipped:     $SKIPPED_COUNT file(s)"
for f in "${SKIPPED_LIST[@]:-}"; do
  [[ -n "$f" ]] && echo "  - $f"
done
echo "Protected:   $PROTECTED_COUNT file(s) (project-owned state, preserved)"
for f in "${PROTECTED_LIST[@]:-}"; do
  [[ -n "$f" ]] && echo "  ! $f"
done
echo "Blocked:     $BLOCKED_COUNT file(s) (refused: symlinked destination or parent)"
for f in "${BLOCKED_LIST[@]:-}"; do
  [[ -n "$f" ]] && echo "  x $f"
done
if [[ "$RESET_ADAPTER" -eq 1 ]]; then
  echo "Backed up:   $BACKED_UP_COUNT file(s)$( [[ -n "$BACKUP_DIR" ]] && echo " -> $BACKUP_DIR" )"
  for f in "${BACKED_UP_LIST[@]:-}"; do
    [[ -n "$f" ]] && echo "  ~ $f"
  done
fi
echo "========================================================"

if [[ "$BLOCKED_COUNT" -gt 0 ]]; then
  exit 1
fi

exit 0
