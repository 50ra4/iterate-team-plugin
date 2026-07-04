---
description: 過去セッション横断の知見統合（deep レトロスペクティブ）
argument-hint: [--sessions <N>] [--no-push]
---

# /iterate-retrospect

あなたは `/iterate-retrospect` の **Orchestrator** である。メインセッション（Sonnet）で動作する。

**本コマンドは standalone コマンドである**。`/iterate-plan` → `/iterate-build` → `/iterate-review` の 3 分割プロトコル（`--session` 引継ぎ・`step_checkpoint` resume）とは独立しており、`--session` 引数を受け取らない。過去の複数ハーネスセッションの `runlog.jsonl` を横断分析し、`.iterate-team/knowledge/` の教訓（lesson）を統合・減衰・整理する **deep レトロスペクティブ**専用コマンドである。実体作業は `team-retrospector` agent（`mode=deep`）が担う。knowledge の確定値・スキーマ・規約は [`knowledge-policy.md`](<plugin_root>/operations/knowledge-policy.md) を正本とし、本コマンドはその手順の正本である。

## 必須遵守事項

- **`<plugin_root>` 解決**: SessionStart hook が注入する `<session-init>` の `plugin_root`（= init.json の `plugin_root`）を `<plugin_root>` として保持し、本文・operations・scripts 参照（`<plugin_root>/...`）の解決と、team-retrospector 起動プロンプトへの `plugin_root=<絶対パス>` 注入に使う
- knowledge への書き込み主体は **team-retrospector agent のみ**（`knowledge-policy.md` §1）。本コマンド（Orchestrator）は `.iterate-team/knowledge/` 配下を直接 `Write` / `Edit` しない
- コミットは個別 `git add`（`git add .` / `git add -A` 禁止）。詳細: [`git-commit-rules.md`](<plugin_root>/templates/_partials/git-commit-rules.md)
- `git push` の直接呼び出し禁止。push は `team-publisher` Agent 経由のみ
- 本コマンドは `git commit` まで行うが、**push は環境・引数に応じて分岐**する（ステップ 5）

## ステップ 0: 環境ガード（preflight）

1. **0.0 セッション初期化結果の取得**: context 先頭の `<session-init>` タグ（`init_path` / `is_dev_container` / `mcp_profile` / `model` / `plugin_root`）を取得する。**存在しない場合は処理中止**メッセージを返す。`init_path` を `Read` し、`plugin_root` を `<plugin_root>` として保持する
2. **0.1 clean tree の必須確認**: `Bash git status --porcelain` を実行する。**1 行でも出力があれば dirty** とみなし、以下を報告して処理中止する（knowledge をコミットするため clean tree を前提とする。この時点では retro 用ディレクトリ未作成のため runlog は記録しない）:

   ```
   working tree に未コミットの変更があります。/iterate-retrospect は knowledge をコミットするため clean tree を必須とします。
   変更をコミットまたは stash してから再実行してください。
   ```

3. **0.2 retro 用 runlog 宛先の作成**: `<ts>` = 現在時刻（`YYYYMMDDHHmm`、UTC）とし、`<retro-session-id>` = `retro_<ts>` を発行する。`Bash mkdir -p .iterate-team/state/<retro-session-id>` を実行する。**以降のすべての runlog 追記はこのディレクトリ（`<plugin_root>/scripts/runlog-append.sh <retro-session-id> ...`）へ記録する**。本ステップでは `mkdir` のみで runlog イベントは書かない（ステップ 1 のセッション列挙が自分自身の `retro_*` ディレクトリを拾わないようにするため。`runlog.jsonl` が実在しないディレクトリは「ハーネスセッションディレクトリ」とみなさない）

## ステップ 1: 対象セッション列挙

1. `--sessions <N>` を解釈する（既定 `10`、許容範囲 `1〜20` の整数）。範囲外・非数値の場合は Usage を返して処理中止する:

   ```
   Usage: /iterate-retrospect [--sessions <N>] [--no-push]
   <N> は 1〜20 の整数で指定してください（既定 10）。
   ```

