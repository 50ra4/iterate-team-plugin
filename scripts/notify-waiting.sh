#!/usr/bin/env bash
# Claude Code Notification hook: ユーザーの回答待ち（permission / idle / AskUserQuestion）に
# なったタイミングで通知音を鳴らす。
#
# 仕様:
#   - devcontainer 環境（CLAUDE_CONFIG_DIR=/home/node/.claude）でのみ鳴らす。
#     host / Web 版では何もせず exit 0（settings.json を共有しても無音）。
#   - 音源 ${CLAUDE_PLUGIN_ROOT}/assets/notify.wav を paplay → aplay → ffplay の順で再生試行。
#     いずれも不可 / WAV 不在ならターミナルベル（BEL）にフォールバック。
#   - hook をブロックしないよう常に exit 0。stdin の hook JSON は読み捨てる。
#
# 環境変数:
#   CLAUDE_CONFIG_DIR   dev container 判定マーカー（session-start.sh と同一基準）
#   CLAUDE_PROJECT_DIR  プロジェクトルート（Claude Code が hook 実行時に注入）
set -uo pipefail

# stdin の hook payload は使わないが、パイプ詰まり回避のため読み捨てる。
cat >/dev/null 2>&1 || true

# dev container 以外は無音で終了。
if [ "${CLAUDE_CONFIG_DIR:-}" != "/home/node/.claude" ]; then
  exit 0
fi

# 音源はプラグイン資産。hook 実行 env には ${CLAUDE_PLUGIN_ROOT} が注入される。
# 未設定 (プラグイン外で直接呼んだ等) の場合は本スクリプトの親 (プラグインルート) で代替。
plugin_root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
wav="${plugin_root}/assets/notify.wav"

play_wav() {
  [ -f "$wav" ] || return 1
  # 最初に見つかった再生コマンドを使う。再生がハングしても回答待ち通知を
  # 遅延させないよう、timeout があれば再生を 5 秒で打ち切る。
  local player
  for player in paplay aplay ffplay; do
    command -v "$player" >/dev/null 2>&1 || continue
    case "$player" in
      paplay) set -- paplay "$wav" ;;
      aplay) set -- aplay -q "$wav" ;;
      ffplay) set -- ffplay -nodisp -autoexit -loglevel quiet "$wav" ;;
    esac
    if command -v timeout >/dev/null 2>&1; then
      timeout 5 "$@" >/dev/null 2>&1 && return 0
    else
      "$@" >/dev/null 2>&1 && return 0
    fi
  done
  return 1
}

# 音声ファイル再生に失敗 / WAV 不在ならターミナルベルにフォールバック。
# 制御端末があれば /dev/tty へ、無ければ stdout へ BEL を出力する。
# サブシェルで先に stderr を捨て、/dev/tty オープン失敗時のエラーを抑止する。
if ! play_wav; then
  ( exec 2>/dev/null; printf '\a' >/dev/tty ) || printf '\a'
fi

exit 0
