#!/usr/bin/env bash
# state-prune.sh — .iterate-team/state/ のセッション prune スクリプト
#
# 実行環境前提: Linux / GNU coreutils（dev container・メイン checkout）。
# bash 3.2 / macOS 互換は目標外。
#
# prune 対象は --state-root（未指定時は同リポジトリルート配下の .iterate-team/state）で解決する。
#
# symlink・パス逸脱は fail-closed（破壊しない方向）:
#   (a) 走査中に symlink を検出した場合は辿らず、削除対象から除外して残す。
#   (b) 削除候補の解決後絶対パス（symlink 解決後）が state root 配下から逸脱する場合は
#       削除対象にしない。いずれも当該エントリのみスキップして処理は継続する。
#
# Usage:
#   state-prune.sh [--state-root <path>] [--apply]
#
# Options:
#   --state-root <path>   prune 対象の state ルートパス（未指定時は git toplevel/.iterate-team/state）
#   --apply               実削除を行う（未指定時は dry-run）
#
# Exit code:
#   0 = 正常終了（dry-run 完了 / --apply 完了）
#   1 = 異常終了（gate 欠落 / worktree で --apply 試行 / 引数不正 等）

set -euo pipefail

# ---- 保持基準定数（state-retention-policy.md 確定値） ----
readonly RETENTION_DAYS=30        # ハーネスセッション保持日数
readonly SESSIONS_KEEP_COUNT=20   # sessions/<uuid>/ 最新保持件数
readonly GRACE_PERIOD_DAYS=30     # sessions/<uuid>/ grace period（日数）

# ---- 引数パース ----
STATE_ROOT_ARG=""
APPLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --state-root)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: --state-root には引数が必要です" >&2
        exit 1
      fi
      STATE_ROOT_ARG="$2"
      shift 2
      ;;
    --apply)
      APPLY=true
      shift
      ;;
    *)
      echo "ERROR: 不明な引数: $1" >&2
      echo "Usage: state-prune.sh [--state-root <path>] [--apply]" >&2
      exit 1
      ;;
  esac
done

# ---- --apply 時のメイン checkout 判定 ----
# git rev-parse --git-common-dir と --git-dir が一致する場合のみメイン checkout
# linked worktree では --git-dir が .git/worktrees/<name> を指し不一致になる。
# linked worktree からの --apply は明確な拒否メッセージを出して遮断する。
if [[ "$APPLY" == true ]]; then
  # bare リポジトリの場合も拒否
  IS_BARE="$(git rev-parse --is-bare-repository 2>/dev/null || echo "false")"
  if [[ "$IS_BARE" == "true" ]]; then
    echo "ERROR: bare リポジトリでは --apply を実行できません。" >&2
    exit 1
  fi

  GIT_COMMON_DIR="$(git rev-parse --git-common-dir 2>/dev/null || echo "")"
  GIT_DIR="$(git rev-parse --git-dir 2>/dev/null || echo "")"

  # git rev-parse は CWD 基準の相対パスを返すことがある（例: repo root のサブディレクトリから
  # 実行すると --git-dir が ../../.git、--git-common-dir が絶対パスになり形式がずれる）。
  # 形式差のまま比較するとメイン checkout のサブディレクトリを linked worktree と誤判定し、
  # ドキュメント上は許可される「メイン checkout 上の --apply」が失敗する。比較前に絶対パスへ正規化する。
  GIT_COMMON_DIR="$(realpath -m -- "$GIT_COMMON_DIR" 2>/dev/null || echo "$GIT_COMMON_DIR")"
  GIT_DIR="$(realpath -m -- "$GIT_DIR" 2>/dev/null || echo "$GIT_DIR")"

  if [[ "$GIT_COMMON_DIR" != "$GIT_DIR" ]]; then
    echo "ERROR: --apply はメイン checkout 上でのみ実行可能です。" >&2
    echo "  現在の実行位置が git worktree（linked worktree）のため、実削除を拒否しました。" >&2
    echo "  メイン checkout に cd してから再実行してください。" >&2
    exit 1
  fi
fi

# ---- リポジトリルート解決 ----
REPO_ROOT="$(git rev-parse --show-toplevel)"