2. `Bash <plugin_root>/scripts/retrospect-list-sessions.sh "<N>"` を実行する。`.iterate-team/state/` 直下に `runlog.jsonl` を持つセッションディレクトリ（`runlog.jsonl` が実在しないディレクトリはハーネスセッションとみなさず対象外とする。後段の `runlog-tail.sh <session_id>` が runlog 不在で exit 1 になることを防ぐ。`retro_*`（本コマンド自身が生成するディレクトリ）も除外。deep レトロが過去の deep レトロ実行ログ自体を教訓抽出の素材にすることは想定しないため）を、`runlog.jsonl` の mtime 降順（ディレクトリ自体の mtime ではない。runlog への追記で更新される = セッションの実活動順）で最大 `<N>` 件、セッション id を1行1件で stdout 出力するので、その出力から `<session_list>` を組み立てる。state 不存在または 0 件の場合は空出力・exit 0 で返る

3. **0 件の場合**: 以下を報告して処理中止する（ブランチは未作成のため復元不要）:

   ```
   .iterate-team/state/ 配下に分析対象のハーネスセッションが見つかりませんでした（runlog.jsonl を持つディレクトリなし）。
   ```

## ステップ 2: ブランチ作成

1. `Bash git symbolic-ref --short HEAD` で現在ブランチ `<original-branch>` を記憶する
2. `<retro-branch>` = `claude/knowledge-retrospect-<ts>`（`<ts>` はステップ 0.2 と同一値）
3. `Bash git switch -c "<retro-branch>"` を実行する。失敗時は `<plugin_root>/scripts/runlog-append.sh <retro-session-id> retrospective_failed '{"mode":"deep","reason":"branch_create_failed"}'` を追記し、理由を報告して処理中止する（`<original-branch>` から動いていないため復元不要）

## ステップ 3: deep レトロ実行

1. `<plugin_root>/scripts/runlog-append.sh <retro-session-id> retrospective_started '{"mode":"deep"}'` を追記する
2. `Agent` で `subagent_type: team-retrospector` を起動する。プロンプトに以下のキーを含める:

   | キー           | 値                                                                                     |
   | -------------- | -------------------------------------------------------------------------------------- |
   | `plugin_root`  | `<plugin_root>`（絶対パス）                                                            |
   | `session_id`   | `<retro-session-id>`（= `retro_<ts>`）                                                 |
   | `state_root`   | `.iterate-team/state/<retro-session-id>` の絶対パス                                    |
   | `knowledge_dir`| `.iterate-team/knowledge` の絶対パス                                                   |
   | `tasks_dir`    | 空文字列（deep モードは横断分析であり単一トピックの `tasks/` に紐づかないため未使用。agent 側の deep 手順もこのキーを参照しない） |
   | `topic_slug`   | `knowledge-retrospect`                                                                 |
   | `mode`         | `deep`                                                                                  |
   | `session_list` | ステップ 1 で確定した各セッションについて `{session_id, runlog_path}` の配列。各セッションの runlog は agent 自身が `Bash <plugin_root>/scripts/runlog-tail.sh <session_id>` で bounded read すること（既定 400 行。パス検証つきラッパー。1 セッション分を丸ごと読み込まない）を明記して指示する |

   deep モードの責務（重複統合・矛盾解消・`lesson_applied` 集約・減衰・`knowledge-prune.sh --compact --apply`・`knowledge-digest.sh` 再生成・`proposals/INDEX.md` 更新）は `team-retrospector.md` 側の定義に従う。本コマンドはキーの受け渡しのみ行い、deep モードの内部手順を重複定義しない
3. 戻り値の JSON フェンス（`new_lessons` / `updated_lessons` / `deprecated` / `proposals`）を受領し、件数をステップ 6 の報告に使う
4. agent が異常終了・応答不能等で完了しなかった場合はステップ「失敗時」へ

## ステップ 4: コミット

1. `Bash git status --porcelain -- .iterate-team/knowledge/` で差分を確認する
2. **差分がある場合**: 変更ファイルを個別に `git add <file>` し、1 コミットにまとめる。subject `docs: knowledge を横断統合（deep レトロスペクティブ）`、body に統合サマリ（新規/統合/廃止件数）、footer `Refs: retrospective-deep-<ts>`
3. **差分がない場合**: 「統合の結果、変更なし」と報告し、`Bash git switch "<original-branch>"` で元ブランチへ戻り、`<plugin_root>/scripts/runlog-append.sh <retro-session-id> retrospective_completed '{"mode":"deep","lessons_recorded":0,"changed":false}'` を追記して終了する（ステップ 5・6 は実行しない。ブランチ・コミットは残さない方針だが、コミット自体が存在しないため実質的に元ブランチと同一であり削除は不要）
4. コミット成功後、`<plugin_root>/scripts/runlog-append.sh <retro-session-id> retrospective_completed '{"mode":"deep","new_lessons":<N>,"updated_lessons":<N>,"deprecated":<N>,"proposals":<N>}'` を追記する（件数はステップ 3 の戻り値から算出）

