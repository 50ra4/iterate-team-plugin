# SessionStart hook 仕様

iterate-team ハーネスのセッション初期化を Claude Code の `SessionStart` hook に集約し、結果を Claude Code セッション単位の `init.json` に永続化する。

## 目的

- `/iterate-team` の step 0 の重複した環境判定 / モデル確認を 1 回に圧縮する
- 同一 checkout で複数セッションが並走しても、相互に判定を上書きしないよう **Claude Code 側 session_id でスコープ** する
- 固定パス (`.iterate-team/state/session-init.json` のような単一ファイル方式) は採用しない
- プラグイン資産ルート `${CLAUDE_PLUGIN_ROOT}` を `init.json` の `plugin_root` に記録し、Orchestrator が各 subagent プロンプトへ絶対パスを注入できるようにする（`${CLAUDE_PLUGIN_ROOT}` は agent/command 本文では展開保証されないため、hook 経由で永続化する）

## 構成

```
プラグイン manifest (.claude-plugin/plugin.json)
  └─ hooks.SessionStart → "${CLAUDE_PLUGIN_ROOT}/scripts/session-start.sh"
      (Claude Code はプラグイン hook 実行時に ${CLAUDE_PLUGIN_ROOT} / ${CLAUDE_PROJECT_DIR} を
       env へ注入する。cwd 非依存で、サブディレクトリから起動されても
       ${CLAUDE_PROJECT_DIR} がリポジトリルートを指すため hook が失敗しない)

${CLAUDE_PLUGIN_ROOT}/scripts/session-start.sh
  ├─ stdin: Claude Code が SessionStart で渡す JSON ({session_id, model, source, ...})
  ├─ env: ${CLAUDE_PLUGIN_ROOT}（プラグイン資産ルート）/ ${CLAUDE_PROJECT_DIR}（対象リポジトリルート）
  ├─ seed: 対象リポジトリ直下に .iterate-team/{state,tasks,changes} を作成
  ├─ 永続化先: .iterate-team/state/sessions/<claude-session-id>/init.json
  └─ stdout: { hookSpecificOutput: { hookEventName: "SessionStart",
                                     additionalContext: "<session-init ... />..." } }
```

## init.json スキーマ (`schema_version: 2`)

| キー                | 型                      | 説明                                                                                                                                     |
| ------------------- | ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `schema_version`    | integer                 | 本スキーマのバージョン。互換性破壊変更時にインクリメントする（`plugin_root` 追加で 2）                                                   |
| `claude_session_id` | string                  | Claude Code 側の session*id (hook 入力 JSON の `session_id`)。\*\*ハーネス側の `<session-id>` (`YYYYMMDDHHmm*<topic-slug>`) とは別物\*\* |
| `created_at`        | string (ISO 8601 / UTC) | hook 実行時刻                                                                                                                            |
| `project_dir`       | string                  | `CLAUDE_PROJECT_DIR` または cwd の絶対パス（対象リポジトリルート）                                                                       |
| `plugin_root`       | string                  | `CLAUDE_PLUGIN_ROOT`（プラグイン資産ルート絶対パス）。Orchestrator が `<plugin_root>/...` 参照の解決と subagent への注入に使う           |
| `source`            | string                  | Claude Code が渡す起動種別 (`startup` / `resume` / `clear` 等)                                                                           |
| `model`             | string                  | hook 入力 JSON の `model`。未提供時は `"unknown"`                                                                                        |
| `model_warning`     | string                  | Opus 系検出時の警告文。それ以外は空文字列                                                                                                |
| `is_dev_container`  | boolean                 | `CLAUDE_CONFIG_DIR == /home/node/.claude` の場合 `true`、それ以外 `false`                                                                |
| `mcp_profile`       | string                  | `"devcontainer"` または `"host"`                                                                                                         |
| `mcp_json_target`   | string                  | `.mcp.json` の symlink 先 (`.mcp.host.json` / `.mcp.devcontainer.json` / 空)                                                             |
| `claude_config_dir` | string                  | hook 実行時の `CLAUDE_CONFIG_DIR` (空文字列の場合あり)                                                                                   |

## additionalContext フォーマット

hook は以下のテキストを `hookSpecificOutput.additionalContext` として出力する:

```
<session-init init_path="<絶対パス>" claude_session_id="<id>" is_dev_container="<bool>" mcp_profile="<profile>" model="<model-id>" plugin_root="<絶対パス>" />
[session-start-hook] ハーネス初期化完了。/iterate-team の step 0 は本 session-init を参照して再判定を省略する。plugin_root は init.json の plugin_root を参照。スキーマは <plugin_root>/operations/session-start-hook.md を参照。
[session-start-hook] 警告: Opus 系モデル ... (Opus 検出時のみ)
```

