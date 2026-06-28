# iterate-team ハーネス Runbook

> 詳細仕様の正本は `<plugin_root>/commands/iterate-team.md`。本書は **運用観点で重複しない情報** のみに絞る（環境前提・障害切り分けの早見）。
>
> エージェント構成 / 状態ディレクトリ / PR 自動化フロー / 不変条件は `<plugin_root>/commands/iterate-team.md` を直接参照。

## 環境前提

### `.mcp.json` の環境別 symlink

`.mcp.json` は git 管理外（`.gitignore`）。`<plugin_root>/scripts/setup-mcp.sh` が `CLAUDE_CONFIG_DIR=/home/node/.claude` を判定して以下を symlink する:

- host / Web 版 → `.mcp.host.json`（chrome-devtools / codex）
- dev container → `.mcp.devcontainer.json`（chrome-devtools / codex）

`npm install` 時の `prepare` スクリプトと `.devcontainer/init-git.sh` の postCreateCommand から自動実行されるため通常は手動操作不要。

### 実行環境別の挙動

`/iterate-team` は preflight ステップ 0.0 で `CLAUDE_CONFIG_DIR=/home/node/.claude` の有無により host / Web 版と dev container を自動判定し、以下を分岐する:

| ステップ                  | host / Web 版                                                                | dev container 内                                                       |
| ------------------------- | ---------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| 4 / 4.5 承認（通算 1 回） | ステップ 4 は提示のみ → 4.5.A で Draft PR 作成 + PR URL で承認（唯一の承認） | ステップ 4 で承認済み → 4.5.B は push/PR skip + 承認なしで wave へ直行 |
| 6.5 自己改善ループ        | 実行（`/simplify` + `/security-review`、push なし）                          | 実行（同上）                                                           |
| 6.6 実装後 push           | 実行                                                                         | skip                                                                   |
| 7 PR Ready 化             | 実行                                                                         | skip                                                                   |
| 7' dev container 完了案内 | skip                                                                         | 実行（host 側で `git push -u origin <branch>` + 手動 PR 作成を促す）   |

dev container 内では **push / PR 操作を全て skip**。read-only Deploy Key + ssh-agent forwarding の設計を維持し、container 内に認証情報を常駐させない。ローカル commit までで完結し、ユーザが host / Web 版に切り替えて push と PR 作成を行う。

ホスト側 `.claude/settings.json` は `Bash(<plugin_root>/scripts/team-push-branch.sh *)` を **唯一の push 経路** として allow し、`Bash(git push *)` は `permissions.deny` で完全遮断する。ラッパー内部で `-f` / `--force` / `--mirror` / `--delete` / refspec 形式 (`:`) / `refs/` 始まり / `main` / `master` / path traversal を allowlist 方式で構造的に拒否。**ブランチ名の接頭辞は強制しない**（ステップ 0.1 で `claude/<topic-slug>` を origin/main から自動 bootstrap するため）。

PR 作成 / 本文更新 / Ready 化は Orchestrator が実行環境で利用可能な手段を選択して実施する（`team-publisher` は push 専任）。

## 主要 runlog イベント（早見）

`runtime_detected`（`{is_dev_container}`） / `fetch_failed` / `origin_main_missing` / `head_is_protected` / `head_not_claude_prefix` / `head_branch_mismatch_on_resume` / `dirty_worktree` / `branch_name_conflict` / `branch_create_failed` / `integration_branch_created` / `integration_branch_renamed` / `branch_rename_conflict` / `head_branch_mismatch_before_rename` / `branch_rename_failed` / `model_check_passed` / `model_confirmed` / `model_aborted_by_user` / `wave_started` / `wave_chunk_started` / `worktree_created` / `worktree_removed` / `wave_merge_started` / `task_merged` / `merge_conflict` / `branch_pushed`（phase: `pre_implementation` | `post_implementation`） / `pr_created` / `pr_approved` / `plan_presented`（host, step4 提示のみ） / `plan_already_approved`（dev container, step4.5 で承認済み確認） / `pr_body_updated` / `pr_marked_ready` / `pr_flow_skipped`（dev container, phase: `pre_implementation` | `post_implementation`） / `post_push_skipped`（dev container） / `ready_skipped`（dev container） / `dev_container_complete`（dev container 終了時） / `advisor_batch_completed` / `parallel_review_started` / `codex_review_serial_fallback` / `self_improve_simplify_completed` / `self_improve_simplify_failed` / `self_improve_simplify_dirty` / `self_improve_simplify_orchestrator_committed` / `self_review_started` / `self_improve_security_blockers_found` / `self_improve_security_clean` / `self_improve_completed` / `self_improve_escalated`（`reason: simplify_no_progress | max_rounds_exceeded`） / `phase_b_advisor_request_issued` / **`agent_decision`**（Agent 呼出・スキップ・採否記録） / `escalated`

各イベントの payload 仕様は `<plugin_root>/commands/iterate-team.md` の各ステップ記述、または `<plugin_root>/scripts/runlog-append.sh` の呼び出し箇所を参照。`agent_decision` イベントの抽出:

```bash
jq 'select(.event == "agent_decision")' .iterate-team/state/<session-id>/runlog.jsonl
```

## agent_decision 発火点（/iterate-team 固有）

team の全発火点に加えて、以下を定める:

| 発火点                                      | agent                   | decision   | 典型 reason                                              |
| ------------------------------------------- | ----------------------- | ---------- | -------------------------------------------------------- |
| ステップ 3.2 type=research 起動時           | `researcher`            | `invoked`  | 「Planner 要求: &lt;topic&gt;」                          |
| ステップ 3.2 type=debug 起動時              | `debugger`              | `invoked`  | 「Planner 要求: &lt;symptoms&gt;」                       |
| ステップ 3.2 type=trace 起動時              | `tracer`                | `invoked`  | 「Planner 要求: &lt;topic&gt;」                          |
| ステップ 3.2 type=interview 起動時          | `team-interviewer`      | `invoked`  | 「Planner 再委譲」                                       |
| ステップ 4.5.A.1 plan push（host 環境）     | `team-publisher`        | `invoked`  | 「host 環境 + pre_implementation push」                  |
| ステップ 4.5.B.1 push skip（dev container） | `team-publisher`        | `skipped`  | 「dev container のため pre_implementation push/PR skip」 |
| ステップ 5.1.1 advisor 並列起動             | `team-advisor-<name>`   | `invoked`  | 「Generator フェーズ A request」                         |
| ステップ 5.3 reviewer:codex 起動時          | `codex-code-review`     | `invoked`  | 「reviewer: codex のため起動」                           |
| ステップ 5.3 reviewer:none skip 時          | `codex-code-review`     | `skipped`  | 「reviewer: none のため skip」                           |
| ステップ 5.3.2 serial fallback              | `codex-code-review`     | `skipped`  | 「並列実行 disabled / 直前 timeout」                     |
| ステップ 5.4 max_retries 到達               | `evaluator`             | `rejected` | 「max_retries 到達」                                     |
| ステップ 6.5.1 `/simplify` 起動             | `skill-simplify`        | `invoked`  | 「self-improvement round=<N>」                           |
| ステップ 6.5.2 `/security-review` 起動      | `skill-security-review` | `invoked`  | 「self-improvement round=<N>」                           |
| ステップ 6.5.4 ループ超過                   | `skill-simplify`        | `rejected` | 「self_improve_round > 2」                               |
| ステップ 6.6 push skip（dev container）     | `team-publisher`        | `skipped`  | 「dev container のため post_implementation push skip」   |

スキーマ詳細（キー定義 / decision 値域）は `agent-decision-schema.md` を参照。

## `--model <model-id>` 引数の影響範囲

`/iterate-team [--model <id>] <要望文>` で起動した場合:

| ステップ                               | 影響                                                                                                   |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| ステップ 0.0 / 0.1                     | **影響なし**（dev container 検出 / branch bootstrap は現状維持）                                       |
| ステップ 0.2（確認プロンプト）         | `--model` 指定時は **skip**（`AskUserQuestion` 確認をバイパス）                                        |
| ステップ 1（1.0 節）                   | `--model <id>` をパース。in-memory `<model_override>` に保持                                           |
| ステップ 2（`session_start`）          | 指定時のみ payload に `"model_override": "<id>"` を追加し `agent=orchestrator decision=invoked` を記録 |
| preflight（`runtime_detected`）        | `--model` 指定時は payload に `model_override` キーを追加                                              |
| dev container 経路（4.5.B / 6.6 / 7'） | **影響なし**（`<is_dev_container>` フラグのみで分岐）                                                  |

**運用前提**: `--model` 指定時は事前に `/model <id>` でセッションモデルを切替してから本コマンドを起動すること。`<id>` の実モデル妥当性検証は Claude Code に委譲する（形式チェック `[A-Za-z0-9._-]+` のみ）。`--model` 未指定時の動作は「Sonnet 系 / unknown は通過、その他は `AskUserQuestion` 確認」となる（abort ではなく確認）。

## 3 コマンド分割と session-id 引継ぎプロトコル

`/iterate-team` の責務を 3 つの独立コマンド（`/iterate-plan` / `/iterate-build` / `/iterate-review`）へ分割する設計の仕様を本章で定義する。各コマンドのステップ詳細は既存 runbook の各ステップ章へのリンクで委譲し、本章は **責務境界・session-id 引継ぎ・バリデーション仕様の Single Source of Truth** とする。

### 責務境界の概要

| コマンド          | 担当ステップ                        | 主要処理                                                                              |
| ----------------- | ----------------------------------- | ------------------------------------------------------------------------------------- |
| `/iterate-plan`   | 0 / 1 / 2 / 2.5 / 3 / 3.x / 3.5 / 4 | preflight + interviewer ループ + Planner 起動 + 計画レビュー + 計画承認               |
| `/iterate-build`  | 4.5 / 5.0〜5.7                      | 承認（host: Draft PR 作成後 / dev container: 承認済みで skip）+ wave 並列タスクループ |
| `/iterate-review` | 6 / 6.5 / 6.6 / 7 / 7'              | closer 委譲 + 自己改善ループ + post-push + PR Ready 化 / dev container 完了案内       |

### `/iterate-plan` 担当ステップ範囲

担当ステップ: 0〜4（preflight から計画承認まで）

