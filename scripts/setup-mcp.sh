#!/usr/bin/env bash
# 目的: 実行環境（host / dev container）を判定し、`.mcp.json` を適切なテンプレートへの
#       symlink として作成する。
# 判定: `CLAUDE_CONFIG_DIR=/home/node/.claude`（dev container の containerEnv で固定）
#       が設定されていれば dev container と判定し、`.mcp.devcontainer.json` を選ぶ。
#       それ以外（host / Web 版 Claude Code）は `.mcp.host.json` を選ぶ。
# 呼出元: 対象リポジトリのルートで手動実行（または対象リポ側のセットアップ手順から）。
#         配布プラグインとして対象リポ外（npm/global/marketplace）へ置かれるため、
#         対象リポは他スクリプトと同じく CLAUDE_PROJECT_DIR → CWD の git root → pwd で解決する
#         （プラグイン自身の配置先は基準にしない）。
# 前提: 対象リポに `.mcp.host.json` / `.mcp.devcontainer.json` テンプレートが存在すること
#       （permissions 設定と同様に対象リポ側が提供する。未検出時は下記で明示エラー）。
# exit code: 0 成功 / 1 テンプレート未検出 / 1 symlink 作成失敗

set -euo pipefail

REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$REPO_ROOT"

if [ "${CLAUDE_CONFIG_DIR:-}" = "/home/node/.claude" ]; then
  TARGET=".mcp.devcontainer.json"
  ENV_LABEL="dev container"
else
  TARGET=".mcp.host.json"
  ENV_LABEL="host"
fi

if [ ! -f "$TARGET" ]; then
  echo "[setup-mcp] ERROR: $TARGET が $REPO_ROOT に存在しません。" >&2
  exit 1
fi

# 既存の .mcp.json を点検
if [ -L .mcp.json ]; then
  CURRENT="$(readlink .mcp.json)"
  if [ "$CURRENT" = "$TARGET" ]; then
    echo "[setup-mcp] $ENV_LABEL: .mcp.json -> $TARGET（変更なし）"
    exit 0
  fi
  echo "[setup-mcp] $ENV_LABEL: .mcp.json の symlink target を $CURRENT から $TARGET に更新します。"
elif [ -e .mcp.json ]; then
  # 通常ファイルが残っている場合（旧仕様 / 手動編集）はバックアップ
  BACKUP=".mcp.json.bak.$(date +%Y%m%d%H%M%S)"
  echo "[setup-mcp] WARNING: .mcp.json が通常ファイルとして存在します。$BACKUP に退避します。" >&2
  mv .mcp.json "$BACKUP"
fi

ln -sf "$TARGET" .mcp.json
echo "[setup-mcp] $ENV_LABEL: .mcp.json -> $TARGET（symlink 作成済み）"
