---
description: .agent-os/ プロジェクト適応レイヤの初期化・再観測
argument-hint: [--no-push] [--reset-adapter]
---

# /iterate-adapt

あなたは `/iterate-adapt` の **Orchestrator** である。メインセッション（Sonnet）で動作する。

**本コマンドは standalone コマンドである**。`/iterate-plan` → `/iterate-build` → `/iterate-review` の 3 分割プロトコル（`--session` 引継ぎ・`step_checkpoint` resume）とは独立しており、`--session` 引数を受け取らない。対象リポジトリ直下 `.agent-os/`（プロジェクト適応レイヤ）を初期構築・再観測する専用コマンドである。実体作業は `team-profiler` agent が担う。adapter の確定値・スキーマ・規約は [`adapter-policy.md`](<plugin_root>/operations/adapter-policy.md) を正本とし、本コマンドはその手順の正本である。

## 必須遵守事項

- **`<plugin_root>` 解決**: SessionStart hook が注入する `<session-init>` の `plugin_root`（= init.json の `plugin_root`）を `<plugin_root>` として保持し、本文・operations・scripts 参照（`<plugin_root>/...`）の解決と、team-profiler 起動プロンプトへの `plugin_root=<絶対パス>` 注入に使う
- **`.agent-os/` への観測・生成主体は team-profiler agent のみ**（`adapter-policy.md` §6）。本コマンド（Orchestrator）は `.agent-os/` 配下を直接 `Write` / `Edit` しない。Orchestrator の役割は scaffold インストーラの起動・validate・git add/commit・push 分岐に限られる
- コミットは個別 `git add`（`git add .` / `git add -A` 禁止）。詳細: [`git-commit-rules.md`](<plugin_root>/templates/_partials/git-commit-rules.md)
- `git push` の直接呼び出し禁止。push は `team-publisher` Agent 経由のみ
- 本コマンドは `git commit` まで行うが、**push は環境・引数に応じて分岐**する（ステップ 6）
- `$ARGUMENTS` から `--no-push` / `--reset-adapter` の 2 個の boolean flag を解釈する（値を取らない・順不同・両方省略可）。上記 2 種以外の引数を検出した場合は Usage を返して処理中止する:

  ```
  Usage: /iterate-adapt [--no-push] [--reset-adapter]
  ```

## ステップ 0: 環境ガード（preflight）

1. **0.0 セッション初期化結果の取得**: context 先頭の `<session-init>` タグ（`init_path` / `is_dev_container` / `mcp_profile` / `model` / `plugin_root`）を取得する。**存在しない場合は処理中止**メッセージを返す。`init_path` を `Read` し、`plugin_root` を `<plugin_root>` として、`project_dir`（init.json の `project_dir`。対象リポジトリのルート絶対パス）を `<project_dir>` として保持する。`<adapter_dir>` = `<project_dir>/.agent-os` の絶対パスをこの時点で計算し in-memory 保持する（既存有無は確認しない。存在チェックなしで後段の全ステップへ渡す規約は `harness-common.md#adapter-注入全コマンド共通` と同一）
2. **0.1 clean tree の必須確認**: `Bash git status --porcelain` を実行する。**1 行でも出力があれば dirty** とみなし、以下を報告して処理中止する（`.agent-os/` をコミットするため clean tree を前提とする。この時点では adapt 用ディレクトリ未作成のため runlog は記録しない）:

   ```
   working tree に未コミットの変更があります。/iterate-adapt は .agent-os/ をコミットするため clean tree を必須とします。
   変更をコミットまたは stash してから再実行してください。
   ```

3. **0.2 adapt 用 runlog 宛先の作成**: `<ts>` = 現在時刻（`YYYYMMDDHHmm`、UTC）とし、`<adapt-session-id>` = `adapt_<ts>` を発行する。`Bash mkdir -p .iterate-team/state/<adapt-session-id>` を実行する。**以降のすべての runlog 追記はこのディレクトリ（`<plugin_root>/scripts/runlog-append.sh <adapt-session-id> ...`）へ記録する**

## ステップ 1: ブランチ作成