Orchestrator (`<plugin_root>/commands/iterate-team.md`) は step 0 で:

1. コンテキストから `<session-init ... />` タグを検出する
2. `init_path` 属性の絶対パスを `Read` で読み込み、init.json 全体を取得する
3. `is_dev_container` / `mcp_profile` / `model` / `plugin_root` を後続ステップに引き継ぐ（`plugin_root` は以降の `<plugin_root>/...` 参照解決と subagent プロンプトへの注入に使う）

`<session-init>` タグが存在しない場合は **初期化未完了として処理を中止** する (誤起動防止)。

## モデル判定の三層防御

| 層   | 場所                                                                                   | 効果                                                                                                               |
| ---- | -------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| 一次 | プロジェクトの `.claude/settings.json` の `model`（任意。Sonnet 既定にしておくと安全） | デフォルトモデルを Sonnet に寄せる                                                                                 |
| 二次 | 本 hook (`${CLAUDE_PLUGIN_ROOT}/scripts/session-start.sh`)                             | 入力 JSON の `model` を判定し、Opus 系を検出したら `additionalContext` に **警告のみ** 挿入 (セッション継続は許可) |
| 三次 | `/iterate-team` の step 0                                                              | init.json の `model` を読み、Opus 系なら処理中止                                                                   |

二次防御で **abort せず警告のみ** にしている理由は、Opus セッションでも `/iterate-*` 以外の通常作業 (コードレビュー・読書) を継続できる柔軟性を維持するため。abort は `/iterate-*` 起動時にのみ発生させる。

## 失敗モード

| 状況                | hook の挙動                                               | Orchestrator step 0 の挙動                                                                          |
| ------------------- | --------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| 正常                | init.json 書き出し + `<session-init>` 出力                | init.json を Read して継続                                                                          |
| `session_id` 欠落   | 警告 additionalContext のみ出力、exit 1、init.json 未生成 | `<session-init>` 不在 → abort                                                                       |
| `jq` 未インストール | エラー出力 + exit 1                                       | `<session-init>` 不在 → abort                                                                       |
| init.json 生成失敗  | 警告 additionalContext のみ、exit 1                       | `<session-init>` 不在 → abort                                                                       |
| Opus 検出           | init.json 書き出し + warning 付き `<session-init>` 出力   | `<session-init>` の `model` 属性または init.json `model_warning` 確認 → `/iterate-*` 起動時は abort |

## 並走セッションでの独立性

同 checkout で 2 つの Claude Code セッションを並走させた場合、各セッションは独自の `session_id` を持つため、`.iterate-team/state/sessions/<id-A>/init.json` と `.iterate-team/state/sessions/<id-B>/init.json` は完全に分離される。後発セッションが先発セッションの init.json を上書きしないことを以下で確認できる:

```bash
ls -la .iterate-team/state/sessions/
# 各 session-id ディレクトリが独立して並ぶ
```

古い / 壊れた init.json は次回 SessionStart 実行時に同一 session-id ディレクトリ内で上書きされる (`mv` による atomic replace)。**別 session-id ディレクトリは触らない**。

## 補足: ハーネス `<session-id>` との関係

ハーネス側 (Planner) が `YYYYMMDDHHmm_<topic-slug>` 形式で発行する `<session-id>` は本 hook の対象外。Planner 完了後にしか確定しないため、SessionStart 時点では利用不可。両者を混同しないよう、init.json のキーは `claude_session_id` と明示している。

## 関連 hook: Notification（回答待ち通知音）

`SessionStart` とは別に `Notification` hook をプラグイン manifest（`.claude-plugin/plugin.json` の `hooks.Notification`、matcher `"*"`）に登録している。Claude Code がユーザーの回答待ち（permission 要求 / idle / AskUserQuestion 提示）になったタイミングで `${CLAUDE_PLUGIN_ROOT}/scripts/notify-waiting.sh` を実行し、通知音を鳴らす。

- **devcontainer のみ発火**: スクリプトは `CLAUDE_CONFIG_DIR=/home/node/.claude`（SessionStart hook と同一の dev container 判定基準）のときだけ音を鳴らし、host / Web 版では無音で `exit 0` する。
- **音源**: `${CLAUDE_PLUGIN_ROOT}/assets/notify.wav`（`scripts/gen-notify-wav.py` で再生成可能）を `paplay`→`aplay`→`ffplay` の順で再生試行。いずれも不可 / WAV 不在ならターミナルベル（BEL）にフォールバック。
- **プラグイン hook として登録**: プラグインが有効なセッションで発火する。プロジェクト側の `.claude/settings.json` に二重登録しない（多重発火を避けるため）。

## 参照

- 詳細仕様の正本: `<plugin_root>/commands/iterate-team.md`（step 0）