# ---- state root 解決 ----
if [[ -n "$STATE_ROOT_ARG" ]]; then
  # --state-root 指定時は realpath -e で正規化（存在必須）
  if ! STATE_ROOT_REAL="$(realpath -e -- "$STATE_ROOT_ARG" 2>/dev/null)"; then
    echo "ERROR: --state-root で指定されたパスが存在しません: $STATE_ROOT_ARG" >&2
    exit 1
  fi
else
  # 未指定時はリポジトリルート配下の .iterate-team/state
  DEFAULT_STATE="$REPO_ROOT/.iterate-team/state"
  if ! STATE_ROOT_REAL="$(realpath -e -- "$DEFAULT_STATE" 2>/dev/null)"; then
    echo "ERROR: デフォルト state root が存在しません: $DEFAULT_STATE" >&2
    exit 1
  fi
fi

# ---- state root マーカー検証（破壊的削除の安全装置） ----
# state ディレクトリ直下には必ず escalation-template.md（ハーネス全セッション共通
# テンプレート、state-retention-policy.md「保護対象」参照）が存在する。これをマーカーとし、
# 直下に存在しないディレクトリは state root と見なさず fail-closed で拒否する。
# 存在確認だけでは `--state-root .`（gate ファイルがあるメイン checkout）やパスの
# 打ち間違いを通してしまい、任意ディレクトリ直下の 30 日超エントリを誤って rm -rf し得る。
STATE_MARKER="$STATE_ROOT_REAL/escalation-template.md"
if [[ ! -f "$STATE_MARKER" ]]; then
  echo "ERROR: state root が .iterate-team/state ではありません（マーカー欠落）: $STATE_ROOT_REAL" >&2
  echo "  state 直下マーカー escalation-template.md が存在しません。" >&2
  echo "  誤削除防止のため、escalation-template.md を持つ state ディレクトリのみ処理対象とします。" >&2
  exit 1
fi

# ---- --apply 時の state root 固定（checkout 配下の .iterate-team/state に限定） ----
# マーカー検証だけでは、同名マーカー（escalation-template.md）を置いた別ディレクトリを
# 通常 checkout から --state-root に渡すと実削除が通ってしまう。ポリシー「メイン checkout
# 上の .iterate-team/state のみ実削除」を担保するため、--apply 時は解決済み state root が
# 現在の checkout の .iterate-team/state と一致することを必須化する。dry-run は実削除を
# 伴わないため任意 state root を許容する（テスト・任意 state の点検用途）。
if [[ "$APPLY" == true ]]; then
  CANONICAL_STATE="$(realpath -m -- "$REPO_ROOT/.iterate-team/state" 2>/dev/null || echo "$REPO_ROOT/.iterate-team/state")"
  if [[ "$STATE_ROOT_REAL" != "$CANONICAL_STATE" ]]; then
    echo "ERROR: --apply の state root はメイン checkout の .iterate-team/state に限定されます。" >&2
    echo "  指定された state root: $STATE_ROOT_REAL" >&2
    echo "  許可される state root: $CANONICAL_STATE" >&2
    echo "  dry-run（--apply なし）であれば任意の --state-root を点検できます。" >&2
    exit 1
  fi
fi

# ---- 削除候補集合の算出（単一関数・dry-run と --apply で共通） ----
# 戻り値: 削除候補の絶対パスを NUL 区切りで CANDIDATES 配列に格納
CANDIDATES=()
TOTAL_SIZE=0
NOW_EPOCH="$(date +%s)"

# ---- 共通ヘルパー ----