1. `Bash git symbolic-ref --short HEAD` で現在ブランチ `<original-branch>` を記憶する
2. `<adapt-branch>` = `claude/adapter-<ts>`（`<ts>` はステップ 0.2 と同一値）
3. `Bash git switch -c "<adapt-branch>"` を実行する。失敗時は理由を報告して処理中止する（`<original-branch>` から動いていないため復元不要。この時点では runlog 対象イベントが定義されていないため runlog は記録しない）

## ステップ 2: host 承認ゲート

`.agent-os/` は git 追跡対象ファイルであり、本コマンドは対象リポジトリへ**書き込みを伴う変更**を加える。サイレント編集にしないため、host 環境では書き込み前にユーザー確認を必須とする。

- **`<is_dev_container>=false`（host / Web 版）**: `AskUserQuestion` で「`.agent-os/` を対象リポジトリに追加/更新します。これは git 追跡対象ファイルです。続行しますか？」（選択肢: `続行` / `中止`）を尋ねる。
  - `続行` 選択時: ステップ 3 へ進む
  - `中止` 選択時: `Bash <plugin_root>/scripts/git-switch-branch.sh "<original-branch>"` で元ブランチへ戻り、`<adapt-branch>` を削除する（検証付き削除ラッパーは `retrospect-delete-branch.sh` と同型で `scripts/` 側に別途追加が必要。未整備の間は削除を省略し、コミット 0 件の `<adapt-branch>` をローカルに残したまま元ブランチへ戻ってよい）。理由を報告して処理中止する
- **`<is_dev_container>=true`（dev container）**: 本ゲートを **skip** し、そのままステップ 3 へ進む（dev container はユーザーの明示操作下で起動される前提のため）

## ステップ 3: install scaffold（adapter-bootstrap.sh）

`Bash <plugin_root>/scripts/adapter-bootstrap.sh --target "<project_dir>"` を実行する（`--reset-adapter` がユーザー引数に含まれる場合は末尾に追加する）。本スクリプトは `<project_dir>/.agent-os/` の 8 ファイル scaffold（既存ファイルは上書きしない）と `GLOBAL_AGENTS.md` を設置する（`--adapter-only` が既定。`adapter-policy.md` §2・§9）。実行失敗時は理由を報告し、ステップ 1 で作成したブランチへ元ブランチから戻らず現在ブランチのまま処理を中止する（コミット前のため復元は不要）。

## ステップ 4: 観測（team-profiler）

1. `Agent` で `subagent_type: team-profiler` を起動する。プロンプトに以下のキーを含める:

   | キー          | 値                                                                                                             |
   | ------------- | ---------------------------------------------------------------------------------------------------------------- |
   | `plugin_root` | `<plugin_root>`（絶対パス）                                                                                       |
   | `session_id`  | `<adapt-session-id>`（= `adapt_<ts>`）                                                                            |
   | `project_dir` | `<project_dir>`（絶対パス）                                                                                       |
   | `adapter_dir` | `<adapter_dir>`（= `<project_dir>/.agent-os` の絶対パス）                                                         |
   | `topic_slug`  | `<project_dir>` のディレクトリ名を kebab-case 化した slug（英数字以外を `-` に置換・小文字化・前後の `-` を除去）。空文字になる場合は既定値 `project-adapter` を用いる |

   team-profiler は `project-profile.md` / `command-map.md` / `risk-map.md` / `architecture-map.md` の 4 ファイルを生成・更新し、完了時に自ら `adapter_observed` を runlog へ自己記録する（`adapter-policy.md` §8。Bash を持つ agent としての自己記録経路）
2. 戻り値の JSON フェンス（`files` / `verified_commands` / `risk_areas` / `open_hypotheses`）を受領し、ステップ 6 の報告に使う
3. agent が異常終了・応答不能等で完了しなかった場合はステップ「失敗時」へ

## ステップ 5: validate + commit

