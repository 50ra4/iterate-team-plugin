---
description: レビューフェーズ専用ハーネス（closer 委譲 + 自己改善ループ + post-push + PR Ready 化）。既存 /iterate-build で実装完了済みセッションに対して実行する。
argument-hint: --session <session-id> [--model <id>] [--resume-checkpoint <session-id>]
---

# /iterate-review

あなたは iterate-review ハーネスの **Orchestrator** である。本コマンドの担当ステップ範囲は既存 `/iterate-team` の **ステップ 6〜7'** のみ（closer 委譲 / 自己改善ループ / post-push / PR Ready 化 / dev container 完了案内）。ステップ 0〜5（環境ガード〜wave 並列タスクループ）は本コマンドの範囲外であり、`/iterate-build` が担当する。

## 必須遵守事項

共通ルールは [`harness-common.md#必須遵守事項`](<plugin_root>/operations/harness-common.md#必須遵守事項) を参照。team 固有要点は [`iterate-team-runbook.md#不変条件team-固有`](<plugin_root>/operations/iterate-team-runbook.md#不変条件team-固有) を参照。

- **`<plugin_root>` 解決**: SessionStart hook が注入する `<session-init>` の `plugin_root`（= init.json の plugin_root）を `<plugin_root>` として保持し、本文・operations・scripts 参照（`<plugin_root>/...`）の解決と、全 subagent 起動プロンプトへの `plugin_root=<絶対パス>` 注入に使う。ランタイム状態は対象リポジトリ直下 `.iterate-team/{state,tasks,changes}/`
- **`git push` の直接呼び出し禁止**。push は `team-publisher` Agent 経由のみ（内部で `<plugin_root>/scripts/team-push-branch.sh` ラッパー）
- **`/simplify` / `/security-review` は Orchestrator メインセッションが `Skill` ツール経由で呼び出す**（team-\* subagent は `Skill` 非付与設計のため呼び出せない）
- **PR 作成 / 本文更新 / Ready 化は Orchestrator が実行環境で利用可能な手段を選択**（team-publisher は push 専任）

## 引数処理

### `--session <session-id>` 引数の検証

`--session <session-id>` 引数が**不在の場合**: 処理中止し、以下を案内する:

```
--session <session-id> が必要です。先に /iterate-plan / /iterate-build を実行してください。
```

`<session-id>` の値が `[A-Za-z0-9._-]+` パターンに一致しない場合: Usage を返して処理中止する:

```
Usage: /iterate-review --session <session-id> [--model <id>] [--resume-checkpoint <session-id>]
<session-id> は英数字・ドット・アンダースコア・ハイフンのみ使用可能です。
```

`--session` 引数のバリデーションは `<plugin_root>/scripts/iterate-validate-session.sh`（task-1_3_1 で新規作成）経由で行う。validate-session.sh の戻り値から `integration_branch` を取得し、後続の HEAD 整合検証 (c) で使用する（通常の `--session` 起動でも別の `claude/*` ブランチ上で処理が進むリスクを排除するため、`--resume-checkpoint` 経路と同等の HEAD 照合を必須化する）。

### `--model <id>` 引数の処理

詳細は [`harness-common.md#ステップ-1-引数処理`](<plugin_root>/operations/harness-common.md#ステップ-1-引数処理) を参照。`--model <id>` 検出時に値検証し `<model_override>` として保持する。

### `--resume-checkpoint <session-id>` 引数の処理

`--resume-checkpoint <session-id>` で起動された場合、checkpoint payload の `next_step` を確認する。担当範囲の判定は数値・文字列双方を許容して行い（後方互換: 旧 runlog は数値で書き込まれている場合がある）、[`iterate-team-runbook.md` の分岐表](<plugin_root>/operations/iterate-team-runbook.md#next_step-値域と担当コマンドの分岐表)を SSOT とする。文字列専用識別子（`"3.5-replan"` 等）は数値表現が存在しないため文字列照合を維持する。本コマンド担当値（`6` / `"6"` / `"6.5"` / `"6.6"` / `"6.7"` / `"7"` / `"7'"`）以外のとき、処理中止し担当コマンドを案内する（`"6.7"` 追加前の旧 checkpoint は `next_step:"7"` のまま記録されているため、旧 checkpoint からの resume も従来どおり本コマンド担当範囲として扱われ後方互換を維持する）:

- `next_step` が `/iterate-plan` 担当値（`"2.5"` / `"3"` / `"3.2"` / `"3.5"` / `"3.5-replan"` / `"4"`）:

```
checkpoint の next_step が本コマンドの担当範囲外です。/iterate-plan --resume-checkpoint <session-id> を実行してください。
```

- `next_step` が `/iterate-build` 担当値（`"4.5"` / `"5"` / `"5.0"` 〜 `"5.7"`）:

```
checkpoint の next_step が本コマンドの担当範囲外です。/iterate-build --resume-checkpoint <session-id> を実行してください。
```

- 上記いずれの担当値にも一致しない場合: 「未知の next_step 値: <value>」エラーを返して処理中止

## 環境ガードと session 引継ぎ検証

### HEAD 整合検証（`--resume-checkpoint` 経路と同等のロジック）

`--resume-checkpoint` 経路の HEAD 整合検証 (a)(b)(c) と同等のロジックを実行する:

- **(a) `<head>` = `git symbolic-ref --short HEAD` を取得**。`main` / `master` の場合は処理中止
- **(b) `claude/` 接頭辞検証**: `<head>` が `claude/` で始まらない場合は処理中止
- **(c) `integration_branch` との HEAD 照合**（必須）: `--resume-checkpoint` 経路では `<step_checkpoint_payload>.integration_branch` から、通常の `--session` 起動では validate-session.sh の戻り値（または runlog.jsonl の最終 `step_checkpoint` payload）から `integration_branch` を取得する。取得できた場合、`<head> == <integration_branch>` であることを検証する。不一致なら `head_branch_mismatch` / `{head, integration_branch}` を runlog 追記後処理中止（別の `claude/*` ブランチ上での誤実行を防止）。`integration_branch` を取得できない場合は (b) の `claude/` 接頭辞検証のみで通過する

詳細は [`iterate-team-runbook.md#ステップ-0-環境ガードpreflight`](<plugin_root>/operations/iterate-team-runbook.md#ステップ-0-環境ガードpreflight) を参照。

### session 引継ぎ検証

`--session <session-id>` で指定された `.iterate-team/state/<session-id>/runlog.jsonl` に `all_tasks_completed` イベント、または `step_checkpoint` の `next_step` が `6` もしくは `"6"` のイベントが存在しない場合、処理中止し以下を案内する（`next_step` は数値 `6` と文字列 `"6"` の双方が存在し得るため双方許容で照合する。後方互換: 旧 runlog は数値で書き込まれている場合がある）:

```
実装フェーズが未完了です。/iterate-build --session <session-id> を実行してください。
```

検出コマンド:

```bash
tail -n 500 .iterate-team/state/<session-id>/runlog.jsonl \
  | jq -c 'select(.event=="all_tasks_completed" or (.event=="step_checkpoint" and (.next_step==6 or .next_step=="6")))' \
  | tail -n 1
```

### モデル判定

詳細は [`iterate-team-runbook.md#ステップ-0-環境ガードpreflight`](<plugin_root>/operations/iterate-team-runbook.md#ステップ-0-環境ガードpreflight) を参照。`--model <id>` 指定時は skip。`*sonnet*` / `unknown` はサイレント通過、その他は `AskUserQuestion` で確認を必須化する。

## ステップ 6: 全タスク完了 — closer 委譲

`Agent subagent_type: team-closer` を起動してチェックリスト一括コミットを行う。runlog: `all_tasks_completed`。

詳細: [`harness-common.md#ステップ-6-全タスク完了--closer-委譲`](<plugin_root>/operations/harness-common.md#ステップ-6-全タスク完了--closer-委譲)

## ステップ 6.5: 自己改善ループ（Skill: /simplify → /security-review）

closer 完了後、push 前に `<integration-branch>` を対象とした自己改善ループを回す。`self_improve_round` カウンタ（in-memory、起動時 0）で管理し、**初回 `round=0` + 最大 2 リトライラウンド `round=1,2` = 合計最大 3 ラウンド**（`self_improve_round > 2` でエスカレーション）。`<is_dev_container>` に依らず実行。

**`--resume-checkpoint` 時の `self_improve_round` 復元**: checkpoint payload に `self_improve_round` キーが存在する場合、その値を in-memory カウンタに復元してからループを再開する（キー不在の場合は 0 として扱う）。

**6.5 完了 `step_checkpoint` の必須キー**: ループ正常完了（6.5.4 で blocker なし → 6.6 遷移）時の `step_checkpoint` には `self_improve_round` を必ず含める:

```bash
<plugin_root>/scripts/runlog-append.sh "<session-id>" step_checkpoint '{"step":"6.5","integration_branch":"<integration-branch>","self_improve_round":<self_improve_round>,"next_step":"6.6"}'
```

### ステップ 6.5.1: `/simplify` 実行

`Skill` ツールで `skill: simplify` を起動。未コミット差分は Orchestrator が個別 `git add` + 1 コミットで自動集約する。

詳細: [`iterate-team-runbook.md#651-simplify-実行dirty-差分の-orchestrator-自動コミット--無進捗ガード`](<plugin_root>/operations/iterate-team-runbook.md#651-simplify-実行dirty-差分の-orchestrator-自動コミット--無進捗ガード)

### ステップ 6.5.2: `/security-review` 実行

`Skill` ツールで `skill: security-review` を起動し、脆弱性スキャンを行う。結果を `<state-root>/responses/self-security-review-round-<self_improve_round>.md` に Write する。

詳細: [`iterate-team-runbook.md#652-security-review-実行read-only`](<plugin_root>/operations/iterate-team-runbook.md#652-security-review-実行read-only)

### ステップ 6.5.4: ループ判定

blocker が無ければステップ 6.6 へ。blocker があれば `self_improve_round += 1` し、`> 2` でエスカレーション（疑似 task-id `self-improvement`）。残ラウンドがあれば 6.5.1 へ戻る。

**blocker 検出後 6.5.1 へ戻る前の mid-loop checkpoint 保存（必須）**: `self_improve_round += 1` した直後、6.5.1 へ戻る前に以下の `step_checkpoint` を保存する。これにより中断後 resume で更新済みの `self_improve_round` が正しく復元され、最大 3 ラウンド保証が崩れない:

```bash
<plugin_root>/scripts/runlog-append.sh "<session-id>" step_checkpoint '{"step":"6.5","integration_branch":"<integration-branch>","self_improve_round":<updated_self_improve_round>,"next_step":"6.5"}'
```

詳細: [`iterate-team-runbook.md#654-ループ判定`](<plugin_root>/operations/iterate-team-runbook.md#654-ループ判定)

### ステップ 6.5.5: self-improvement 対象外の保証

`<integration-branch>` 上でのみ動作。worktree 内への変更は禁止。push は本ステップでは実行しない。

詳細: [`iterate-team-runbook.md#655-不変条件`](<plugin_root>/operations/iterate-team-runbook.md#655-不変条件)

## ステップ 6.6: 実装コミット群を remote へ push（host 環境のみ）

`<is_dev_container>=true` の場合、本ステップ全体を skip（runlog `post_push_skipped` + `agent_decision team-publisher skipped`）。

`<is_dev_container>=false` の場合のみ、`Agent subagent_type: team-publisher` を operation `push_branch`、phase `post_implementation` で起動し統合ブランチ全体を push する。

両分岐とも完了直後に `step_checkpoint`（`next_step:"6.7"`）を追記し、ステップ 6.7 へ進む。

詳細: [`iterate-team-runbook.md#ステップ-66-実装コミット群を-remote-へ-pushhost-環境のみ`](<plugin_root>/operations/iterate-team-runbook.md#ステップ-66-実装コミット群を-remote-へ-pushhost-環境のみ)

## ステップ 6.7: 軽量レトロスペクティブ（team-retrospector）

ステップ 6.6 完了後、ステップ 7（PR Ready 化）の前に `team-retrospector`（`mode=light`）を起動し、当該セッションの runlog から教訓（lesson）を抽出して `.iterate-team/knowledge/` へ永続化する（確定値の正本: `knowledge-policy.md`）。knowledge への書き込み主体は本ステップと `/iterate-retrospect` の team-retrospector のみに限定される。

1. runlog `retrospective_started`（detail: `{"mode":"light"}`）を追記 → `<plugin_root>/scripts/runlog-agent-decision.sh` で `team-retrospector` の `invoked` を追記
2. `Agent subagent_type: team-retrospector` を起動。プロンプトキー: `plugin_root` / `session_id` / `state_root` / `knowledge_dir`（`<repo-root>/.iterate-team/knowledge` 絶対パス）/ `tasks_dir` / `topic_slug` / `mode=light`
3. 戻り値 JSON（`new_lessons` / `updated_lessons` / `deprecated` / `proposals`）を検証 → `Bash git status --porcelain -- .iterate-team/knowledge/` で差分確認 → 差分があれば**個別 `git add`**（`lessons.jsonl` / `.gitattributes` / `.gitignore` / `proposals/` 配下の各ファイル。`lessons.md` は git 管理外のため対象外。`git add -A` / `git add .` 禁止）→ 1 コミットにまとめる。subject `docs: セッションレトロスペクティブ知見を記録`、フッタ `Refs: retrospective-<session-id>`
4. `<is_dev_container>=false`（host）: `team-publisher` による 2 回目 push（ステップ 6.6 と同じ規約）に本コミットを含める。`<is_dev_container>=true`（dev container）: push は skip（ステップ 7' の手動 push 案内に本コミットも含めて案内される）
5. runlog `retrospective_completed`（detail: `{"mode":"light","lessons_recorded":N,"proposals_recorded":M}`。`N` = `new_lessons` と `updated_lessons` の合計件数、`M` = `proposals` の件数。定義は runbook 6.7.4 と同一）を追記 → `step_checkpoint`（`next_step:"7"`）を追記 → ステップ 7 へ進む

**fail-open 規定**: team-retrospector の起動失敗 / 戻り値 JSON 不正・必須キー欠落 / knowledge コミット失敗のいずれかが発生した場合、以下の手順で復旧する（詳細な手順の正本は runbook 6.7.5）: 1) `Bash <plugin_root>/scripts/knowledge-recover.sh "<session-id>"` を実行する。スクリプトは `.iterate-team/knowledge/` の staged 変更を unstage してから HEAD 追跡ファイルの worktree を復元し（HEAD に無い staged 新規ファイル — コミット失敗直後の生成物 — は削除せず untracked へ戻して退避対象に含める。tracked/staged が皆無の初回実行時は復元を skip する）、残る untracked / git 無視対象の生成物（`.gitattributes` 等のドットファイル、`.gitignore` により無視される `lessons.md` を含む）を `.iterate-team/state/<session-id>/failed-retrospective/` へ退避して作業ツリーを clean に戻す（生成物は人間の事後調査用に温存し、`git clean` は使わない）。1 件以上退避した場合は退避先の相対パスを stdout に1行出力し、clean 化成功で exit 0、失敗時は stderr 診断 + exit 1 を返す。2) runlog `retrospective_failed`（detail: `{"mode":"light","reason":"...","evacuated_to":"..."}`。`evacuated_to` は手順1のスクリプトが退避先を出力した場合のみ含める。スクリプトが exit 非 0 の場合もその旨を reason に含めて記録の上で続行する）を追記して**ステップ 7 へ続行する**。本ステップはハーネス全体の中で**唯一、失敗してもステップ 9（エスカレーション）へ遷移しない**ステップである（knowledge 記録の失敗で PR 完了を阻害しないため）。push のみが失敗した場合（コミット自体は成功）は本 fail-open の対象外とし、既存の team-publisher 失敗規則（ステップ 8）に従いステップ 9 へ遷移する。

詳細: [`iterate-team-runbook.md#ステップ-67-軽量レトロスペクティブ`](<plugin_root>/operations/iterate-team-runbook.md#ステップ-67-軽量レトロスペクティブ)

## ステップ 7: PR Ready 化とユーザーへ一括報告（host 環境のみ）

`<is_dev_container>=true` の場合、本ステップを skip してステップ 7' へ（runlog `ready_skipped`）。

`<is_dev_container>=false` の場合のみ、Draft PR を Ready 化し、完了タスク数 / 試行回数 / コミット一覧 / PR URL / 記録レッスン数・プラグイン改善提案の有無 / runlog パスを結論ファーストで報告する。

詳細: [`iterate-team-runbook.md#ステップ-7-pr-ready-化とユーザーへ一括報告host-環境のみ`](<plugin_root>/operations/iterate-team-runbook.md#ステップ-7-pr-ready-化とユーザーへ一括報告host-環境のみ)

## ステップ 7': dev container 専用 — ローカル完了報告と引き継ぎ案内

`<is_dev_container>=true` の場合のみ実行。push / PR Ready 化は行わず、host 側 / Web 版での手動 push + PR 作成案内をユーザに提示して終了する。runlog: `dev_container_complete`。

報告メッセージテンプレ全文: [`iterate-team-runbook.md#ステップ-7-dev-container-専用--ローカル完了報告と引き継ぎ案内`](<plugin_root>/operations/iterate-team-runbook.md#ステップ-7-dev-container-専用--ローカル完了報告と引き継ぎ案内)

## 実行環境別の分岐まとめ

| ステップ                  | host / Web 版                                       | dev container 内 |
| ------------------------- | --------------------------------------------------- | ---------------- |
| 6.5 自己改善ループ        | 実行（`/simplify` + `/security-review`、push なし） | 実行（同上）     |
| 6.6 実装後 push           | 実行                                                | skip             |
| 6.7 軽量レトロ            | 実行（commit + push）                               | 実行（commit のみ） |
| 7 PR Ready 化             | 実行                                                | skip             |
| 7' dev container 完了案内 | skip                                                | 実行             |

`<is_dev_container>` 判定の詳細は [`iterate-team-runbook.md#実行環境別の挙動`](<plugin_root>/operations/iterate-team-runbook.md#実行環境別の挙動) を参照。

## ステップ 8: 失敗時挙動

共通失敗条件は [`harness-common.md#ステップ-8-失敗時挙動`](<plugin_root>/operations/harness-common.md#ステップ-8-失敗時挙動) を参照。team 固有の追加エラーは [`iterate-team-runbook.md#ステップ-8-失敗時挙動team-固有の追加エラー`](<plugin_root>/operations/iterate-team-runbook.md#ステップ-8-失敗時挙動team-固有の追加エラー) を参照。

## ステップ 9: エスカレーション

`<task-id>` 決定規則（自己改善ループ由来 → 疑似 `self-improvement` を含む）は [`iterate-team-runbook.md#ステップ-9-エスカレーションteam-固有-task-id-決定規則`](<plugin_root>/operations/iterate-team-runbook.md#ステップ-9-エスカレーションteam-固有-task-id-決定規則) を参照。

## 引数

要望文: $ARGUMENTS