# パス収容確認: 解決済みパスが state root 配下かどうかを判定する。
# 末尾スラッシュ付きプレフィックス比較で兄弟ディレクトリ（/x/state-backup 等）の誤マッチを防ぐ。
is_under_state_root() {
  local resolved="$1" root="$2"
  [[ "$resolved" == "$root"/* || "$resolved" == "$root" ]]
}

# 削除候補追加: CANDIDATES に追加して TOTAL_SIZE を加算する。
add_candidate() {
  local path="$1"
  CANDIDATES+=("$path")
  local dir_size
  dir_size="$(du -sb -- "$path" 2>/dev/null | cut -f1 || echo 0)"
  TOTAL_SIZE=$(( TOTAL_SIZE + dir_size ))
}

# ---- ハーネスセッションディレクトリの prune 判定 ----
# state root 直下のエントリを列挙（symlink は辿らず除外）
compute_session_candidates() {
  local state_root="$1"
  local now_epoch="$NOW_EPOCH"
  local retention_secs=$(( RETENTION_DAYS * 86400 ))

  while IFS= read -r -d '' entry; do
    local basename_entry
    basename_entry="$(basename -- "$entry")"

    # escalation-template.md は除外
    if [[ "$basename_entry" == "escalation-template.md" ]]; then
      continue
    fi

    # sessions ディレクトリ自体は ハーネスセッション直下扱いではない（後で処理）
    if [[ "$basename_entry" == "sessions" ]]; then
      continue
    fi

    # symlink は辿らず、削除対象から除外して残す（fail-closed）
    if [[ -L "$entry" ]]; then
      continue
    fi

    # ディレクトリでないエントリ（ファイル等）はスキップ
    if [[ ! -d "$entry" ]]; then
      continue
    fi

    # 解決後実パスが state root 配下であることを確認（パス逸脱チェック）
    local resolved
    if ! resolved="$(realpath -- "$entry" 2>/dev/null)"; then
      # realpath 失敗（symlink ループ等）は fail-closed でスキップ
      continue
    fi
    if ! is_under_state_root "$resolved" "$state_root"; then
      continue
    fi

    # 保持期間判定: runlog.jsonl の mtime、欠落時は dir mtime フォールバック
    local mtime_epoch
    local runlog="$entry/runlog.jsonl"
    if [[ -f "$runlog" ]]; then
      mtime_epoch="$(stat -c %Y "$runlog" 2>/dev/null || stat -c %Y "$entry")"
    else
      mtime_epoch="$(stat -c %Y "$entry" 2>/dev/null || echo 0)"
    fi

    local age_secs=$(( now_epoch - mtime_epoch ))
    if [[ $age_secs -gt $retention_secs ]]; then
      add_candidate "$resolved"
    fi

  done < <(find "$state_root" -maxdepth 1 -mindepth 1 -print0 2>/dev/null)
}

# ---- sessions/<uuid>/ 配下エントリの prune 判定 ----
compute_sessions_uuid_candidates() {
  local state_root="$1"
  local sessions_base="$state_root/sessions"

  if [[ ! -d "$sessions_base" ]]; then
    return 0
  fi

  local now_epoch="$NOW_EPOCH"
  local grace_secs=$(( GRACE_PERIOD_DAYS * 86400 ))

  # sessions/ 直下の各 uuid ディレクトリを列挙
  while IFS= read -r -d '' uuid_dir; do
    # symlink は除外
    if [[ -L "$uuid_dir" ]]; then
      continue
    fi
    if [[ ! -d "$uuid_dir" ]]; then
      continue
    fi

    # uuid_dir 配下のエントリを集めて created_at で降順ソート
    # まず全エントリとそのキー値（epoch）を収集
    local entries=()
    local entry_epochs=()

    while IFS= read -r -d '' entry; do
      # symlink は除外
      if [[ -L "$entry" ]]; then
        continue
      fi
      if [[ ! -d "$entry" ]]; then
        continue
      fi

      # 解決後実パスが state root 配下であることを確認
      local resolved
      if ! resolved="$(realpath -- "$entry" 2>/dev/null)"; then
        continue
      fi
      if ! is_under_state_root "$resolved" "$state_root"; then
        continue
      fi

      # created_at の取得（jq でパース、失敗時は mtime フォールバック）
      local init_json="$entry/init.json"
      local key_epoch
      local created_at=""
      if [[ -f "$init_json" ]]; then
        created_at="$(jq -r '.created_at // empty' "$init_json" 2>/dev/null || echo "")"
      fi
      if [[ -n "$created_at" ]]; then
        # ISO8601 → epoch（GNU date -d を使用。jq fromdateiso8601 は JSON 文字列として渡す必要があり
        # プレーンな ISO 日付文字列では常にエラーになるため GNU date -d に変更）
        key_epoch="$(date -d "$created_at" +%s 2>/dev/null || echo "")"
        if [[ -z "$key_epoch" ]]; then
          # jq パース失敗時は mtime フォールバック（fail-closed: 保護側）
          key_epoch="$(stat -c %Y "$entry" 2>/dev/null || echo "$now_epoch")"
        fi
      else
        # init.json なし または created_at 欠落: mtime フォールバック
        key_epoch="$(stat -c %Y "$entry" 2>/dev/null || echo "$now_epoch")"
      fi

      entries+=("$resolved")
      entry_epochs+=("$key_epoch")
    done < <(find "$uuid_dir" -maxdepth 1 -mindepth 1 -print0 2>/dev/null)

    local total_entries=${#entries[@]}
    if [[ $total_entries -eq 0 ]]; then
      continue
    fi

    # created_at 降順でソート（最新が先頭）
    # バブルソート（件数は最大でも数十件程度なので許容）
    local indices=()
    for (( i=0; i<total_entries; i++ )); do
      indices+=("$i")
    done

    # 降順バブルソート
    local n=$total_entries
    for (( i=0; i<n-1; i++ )); do
      for (( j=0; j<n-i-1; j++ )); do
        local idx_a="${indices[$j]}"
        local idx_b="${indices[$((j+1))]}"
        if [[ "${entry_epochs[$idx_a]}" -lt "${entry_epochs[$idx_b]}" ]]; then
          indices[$j]="$idx_b"
          indices[$((j+1))]="$idx_a"
        fi
      done
    done

    # 各エントリが削除対象かどうか判定
    local rank=0
    for idx in "${indices[@]}"; do
      rank=$(( rank + 1 ))
      local entry_path="${entries[$idx]}"
      local key_epoch_val="${entry_epochs[$idx]}"

      # (a) 最新 N 件以内: 件数保護
      if [[ $rank -le $SESSIONS_KEEP_COUNT ]]; then
        continue
      fi

      # (b) grace period 以内: 時間保護
      local age_secs=$(( now_epoch - key_epoch_val ))
      if [[ $age_secs -le $grace_secs ]]; then
        continue
      fi

      # (a)(b) どちらにも該当しない場合のみ削除対象
      add_candidate "$entry_path"
    done

  done < <(find "$sessions_base" -maxdepth 1 -mindepth 1 -print0 2>/dev/null)
}

# 削除候補を算出
compute_session_candidates "$STATE_ROOT_REAL"
compute_sessions_uuid_candidates "$STATE_ROOT_REAL"

# ---- dry-run または --apply の実行 ----
if [[ "$APPLY" == false ]]; then
  # dry-run: 削除対象を列挙するだけ（実削除しない）
  echo "=== state-prune.sh dry-run ==="
  echo "state root: $STATE_ROOT_REAL"
  echo ""

  if [[ ${#CANDIDATES[@]} -eq 0 ]]; then
    echo "削除対象なし（保持基準内のエントリのみ）"
  else
    echo "削除対象一覧:"
    for candidate in "${CANDIDATES[@]}"; do
      echo "  - $candidate"
    done
    echo ""
    echo "削除対象ディレクトリ件数: ${#CANDIDATES[@]} directories"
    echo "合計サイズ: ${TOTAL_SIZE} bytes"
  fi
else
  # --apply: 実削除
  echo "=== state-prune.sh --apply ==="
  echo "state root: $STATE_ROOT_REAL"
  echo ""

  if [[ ${#CANDIDATES[@]} -eq 0 ]]; then
    echo "削除対象なし（保持基準内のエントリのみ）"
  else
    echo "削除対象一覧:"
    for candidate in "${CANDIDATES[@]}"; do
      echo "  - $candidate"
    done
    echo ""
    echo "実削除を開始します..."

    for candidate in "${CANDIDATES[@]}"; do
      # 削除直前に絶対パスであることを再アサート（引数インジェクション防止）
      if [[ "$candidate" != /* ]]; then
        echo "  SKIP（絶対パスでない）: $candidate" >&2
        continue
      fi
      # 削除直前に state root 配下であることを再アサート
      if [[ "$candidate" != "$STATE_ROOT_REAL"/* && "$candidate" != "$STATE_ROOT_REAL" ]]; then
        echo "  SKIP（配下外パス）: $candidate" >&2
        continue
      fi
      echo "  削除: $candidate"
      rm -rf -- "$candidate"
    done

    echo ""
    echo "削除完了: ${#CANDIDATES[@]} directories, ${TOTAL_SIZE} bytes"
  fi
fi

exit 0