1. `Bash <plugin_root>/vendor/agent-os/scripts/validate-agent-os.sh --adapter "<project_dir>"` を実行する。exit code が非 0 の場合はその内容を後段の報告に含めるが、**処理は中止せず**次項のコミットへ進む（部分的にでも生成済みの資産を失わないため）
2. `Bash git status --porcelain -- .agent-os/` で差分ファイル一覧を取得する
3. **差分がある場合**: 変更ファイルを 1 件ずつ `git add <file>` する（`git add -A` / `git add .` 禁止、`adapter-policy.md` §7）。1 コミットにまとめる。subject `docs: .agent-os アダプタを初期化/更新`、footer `Refs: adapter-<ts>`
4. **差分がない場合**（`--reset-adapter` なしの再実行等）: 「観測の結果、差分なし」と報告し、`Bash <plugin_root>/scripts/git-switch-branch.sh "<original-branch>"` で元ブランチへ戻って終了する（ステップ 6 は実行しない。ブランチ・コミットは残さない方針だがコミット自体が存在しないため実質的に元ブランチと同一であり削除は不要）
5. コミット成功後、`<plugin_root>/scripts/runlog-append.sh <adapt-session-id> adapter_updated '{"files":[<changed files>],"reason":"<--reset-adapter 指定による再観測 or 初期設置>"}'` を追記する
6. コミット失敗（pre-commit hook reject 等）時はステップ「失敗時」へ

## ステップ 6: push 分岐 + 報告

- **host 環境（`<is_dev_container>=false`）かつ `--no-push` 未指定**: `Agent subagent_type: team-publisher` を `{"operation":"push_branch","owner":"<owner>","repo":"<repo>","branch":"<adapt-branch>","phase":"post_implementation","session_id":"<adapt-session-id>"}` で起動し、`<adapt-branch>` を push する（push はこの経路のみ・唯一の push 経路）。push 成否をステップ 6 の報告に含める
- **dev container（`<is_dev_container>=true`）または `--no-push` 指定時**: push を skip し、以下の手動手順を案内する:

  ```
  push は行われていません。host 環境または Web 版で以下を実行してください:

    git push -u origin <adapt-branch>

  push 後、必要であれば GitHub UI で <adapt-branch> → <original-branch> の PR を作成してください。
  ```

結論ファーストで以下を報告する:

- スタック要約（team-profiler の `project-profile.md` 生成結果から 1〜2 行）
- 検証済みコマンド件数（`verified_commands`）
- 主要な危険領域（`risk_areas` 件数 + 代表例があれば 1〜2 件）
- `.agent-os/` が対象リポジトリへコミット済み・git 追跡対象であること
- ブランチ名（`<adapt-branch>`）
- push した場合: push 結果。push しなかった場合: 手動 push 手順
- runlog パス（`.iterate-team/state/<adapt-session-id>/runlog.jsonl`）
- 次の一手: `/iterate-plan` を実行すると、5 agent（`team-planner`/`team-generator`/`team-evaluator`/`team-interviewer`/`team-test-coder`）が今回構築した adapter を尊重して計画・実装する旨を案内する

報告後、`Bash <plugin_root>/scripts/git-switch-branch.sh "<original-branch>"` で元ブランチへ戻る（**push の有無に関わらず、作成したブランチとコミットはローカルに残す**）。

## 失敗時（fail-open・エスカレーションなし）

team-profiler の異常終了、またはステップ 5 のコミット失敗時は以下を行う。本コマンドの失敗によってユーザー作業を止めないため、エスカレーションは行わない:

1. `.agent-os/` を `Bash <plugin_root>/scripts/adapter-recover.sh "<adapt-session-id>"` で復旧する（`knowledge-recover.sh` と同型構造の fail-open スクリプト。**Phase 2 で新規追加予定であり、本コマンド作成時点では未実装**。`adapter-policy.md` §7 参照）。**未実装の間の代替手順**: `Bash <plugin_root>/scripts/git-switch-branch.sh "<original-branch>"` で元ブランチへ戻り、作業ツリーを clean に戻して処理を中止する（`<adapt-branch>` は削除せずローカルに残し、事後調査可能にする）
2. 失敗理由をユーザーへ報告して終了する

## 引数

`$ARGUMENTS`: `[--no-push] [--reset-adapter]`
