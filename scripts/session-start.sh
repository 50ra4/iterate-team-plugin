#!/usr/bin/env bash
# Claude Code SessionStart hook for the iterate-team ハーネス。
#
# 役割:
#   - 各 Claude Code セッション開始時に 1 回実行される
#   - Claude Code から stdin で渡される hook 入力 JSON (`session_id` / `model` 等) を解釈
#   - 対象リポジトリ直下に runtime 状態ディレクトリ `.iterate-team/{state,tasks,changes}` を seed する
#   - 実行環境判定 (host / dev container) / MCP プロファイル選択結果 / モデル情報 / plugin_root を
#     `.iterate-team/state/sessions/<claude-session-id>/init.json` に永続化
#   - stdout に `hookSpecificOutput.additionalContext` を出力し、Orchestrator に
#     init.json の絶対パスを `<session-init ... />` タグ経由で伝達する
#
# Why: 旧構成では `/iterate-team` の step 0 で同一の環境判定を毎回実行しており、agent
# 再起動のたびに同じ Bash 呼び出しが繰り返されていた。SessionStart hook 化と
# session-id スコープのキャッシュにより、判定を 1 回に圧縮する。
# 固定パス (e.g. `.iterate-team/state/session-init.json`) を採用しない理由は、同 checkout で
# 複数セッションが並走する場合に後発セッションが先行セッションの判定を上書きしないため。
#
# plugin_root: 本 hook は Claude Code プラグインとして実行される際 ${CLAUDE_PLUGIN_ROOT}
# (プラグイン資産ルート) を env で受け取る。agent/command 本文では ${CLAUDE_PLUGIN_ROOT} の
# 展開が保証されないため、ここで init.json に plugin_root として永続化し、Orchestrator が
# step 0.0 で読み取って各 subagent プロンプトへ絶対パスを注入する。
#
# 仕様詳細: <plugin_root>/operations/session-start-hook.md
#
# 失敗モード:
#   - jq / mkdir 等の致命エラー時は exit 1。Claude Code は SessionStart の非ゼロ exit を
#     セッションブロックに使わない仕様だが、stdout に additionalContext を出力しないため、
#     Orchestrator step 0 が `<session-init>` 不在を検出して abort する
#   - hook 入力 JSON に session_id が欠落していた場合も同様 (init.json を書かず警告のみ stdout)

set -uo pipefail

INPUT="$(cat || true)"

# project_dir 解決 (Claude Code が CLAUDE_PROJECT_DIR を注入する想定。未注入時は cwd)
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

emit_context_only() {
  # init.json を書かずに warning だけ出して終了 (Orchestrator は session-init 不在で abort)
  local msg="$1"
  jq -n --arg msg "$msg" '{
    hookSpecificOutput: {
      hookEventName: "SessionStart",
      additionalContext: $msg
    }
  }'
}