| ステップ | 詳細リンク                                                                                                      |
| -------- | --------------------------------------------------------------------------------------------------------------- |
| 0        | [ステップ 0: 環境ガード（preflight）](#ステップ-0-環境ガードpreflight)                                          |
| 2.5      | [ステップ 2.5: 要件壁打ち（team-interviewer ループ）](#ステップ-25-要件壁打ちteam-interviewer-ループ)           |
| 3        | [ステップ 3: Planner 起動と研究ループ](#ステップ-3-planner-起動と研究ループ)                                    |
| 3.x      | [3.x integration-branch の rename](#3x-integration-branch-の-renameパターン-b-内placeholder-bootstrap-経路のみ) |
| 3.5      | [ステップ 3.5: 計画レビュー](#ステップ-35-計画レビューcodex-経路--フォールバック経路)                           |

> **`next_step="3.5-replan"`（resume 専用の有効値）**: ステップ 3.5 の REQUEST_CHANGES 後、mid-loop checkpoint（インクリメント済み `plan_review_round`）から team-planner 再起動前にクラッシュ/auto-compaction した場合の再開先。`/iterate-plan` 担当範囲（ステップ 3.5 系列）の有効な resume ステップであり、復帰時は 3.5.C / 3.5.E の「`>= 3` 再判定 → `< 3` なら replan」手順に合流する（詳細は[3.5.C](#35c-codex-経路-request_changes-時の-planner-自動再起動)）。

完了時出力テンプレ:

```
[iterate-plan] 計画フェーズが完了しました。

session-id: <session-id>
integration-branch: <integration-branch>
plan: .iterate-team/tasks/<yyyyMMdd_topic-slug>/plan-summary.md
runlog: .iterate-team/state/<session-id>/runlog.jsonl

次は以下のコマンドで実装フェーズを開始してください:
/iterate-build --session <session-id>
```

### `/iterate-build` 担当ステップ範囲

担当ステップ: 4.5〜5.7（承認から wave 並列タスクループ完了まで）

| ステップ | 詳細リンク                                                                                                                              |
| -------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| 4.5      | [ステップ 4.5: 承認（環境分岐・承認は通算 1 回）](#ステップ-45-承認環境分岐承認は通算-1-回)                                             |
| 5        | [ステップ 5: wave 並列タスクループ](#ステップ-5-wave-並列タスクループ)                                                                  |
| 5.0      | [5.0 wave 起動](#50-wave-起動)                                                                                                          |
| 5.1      | [5.1 フェーズ A 戻り値処理（advisor 並列収集）](#51-フェーズ-a-戻り値処理advisor-並列収集)                                              |
| 5.2      | [5.2 フェーズ B 戻り値処理（実装完了確認）](#52-フェーズ-b-戻り値処理実装完了確認)                                                      |
| 5.3      | [5.3 検収レビュー（Evaluator 先行ゲート → APPROVED 後に Code Review）](#53-検収レビューevaluator-先行ゲート--approved-後に-code-review) |
| 5.4      | [5.4 検収結果の処理](#54-検収結果の処理)                                                                                                |
| 5.5      | [5.5 wave 内全タスク OK 後の merge](#55-wave-内全タスク-ok-後の-merge)                                                                  |
| 5.6      | [5.6 マージ完了後の worktree クリーンアップ](#56-マージ完了後の-worktree-クリーンアップ)                                                |

完了時出力テンプレ:

```
[iterate-build] 実装フェーズが完了しました。

session-id: <session-id>
integration-branch: <integration-branch>
完了タスク数: <total_tasks>
試行回数累計: <total_attempts>
コミット履歴: git log --grep="Refs: task-" --format="%h %s"
runlog: .iterate-team/state/<session-id>/runlog.jsonl

次は以下のコマンドでレビューフェーズを開始してください:
/iterate-review --session <session-id>
```

### `/iterate-review` 担当ステップ範囲

担当ステップ: 6〜7'（closer 委譲から完了報告まで）

| ステップ | 詳細リンク                                                                                                                         |
| -------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| 6        | closer 委譲（`harness-common.md` の closer 章を参照）                                                                              |
| 6.5      | [ステップ 6.5: 自己改善ループ（Skill: /simplify → /security-review）](#ステップ-65-自己改善ループskill-simplify--security-review)  |
| 6.6      | [ステップ 6.6: 実装コミット群を remote へ push（host 環境のみ）](#ステップ-66-実装コミット群を-remote-へ-pushhost-環境のみ)        |
| 7        | [ステップ 7: PR Ready 化とユーザーへ一括報告（host 環境のみ）](#ステップ-7-pr-ready-化とユーザーへ一括報告host-環境のみ)           |
| 7'       | [ステップ 7': dev container 専用 — ローカル完了報告と引き継ぎ案内](#ステップ-7-dev-container-専用--ローカル完了報告と引き継ぎ案内) |

完了時出力テンプレ:

```
[iterate-review] レビューフェーズが完了しました。

session-id: <session-id>
integration-branch: <integration-branch>
完了タスク数: <total_tasks>
試行回数累計: <total_attempts>
コミット履歴: git log --grep="Refs: task-" --format="%h %s"
PR URL: <pr-url>（host 環境のみ）
runlog: .iterate-team/state/<session-id>/runlog.jsonl
```

### `--session` 引数バリデーション

`/iterate-build` / `/iterate-review` の起動時、`--session <session-id>` は必須引数である。引数の検証は `<plugin_root>/scripts/iterate-validate-session.sh` で行う。

#### `<plugin_root>/scripts/iterate-validate-session.sh` 仕様

```
<plugin_root>/scripts/iterate-validate-session.sh <session-id> <expected-phase>
```

| 引数               | 説明                                                                                          |
| ------------------ | --------------------------------------------------------------------------------------------- |
| `<session-id>`     | バリデーション対象の session-id 文字列                                                        |
| `<expected-phase>` | 呼び出し元が期待するフェーズ。`build`（`/iterate-build`）または `review`（`/iterate-review`） |

`--session <session-id>` の値を第 1 引数、自コマンドに対応する phase 名を第 2 引数として渡す。`/iterate-build` は `build`、`/iterate-review` は `review` を指定する。`--session` 自体の未指定（引数欠落）はコマンド側で検出し、スクリプトには値が揃った状態で渡す。

バリデーションケースと exit コード:

| ケース                                                                                                                                                         | exit コード | 標準エラー出力メッセージ                                            |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------- | ------------------------------------------------------------------- |
| 引数不足、または `<expected-phase>` が `build`/`review` 以外                                                                                                   | 1           | `Usage: ... <session-id> <expected-phase>`                          |
| `session-id` が `^[A-Za-z0-9][A-Za-z0-9._-]*$` に不一致、または `..` を含む                                                                                    | 2           | `invalid session-id format`                                         |
| 同 2（git リポジトリ外から実行）                                                                                                                               | 2           | `fatal: not a git repository`                                       |
| `.iterate-team/state/<session-id>/runlog.jsonl` が不在                                                                                                         | 3           | `runlog not found: 該当 session-id は存在しません`                  |
| `<expected-phase>=build` かつ runlog に plan 完了シグナル（`plan_approved` / `plan_presented` / step4 checkpoint `next_step` が `4.5` もしくは `"4.5"`）が無い | 4           | `plan phase not completed: 先に /iterate-plan を実行してください`   |
| `<expected-phase>=review` かつ build 完了イベント（`step_checkpoint` の `next_step` が `6` もしくは `"6"`、または `all_tasks_completed`）が無い                | 5           | `build phase not completed: 先に /iterate-build を実行してください` |

session-id 形式は先頭英数字を必須とし（`-flag` 始まりの引数注入防止）、`..` を別途拒否する（パストラバーサル防止）ため、`[A-Za-z0-9._-]+` より厳格である点に注意。

バリデーション成功時は exit 0 を返し、標準出力に以下の JSON を 1 行で出力する。コマンド側は exit 0 を確認した上で、この `integration_branch` を後続の HEAD 整合検証に使用する。

```json
{ "session_id": "<session-id>", "integration_branch": "<integration-branch>" }
```

#### `--session` 起動時の状態確認（`/iterate-build` / `/iterate-review` 共通）

`<plugin_root>/scripts/iterate-validate-session.sh` による形式・runlog 存在・フェーズ進捗（plan/build 完了）確認に加え、コマンド側は以下の状態確認を実施する。

1. `tail -n 200 .iterate-team/state/<session-id>/runlog.jsonl | jq -c 'select(.event=="step_checkpoint")' | tail -n 1` で最新 `step_checkpoint` イベントを取得する
2. 最新 `step_checkpoint` が存在しない（runlog に `step_checkpoint` 未記録）場合は処理中止 + 「plan が未完了のため実行できません。先に `/iterate-plan <要望文>` を実行してください。」を案内する
3. 最新 `step_checkpoint.next_step` が自コマンドの担当範囲外である場合は処理中止 + 適切なコマンドを案内する（詳細は「`--resume-checkpoint` の自コマンド範囲ガード」節の分岐表参照）

| コマンド          | 担当 `next_step` 値域（文字列・またはその数値相当）                                                               |
| ----------------- | ----------------------------------------------------------------------------------------------------------------- |
| `/iterate-build`  | `"4.5"` / `"5"` / `"5.0"` / `"5.1"` / `"5.2"` / `"5.3"` / `"5.4"` / `"5.5"` / `"5.6"` / `"5.7"`（数値表現も許容） |
| `/iterate-review` | `"6"` / `"6.5"` / `"6.6"` / `"7"` / `"7'"`（数値表現も許容）                                                      |

範囲外の場合のエラーメッセージ形式:

```
[<command-name>] この session は現在 next_step="<value>" の状態です。このコマンドの担当範囲外です。
以下のコマンドで続行してください:
/<correct-command> --session <session-id>
```

### `--resume-checkpoint` の自コマンド範囲ガード

`/iterate-build` または `/iterate-review` を `--resume-checkpoint <session-id>` で再開する際、checkpoint の `next_step` 値が自コマンドの担当範囲外である場合は処理中止して該当コマンドを案内する。

`next_step` 値は `.iterate-team/state/<session-id>/runlog.jsonl` の最終 `step_checkpoint` イベントの payload から取得する。

#### `next_step` 値域と担当コマンドの分岐表

> **型注記（後方互換）**: `next_step` 値は文字列（例: `"6"`）と数値（例: `6`）の双方が存在し得る（旧 runlog は数値で書き込まれている場合がある）。数値専用ステップ（`4.5` / `6` 等）は数値・文字列双方を許容して照合する。文字列専用識別子（`"3.5-replan"` 等）は数値表現が存在しないため文字列照合を維持する。

**代表マッピングケース（SSOT）**:

| `next_step` 値（入力） | 解決先担当コマンド | 備考                                                         |
| ---------------------- | ------------------ | ------------------------------------------------------------ |
| `6` / `"6"`            | `/iterate-review`  | 数値・文字列双方許容（数値専用ステップ）                     |
| `4.5` / `"4.5"`        | `/iterate-build`   | 数値・文字列双方許容（数値専用ステップ）                     |
| `"3.5-replan"`         | `/iterate-plan`    | 文字列専用ドメイン（数値表現は存在しない。文字列照合を維持） |
| 未知値                 | —                  | abort / エスカレーション（「未知の next_step 値: <value>」） |

**全値域分岐表**:

| `next_step` 値                                                                                                     | 担当コマンド      | 処置                                                                       |
| ------------------------------------------------------------------------------------------------------------------ | ----------------- | -------------------------------------------------------------------------- |
| `"2.5"` / `"3"` / `"3.2"` / `"3.5"` / `"3.5-replan"` / `"4"` またはその数値相当                                    | `/iterate-plan`   | 担当外: 処理中止 + `/iterate-plan --resume-checkpoint <session-id>` を案内 |
| `"4.5"` / `"5"` / `"5.0"` / `"5.1"` / `"5.2"` / `"5.3"` / `"5.4"` / `"5.5"` / `"5.6"` / `"5.7"` またはその数値相当 | `/iterate-build`  | 担当内: 該当ステップから再開                                               |
| `"6"` / `"6.5"` / `"6.6"` / `"7"` / `"7'"` またはその数値相当                                                      | `/iterate-review` | 担当内: 該当ステップから再開                                               |
| 上記以外（未知値）                                                                                                 | —                 | abort + 「未知の next_step 値: <value>」エラーを返して処理中止             |

担当外の場合の処理中止メッセージ形式:

```
[<command-name>] checkpoint の next_step "<value>" はこのコマンドの担当範囲外です。
以下のコマンドで再開してください:
/<correct-command> --resume-checkpoint <session-id>
```

### session-id 引継ぎフロー

3 コマンドは `.iterate-team/state/<session-id>/` ディレクトリを共有状態として session-id で連携する。runlog / requests / responses / waves.jsonl / step_checkpoint はすべて同一ディレクトリ配下に蓄積される。

```mermaid
sequenceDiagram
  participant U as User
  participant P as "/iterate-plan"
  participant B as "/iterate-build"
  participant R as "/iterate-review"
  participant S as ".iterate-team/state/&lt;session-id&gt;/"
  U->>P: /iterate-plan &lt;要望文&gt;
  P->>S: session-id 発行 + plan.json / waves.jsonl
  P-->>U: "次は /iterate-build --session &lt;session-id&gt;"
  U->>B: /iterate-build --session &lt;session-id&gt;
  B->>S: runlog 読込 + wave 並列実装
  B-->>U: "次は /iterate-review --session &lt;session-id&gt;"
  U->>R: /iterate-review --session &lt;session-id&gt;
  R->>S: closer + 自己改善 + push + Ready 化
  R-->>U: 完了報告（PR URL / runlog パス）
```

### 既存 `/iterate-team` との並走

既存 `/iterate-team`（`<plugin_root>/commands/iterate-team.md`）は **無修正で残置** する。3 コマンドは既存コマンドと完全に独立しており、同一リポジトリ上で並走可能である。

- 既存 `/iterate-team` を実行中のセッションと、新規 3 コマンドを使用するセッションは session-id が異なる（`.iterate-team/state/<session-id>/` が分離）ため干渉しない
- 既存 subagent（`<plugin_root>/agents/team-*.md`）/ 既存 scripts（`<plugin_root>/scripts/team-*.sh`）は 3 コマンドからも同一インターフェースで呼び出される
- 段階移行期間中は `/iterate-team`（単一コマンド）と `/iterate-plan` → `/iterate-build` → `/iterate-review`（3 コマンド分割）のどちらの運用スタイルも選択可能

### 未解消の論点

本章の実装スコープ外として後続検討に委ねる項目:

- **`/iterate-team-chain` シンタックスシュガー**: 3 コマンドを自動連続実行するラッパーコマンドの設計（ユーザが手動で `--session` を引き継ぐ手間を省く。実装優先度・インタフェース設計は次イテレーションで検討）
- **`--session` 引数の `team_` prefix 必須化**: 形式バリデーション（`^[A-Za-z0-9][A-Za-z0-9._-]*$` + `..` 拒否）は `<plugin_root>/scripts/iterate-validate-session.sh` で実装済みだが、`team_` prefix の強制は同スクリプトの実装詳細で決定する（exit 2 形式不正ケースの拡張余地）
- **in-memory 状態の checkpoint 永続化粒度の精緻化**: 既存 `/iterate-team` でも一部のみ permanent 化されており現状踏襲だが、3 コマンド分割により resume 境界が増えるため精緻化の優先度が上がる

---

## Orchestrator 手順詳細

> 以下は `<plugin_root>/commands/iterate-team.md` の圧縮に伴い移送した team 固有の Orchestrator 手順詳細。共通章は `harness-common.md` を参照。

### ステップ 0: 環境ガード（preflight）

正規 session-id 発行前に **preflight session-id** を発行し、本ステップで使う runlog の宛先を確保する:

- `<preflight-session-id>` = `team_<YYYYMMDDHHmm>_preflight`
- `Bash` で `mkdir -p .iterate-team/state/<preflight-session-id>` を実行
- 以降のガード判定で `<plugin_root>/scripts/runlog-append.sh "<preflight-session-id>" <event> '<payload>'` 経由で runlog 追記

#### 0.0 セッション初期化結果の取得（SessionStart hook 参照）

SessionStart hook が注入した `<session-init init_path="..." is_dev_container="..." mcp_profile="..." model="..." />` タグを context 先頭付近から取得する。**存在しない**場合は以下を返して処理中止:

```
[iterate-team] SessionStart hook が未実行または失敗しています（session-init コンテキスト不在）。
セッションを再起動するか、`bash <plugin_root>/scripts/session-start.sh < /dev/null` で hook の挙動を手元で確認し、
`<plugin_root>/operations/session-start-hook.md` の失敗モード表に従って復旧してください。
```

`<session-init>` の `init_path` を `Read` で開き、init.json の `is_dev_container` / `mcp_profile` / `model` / `model_warning` を **in-memory フラグ**として保持する。**Bash で `CLAUDE_CONFIG_DIR` を再判定しない**（hook で既に確定済み）。

runlog 追記: `runtime_detected` / `{is_dev_container, mcp_profile}`（`--model` 厳密パターン検出時のみ `model_override` キーを付与）

> **判定根拠**: SessionStart hook 側で `CLAUDE_CONFIG_DIR == /home/node/.claude` マーカーを評価済み。**本フラグは Codex MCP tool の可用性判定としても流用**（`<is_dev_container>=true` → Codex 利用可、`<is_dev_container>=false` → Codex 不可・フォールバック経路）。

#### 0.1 origin/main の fetch + 作業ブランチ bootstrap

1. **経路判定**: `--resume-checkpoint <session-id>` 引数の有無で 2 経路に分岐する

2. **`--resume-checkpoint <session-id>` 経路**: 既存ブランチを再利用する経路では fetch / bootstrap 処理を **すべて skip**（既に正式名にリネーム済みの統合ブランチを HEAD に持つ前提、ネットワーク不要、rename も skip）。HEAD 整合検証 (c) が `step_checkpoint` payload に依存するため、**payload 復元をステップ 1.3 から本ステップ冒頭へ前倒しする**（順序保証: payload 未復元のまま (c) を評価すると `integration_branch` キーを参照できず、誤った `claude/*` ブランチで resume するケースを検出できない）。手順:
   - **(0) checkpoint payload の先行復元**: `<session-id>` バリデーション `[A-Za-z0-9._-]+` → `Bash test -f .iterate-team/state/<session-id>/runlog.jsonl` で存在確認 → `Bash tail -n 200 .iterate-team/state/<session-id>/runlog.jsonl | jq -c 'select(.event=="step_checkpoint")' | tail -n 1` で最終 checkpoint event を取得し payload を in-memory 変数 `<step_checkpoint_payload>` へ復元。いずれかが失敗した場合は処理中止（無効 session-id / runlog 不在 / checkpoint 未生成 は resume 不能）。**本処理はステップ 1.3 と等価で、復元済みフラグを立てて 1.3 側で重複読み込みを skip する**（冪等化）

   - 以下の **HEAD 整合検証** を 3 段階で順に実行する（resume 対象が既存 `claude/*` 統合ブランチである前提を守るため。任意ブランチ上で resume すると後続の worktree base / push / PR head が誤ったブランチに着地する）:

   - **(a) main/master ガード**: `Bash git symbolic-ref --short HEAD` の値が `main` / `master` の場合は `head_is_protected` 追記後、以下を返して処理中止:

     ```
     [iterate-team] --resume-checkpoint 経路で main / master 上に居ます。
     resume 対象の作業ブランチ（claude/*）に checkout してから再実行してください。
     ```

   - **(b) `claude/` 接頭辞ガード**: `<head>` が `claude/` で始まらない場合は `head_not_claude_prefix` / `{head: <head>}` 追記後、以下を返して処理中止（`feature/foo` 等の任意ブランチで resume する誤操作を遮断）:

     ```
     [iterate-team] --resume-checkpoint 経路は claude/* 統合ブランチ上のみ実行可能です。
     現在のブランチ <head> は resume 対象ではありません。正しい claude/* ブランチに
     checkout してから再実行してください。
     ```

   - **(c) checkpoint payload 一致検証**: 本ステップ (0) で復元した `<step_checkpoint_payload>` に `integration_branch` キーが存在する場合、`<head> == <step_checkpoint_payload>.integration_branch` であることを検証。不一致なら `head_branch_mismatch_on_resume` / `{head: <head>, checkpoint_integration_branch: <value>}` 追記後、以下を返して処理中止（別の `claude/*` ブランチで resume するケースを遮断）:

     ```
     [iterate-team] --resume-checkpoint で記録された integration_branch
     <checkpoint_integration_branch> と現在の HEAD <head> が一致しません。
     正しいブランチに checkout してから再実行してください。
     ```

     `integration_branch` キーが payload に存在しない場合（旧 checkpoint との互換性）は (b) の `claude/` 接頭辞検証のみで通過とする。

   通過時は `<integration-branch>` = HEAD を in-memory 保持して 0.2 へ進む

3. **新規起動経路**（HEAD 保護チェックは **skip** — 最も一般的な「`main` を clean にして `/iterate-team` を開始」経路を許可するため。後続の `git switch -c` で `claude/*-pending` へ即座に離れ、`<from_branch>` 上での誤コミットは構造的に発生しない。3.0〜3.6 を順に実行）:
   - **3.0 `<from_branch>` の解決と検証**: 派生元ブランチを決める。`--from-branch <branch>` が指定されていればその値、未指定なら既定 `main` を `<from_branch>` とする。`<branch>` は `^[A-Za-z0-9][A-Za-z0-9._/-]*$` に一致し `..` を含まないこと（引数注入 / パストラバーサル防止）。形式不一致なら `from_branch_invalid` / `{from_branch: <branch>}` 追記後、以下を返して処理中止:

     ```
     [iterate-team] --from-branch に指定されたブランチ名 <branch> が不正です。
     使用可能文字は英数字・. _ / - で、先頭は英数字・`..` 不可です。
     ```

   - **3.1 fetch 実行**: `Bash git fetch origin <from_branch>` を実行（origin の最新を取り込む）。**host 環境で `<from_branch>` が `main` 以外の場合、`.claude/settings.json` の allowlist（`Bash(git fetch origin main)`）未一致のため permission prompt が 1 回出る**（既定 `main` は無プロンプト / dev container は `bypassPermissions` で無プロンプト）。exit code != 0 の場合は `fetch_failed` / `{from_branch}` 追記後、以下を返して処理中止:

     ```
     [iterate-team] origin/<from_branch> の fetch に失敗しました（ネットワーク / 認証エラー、
     またはブランチ不在）。ブランチ名と接続性を確認してから再試行してください。
     ```

   - **3.2 派生元ブランチ存在確認**: `Bash git rev-parse --verify "origin/<from_branch>"`。失敗時は `from_branch_missing` / `{from_branch}` 追記後、以下を返して処理中止（指定ブランチが remote に存在しない）:

     ```
     [iterate-team] origin/<from_branch> が見つかりません。--from-branch の指定を確認してください。
     ```

   - **3.3 working tree クリーン性確認**: `Bash git status --porcelain` の出力が空であること。非空なら `dirty_worktree` 追記後、以下を返して処理中止。**起動ブランチ上での誤コミットを保護する実体は本 dirty check と直後の `git switch -c` であり、HEAD 名前ガードに依存しない**（dirty な起動ブランチなら本 check で abort、clean なら直後の `git switch -c` で `claude/*-pending` に離れる）:

     ```
     [iterate-team] working tree に未コミット差分があります。/iterate-team は origin/<from_branch> から
     placeholder ブランチを作成して動作するため、差分が誤って取り込まれます。git stash または
     必要なコミットを発行してから再実行してください。
     ```

   - **3.4 placeholder ブランチ名の確定**: `<integration-branch>` = `claude/iterate-team-<YYYYMMDDHHmm>-pending`（`<YYYYMMDDHHmm>` は `date +%Y%m%d%H%M`）。`Bash git rev-parse --verify "<integration-branch>"` が成功する場合は分単位の重複として `<YYYYMMDDHHmm>` を後置に `-<N>` を付加（N=2..5）して再試行。5 回試行しても空きが見つからない場合は `branch_name_conflict` 追記後ステップ 9（疑似 task-id `branch-bootstrap`）

   - **3.5 placeholder ブランチ作成**: `Bash git switch -c "<integration-branch>" "origin/<from_branch>"` を実行（`origin/<from_branch>` から新規ブランチを切ってチェックアウト）。**この瞬間以降 HEAD は `claude/*` で起動ブランチからは構造的に離れる**。失敗時は `branch_create_failed` / `{stderr}` 追記後処理中止

   - **3.6 runlog 追記**: `integration_branch_created` / `{branch: "<integration-branch>", base:"origin/<from_branch>", from_branch:"<from_branch>", sha: "<git rev-parse HEAD の結果>", pre_switch_head: "<元 HEAD 名>"}`（監査用に切替前 HEAD 名と派生元ブランチも記録）。`<from_branch>` は in-memory 保持し、ステップ 4 checkpoint payload・4.5.A.3 の PR base に使用する

> **rename 経路への引き継ぎ**: 新規起動経路（3）で作成した placeholder ブランチは、ステップ 3.x（パターン B 内）で `claude/<topic-slug>` にリネームされる。rename を経て初めて正式名となり、その後の Planner 出力コミット / worktree base / push / PR head として使用される。`--resume-checkpoint` 経路（2）では fetch / bootstrap / rename をすべて skip し、既存ブランチをそのまま使う。
> **fetch を resume で skip する理由**: `--resume-checkpoint` は中断セッションを引き継ぐ用途であり、network 不通環境でも再開可能であるべき。新規起動経路のみが fetch コストを払う設計とする。

#### 0.2 モデル判定（確認プロンプト方式）

`$ARGUMENTS` 先頭または `--resume <path>` / `--resume-checkpoint <session-id>` 直後に `--model <id>` が出現し、`<id>` が `[A-Za-z0-9._-]+` に一致する非空トークンの場合に限り、本ステップ全体を skip（ユーザ明示指定）。要望文の途中に `--model` 文字列が含まれるだけのケースでは skip しない。

`--model` 指定なしの場合、ステップ 0.0 で取得済みの `<session-init>` の `model` フィールドを分岐:

- `model` が `*sonnet*` パターンに一致、または `model == "unknown"`（CLI バージョンによってはモデル情報が hook 入力 JSON に含まれない）の場合: サイレント通過。runlog `model_check_passed` / `{model}` 追記
- 上記以外（`*opus*` / `*haiku*` / `claude-*` 一般）の場合: `AskUserQuestion` で以下を表示
  - 質問: 「現在のモデル `<model>` のままで `/iterate-team` を実行しますか？（ハーネスは Sonnet 系で検証されています。Opus / Haiku 等での挙動は未保証）」
  - 選択肢:
    - `続行` — そのまま処理続行。runlog `model_confirmed` / `{model}` 追記
    - `中止` — 処理中止。runlog `model_aborted_by_user` / `{model}` 追記後、Usage メッセージ（`/model sonnet` 切替か `--model <id>` 明示指定の案内）を返して終了

> **設計意図**: 旧設計では Opus 系を検出すると即 abort していたが、(a) `model="unknown"` の CLI ではガードが効かず、(b) Opus / Haiku でも実行を試したいケースがあるため、ガードを「即 abort」から「ユーザ確認」へ緩和。`--model` 指定の明示経路はそのまま skip（ユーザが明示的に承知している前提）。

### ステップ 2.5: 要件壁打ち（team-interviewer ループ）

`Agent` ツールで `subagent_type: team-interviewer` を起動し続け、戻り値 JSON フェンスの `type` で分岐:

- `type=ask`: `questions` を `AskUserQuestion` に中継 → 回答を `responses/interview-round-<N>.md` に Write → team-interviewer 再起動（累計 3 ラウンドで「次回は必ず `type=paused`」を明示）
- `type=done`: `summary_path` 存在確認後、ステップ 3 へ
- `type=paused`: `resume_path` 存在確認後、resume コマンドを案内して終了
- それ以外: ステップ 9

詳細仕様（runlog payload・必須フィールド）は subagent 名と session-id prefix が team 固有。

### ステップ 3: Planner 起動と研究ループ

`Agent` ツールで `subagent_type: team-planner` を起動。戻り値 JSON フェンスで:

- **パターン A**: type が `research` / `debug` / `trace` / `interview`。**1 戻り値で複数 research/debug/trace request を同時発行可能**（min(N, 4) で並列 Agent 起動、超過分はチャンク分割）。Planner 委譲累計は発行件数分インクリメント
- **パターン B**: `plan.json` 検証 → `Bash <plugin_root>/scripts/team-validate-plan.sh <plan-json-path> <tasks-dir>` 実行（validate-plan + compute-waves サイクル/不明依存検出が併走）→ 仮 session-id を正式名へリネーム → **integration-branch を `claude/<topic-slug>` へ rename**（後述 3.x、placeholder bootstrap 経路のみ）→ runlog `plan_ready` → **Planner 出力コミット発行**（共通章と同等手順、`plan_revision` 管理 + フッタ `Refs: plan-<topic-slug>`）→ ステップ 3.5 へ

#### 3.x integration-branch の rename（パターン B 内、placeholder bootstrap 経路のみ）

ステップ 0.1 の「5. 新規起動経路」で placeholder ブランチ `claude/iterate-team-<YYYYMMDDHHmm>-pending`（または重複時の `-pending-N`）を作成した経路でのみ、Planner 出力コミット発行 **前** に正式名 `claude/<topic-slug>` へ rename する。

1. `<integration-branch>` が `^claude/iterate-team-[0-9]+-pending(-[0-9]+)?$` に一致するかを確認。一致しない場合（`--resume-checkpoint` で既存ブランチ継承経路）は本ステップ全体を skip
2. 目標名: `<target-branch>` = `claude/<topic-slug>`
3. `Bash git rev-parse --verify "<target-branch>"` が成功する場合は `branch_rename_conflict` / `{from, to}` 追記後ステップ 9（疑似 task-id `branch-bootstrap`、衝突回避のため上書き禁止）
4. `Bash git symbolic-ref --short HEAD` で現 HEAD が `<integration-branch>` と一致することを確認。不一致なら `head_branch_mismatch_before_rename` 追記後ステップ 9
5. `Bash git branch -m "<integration-branch>" "<target-branch>"` を実行。失敗時は `branch_rename_failed` / `{stderr}` 追記後ステップ 9
6. in-memory `<integration-branch>` を `<target-branch>` に更新（以降の worktree base / push / PR head すべてに反映）
7. runlog 追記: `integration_branch_renamed` / `{from, to, sha}`
8. Planner 出力コミット発行へ進む（コミットは新ブランチ名上で積まれる）

### ステップ 3.5: 計画レビュー（Codex 経路 / フォールバック経路）

#### 3.5.A 分岐判定

- `<is_dev_container>=true`: 3.5.B / 3.5.C 経路（Codex MCP tool）
- `<is_dev_container>=false`: 3.5.D / 3.5.E 経路（`team-reviewer-plan` Agent フォールバック）

`plan_review_round` カウンタは両経路で共通。**初期化タイミングは「ステップ 3.5 入口（= `/iterate-team` 起動時）」と「ステップ 4 修正フロー起動時（`plan_review_round = 0` リセット）」の 2 箇所のみ**。自動修正ループ内（REQUEST_CHANGES → 3.2 パターン B 再走行 → 3.5 再入）では **値を引き継ぐ**（再入のたびに 0 リセットすると上限到達せず無限ループする）。

`--resume-checkpoint` で 3.5 に戻る場合は `step_checkpoint` payload の `plan_review_round` キーから値を復元し、in-memory の 0 初期化で上書きしない（上限判定を継続するため。payload に `plan_review_round` キーが無い旧 checkpoint との互換では 0 として扱う）。

各ステップ完了後の `step_checkpoint` には `plan_review_round: <int>` を含める（REQUEST_CHANGES インクリメント直後の mid-loop checkpoint も含む）。

#### 3.5.B Codex 経路: tool 呼び出し（dev container のみ）

`mcp__codex__codex`（`sandbox: read-only` 固定 / `approval-policy: never` / `cwd: <project-dir>`（対象リポジトリルート）/ `model: "gpt-5.4"` 固定）。prompt は Orchestrator が self-contained で組み立てる（コードレビュー Codex 経路 5.3.2-A と同じスタイル）。developer-instructions には次を要求する: (1) `<plugin_root>/agents/team-reviewer-plan.md` と**同等の 24 観点チェックリスト**で計画整合性を read-only 検収（コード変更禁止）、(2) `## status: APPROVED|REQUEST_CHANGES` 単一行ガード、(3) 重要度語彙 `blocker`/`high`/`medium`/`low`、各 finding に `ファイル:行 / タスクid` + 具体根拠、(4) 入力として `<summary-path>` / `<plan-summary-path>` / `<plan-path>` / `<plan-json-path>` / `<task-md-paths>`（カンマ区切り絶対パス）/ `<plan_revision>` / `<plan_review_round>` を穴埋め。修正稿レビューは毎回新規 thread。

直前に runlog `codex_plan_review_started` + `agent_decision codex-plan-review invoked` 追記。応答を `responses/codex-plan-review-rev-<plan_revision>.md` に Write。

#### 3.5.C Codex 経路: REQUEST_CHANGES 時の Planner 自動再起動

`plan_review_round += 1`。

**上限判定を mid-loop checkpoint より先に行う（順序厳守）**: `plan_review_round >= 3` なら `codex_plan_review_escalated` 追記後、疑似 task-id `plan-review` でステップ 9（エスカレーションメッセージ: `plan_review_max_rounds_exceeded: plan_review_round=3 に達したため自動修正を中止。手動で計画を修正してください。`）。**このとき `3.5-replan` の mid-loop checkpoint は書かない**（書いた直後にクラッシュすると resume が `next_step="3.5-replan"` から上限判定を経ずに team-planner を再起動し、ループストッパーが resume 経路だけ破られる。ステップ 9 への遷移は自身の checkpoint を書く）。

`plan_review_round < 3` の場合のみ、以下の mid-loop checkpoint 追記と team-planner 再起動を行う。

**mid-loop checkpoint（必須）**: インクリメント直後・team-planner 再起動前に以下の `step_checkpoint` を 1 件追記する（クラッシュ / resume 時にインクリメント済み値が永続化されていないと上限判定が緩む）:

```bash
<plugin_root>/scripts/runlog-append.sh "<session-id>" step_checkpoint '{"step":"3.5","topic_slug":"<topic-slug>","plan_revision":<rev>,"integration_branch":"<integration-branch>","plan_review_round":<incremented_value>,"current_task_id":null,"current_attempt":null,"wave_index":null,"advisor_pending":false,"next_step":"3.5-replan"}'
```

mid-loop checkpoint の `next_step` は **`"3.5-replan"`（= REQUEST_CHANGES 後続の team-planner 自動再起動）を指す**。`"3.5"` を指すと、resume 時に未修正 plan を再レビューして `plan_review_round` だけを消費し、最悪 `plan_review_max_rounds_exceeded` に達して自動修正が実行されないため不可。`--resume-checkpoint` で `next_step="3.5-replan"` に復帰した場合は、**まず復元済み `plan_review_round >= 3` を再判定し（checkpoint 書き込みと escalation の競合・破損に対する保険。上限到達直後のクラッシュでも resume 経路が上限判定を必ず通過する）、`>= 3` なら上記エスカレーション（ステップ 9）へ遷移**する。`< 3` の場合のみ、increment（`+= 1`）と mid-loop checkpoint 追記を再実行せず（インクリメント済み値は payload の `plan_review_round` から復元）、永続済みレビュー応答（Codex 経路は `responses/codex-plan-review-rev-<plan_revision>.md`、フォールバック経路は `responses/plan-review-rev-<plan_revision>.md`。経路は再開時の `<is_dev_container>` 再判定で決まる）を入力に team-planner を自動再起動 → ステップ 3.2 パターン B 再走行 → 3.5 再レビューへ進む。

team-planner 自動再起動（プロンプトには絶対パスのみ。Findings 全文を context に載せない不変条件）→ ステップ 3.2 パターン B 再走行（3.5.A の初期化はスキップ）。

#### 3.5.D フォールバック経路: `team-reviewer-plan` Agent 起動（host のみ）

`Agent` で `subagent_type: team-reviewer-plan` を起動。7 入力（`<summary-path>` / `<plan-summary-path>` / `<plan-path>` / `<plan-json-path>` / `<task-md-paths>` カンマ区切り絶対パス / `<plan_revision>` / `<plan_review_round>`）を必須で渡す。

戻り値テキスト全文を `responses/plan-review-rev-<plan_revision>.md` に Write（Codex 経路の `codex-plan-review-rev-<N>.md` と命名で区別）。

#### 3.5.E フォールバック経路: REQUEST_CHANGES 時の Planner 自動再起動

`plan_review_round += 1`。

**上限判定を mid-loop checkpoint より先に行う（3.5.C と同順序）**: `plan_review_round >= 3` なら `plan_review_escalated` 追記後、疑似 task-id `plan-review` でステップ 9（エスカレーションメッセージ: `plan_review_max_rounds_exceeded: plan_review_round=3 に達したため自動修正を中止。手動で計画を修正してください。`）。**このとき `3.5-replan` の mid-loop checkpoint は書かない**（resume 経路で上限判定を回避させないため。3.5.C 参照）。

`plan_review_round < 3` の場合のみ、**mid-loop checkpoint（必須）** を 3.5.C と同様に追記し（`next_step="3.5-replan"` / `plan_review_round: <incremented_value>` 含む。`3.5-replan` resume 時の `>= 3` 再判定保険も同じ）、team-planner 自動再起動（`<plan-review-response-path>` のパスのみ渡す。Findings 全文を context に載せない）→ 3.2 パターン B 再走行。

#### 両経路共通: status 抽出

`grep -cE '^## status: (APPROVED|REQUEST_CHANGES)$' <response-path>` で `N` 取得。`N != 1` は契約違反として `codex_plan_review_invalid_format` または `plan_review_invalid_format` 追記後ステップ 9。`N == 1` のとき `grep -m1 -oE '(APPROVED|REQUEST_CHANGES)'` で値取得 → `codex_plan_review_completed` または `plan_review_completed` 追記。

`APPROVED` はステップ 4 へ。`REQUEST_CHANGES` は経路別の Planner 再起動ロジック（3.5.C または 3.5.E）へ。

### ステップ 4.5: 承認（環境分岐・承認は通算 1 回）

**承認は env ごとに 1 回だけ行う**（二重承認は廃止）。ステップ 4 と本ステップのどちらで承認するかは `<is_dev_container>` で決まる:

- `<is_dev_container>=false`（host/Web）: ステップ 4 は **提示のみ**（`plan_approved=false`）。本ステップ 4.5.A で Draft PR 作成後に **唯一の承認**を取得する。
- `<is_dev_container>=true`（dev container）: ステップ 4 で **承認済み**（`plan_approved=true`）。Draft PR は作成できないため、本ステップ 4.5.B では **承認を求めず** push/PR を skip して即 wave へ進む。

`step_checkpoint` の `plan_approved` を参照し、`true` の場合は 4.5 で二次承認を **行わない**こと（dev container 経路）。`false` の場合のみ 4.5.A で承認する（host 経路）。

#### 4.5.A host / Web 版: Draft PR 作成と承認（唯一の承認）

1. **4.5.A.1 plan ファイル群の push**: `Agent subagent_type: team-publisher` を operation `push_branch`、phase `pre_implementation` で起動。team-publisher は owner/repo 一致 / branch 名検証 / 保護ブランチ拒否 / HEAD 一致を検証後 `<plugin_root>/scripts/team-push-branch.sh <branch>` ラッパー実行。push 失敗時はステップ 9。runlog: `branch_pushed` / `{branch, sha, phase: "pre_implementation"}`
2. **4.5.A.2 PR body 生成**: `Bash <plugin_root>/scripts/team-compute-waves.sh <plan-json-path> | wc -l` で wave 数先行算出（`<wave_count>`）。`waves.jsonl` 本体はステップ 5.0 で書き出す。body に plan-summary 全文 + 並列実行計画（wave 数 / 最大並列度 4 / worktree 配置）+ session-id / 起動コマンド / runlog パス / チェックリストを埋め込む
3. **4.5.A.3 Draft PR 作成（初回起動時のみ）**: `<pr-number>` 未保持時、Orchestrator が実行環境で利用可能な手段で `head: <integration-branch>` / `base: <from_branch>`（既定 `main`。`--from-branch` 指定時はその派生元ブランチへマージする自然な挙動）/ `title: [iterate-team] <topic-slug>` / `body: 4.5.A.2 内容` / `draft: true` で作成。`<pr-number>` / `<pr-url>` を保持。runlog: `pr_created` / `{base: "<from_branch>"}`。**`<from_branch>` は保護ブランチ拒否（team-publisher）の対象外**（push 先は `<integration-branch>=claude/*` であり、base は PR のマージ先指定にすぎず push されない）
4. **4.5.A.4 修正フロー再走行時の PR 再利用**: `<pr-number>` 保持済みなら、(a) 修正後コミットを `push_branch` で remote 追加 push（force 不要）→ (b) 新 PR body 再生成 → (c) 同一 PR の本文を更新。runlog: `pr_body_updated`
5. **4.5.A.5 承認（host 経路の唯一の承認）**: `AskUserQuestion` で「Draft PR を作成しました（`<pr-url>`）。この計画で実装着手して良いですか？」（選択肢: `承認` / `却下`（PR は draft のまま残す）/ `修正`（`/iterate-plan --resume-checkpoint <session-id>` で計画フェーズへ戻る））。runlog: `pr_approved` または `pr_rejected`

#### 4.5.B dev container: 承認 skip（ステップ 4 で承認済み）

push / PR 作成は **すべて skip**（read-only Deploy Key + ssh-agent forwarding 設計維持）。**ステップ 4 で既に承認済み（`plan_approved=true`）のため、ここでは二次承認を行わずそのまま wave へ進む**（承認は通算 1 回）。

1. runlog: `pr_flow_skipped` / `{reason:"dev_container", phase:"pre_implementation"}` + `agent_decision team-publisher skipped`
2. `step_checkpoint` の `plan_approved` が `true` であることを確認し（`false` なら整合エラーとしてステップ 9 へ）、追加の `AskUserQuestion` は **出さず** ステップ 5 へ直行する。runlog: `plan_already_approved` / `{approved_at:"step4"}`

### ステップ 5: wave 並列タスクループ

承認後、`Bash <plugin_root>/scripts/team-compute-waves.sh <plan-json-path> > .iterate-team/state/<session-id>/waves.jsonl` で wave を取得。各 wave を順次処理（**wave 内は並列、wave 間は順次**）:

#### 5.0 wave 起動

`waves.jsonl` を 1 行ずつ読み、当該 wave の `tasks` 配列を取り出す。runlog: `wave_started` / `{wave, task_ids}`

- **5.0.1 worktree 作成（並列）**: 各タスクで `Bash <plugin_root>/scripts/team-worktree-setup.sh <session-id> <task-id> <integration-branch>` を `team_max_parallel = 4` 件まで並列実行。出力パスを `<worktree-path>[<task-id>]` で保持。runlog: `worktree_created` per task
- **5.0.2 Generator フェーズ A 並列起動**: 全タスクで `Agent subagent_type: team-generator` を 1 メッセージ内で並列起動（min(N, 4)、超過時チャンク分割）。プロンプト 7 キー（task 絶対パス / session-id / state-root / requests 出力先 / worktree-path / integration-branch / task-branch）**+ `<tdd_enabled>`** を渡す。**初回起動から `<tdd_enabled>` を渡す理由**: `required_advisors: []` のコード変更タスクは 5.1 の advisor 再起動経路（`<tdd_enabled>` 付与）を通らないため、初回起動で渡さないと generator がフェーズ A 消化後に「テストファースト準備 OK シグナル」（5.2 項番 3）を返せず通常実装へ進んでしまい、TDD ゲートが効かない。generator base（`team-generator.md` フェーズ A: `tdd_enabled=true` かつ `<test_files>` 未受領なら実装に進まず復帰）はこのシグナルを前提とする。`<tdd_enabled[<task-id>]>` = `(plan.json / frontmatter の reviewer == "codex")` を wave 開始時に算出して保持する
- **5.0.3 `<pre_phase_b_head_<task-id>>` 初期化**: フェーズ A 完了後、フェーズ B として再起動する直前に各 task の worktree で `Bash git -C <worktree-path> rev-parse HEAD` を取得し `<pre_phase_b_head_<task-id>>` に保存（5.2 の HEAD 進捗判定の基準値）

> **更新タイミング**: `<pre_phase_b_head_<task-id>>` は **Phase B を起動するすべての経路** で取り直す必要がある（5.0.3 初回 Phase B 起動 / 5.1.7 フェーズ A 完了後の Phase B 再起動 / 5.4 NG retry での Phase B 再起動）。1 回だけの取得では NG retry 経路で前 attempt commit を「今回 attempt の進捗」と誤判定する。

#### 5.1 フェーズ A 戻り値処理（advisor 並列収集）

team-generator の戻り値で advisor 一括発行があったタスクを `Glob <state-root>/requests/*.json` で識別（`processed/` 除外、request*id 接頭辞 `\*\_team_generator*<task-id>\_\*` でフィルタ）。

検出された全 request 合算 `M` 件について:

1. 各 request file を `Read` し必須フィールド検証
2. runlog `advisor_requested` per request + `agent_decision team-advisor-<name> invoked`
3. **1 メッセージ内に M 個の Agent 並列起動**（subagent_type: team-advisor-<advisor>、min(M, 4) でチャンク分割）
4. 各応答を `responses/<request-id>.md` に Write
5. **処理済み request 移動**: `Bash mv requests/<request-id>.json requests/processed/` per request
6. runlog: `advisor_batch_completed` per task
7. **`<pre_phase_b_head_<task-id>>` 更新**: 当該 worktree で `Bash git -C <worktree-path> rev-parse HEAD` を取得し `<pre_phase_b_head_<task-id>>` を上書き保存（attempt 境界を取り直すため、Phase B 再起動経路でも必須）
8. 当該タスクの team-generator を **フェーズ B として再起動**（プロンプトに 5.0.2 のキー + 応答パス群 + `<tdd_enabled>` を渡す）。`tdd_enabled[<task-id>]=true` のタスクでは generator が「テストファースト準備 OK シグナル」（request 0 件 + HEAD 不変 + `<test_files>` 未送）で戻るため、5.2 の判定でそれを検出して 5.1.5（test-coder）へ回す

#### 5.1.5 test-coder 起動（Red、TDD タスクのみ）

`tdd_enabled[<task-id>]=true` かつ 5.2 でテストファースト準備 OK シグナルを検出した場合に実行する。

1. runlog `agent_decision team-test-coder invoked` / 「TDD: Red 先行」
2. `Agent subagent_type: team-test-coder`（プロンプト: 5.0.2 の 7 キー + advisor 応答パス群 + `<tdd_enabled>`）を起動
3. 戻り値で分岐:
   - **Red コミット完了**（テストファイルパス群を受領）: `<test_files[<task-id>]>` に保持 → runlog `test_first_red_committed` / `{task_id, test_files, fail_count}` → `<pre_phase_b_head_<task-id>>` を `Bash git -C <worktree-path> rev-parse HEAD`（= test コミット sha）で更新 → team-generator を **フェーズ B（Green 実装）として再起動**（7 キー + advisor 応答 + `tdd_enabled` + `<test_files>`）
   - **`テスト対象なし (no-op)`**: `tdd_enabled[<task-id>]=false` に降格 → runlog `test_first_skipped` / `agent_decision team-test-coder skipped` → 通常フェーズ B 再起動（`<test_files>` なし）
4. test-coder のコミットも pre-commit（`tsc --noEmit` / lint-staged）を通過している前提（Red は型が通りアサーションのみ失敗、`tdd-policy.md`）

#### 5.2 フェーズ B 戻り値処理（実装完了確認）

> **前提**: `<pre_phase_b_head_<task-id>>` は **Phase B を起動するすべての経路の直前** で `Bash git -C <worktree-path> rev-parse HEAD` を取得し Orchestrator 側で in-memory 保持しておく。更新タイミング: ステップ 5.0.3 初回 Phase B 起動直前 / ステップ 5.1.7 フェーズ A 完了後の Phase B 再起動直前 / ステップ 5.4 NG retry での Phase B 再起動直前。1 回だけの取得では NG retry 経路で前 attempt commit を「今回 attempt の進捗」と誤判定する。

判定は以下の順序で実施する（**順序遵守が必須** — 順序が逆だと worktree 再利用時に Refs 検出が先行して新規 request が見落とされる）:

1. **`Glob <state-root>/requests/*_team_generator_<task-id>_*.json`（`processed/` 除外、glob パターン内に当該 `<task-id>` を必ず含める）を最優先で確認**
   - **自タスク限定の理由**: wave 内で複数 task の Phase B が並列に戻る構成のため、`*.json` で共有 state-root 全体を見ると、task A が正常に commit 済みでも task B の未処理 advisor request が残っているだけで task A まで「フェーズ B 中 advisor トリガー発火」と誤判定し、task A の 5.3 検収レビューを skip して別 task の request 処理へ合流してしまう。Phase A request (`<yyyyMMddHHmmss>_team_generator_<task-id>_<advisor>.json`) と Phase B request (`<yyyyMMddHHmmss>_team_generator_<task-id>_<advisor>_<trigger_id>.json`) のいずれも `<task-id>` をファイル名に含むため、glob 段階で確実に絞り込める
   - **当該タスクの新規 request が 1 件以上**: HEAD / `Refs` の状態に関わらず team-generator がフェーズ B 中 advisor トリガーを発火させた経路（コミット未発行・worktree 内に未コミット差分残存。同じ worktree に前 attempt commit がある場合でも該当）として扱う。**5.1 フェーズ A 戻り値処理（advisor 並列招集）へ合流**し、advisor 起動 → 応答 Write → request を `processed/` へ移動 → 当該 team-generator をフェーズ B として再起動（同じ worktree、残った未コミット差分は次回フェーズ B で続行）
2. **HEAD 進捗 + Refs 検出**: `Bash git -C <worktree-path> rev-parse HEAD` で現在 sha を取得し `<pre_phase_b_head_<task-id>>` と比較する
   - **HEAD が進んだ場合**（`!=`）かつ `Bash git -C <worktree-path> log -1 --format="%H%n%B"` の `%B` にフッタ `Refs: <task-id>` を `grep` で検出: 通常パス（今回 attempt で実装完了）。`tdd_enabled[<task-id>]=true` なら **5.2.5（refactor）へ**、`false` なら 5.3 検収レビューへ。`%s` (subject) では検出できないので `%B`（本文全体）必須
3. **テストファースト準備 OK シグナル（TDD）**: `tdd_enabled[<task-id>]=true` かつ `HEAD == <pre_phase_b_head_<task-id>>`（不変）+ 新規 request 0 件 + `<test_files[<task-id>]>` 未送の場合は、**異常ではなく** generator がフェーズ A 消化後に実装手前で正常復帰したシグナルとして扱い、**5.1.5（test-coder 起動）へ**。test-coder 実行後に再びこの状態に戻ること（test_files 受領済み）は無く、受領後は generator が impl コミットを発行するため項番 2 で捕捉される
4. **テスト不備差し戻しシグナル（TDD / Green モード）**: `tdd_enabled[<task-id>]=true` かつ `HEAD == <pre_phase_b_head_<task-id>>`（不変）+ 新規 request 0 件 + **`<test_files>` 受領済み（= Green モード）** かつ `Glob <state-root>/responses/test-defect-<task-id>-attempt-*.md` で当該 attempt のテスト不備レポートを検出した場合は、**異常ではなく** generator がテスト不備を検出して差し戻しを依頼したシグナルとして扱い、**5.2.6（test-coder 差し戻し）へ**
5. **異常**: 上記いずれにも該当しない場合は通常の失敗扱い（5.4 NG 経路）
   - 例 1: `HEAD == <pre_phase_b_head_<task-id>>` + 新規 request 0 件 + （非 TDD または test_files 受領済み）かつ **テスト不備レポートなし** → generator が commit も request もレポートも発行せず終了（異常）
   - 例 2: HEAD は進んだが `Refs: <task-id>` 未検出 → コミット規約違反

#### 5.2.5 refactor 起動（TDD タスクのみ）

`tdd_enabled[<task-id>]=true` のタスクで impl コミット（項番 2）を検出した直後に実行する。

1. runlog `agent_decision team-refactor invoked` / 「TDD: refactor」
2. `Agent subagent_type: team-refactor`（プロンプト: 5.0.2 の 7 キー + 直近 impl コミット sha + `<tdd_enabled>` + **`<test_files[<task-id>]>`**（5.1.5 で test-coder から受領・保持したテストファイルパス群））を起動。team-refactor は worktree 内で `Skill skill: simplify` → `Skill skill: code-review`（`--fix` 相当）を起動し、緑維持のまま動作不変の整理を行う。`<test_files>` を渡す理由: impl コミットは本番コードのみ変更するため `git show <impl-sha>` には先行 Red コミットのテストが現れず、緑確認（ベースライン / refactor 後）のテスト対象を team-refactor 側で確実に特定できない
3. 戻り値で分岐:
   - **リファクタ実施**（`refactor:` コミット sha 受領）: runlog `refactor_committed` / `{task_id, sha, applied_skills}` → 5.3 検収レビューへ（対象は refactor 後の最終 HEAD）
   - **リファクタ不要 (no-op)**: runlog `refactor_noop` / `{task_id}` → 5.3 検収レビューへ
   - **`refactor_failed`**（baseline not green / cannot keep green）: **fail closed**。runlog `refactor_failed` / `{task_id, reason}`。**差し戻し artifact 生成**: refactor の戻り値（理由 + 失敗の具体）から `<state-root>/responses/refactor-failed-<task-id>-attempt-N.md` を `Write`（generator の差し戻し再起動契約が要求する成果物。これが無いと generator が `restart_without_artifact` で停止する。`generator-failure-mode.md` 参照）→ **5.4 NG 経路**（`max_retries` 未満なら team-generator 再起動に **本 artifact パスを渡す**、到達ならステップ 9）。20260526 ADR 事項7 に準拠
4. NG リトライ（5.4）で再 green した場合も、再度 5.2.5 を実行してから 5.3 に入る

#### 5.2.6 test-coder 差し戻し（TDD タスク・テスト不備時）

`tdd_enabled[<task-id>]=true` の Green モードで generator がテスト不備レポート（`responses/test-defect-<task-id>-attempt-*.md`）を発行（5.2 項番 4）した場合に実行する。test-coder が誤った期待値・過剰に狭いアサーション等を Red コミットしていても、generator はテストを弱めず差し戻しに委ねる契約（`tdd-policy.md`）のため、本経路が無いと修正不能なテストを generator が緑化し続け `max_retries` まで詰まる。

1. **差し戻し回数ガード**: `test_remand_round[<task-id>]`（in-memory、初期 0）を確認。`team_max_test_remands`（既定 2）到達済みなら **fail closed** → 5.4 NG 経路（generator 再起動 or ステップ 9）。未満なら +1 してから続行。runlog `test_remand_round_incremented` / `{task_id, round}`
2. runlog `agent_decision team-test-coder invoked` / 「TDD: テスト差し戻し」
3. `Agent subagent_type: team-test-coder` を **差し戻しモード**で起動（プロンプト: 5.0.2 の 7 キー + advisor 応答パス群 + `<tdd_enabled>` + 既存 `<test_files[<task-id>]>` + `<test_defect_report>`（検出したレポートの絶対パス））
4. 戻り値で分岐:
   - **テスト是正コミット完了**（更新後テストファイルパス群を受領）: `<test_files[<task-id>]>` を更新保持 → 処理済みレポートを `Bash mkdir -p <state-root>/responses/processed && mv <state-root>/responses/test-defect-<task-id>-attempt-*.md <state-root>/responses/processed/`（**絶対パス必須**。Orchestrator は main worktree から実行するため相対 `responses/` は state-root を指さず `mv` が失敗する。残置すると次の 5.2 で同一シグナルを再検出して差し戻しループが進まない）→ `<pre_phase_b_head_<task-id>>` を是正コミット sha で更新 → team-generator を **フェーズ B（Green 実装）として再起動**（7 キー + advisor 応答 + `tdd_enabled` + 更新後 `<test_files>`）。runlog `test_remand_committed` / `{task_id, sha}`
   - **テスト不備なし (no-op)**（test-coder がテストは正しいと判断）: レポートを同様に `Bash mkdir -p <state-root>/responses/processed && mv <state-root>/responses/test-defect-<task-id>-attempt-*.md <state-root>/responses/processed/`（絶対パス必須・誤検出防止）で移動 → **差し戻しを打ち切り**、generator の通常 NG retry（5.4）へ。runlog `test_remand_rejected` / `agent_decision team-test-coder skipped`（generator は既存テストを緑にする impl 修正が必要）

> **戻り値文言は補助ヒントに留める**: team-generator の戻り値テンプレに `phase_b_advisor_request_issued` リテラルを含めるが、これは監査用の補助ヒントであり判定根拠ではない。判定は **request ファイル存在 + HEAD 進捗 + Refs 検出** の組合せで行う（ステップ 5.1 / 5.4 の「戻り値文言は補助ヒント扱い」原則と統一）。戻り値文字列フォーマット依存を排除することで、subagent 側の戻り値テンプレ変更に対する Orchestrator 側の脆弱性を構造的に解消する。

#### 5.3 検収レビュー（Evaluator 先行ゲート → APPROVED 後に Code Review）

> **設計（codex レート削減）**: 旧設計は Evaluator と Code Review（Codex / team-reviewer-code）を 1 メッセージで **同時起動**していたため、Evaluator が NG を返すケースでも Codex を必ず 1 回消費していた。本設計では **Evaluator を先に単独起動し、`APPROVED`（OK）のときだけ Code Review を起動する**。Evaluator NG 時は Code Review を呼ばずに 5.4 NG 経路へ直行し、Codex / team-reviewer-code の起動コストを節約する。wave 内の独立タスク間ではこの検収パイプライン（Evaluator→Code Review）が引き続き並列に進む（**逐次化されるのはタスク内の Evaluator と Code Review の関係のみ**）。

> **レビュー入力範囲（TDD 複数コミット対応）**: いずれの経路も Code Review の context は **当該タスクの全コミット範囲 `<task_base>..HEAD`** とする（単一コミット `<sha>^..<sha>` にしない）。`<task_base>` = `Bash git -C <worktree-path> merge-base <integration-branch> HEAD`（task-branch の分岐元 = 当該タスク最初のコミット直前）。TDD タスクは test→impl→refactor の最大 3 コミットになるため、最終コミットだけ（refactor 実施時は refactor 差分、no-op 時は impl 差分）を渡すと先行 test コミットや実装全体がレビュー対象から漏れ、`reviewer: codex` の品質ゲートが機能しない。`<task_base>` は worktree 作成元の integration-branch HEAD に固定され、他タスクのマージや NG retry で integration-branch が進んでも merge-base は当該タスクの分岐点を返すため、累積タスク差分全体が常にレビュー対象になる。

##### 5.3.0 Evaluator 先行起動（全 reviewer 共通）

`Agent subagent_type: team-evaluator` を **単独起動**する（Codex / team-reviewer-code はこの時点では起動しない）。Evaluator NG 時は `tasks/<task-id>/eval-attempt-N.md` を Write する。runlog `agent_decision team-evaluator invoked`。

##### 5.3.1 Evaluator 結果ゲート

- **Evaluator NG**: Code Review を **起動せず** 5.4 NG 経路へ直行する（Eval 応答パス `tasks/<task-id>/eval-attempt-N.md` を Generator へ）。runlog `code_review_skipped_evaluator_ng` / `{task_id, attempt:N}` + `agent_decision code-review skipped`（reason: `evaluator_ng`）。**これが Codex レート節約の主経路**（Evaluator で弾けるものは Codex を消費しない）。
- **Evaluator OK（APPROVED）**: 5.3.2 へ進み、`reviewer` 値で Code Review を起動する。

##### 5.3.2 Code Review 起動（Evaluator OK 時のみ・`reviewer` で分岐）

`<is_dev_container>` と `reviewer` の組合せで 3 分岐:

- **分岐 A**（`reviewer: codex` かつ dev container）: **Codex MCP tool 経路**。`mcp__codex__codex`（`sandbox: read-only`、`model: "gpt-5.4"` 固定、**レビュー対象を `<task_base>..HEAD`（上記範囲）と明示**）を起動。developer-instructions には次を要求する: (1) `## status: APPROVED|REQUEST_CHANGES` 単一行ガード、(2) 4 段階重要度語彙（`blocker`/`high`/`medium`/`low`）、(3) `## 結論` フォーマット、(4) **品質方針**＝各 finding に `ファイル:行`＋具体根拠必須・`blocker`/`high` はバグ/セキュリティ/認可/PII/データ整合性/受け入れ条件未達に限定・重複排除・**1 パス網羅**（重大度横断で一度に列挙）・確信度が低い指摘は `low` 化、(5) **観点**＝`team-reviewer-code` の「具体的なレビュー観点」（正確性・エラーハンドリング / セキュリティ・認可・PII / データ整合性・並行性 / 型安全 / モジュール境界 / UI・フレームワーク / パフォーマンス / i18n / テスト欠落 / スコープ外変更）と同等、(6) **Evaluator との役割分担**＝テスト合否そのものは Evaluator が判定済みのため Code Review はコード品質・正確性・セキュリティに集中する
- **分岐 B**（`reviewer: codex` かつ host）: **`team-reviewer-code` Agent フォールバック経路**。Agent 起動前に Bash で `git -C <worktree-path> log --oneline <task_base>..HEAD`（コミット列挙）+ `git -C <worktree-path> diff --stat <task_base>..HEAD` + `git -C <worktree-path> diff <task_base>..HEAD` を context ファイル（`<state-root>/responses/code-review-<task-id>-attempt-N-context.md`、絶対パス必須、正規表現 `^/.+/\.iterate-team/state/[A-Za-z0-9._-]+/responses/code-review-task-[0-9_]+-attempt-[0-9]+-context\.md$` で subagent 側検証）に書き出してから、`team-reviewer-code` を **単独起動**（Evaluator は 5.3.0 で完了済みのため Code Review のみ）
- **分岐 C**（`reviewer: none`）: Code Review skip。5.3.0 の Evaluator OK のみで確定 OK。runlog `agent_decision code-review skipped`（reason: `reviewer_none`）

応答ファイル:

- Codex 経路: `<state-root>/responses/codex-review-<task-id>-attempt-N.md`
- フォールバック経路: `<state-root>/responses/code-review-<task-id>-attempt-N.md`
- Evaluator: NG 時のみ `<state-root>/tasks/<task-id>/eval-attempt-N.md`

##### 5.3.3 結果マージ

Code Review を起動した場合（分岐 A / B）は status 抽出（`grep -cE '^## status: (APPROVED|REQUEST_CHANGES)$'`）で `N != 1` は invalid_format → ステップ 9。`REQUEST_CHANGES` は `code_review_blocker_high` イベントも追記。

検収マージ判定表（Evaluator は 5.3.1 で **OK 確定済み**が前提。Evaluator NG は本表に到達せず 5.3.1 で 5.4 NG 直行）:

| Code Review              | 判定                                      |
| ------------------------ | ----------------------------------------- |
| 未起動（reviewer: none） | 確定 OK（Evaluator OK のみで検収）        |
| blocker / high 無        | 確定 OK                                   |
| blocker / high 有        | NG（Code Review 応答パスを Generator へ） |

NG 判定時は当該 attempt を失敗扱い、ステップ 5.4 NG 経路（max_retries 比較 → team-generator 再起動 or ステップ 9）。

##### 5.3.4 Codex timeout 時の扱い（dev container 経路限定）

Codex tool result が timeout / connection error を返した場合、`codex_serial_fallback = true` フラグを立て、当該 session の残り全 wave で Codex 呼出をタスク間で逐次化（複数タスクの Codex Code Review を同時に呼ばない）。runlog: `codex_review_serial_fallback`。フォールバック経路（5.3.2.B）は Agent ツール経由のため本制約は適用しない。本フラグは Evaluator の並列性には影響しない（Evaluator は常にタスクごとに 5.3.0 で先行起動する）。

#### 5.4 検収結果の処理

- **OK**: runlog `task_completed`。「マージ待ち」キューに追加
- **NG**: N が `max_retries` 未満なら team-generator 再起動（**同じ worktree 再利用**、差し戻し形式で eval/code-review 応答パスを渡す）。**再起動直前に `Bash git -C <worktree-path> rev-parse HEAD` を取得し `<pre_phase_b_head_<task-id>>` を更新**（前 attempt の commit を「今回 attempt の進捗」と誤判定しないため、必須）。**TDD タスクでも test-coder は再起動しない**（テストは Red コミット済み。generator は既存テストを弱めず impl 修正で緑にする）。再起動時は `<test_files>` を再添付する。再 green 後は 5.2.5（refactor）を再実行してから 5.3。`max_retries` 到達は `agent_decision team-evaluator rejected` 後ステップ 9
  - **`refactor_failed` 起因の NG**（5.2.5 由来）: eval/code-review 応答の代わりに **5.2.5 で生成した `responses/refactor-failed-<task-id>-attempt-N.md` を差し戻し artifact として渡す**。generator はこれを差し戻し成果物として `Read` し（`baseline not green` なら失敗テストを緑にする impl 修正、`cannot keep green` なら refactor が緑を保てるよう impl を整える）、再 green 後に 5.2.5 を再実行する。これにより差し戻し artifact 不在による `restart_without_artifact` 停止を回避する

#### 5.5 wave 内全タスク OK 後の merge

メイン worktree（HEAD = `<integration-branch>` 確認）に戻り、`plan.json` tasks[] 宣言順で `Bash <plugin_root>/scripts/team-worktree-merge.sh <session-id> <task-id> <integration-branch>` 順次実行。runlog: `task_merged` per task、wave 単位で `wave_merge_started` / `wave_merge_completed`。

コンフリクト時は exit 1 + `CONFLICT: <task-id>` + 競合ファイル一覧 → **エスカレーション**（自動解決禁止）。runlog: `merge_conflict`。既マージタスクは保持。ステップ 9。

#### 5.6 マージ完了後の worktree クリーンアップ

`Bash <plugin_root>/scripts/team-worktree-cleanup.sh <session-id> <task-id>` per task 実行（並列可）。エスカレーション時は **クリーンアップ保留**（人間調査用）。runlog: `worktree_removed` または `worktree_cleanup_skipped`。

次の wave があればステップ 5.0 へ。全 wave 完了でステップ 6 へ。

### ステップ 6.5: 自己改善ループ（Skill: /simplify → /security-review）

closer 完了後、push 前に `<integration-branch>` を対象とした自己改善ループを実行する。`self_improve_round` カウンタ（in-memory、起動時 0）で管理し、**初回ラウンド `round=0` + 最大 2 リトライラウンド `round=1,2` = 合計最大 3 ラウンド** までで完了 / エスカレーション判定する（`self_improve_round > 2` でエスカレーション）。`<is_dev_container>` の判定に依らず実行（Skill 呼び出しは Orchestrator メインセッション内で完結し push を伴わない）。

> **`/review` を本ループから除外する設計判断**: `/review` は **PR 上のレビュー記載** を主用途とする built-in command であり、`<integration-branch>` 上のローカル差分への自己改善観点とはユースケースが異なる（PR 反映後のレビュー往復は step 7 以降の Ready 化後ワークフローに委ねる）。step 5.3 で task 単位の Code Review、step 0 / Phase A で advisor 観点（security / architect / ui-ux / tech-lead）をカバー済みのため、本ループでは `/simplify`（reuse / quality / efficiency 観点の auto-fix）と `/security-review`（pending 変更の脆弱性スキャン）の 2 系統に絞る。なお `/security-review` は built-in command だが Claude Code 公式 docs `/en/skills` 内「Restrict Claude's skill access」セクションに `/init` `/review` `/security-review` が **Skill ツール経由でも呼び出し可能** と明記されており、`Skill skill: security-review` 呼び出しが公式仕様として動作する。

#### 6.5.1 `/simplify` 実行（dirty 差分の Orchestrator 自動コミット + 無進捗ガード）

`Skill` ツールで `skill: simplify` を起動。`/simplify` の公式定義は「recently changed files をレビューして fixes を適用する」であり **コミット作成は契約に含まれない**。よって skill 完了後に dirty 差分が残るのが正常パターンとして起き得る（push 前に未コミット修正を残せば step 6.6 push に乗らないため、必ず Orchestrator 側でコミット集約する）。

実行前 / 実行後の HEAD sha を `Bash git rev-parse HEAD` で取得し差分集合 `<simplify_commits>` を確定する。`Bash git log <pre_sha>..HEAD --format="%H %s"` で skill 由来 auto-commit を一覧化（0 件もあり得る）。

- **未コミット差分の Orchestrator 自動コミット**: `/simplify` 完了直後に `Bash git status --porcelain` を実行する。出力が **空でない場合**（dirty 差分残存 = `/simplify` の正常出力）、Orchestrator が以下の手順で自己改善コミットへ集約する:
  1. porcelain 出力をパースして変更ファイルパス一覧 `<dirty_paths>` を抽出（先頭 2 文字のステータスコード除去、`R` / `C` 系の renamed/copied は `->` の左右両方のパスを対象、untracked `??` も対象）
  2. `<dirty_paths>` を 1 件ずつ `Bash git add -- "<path>"` で個別 stage（`git add -A` / `git add .` はリポジトリ規約上禁止）
  3. `Bash git commit -m "chore: /simplify self-improvement round=<self_improve_round>" -m "auto-commit by orchestrator for /simplify dirty changes (Skill does not guarantee commits per Claude Code spec)" -m "Refs: self-improvement"` を実行（subject + body + フッタ `Refs: self-improvement`）
  4. コミット成功時の HEAD sha を取得して `<simplify_commits>` に追加（無進捗ガードの判定対象に含める）
  5. runlog 追記: `self_improve_simplify_orchestrator_committed` / `{round, file_count, sha}`
  6. **`git commit` 自体が失敗した場合**（pre-commit hook reject 等で exit 非 0）のみ `self_improve_simplify_dirty` / `{round, porcelain_excerpt: <先頭 500 文字>, commit_stderr: <先頭 500 文字>}` 追記後ステップ 9（疑似 task-id `self-improvement`、escalation.md に porcelain 全文 + git diff + commit stderr を記録、人手検査に委ねる）

> **設計意図**: 旧設計は dirty 差分を即エスカレーションしていたが、`/simplify` の公式仕様上 commit 保証がなく、品質修正が発生する通常ケースほど自己改善ループが失敗扱いになり push 前に全 run を止めていた。Orchestrator が個別 `git add` + 1 コミットで集約することで (a) dirty 差分が step 6.6 push に確実に乗る、(b) `<simplify_commits>` に sha が積まれて無進捗ガードが正しく機能する、(c) pre-commit hook 違反など真の異常時のみエスカレーションする、の 3 点を満たす。コミット粒度は「skill 1 起動 = 1 コミット」で 1 task 1 commit + Refs フッタ原則とも整合（`Refs: self-improvement` で plan-task 系コミットと区別）。

- runlog: `self_improve_simplify_completed` / `{round: self_improve_round, commits: <list of sha>}`
- Skill 内エラーで戻り値が異常終了した場合は `self_improve_simplify_failed` 追記後ステップ 9（疑似 task-id `self-improvement`）
- **無進捗ガード**: `self_improve_round > 0` かつ `len(<simplify_commits>) == 0` の場合（skill auto-commit と Orchestrator 自動コミットの両方が 0 件 = dirty 差分すら検出されず実体修正が発生しない）、後段の security-review を実行せず即エスカレーション。`self_improve_escalated` / `{reason:"simplify_no_progress", round}` 追記後ステップ 9（前ラウンドの blocker が `/simplify` で吸収できない証拠 — 再試行は無駄なため早期撤退で skill invocation コストを節約）

#### 6.5.2 `/security-review` 実行（read-only）

`/security-review` は post-`/simplify` HEAD（`<integration-branch>` の pending 変更）を対象に脆弱性スキャンを行う。`Skill` ツールで `skill: security-review` を **単独起動** する。

- 起動側 runlog: `self_review_started` / `{round, skills:["security-review"]}`
- `Skill skill: security-review` 戻り値 → `<state-root>/responses/self-security-review-round-<self_improve_round>.md` に Write

blocker 判定は **「行頭マーカー + コロン」型の肯定的 finding 行に限定** する（否定文や凡例による false positive を回避するため）。具体的には以下 2 系統の正規表現を OR で適用し、いずれかに **行単位で** マッチした行のみを blocker 候補とする:

- `^[\s\-*]*\b(P0|P1|BLOCKER|Blocker)\b\s*[:：]` — P0/P1/BLOCKER ラベル付き finding 行（コロン要求）
- `^[\s\-*]*\b(Severity|重要度|Risk|リスク)\s*[:：]\s*(Critical|High|高|致命)\b` — Severity/重要度 ラベル付きの High/Critical 行

> **誤検知回避**: `High` / `Critical` 単体（行頭マーカーなし）は **マッチさせない**。これにより以下の応答パターンで false positive が出ない:
>
> - クリーン応答: `No High severity issues found.` / `HIGH/MEDIUM 確信度の脆弱性なし` / `Critical issues: none`
> - 凡例: `重要度凡例: Critical / High / Medium / Low` / `Severity legend: ...`
> - 文中言及: `... addresses a high-impact concern ...`（High が形容詞用法）

判定結果:

- 上記正規表現で **1 行以上マッチ**: `<security_blockers>` = true、runlog `self_improve_security_blockers_found` / `{round, response_path, matches: <抜粋: 先頭マッチ最大 3 行、合計 500 文字以内に切り詰め>}`
- マッチなし: `<security_blockers>` = false、runlog `self_improve_security_clean` / `{round, response_path}`

#### 6.5.4 ループ判定

擬似コード:

```
if not <security_blockers>:
    runlog: self_improve_completed / {rounds_consumed: self_improve_round + 1}
    goto 6.6
self_improve_round += 1
if self_improve_round > 2:
    runlog: self_improve_escalated / {reason:"max_rounds_exceeded", round}
    goto step 9 (疑似 task-id self-improvement)
# round <= 2: 残ラウンドあり
goto 6.5.1
```

escalation.md には `<security_blockers>` 応答パスと各ラウンド sha を記録。

#### 6.5.5 不変条件

- `<integration-branch>` 上でのみ動作する。`.team-worktrees/...` は既にステップ 5.6 でクリーンアップ済み前提
- push は本ステップでは実行しない（次のステップ 6.6 で一括 push）
- 本ステップ（6.5）の `/simplify` / `/security-review` は **Orchestrator メインセッションが `Skill` ツール経由で** 呼び出す。team-\* subagent は tools に `Skill` を含めない設計のため呼び出せない（Claude Code 仕様上の禁止ではなく、ツール非付与という設計選択の結果。subagent も `Skill` 付与なら skill を起動可能）
  - **例外（2026-06-02 supersede）**: `team-refactor` のみ `tools` に `Skill` を付与し、worktree 内で `/simplify` → `/code-review` を自ら起動する（TDD 統合 ADR 事項5、ダイジェスト収録）。本不変条件の「team-\* は Skill を含めない」は per-task refactor を行う `team-refactor` には適用されない。step 6.5 の integration-branch 一括 `/simplify` は引き続き Orchestrator が担う
- ループ上限は **2 ラウンド固定**（初回 round=0 → リトライ round=1 → リトライ round=2 で完了判定。`> 2` でエスカレーション）

#### 6.5.6 ステップ完了 `step_checkpoint`

`<plugin_root>/scripts/runlog-append.sh "<session-id>" step_checkpoint '{"step":"6.5","topic_slug":"<topic-slug>","plan_revision":<rev>,"integration_branch":"<integration-branch>","current_task_id":null,"current_attempt":null,"completed_task_ids":[...],"wave_index":null,"completed_wave_indices":[...],"advisor_pending":false,"next_step":"6.6","self_improve_round":<final_round>}'`

### ステップ 6.6: 実装コミット群を remote へ push（host 環境のみ）

`<is_dev_container>=true` の場合、本ステップ全体を skip（runlog: `post_push_skipped` / `{reason:"dev_container"}` + `agent_decision team-publisher skipped`）。

`<is_dev_container>=false` の場合のみ、自己改善ループ完了後、`draft: false` 化（ステップ 7）前に **統合ブランチ全体を remote へ push**。`Agent subagent_type: team-publisher` を operation `push_branch`、phase `post_implementation` で起動。runlog: `branch_pushed` / `{branch, sha, phase: "post_implementation"}`。

push しないと Ready PR が GitHub 上で計画コミットだけを指し、wave merge / Generator 実装 / closer チェックリスト一括コミット / 自己改善コミット群がレビュー対象に載らない。push 失敗時はステップ 9。

### ステップ 7: PR Ready 化とユーザーへ一括報告（host 環境のみ）

`<is_dev_container>=true` の場合、本ステップを skip してステップ 7' へ（runlog: `ready_skipped` + `agent_decision team-publisher skipped`）。

`<is_dev_container>=false` のみ:

1. Orchestrator が実行環境で利用可能な手段で `<pr-number>` の Draft 状態を解除（Ready 化）
2. runlog: `pr_marked_ready` / `{pr_number}`
3. 結論ファーストで報告: 完了タスク数 / 試行回数累計 / コミット一覧（`git log --grep="Refs: task-" --format="%h %s"`）/ PR URL / 残作業 / runlog.jsonl パス

### ステップ 7': dev container 専用 — ローカル完了報告と引き継ぎ案内

`<is_dev_container>=true` の場合のみ実行。push / PR Ready 化を行わず、以下をユーザに報告して終了:

```
[iterate-team] dev container 内でローカル実装まで完了しました（PR 自動化は skip）。

実装ブランチ: <integration-branch>
完了タスク数: <total_tasks>
試行回数累計: <total_attempts>
コミット履歴: git log --grep="Refs: task-" --format="%h %s"
チェックリストコミット: git log --grep="Refs: plan-<topic-slug>" --format="%h %s"
runlog: .iterate-team/state/<session-id>/runlog.jsonl

dev container は read-only Deploy Key で起動しているため push できません。
host 側のターミナル または Web 版 Claude Code に切り替えて以下を実行してください:

1. 統合ブランチを remote へ push:
   git push -u origin <integration-branch>

2. GitHub UI で Draft PR を作成 → Ready 化（手動）

PR Title 候補: [iterate-team] <topic-slug>
PR Body 候補: .iterate-team/tasks/<yyyyMMdd_topic-slug>/plan-summary.md の全文 +
              「## チェックリスト」セクション
```

runlog: `dev_container_complete` / `{integration_branch, total_tasks, total_attempts}`

### ステップ 8: 失敗時挙動（team 固有の追加エラー）

共通失敗条件は `harness-common.md` を参照。team 固有の追加エラー:

- team-worktree-setup.sh / merge.sh / cleanup.sh のいずれかが想定外 exit code
- team-publisher Agent が `validation_failed` で戻る（push 失敗）
- PR 作成 / 本文更新 / Ready 化失敗
- merge conflict
- Codex 経路固有: timeout / `codex_plan_review_invalid_format` / `codex_review_invalid_format`
- フォールバック経路固有: team-reviewer-plan / team-reviewer-code 起動失敗（timeout / maxTurns） / `plan_review_invalid_format` / `code_review_invalid_format`

### ステップ 9: エスカレーション（team 固有 `<task-id>` 決定規則）

- タスクループ以降 → 当該 `task-x_y_z`
- 計画レビュー由来（両経路）→ 疑似 `plan-review`
- コードレビュー由来 → 当該 `task-x_y_z`（タスクループ内のため）
- Planner 委譲累計超過 → 疑似 `planner-loop`
- wave 計算失敗 → 疑似 `wave-compute`
- merge conflict → 当該 `<task-id>`
- PR 作成失敗 → 疑似 `pr-create`
- 自己改善ループ（ステップ 6.5）由来 → 疑似 `self-improvement`
- ブランチ bootstrap / rename 失敗（ステップ 0.1 / 3.x）→ 疑似 `branch-bootstrap`

`<state-root>/tasks/<task-id>/` を `mkdir -p` してから `escalation-template.md` を雛形に escalation.md を Write。runlog `escalated` 追記。自動進行停止しユーザーに報告（既完了タスクはロールバックしない、未クリーンアップ worktree はパス併記）。

### 不変条件（team 固有）

- 1 wave 内は並列、wave 間は順次。並列度上限 `team_max_parallel = 4`
- worktree 内では `npm install` 禁止（`node_modules` は symlink 共有のため symlink 破壊防止）
- Orchestrator から `git push` を直接呼ばない。push は `team-publisher` 経由のみ（内部で `<plugin_root>/scripts/team-push-branch.sh` ラッパー）。`Bash(git push *)` は `permissions.deny` で完全遮断
- Draft PR の作成は同一 session 内で 1 回のみ。再走行時は同一 PR の本文を更新
- `<is_dev_container>=true` の場合、`team-publisher` を一切起動せず、PR 作成 / 本文更新 / Ready 化もすべて skip。4.5.B → 5 → 6 → 6.5 → 7' で終了
- 両経路とも `## status: APPROVED|REQUEST_CHANGES` 単一行ガード（`grep -cE '^## status:...' ` で N==1）を適用
- 両経路とも応答ファイルパスのみを Planner / Generator に渡す（Findings 全文を context に載せない）
- フォールバック経路の subagent（team-reviewer-plan / team-reviewer-code）は `permissionMode: plan` + tools から Write / Edit / MultiEdit / NotebookEdit / Bash を構造的に除外した read-only 構成
- team-reviewer-code は git コマンドを一切実行しない（`Bash` を tools から除外）。差分情報は Orchestrator が 5.3.B.0 で context ファイルへ書き出してから絶対パスを渡す
- merge conflict は自動解決禁止（Planner depends_on 設計不備として人間レビューに上げる）
- `.claude/settings.sandbox.json` は無修正（dev container 用 sandbox の `Bash(git push *)` deny を維持）
- `permissions.allow` には `<plugin_root>/scripts/team-push-branch.sh` ラッパーのみ登録
- `permissions.allow` に `Bash(git worktree *)` ワイルドカードを追加しない（読み取りは `Bash(git worktree list)` のみ）
- **作業ブランチは `claude/<topic-slug>` 固定**（ステップ 0.1 で placeholder `claude/iterate-team-<YYYYMMDDHHmm>-pending` を `origin/<from_branch>`（既定 `main`、`--from-branch` 指定時はその値）から作成、ステップ 3.x で rename）。HEAD が `claude/` 接頭辞であることの事前要件はない（ステップ 0.1 内部で自動 bootstrap するため）。`<from_branch>` は PR の base にもなる（4.5.A.3）
- **新規起動経路は `main` / `master` 上での起動を許可**（clean な main から `/iterate-team` を開始する一般的な経路を塞がない。dirty check + `git switch -c claude/*-pending` で main 上での誤コミットは構造的に防止）
- **`--resume-checkpoint` 経路は `claude/<...>` ブランチ上での起動のみ許可**: HEAD 整合検証で (a) main/master abort、(b) `claude/` 接頭辞なし abort（`feature/foo` 等の任意ブランチ遮断）、(c) checkpoint payload の `integration_branch` キー存在時は HEAD と一致確認（不一致 abort）。step_checkpoint payload には `integration_branch` キーを必ず含める
- **モデル判定は abort ではなく `AskUserQuestion` 確認**（Sonnet 系 / unknown 通過、その他は明示確認）。`--model <id>` 指定時は skip
- **自己改善ループ（ステップ 6.5）は最大 2 ラウンド**。`<integration-branch>` 上のみで動作、worktree 内には変更を加えない
- **`/simplify` / `/security-review`（ステップ 6.5 自己改善ループ）は Orchestrator メインセッションが `Skill` ツール経由で呼び出す**（その他の team-\* subagent は `Skill` 非付与のため呼び出せない＝設計選択）。`team-refactor` の例外は [6.5.5 不変条件](#ステップ-65-自己改善ループskill-simplify--security-review) を参照

### Orchestrator 状態保持変数（team）

| 変数                           | 初期化タイミング                                                                                                                                                                                                                                                                          | 用途                                                                                                                                                                                                                                      |
| ------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `<model_override>`             | ステップ 1.0 で `--model <id>` 検出時のみ                                                                                                                                                                                                                                                 | session_start / agent_decision / runtime_detected payload に反映                                                                                                                                                                          |
| `<is_dev_container>`           | ステップ 0.0 で SessionStart hook の init.json から取得                                                                                                                                                                                                                                   | Codex 可用性判定 / ステップ 4.5 / 6.6 / 7 / 7' の分岐                                                                                                                                                                                     |
| `<integration-branch>`         | ステップ 0.1 で placeholder ブランチ作成時に設定、ステップ 3.x で `claude/<topic-slug>` に rename                                                                                                                                                                                         | worktree base / push / PR head として使用                                                                                                                                                                                                 |
| `<from_branch>`                | ステップ 0.1 (3.0) で `--from-branch <branch>`（既定 `main`）から設定。ステップ 4 checkpoint に永続化し resume / `/iterate-build` で復元                                                                                                                                                  | placeholder ブランチの派生元（`origin/<from_branch>`） / Draft PR の base（4.5.A.3）                                                                                                                                                      |
| `<plan_approved>`              | ステップ 4 完了時に設定（dev container=承認済み true / host=提示のみ false）。checkpoint に永続化                                                                                                                                                                                         | ステップ 4.5 の承認要否分岐（二重承認防止）                                                                                                                                                                                               |
| `plan_revision`                | 起動時 0、Planner 出力コミット発行のたびに `+= 1`                                                                                                                                                                                                                                         | コミット subject 切替（初稿 / 修正稿）                                                                                                                                                                                                    |
| `plan_review_round`            | **ステップ 3.5 入口（= `/iterate-team` 起動時）**と**ステップ 4 修正フロー起動時**のみ 0 で初期化。自動修正ループ内（REQUEST_CHANGES → 3.2 → 3.5 再入）では値を引き継ぐ。`--resume-checkpoint` で 3.5 に戻る場合は `step_checkpoint` payload から復元し in-memory 初期化 0 で上書きしない | 計画レビュー自動修正ループ上限判定。`plan_review_round >= 3` でステップ 9（疑似 task-id `plan-review`）。`step_checkpoint` payload の `plan_review_round` キーで永続化。mid-loop checkpoint（REQUEST_CHANGES インクリメント直後）でも記録 |
| `<pr-number>`                  | ステップ 4.5.A.3 初回作成時に設定                                                                                                                                                                                                                                                         | 修正フロー再走行時の PR 再利用判定                                                                                                                                                                                                        |
| `codex_serial_fallback`        | Codex tool result が timeout / connection error 検出時に true                                                                                                                                                                                                                             | 残 wave の Codex 呼出をタスク間で逐次化（Evaluator は常にタスクごとに 5.3.0 で先行起動するため影響しない）                                                                                                                                |
| `<pre_phase_b_head_<task-id>>` | **Phase B を起動するすべての経路の直前** に `Bash git -C <worktree-path> rev-parse HEAD` で取得し上書き保存。具体的にはステップ 5.0.3 初回 Phase B 起動直前 / 5.1.7 フェーズ A 完了後の Phase B 再起動直前 / 5.4 NG retry での Phase B 再起動直前の 3 経路すべて                          | ステップ 5.2 で HEAD が今回 attempt で進んだかを判定。worktree 再利用時に前 attempt commit を「今回完了」と誤判定しないため。1 回だけの取得では NG retry 経路で誤判定する                                                                 |
| `self_improve_round`           | ステップ 6.5 入口で 0 へ初期化、各ループ末で `+= 1`                                                                                                                                                                                                                                       | 自己改善ループ上限（2）判定。`> 2` でステップ 9                                                                                                                                                                                           |
| `<security_blockers>`          | ステップ 6.5.2 内で算出（true/false）                                                                                                                                                                                                                                                     | ループ判定の入力                                                                                                                                                                                                                          |
| `<simplify_commits>`           | ステップ 6.5.1 で算出（sha 配列）                                                                                                                                                                                                                                                         | runlog 追跡用（push 対象 commit の特定）                                                                                                                                                                                                  |
