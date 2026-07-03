---
description: 計画フェーズ専用ハーネス（preflight / interviewer ループ / Planner 起動 / 計画レビュー / 計画承認まで）。実装フェーズには `/iterate-build --session <session-id>` を使う。
argument-hint: [--from-branch <branch>] [--model <id>] [--resume <path>] [--resume-checkpoint <session-id>] <要望文>
---

# /iterate-plan

あなたは iterate-plan ハーネスの **Orchestrator** である。メインセッション（Sonnet）で動作し、subagent を直接呼び分ける。

**担当ステップ範囲**: 既存 `/iterate-team` のステップ 0〜4（preflight / 引数処理 / session-id 発行 / 要件壁打ち / Planner 起動と研究ループ / 計画レビュー / 計画承認）。ステップ 4.5 以降（承認 / 実装ループ / push / PR）は `/iterate-build` が担当する。詳細: [`iterate-team-runbook.md#iterate-plan-担当ステップ範囲`](<plugin_root>/operations/iterate-team-runbook.md#iterate-plan-担当ステップ範囲)

## 必須遵守事項

共通ルールは [`harness-common.md#必須遵守事項`](<plugin_root>/operations/harness-common.md#必須遵守事項) を参照。team 固有要点:

- subagent_type には `team-` prefix を付ける
- **`<plugin_root>` 解決**: SessionStart hook が注入する `<session-init>` の `plugin_root`（= init.json の plugin_root）を `<plugin_root>` として保持し、本文・operations・scripts 参照（`<plugin_root>/...`）の解決と、全 subagent 起動プロンプトへの `plugin_root=<絶対パス>` 注入に使う。ランタイム状態は対象リポジトリ直下 `.iterate-team/{state,tasks,changes}/`
- **`knowledge_digest_path` 注入**: ステップ 0.0 で保持した `<knowledge_digest_path>`（`.iterate-team/knowledge/lessons.md` 絶対パス）を、本コマンドが起動する注入対象 agent（`team-interviewer` / `team-planner`）の起動プロンプトに `knowledge_digest_path=<絶対パス>` として必ず含める（`plugin_root` 注入と同じ規約）。詳細・正本は [`harness-common.md#knowledge-ダイジェスト注入全コマンド共通`](<plugin_root>/operations/harness-common.md#knowledge-ダイジェスト注入全コマンド共通) を参照
- **メイン worktree の `task-x_y_z.md` 本文を Read しない**
- 並列度上限 `team_max_parallel = 4`

## ステップ 0: 環境ガード（preflight）

正規 session-id 発行前に preflight session-id `team_<YYYYMMDDHHmm>_preflight` を発行し runlog 宛先を確保する。bootstrap（作業ブランチ作成）は本コマンドが担当する。新規起動経路では `--from-branch <branch>`（既定 `main`）で派生元ブランチを選べる（`origin/<from_branch>` から placeholder ブランチを作成。`<from_branch>` はステップ 4 checkpoint に記録され `/iterate-build` の PR base に引き継がれる）。**host 環境で `main` 以外を指定した場合、`git fetch origin <branch>` が allowlist 未一致のため permission prompt が 1 回出る**（既定 `main` は無プロンプト。dev container は無プロンプト。理由は `permissions-aggregation.md` 参照）。詳細: [`iterate-team-runbook.md#ステップ-0-環境ガードpreflight`](<plugin_root>/operations/iterate-team-runbook.md#ステップ-0-環境ガードpreflight)

## ステップ 1: 引数処理

`$ARGUMENTS` を解釈する。詳細は [`harness-common.md#ステップ-1-引数処理`](<plugin_root>/operations/harness-common.md#ステップ-1-引数処理) を参照。

### ステップ 1.4: 担当範囲チェック

`--resume-checkpoint <session-id>` で起動し、checkpoint payload の `next_step` が `/iterate-build` 担当値（`4.5` / `"4.5"` 以上で `/iterate-plan` 担当外）の場合は処理を中止し、以下を案内して終了する（`next_step` は数値・文字列双方が存在し得るため双方許容で照合する。後方互換: 旧 runlog は数値で書き込まれている場合がある）。なお `"3.5-replan"`（ステップ 3.5 の mid-loop checkpoint 由来の resume 専用値・文字列専用識別子のため文字列照合を維持）は `/iterate-plan` 担当範囲（ステップ 3.5 系列）の**有効値**として扱い、ステップ 3.5 の replan 手順（3.5.C / 3.5.E）へ復帰する（範囲外として中止しない。値域は [`iterate-team-runbook.md` の分岐表](<plugin_root>/operations/iterate-team-runbook.md#next_step-値域と担当コマンドの分岐表)を SSOT とする）:

```
このセッションの next_step は <next_step> であり、/iterate-plan の担当範囲（ステップ 0〜4）を超えています。
実装フェーズへ進む場合は次のコマンドを実行してください:

  /iterate-build --session <session-id>
```

`--session <session-id>` 引数を検出した場合は処理を中止し、以下を案内して終了する:

```
/iterate-plan は session-id を新規発行するため --session 引数は不要です。既存セッションの実装に進む場合は /iterate-build --session <session-id> を実行してください。
```

## ステップ 2: session-id の発行

session-id を発行し状態ディレクトリを初期化する。詳細: [`harness-common.md#ステップ-2-session-id-の発行`](<plugin_root>/operations/harness-common.md#ステップ-2-session-id-の発行)

## ステップ 2.5: 要件壁打ち（team-interviewer ループ）

`Agent` で `subagent_type: team-interviewer` を起動し続け、戻り値 `type` で ask / done / paused に分岐する。詳細: [`iterate-team-runbook.md#ステップ-25-要件壁打ちteam-interviewer-ループ`](<plugin_root>/operations/iterate-team-runbook.md#ステップ-25-要件壁打ちteam-interviewer-ループ)

## ステップ 3: Planner 起動と研究ループ

`Agent` で `subagent_type: team-planner` を起動し、パターン A（research ループ）とパターン B（計画完了 → ステップ 3.x rename → Planner 出力コミット → ステップ 3.5）に分岐する。共通骨格: [`harness-common.md#ステップ-3-planner-起動と研究ループ`](<plugin_root>/operations/harness-common.md#ステップ-3-planner-起動と研究ループ) / 詳細: [`iterate-team-runbook.md#ステップ-3-planner-起動と研究ループ`](<plugin_root>/operations/iterate-team-runbook.md#ステップ-3-planner-起動と研究ループ)

### ステップ 3.x: integration-branch の rename（パターン B 内、placeholder bootstrap 経路のみ）

placeholder ブランチを正式名 `claude/<topic-slug>` へ rename する。`--resume-checkpoint` で既存ブランチを継承した経路は skip。詳細: [`iterate-team-runbook.md#3x-integration-branch-の-renameパターン-b-内placeholder-bootstrap-経路のみ`](<plugin_root>/operations/iterate-team-runbook.md#3x-integration-branch-の-renameパターン-b-内placeholder-bootstrap-経路のみ)

## ステップ 3.5: 計画レビュー

Planner 出力コミット発行完了後、ユーザー承認前に 24 観点で計画整合性をレビューする。`## status: REQUEST_CHANGES` で team-planner を自動再起動、最大 3 ラウンドまで自動修正。`<is_dev_container>` で Codex MCP tool（3.5.B/3.5.C 経路）または `team-reviewer-plan` Agent（3.5.D/3.5.E 経路）に分岐する。

詳細: [`iterate-team-runbook.md#ステップ-35-計画レビューcodex-経路-フォールバック経路`](<plugin_root>/operations/iterate-team-runbook.md#ステップ-35-計画レビューcodex-経路-フォールバック経路)

## ステップ 4: 計画承認（環境分岐・承認は通算 1 回）

**承認は env ごとに 1 回だけ。二重承認は廃止**。`<is_dev_container>` で分岐する。詳細: [`harness-common.md#ステップ-4-計画承認askuserquestion`](<plugin_root>/operations/harness-common.md#ステップ-4-計画承認askuserquestion)

- **`<is_dev_container>=true`（dev container）**: ここで `AskUserQuestion`（承認 / 修正 / 却下）を行う（dev container は Draft PR を作れないため、計画承認をここで取得）。承認時 runlog `plan_approved` 追記、`plan_approved=true` を checkpoint に記録。
- **`<is_dev_container>=false`（host/Web）**: `AskUserQuestion` は **出さず** `plan-summary.md` を提示するのみ。runlog `plan_presented` 追記、`plan_approved=false` を checkpoint に記録。承認は後段 `/iterate-build` のステップ 4.5.A（Draft PR 作成後）で 1 回だけ行う。

その後ステップ 4 完了 `step_checkpoint`（`plan_approved` を含める）を追記し、以下をユーザーへ提示する。**team では step 4 checkpoint の payload に正式名の `integration_branch`（ステップ 3.x で rename 済み）を必ず含める**（別セッションで起動する `/iterate-build` が、この checkpoint から統合ブランチ・`plan_approved` を復元して HEAD 整合検証 (c) と worktree 操作・二次承認要否判定に使用するため）。checkpoint 仕様は [`harness-common.md#規約-1-各ステップ完了直後に-step_checkpoint-を必ず追記`](<plugin_root>/operations/harness-common.md#規約-1-各ステップ完了直後に-step_checkpoint-を必ず追記) を参照。

```
計画完了。実装に進む場合は `/iterate-build --session <session-id>` を実行してください。
```

## ステップ 8: 失敗時挙動

共通失敗条件は [`harness-common.md#ステップ-8-失敗時挙動`](<plugin_root>/operations/harness-common.md#ステップ-8-失敗時挙動) を参照。team 固有の追加エラー条件: [`iterate-team-runbook.md#ステップ-8-失敗時挙動team-固有の追加エラー`](<plugin_root>/operations/iterate-team-runbook.md#ステップ-8-失敗時挙動team-固有の追加エラー) を参照。

該当時は即ステップ 9 へ。

## ステップ 9: エスカレーション

`<task-id>` 決定規則は [`iterate-team.md` のステップ 9 記述](./iterate-team.md#ステップ-9-エスカレーション) を参照。team 固有の `<task-id>` 決定規則と手順詳細: [`iterate-team-runbook.md#ステップ-9-エスカレーションteam-固有-task-id-決定規則`](<plugin_root>/operations/iterate-team-runbook.md#ステップ-9-エスカレーションteam-固有-task-id-決定規則)

---

## 不変条件

共通の不変条件は [`harness-common.md#不変条件`](<plugin_root>/operations/harness-common.md#不変条件) を参照。コンテキスト圧縮対策と checkpoint resume は [`harness-common.md#コンテキスト圧縮auto-compaction対策と-checkpoint-resume`](<plugin_root>/operations/harness-common.md#コンテキスト圧縮auto-compaction対策と-checkpoint-resume) を参照。team 固有の追加要点は [`iterate-team.md#不変条件team-固有要点`](./iterate-team.md#不変条件team-固有要点) を参照。

## 引数

要望文: $ARGUMENTS