# 対象リポジトリの runtime state (.iterate-team/state/) を git の無視対象へ登録する。
#
# Why: 本 hook は dirty check (`/iterate-team` step 0.1 の `git status --porcelain`) より前に
# .iterate-team/state/ 配下へ escalation-template.md と sessions/<id>/init.json を seed する。
# `.iterate-team/state/` をまだ無視していないクリーンな初回 checkout では、これらが untracked
# として現れ、step 0 が `dirty_worktree` で abort してハーネスが起動不能になる。tracked な
# .gitignore を書き換えると差分自体が dirty になるため、ローカル限定で git status に現れない
# .git/info/exclude へ追記する。既に無視済み (.gitignore / グローバル設定 / 既存 exclude /
# 親ディレクトリ ignore のいずれか) なら no-op。チーム共有したい場合は別途 .gitignore に
# `.iterate-team/state/` を追加すればよい (本登録と重複しても害はない)。
ensure_state_ignored() {
  local project_dir="$1"
  command -v git >/dev/null 2>&1 || return 0
  git -C "$project_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

  # 既に無視対象なら追記しない。seed 前でも check-ignore はパターン評価できるため判定可
  # (存在しないパスでも親 ignore や明示パターンに照らして判定される)。代表ファイルで確認する。
  if git -C "$project_dir" check-ignore -q .iterate-team/state/escalation-template.md 2>/dev/null; then
    return 0
  fi

  # exclude は common git dir 基準で解決する (linked worktree でも共有 exclude を指す)。
  # --git-common-dir は main worktree では相対 (.git) を返すことがあるため絶対化する。
  local git_dir
  git_dir="$(git -C "$project_dir" rev-parse --git-common-dir 2>/dev/null || true)"
  [ -n "$git_dir" ] || return 0
  case "$git_dir" in
    /*) : ;;
    *) git_dir="$project_dir/$git_dir" ;;
  esac
  local exclude_file="$git_dir/info/exclude"

  # exclude パターンは toplevel 相対。project_dir がサブディレクトリでも正しく anchor させるため
  # show-prefix (toplevel からの相対パス, 末尾 /) を前置する。toplevel 直下なら空文字列。
  local prefix
  prefix="$(git -C "$project_dir" rev-parse --show-prefix 2>/dev/null || true)"
  local pattern="/${prefix}.iterate-team/state/"

  # 冪等: 既に同一行があれば追記しない。
  if [ -f "$exclude_file" ] && grep -qxF "$pattern" "$exclude_file" 2>/dev/null; then
    return 0
  fi

  mkdir -p "$git_dir/info" 2>/dev/null || return 0
  # 末尾改行の無い既存 exclude に連結して直前パターンを壊さないよう、必要なら改行を先付けする。
  if [ -s "$exclude_file" ] && [ -n "$(tail -c1 "$exclude_file" 2>/dev/null)" ]; then
    printf '\n' >> "$exclude_file" 2>/dev/null || return 0
  fi
  printf '# iterate-team SessionStart hook が自動追記 (runtime state)\n%s\n' "$pattern" \
    >> "$exclude_file" 2>/dev/null || return 0
}

if ! command -v jq >/dev/null 2>&1; then
  echo '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"[session-start-hook] jq が見つかりません。/iterate-* の初期化は失敗します。"}}'
  exit 1
fi

SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
if [ -z "$SESSION_ID" ]; then
  emit_context_only "[session-start-hook] hook 入力 JSON に session_id が欠落しています。/iterate-* は初期化未完了として abort してください。"
  exit 1
fi

# session_id 形式バリデーション (path traversal 防止: 英数 _ - .)
case "$SESSION_ID" in
  *[!A-Za-z0-9._-]* | "" )
    emit_context_only "[session-start-hook] session_id 形式が不正です: $SESSION_ID"
    exit 1
    ;;
esac

# runtime state を seed する前に .iterate-team/state/ を git の無視対象へ登録する
# (seed が untracked 差分として step 0.1 dirty check を誤発火させるのを防ぐ)。
ensure_state_ignored "$PROJECT_DIR"

# runtime 状態ルートを seed (対象リポジトリ直下 .iterate-team/{state,tasks,changes})
RUNTIME_ROOT="$PROJECT_DIR/.iterate-team"
STATE_ROOT="$RUNTIME_ROOT/state"
mkdir -p "$STATE_ROOT" "$RUNTIME_ROOT/tasks" "$RUNTIME_ROOT/changes"

# state root マーカー (state-prune.sh の破壊的削除ガードが必須とする保持対象ファイル)。
# 既存があれば温存し、無ければ空マーカーを seed する。
STATE_MARKER="$STATE_ROOT/escalation-template.md"
[ -f "$STATE_MARKER" ] || : > "$STATE_MARKER"

STATE_DIR="$STATE_ROOT/sessions/$SESSION_ID"
INIT_FILE="$STATE_DIR/init.json"
mkdir -p "$STATE_DIR"

# 環境判定 (iterate-team.md ステップ 0.0 の判定ロジックと同一: CLAUDE_CONFIG_DIR マーカー)
if [ "${CLAUDE_CONFIG_DIR:-}" = "/home/node/.claude" ]; then
  IS_DEV_CONTAINER=true
  MCP_PROFILE="devcontainer"
else
  IS_DEV_CONTAINER=false
  MCP_PROFILE="host"
fi

# モデル情報 (Claude Code が SessionStart 入力 JSON に model を含めるかは
# バージョン依存のため、未提供時は "unknown" を許容)
MODEL="$(printf '%s' "$INPUT" | jq -r '.model // empty' 2>/dev/null || true)"
if [ -z "$MODEL" ]; then
  MODEL="unknown"
fi

MODEL_WARNING=""
case "$MODEL" in
  *opus*|*Opus*|*OPUS*)
    MODEL_WARNING="[session-start-hook] 警告: Opus 系モデル ($MODEL) を検出しました。/iterate-team は Sonnet 系で検証されています。利用する場合は /model sonnet で切替後にセッション再起動してください。"
    ;;
esac

# MCP profile target 解決 (.mcp.json の symlink 先)
MCP_JSON="$PROJECT_DIR/.mcp.json"
MCP_TARGET=""
if [ -L "$MCP_JSON" ]; then
  MCP_TARGET="$(readlink "$MCP_JSON" 2>/dev/null || true)"
elif [ -f "$MCP_JSON" ]; then
  MCP_TARGET="$(basename "$MCP_JSON")"
fi

CREATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

SOURCE="$(printf '%s' "$INPUT" | jq -r '.source // empty' 2>/dev/null || true)"

# plugin_root: プラグインとして実行されている場合 ${CLAUDE_PLUGIN_ROOT} が env に注入される。
# 未設定 (プラグイン外で直接 hook を呼んだ等) の場合は本スクリプトの親ディレクトリで代替する。
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

if ! jq -n \
  --arg session_id "$SESSION_ID" \
  --arg created_at "$CREATED_AT" \
  --arg project_dir "$PROJECT_DIR" \
  --arg plugin_root "$PLUGIN_ROOT" \
  --arg model "$MODEL" \
  --arg model_warning "$MODEL_WARNING" \
  --argjson is_dev_container "$IS_DEV_CONTAINER" \
  --arg mcp_profile "$MCP_PROFILE" \
  --arg mcp_target "$MCP_TARGET" \
  --arg claude_config_dir "${CLAUDE_CONFIG_DIR:-}" \
  --arg source "$SOURCE" \
  '{
    schema_version: 2,
    claude_session_id: $session_id,
    created_at: $created_at,
    project_dir: $project_dir,
    plugin_root: $plugin_root,
    source: $source,
    model: $model,
    model_warning: $model_warning,
    is_dev_container: $is_dev_container,
    mcp_profile: $mcp_profile,
    mcp_json_target: $mcp_target,
    claude_config_dir: $claude_config_dir
  }' > "$INIT_FILE.tmp"; then
  emit_context_only "[session-start-hook] init.json の生成に失敗しました。"
  rm -f "$INIT_FILE.tmp"
  exit 1
fi
mv "$INIT_FILE.tmp" "$INIT_FILE"

# additionalContext へ session-init タグと warning を出力
CTX="<session-init init_path=\"$INIT_FILE\" claude_session_id=\"$SESSION_ID\" is_dev_container=\"$IS_DEV_CONTAINER\" mcp_profile=\"$MCP_PROFILE\" model=\"$MODEL\" plugin_root=\"$PLUGIN_ROOT\" />
[session-start-hook] ハーネス初期化完了。/iterate-team の step 0 は本 session-init を参照して再判定を省略する。plugin_root は init.json の plugin_root を参照。スキーマは <plugin_root>/operations/session-start-hook.md を参照。"

if [ -n "$MODEL_WARNING" ]; then
  CTX="$CTX
$MODEL_WARNING"
fi

jq -n --arg ctx "$CTX" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}'