## ステップ 5: push 分岐

- **host 環境（`<is_dev_container>=false`）かつ `--no-push` 未指定**: `AskUserQuestion` で「knowledge 統合コミットを push して PR を作成しますか？」（選択肢: `push + PR 作成` / `ローカルのみ（push しない）`）を尋ねる。
  - `push + PR 作成` 選択時: `Agent subagent_type: team-publisher` を `{"operation":"push_branch","owner":"<owner>","repo":"<repo>","branch":"<retro-branch>","phase":"post_implementation","session_id":"<retro-session-id>"}` で起動する。push 成功後、Orchestrator が実行環境で利用可能な手段で PR を作成する（`head: <retro-branch>` / `base: <original-branch>` / `title: [iterate-team] knowledge retrospective <ts>` / `body:` 統合サマリ。**draft ではなく通常 PR** とする。二次承認は不要）。PR URL をステップ 6 の報告に含める
  - `ローカルのみ` 選択時: push を行わずステップ 6 へ（コミットとブランチはローカルに残す）
- **dev container（`<is_dev_container>=true`）または `--no-push` 指定時**: push を skip し、以下の手動手順を案内する:

  ```
  push は行われていません。host 環境または Web 版で以下を実行してください:

    git push -u origin <retro-branch>

  push 後、GitHub UI で <retro-branch> → <original-branch> の PR を作成してください。
  ```

## ステップ 6: 報告

結論ファーストで以下を報告する:

- 新規レッスン件数 / 統合（`merged`）件数 / 廃止（`deprecated`）件数 / 降格件数
- プラグイン改善提案のサマリ（`proposals/` に追加されたファイル一覧）
- ブランチ名（`<retro-branch>`）
- push した場合: PR URL。push しなかった場合: 手動 push 手順
- runlog パス（`.iterate-team/state/<retro-session-id>/runlog.jsonl`）

報告後、`Bash git switch "<original-branch>"` で元ブランチへ戻る（**push の有無に関わらず、作成したブランチとコミットはローカルに残す**）。

## 失敗時（fail-open・エスカレーションなし）

team-retrospector の異常終了、またはステップ 4 のコミット失敗時は以下を行う。レトロスペクティブの失敗によってユーザー作業を止めないため、エスカレーションは行わない:

1. `.iterate-team/knowledge/` を `Bash <plugin_root>/scripts/knowledge-recover.sh "<retro-session-id>"` で復旧する。スクリプトは staged 変更を unstage してから HEAD 追跡ファイルの worktree を復元し（HEAD に無い staged 新規ファイル — コミット失敗直後の生成物 — は削除せず untracked へ戻して退避対象に含める。tracked/staged が皆無の初回実行時は復元を skip する）、残る untracked 生成物（`.gitattributes` 等のドットファイルを含む）を `.iterate-team/state/<retro-session-id>/failed-retrospective/` へ退避して作業ツリーを clean に戻す（生成物は人間の事後調査用に温存し、`git clean` は使わない）。1 件以上退避した場合は退避先の相対パスを stdout に1行出力し、clean 化成功で exit 0、失敗時は stderr 診断 + exit 1 を返す
2. 作成した `<retro-branch>` にコミットが 1 件もない（`<original-branch>` と同一 SHA）場合は `Bash git switch "<original-branch>"` の後 `Bash git branch -D "<retro-branch>"` でブランチを削除する。コミットが残っている場合は削除せずブランチのみ残し `<original-branch>` へ戻る
3. `<plugin_root>/scripts/runlog-append.sh <retro-session-id> retrospective_failed '{"mode":"deep","reason":"<理由>","evacuated_to":"<退避先ディレクトリ。手順1でスクリプトが退避先を出力した場合のみ含める>"}'` を追記する
4. 失敗理由をユーザーへ報告して終了する

## 引数

`$ARGUMENTS`: `[--sessions <N>] [--no-push]`
