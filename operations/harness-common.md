# ハーネス共通 runbook（/iterate-team / /iterate-plan / /iterate-build / /iterate-review）

> 本書は team ハーネス（`/iterate-team` / `/iterate-plan` / `/iterate-build` / `/iterate-review`）の共通手順 SoT（Single Source of Truth）。team 固有差分は各セクション末尾の `> **team 固有**:` 引用ブロックで併記する。固有の挙動詳細は `iterate-team-runbook.md` を参照。

## 必須遵守事項

- **回答は日本語、結論ファースト、簡潔に**
- 挨拶・前置き・段階報告・絵文字は禁止
- 各 subagent 呼出時は **Agent ツール** を使う（`subagent_type` に該当 agent 名）

> **team 固有**:
>
> - 各 subagent の `subagent_type` には `team-` prefix を付ける
> - **`git push` の直接呼び出し禁止**。push はすべて `team-publisher` Agent 経由のみ。team-publisher は内部で `Bash(<plugin_root>/scripts/team-push-branch.sh <branch>)` ラッパー経由でのみ push を呼び、`Bash(git push *)` は `permissions.deny` で完全遮断する設計
> - **PR 作成 / 本文更新 / Ready 化は Orchestrator が実行環境で利用可能な手段を選択して実施**（team-publisher は push 専任）
> - **Draft PR の作成は同一 session 内で 1 回のみ**（修正フロー後の再走行時は同一 PR の本文を更新する）
> - 並列度上限 `team_max_parallel = 4`（Sonnet rate-limit / I/O 競合 / Codex MCP 同時セッション安全側）

## knowledge ダイジェスト注入（全コマンド共通）

確定値の正本は [`knowledge-policy.md#7-注入規約`](./knowledge-policy.md#7-注入規約)。本節は Orchestrator 側の共通手順のみを扱う。

Orchestrator はステップ 0.0（session-init 取得）で `<knowledge_digest_path>` = `<repo-root>/.iterate-team/knowledge/lessons.md` の絶対パスを in-memory 保持する。**ファイル不在でもパスは保持したまま進む**（存在チェックは行わない。注入対象 agent 側が `Read` 失敗時に黙って skip する規約のため）。`lessons.md` は git 管理外の生成物（`knowledge-policy.md` §2）であり、SessionStart hook が `lessons.jsonl` の存在時に再生成するため、通常セッションでは既に存在している（fresh clone 直後・並走セッションのマージ直後に生じうる不在・stale をこの hook 再生成が解消する）。knowledge 未導入リポジトリ等で `lessons.jsonl` 自体が無い場合は `lessons.md` も生成されず、その場合も従来どおり注入対象 agent 側が `Read` 失敗時に黙って skip する。

注入対象は以下の 5 agent に限定する（prompt bloat 抑制）。

- `team-planner`
- `team-generator`
- `team-evaluator`
- `team-interviewer`
- `team-test-coder`

上記 5 agent の**すべての起動プロンプト**（初回起動・再起動・差し戻し起動を問わず）に `knowledge_digest_path=<絶対パス>` を、`plugin_root=<絶対パス>` と同じ注入規約で含める。それ以外の agent（`team-closer` / `team-refactor` / `team-advisor-*` / `team-publisher` / `team-reviewer-*` / Codex 系等）には注入しない。

agent 側の適用規則（対象セクションの限定・タスク仕様との矛盾時の劣後・`lesson_applied` の記録条件）は [`templates/_partials/knowledge-injection.md`](../templates/_partials/knowledge-injection.md) を参照。

**代理記録の義務**: 注入対象 5 agent のうち Bash を持たない agent（`team-planner` / `team-interviewer`）は `runlog-append.sh` による `lesson_applied` の自己記録ができない。これらの agent の戻り値に `適用レッスン: L-...` 行が含まれる場合、Orchestrator は各 `lesson_id` につき以下を実行して代理記録する。ただし、記録するのは `lesson_id` が形式 `L-<YYYYMMDDTHHmm>-<4hex>`（正規表現 `L-[0-9]{8}T[0-9]{4}-[0-9a-f]{4}`）に一致する場合のみとし、不一致の文字列は記録しない。agent の戻り値テキストは自由記述であり、形式不一致の文字列を `lesson_applied` として記録すると集計（`applied_count` 反映・減衰判定）を汚染するためである:

```bash
<plugin_root>/scripts/runlog-append.sh "<session-id>" lesson_applied '{"lesson_id":"L-...","agent":"<agent名>","recorded_by":"orchestrator"}'
```

**二重記録の防止**: Bash を持つ agent（`team-generator` / `team-evaluator` / `team-test-coder`）は自己記録するため、これらの戻り値の `適用レッスン:` 行に対して Orchestrator は代理記録**しない**。

規約の対は `templates/_partials/knowledge-injection.md` 規則3。値の正本は [`knowledge-policy.md#7-注入規約`](./knowledge-policy.md#7-注入規約)。

> **team 固有**: knowledge への書き込み主体はステップ 6.7（軽量レトロスペクティブ）と `/iterate-retrospect`（deep レトロスペクティブ）の `team-retrospector` のみに限定される。詳細は `iterate-team-runbook.md#ステップ-67-軽量レトロスペクティブ` を参照。

## adapter 注入（全コマンド共通）

確定値の正本は [`adapter-policy.md#5-注入規約`](./adapter-policy.md#5-注入規約)。本節は Orchestrator 側の共通手順のみを扱う。

Orchestrator はステップ 0.0（session-init 取得）で `<adapter_dir>` = `<project_dir>/.agent-os` の絶対パスを in-memory 保持する。**ファイル・ディレクトリ不在でもパスは保持したまま進む**（存在チェックは行わない。注入対象 agent 側が `Read` 失敗時に黙って skip する規約のため）。`.agent-os/` は git 管理対象の生成物（`adapter-policy.md` §2）であり、`/iterate-adapt` を未実行のリポジトリでは存在しない。その場合も従来どおり注入対象 agent 側が `Read` 失敗時に黙って skip する。

注入対象は knowledge ダイジェスト注入と同じ以下の 5 agent に限定する（prompt bloat 抑制）。

- `team-planner`
- `team-generator`
- `team-evaluator`
- `team-interviewer`
- `team-test-coder`

上記 5 agent の**すべての起動プロンプト**（初回起動・再起動・差し戻し起動を問わず）に `adapter_dir=<絶対パス>` を、`plugin_root`/`knowledge_digest_path` と同じ注入規約で含める。それ以外の agent（`team-closer` / `team-refactor` / `team-advisor-*` / `team-publisher` / `team-reviewer-*` / `team-profiler` / Codex 系等）には注入しない。

agent 側の適用規則（対象ファイルの意味づけ・優先順位・`adapter_applied` の記録条件）は [`templates/_partials/adapter-injection.md`](../templates/_partials/adapter-injection.md) を参照。

**代理記録の義務**: 注入対象 5 agent のうち Bash を持たない agent（`team-planner` / `team-interviewer`）は `runlog-append.sh` による `adapter_applied` の自己記録ができない。これらの agent の戻り値に `適用ルール: <rule-name>` 行が含まれる場合、Orchestrator は各 `<rule-name>` につき以下を実行して代理記録する。ただし、ルール名は knowledge の `lesson_id`（`L-...`）のような厳密な正規表現を持たない自由記述であるため、記録するのは `<rule-name>` が `<adapter_dir>/learned-rules.md`（または split 後の `rules/*.md` いずれかのファイル）内の `## Rule: <name>` 見出しと一致する場合のみとし、一致しない文字列は記録しない。agent の戻り値テキストは自由記述であり、形式不一致の文字列を `adapter_applied` として記録すると集計（適用実績の追跡）を汚染するためである:

```bash
<plugin_root>/scripts/runlog-append.sh "<session-id>" adapter_applied '{"rule":"<rule-name>","agent":"<agent名>","recorded_by":"orchestrator"}'
```

**二重記録の防止**: Bash を持つ agent（`team-generator` / `team-evaluator` / `team-test-coder`）は自己記録するため、これらの戻り値の `適用ルール:` 行に対して Orchestrator は代理記録**しない**。

規約の対は `templates/_partials/adapter-injection.md` §3。値の正本は [`adapter-policy.md#5-注入規約`](./adapter-policy.md#5-注入規約)。

> **team 固有**: `.agent-os/` の観測・生成主体は `/iterate-adapt` の `team-profiler`（および Phase 2 の `team-adapter`）のみに限定される。詳細は `adapter-policy.md` §6 を参照。

## フィードバック捕捉ステージング（capture、全コマンド共通）

確定値の正本は [`adapter-policy.md#6-書き手隔離`](./adapter-policy.md#6-書き手隔離)（`.agent-os/` への書き込み主体は `team-profiler`/`team-adapter` の 2 agent のみ）と `adapter-policy.md` §7（コミット・push フロー / fail-open）。本節は Orchestrator 側の **捕捉（capture）** 手順のみを扱う。捕捉と学習（learn）は物理的に分離されたステップである: `/iterate-plan` → `/iterate-build` → `/iterate-review` は `--session` で引き継がれる別プロセス起動のため、捕捉時点で `.agent-os/` へ直接書き込むことはできない。学習（`.agent-os/` への実書き込み）は `/iterate-review` の直列ステップ（ステップ 6.8。詳細は [`iterate-team-runbook.md#ステップ-68-adapter-学習`](./iterate-team-runbook.md#ステップ-68-adapter-学習)）でのみ行う。

**§6 遵守（重要）**: Orchestrator は捕捉時点で `.agent-os/` を一切 `Write`/`Edit` しない。捕捉したテキストは git 除外の `.iterate-team/state/<session-id>/pending-feedback/` へ一時ステージングするのみである。

### ステージング先とファイル命名

- ディレクトリ: `.iterate-team/state/<session-id>/pending-feedback/`（`.iterate-team/state/` 配下のため git 除外・既存の `Write(.iterate-team/state/*/**)` 許可でカバーされる。新規権限は不要）
- 1 訂正につき 1 ファイル: `<seq>-<source>.txt`（`<seq>` はゼロ埋め連番、例 `001` / `002`。`<source>` は `interviewer` | `plan-approval` | `review` のいずれか）
- 本文はユーザーの訂正テキストを**逐語のまま**（言い換えない・要約しない）格納する
- 任意サイドカー: `<seq>-<source>.context`（1 行のタスク/PR 文脈。例: `task-1_2_3` / `PR #42`）

### 捕捉ポイント

1. **`team-interviewer` step 2.5**: interviewer ラウンドがユーザー自身の言葉による訂正・恒常的な好み（`AskUserQuestion` の回答文そのもの）を検知した場合、当該テキストを `source=interviewer` としてステージングする
2. **計画承認 step 4（修正フロー）**: ユーザーの「修正」/「却下」指示に訂正内容が含まれる場合、`source=plan-approval` としてステージングする
3. **review（`/iterate-review`）**: レビューフェーズ中にユーザーが自由記述で訂正・是正指示を行った場合（`/iterate-review` は既存の対話的承認ステップを持たないため、Orchestrator の完了報告・エスカレーション等に対するユーザーの返信を含む、任意のタイミングを指す）、`source=review` としてステージングする

いずれの捕捉ポイントも Orchestrator が `Write` ツールで直接書き込む（既存の `Write(.iterate-team/state/*/**)` 許可でカバー、新規許可不要）。書き込み直後に軽量な runlog マーカーを追記する（**逐語テキストは runlog に含めない**）:

```bash
<plugin_root>/scripts/runlog-append.sh "<session-id>" feedback_staged '{"source":"<interviewer|plan-approval|review>","seq":<n>}'
```

ステージングされたファイル群は `/iterate-review` ステップ 6.8 で `team-adapter`（`mode=feedback`）の入力 `pending_feedback` 配列（`[{"text":...,"context":...,"source":...}]`）に変換され、学習コミット成功後にクリアされる。手順の正本は [`iterate-team-runbook.md#ステップ-68-adapter-学習`](./iterate-team-runbook.md#ステップ-68-adapter-学習) を参照。

> **team 固有**: 上記 3 捕捉ポイントの Orchestrator 手順詳細は `iterate-team-runbook.md` の該当ステップ（[ステップ 2.5](./iterate-team-runbook.md#ステップ-25-要件壁打ちteam-interviewer-ループ) / ステップ 4 修正フロー / [ステップ 6.8](./iterate-team-runbook.md#ステップ-68-adapter-学習)）を参照。

## 引数

要望文: `$ARGUMENTS`

許容形式（先頭または `--resume <path>` / `--resume-checkpoint <session-id>` 直後にのみ `--model <id>` 配置可）:

- `/iterate-team [--model <id>] <要望文>`
- `/iterate-team [--model <id>] --resume <path>` / `--resume <path> --model <id>` の順序入替も許容
- `/iterate-team [--model <id>] --resume-checkpoint <session-id>` / `--resume-checkpoint <session-id> --model <id>` の順序入替も許容（途中ステップから再開）

## ステップ 1: 引数処理

### 1.0 `--model` 前処理

`$ARGUMENTS` に `--model <id>` が含まれる場合（先頭、または `--resume <path>` の直後）:

1. `<id>` が空、または `--` で始まる別オプションの場合: Usage を返して処理中止
2. `<id>` が `[A-Za-z0-9._-]+` パターンに一致しない場合（禁止文字を含む等）: Usage を返して処理中止
3. パターン一致時のみ in-memory `<model_override>` に保持し、`--model <id>` 部分を除いた残りを以降の引数として扱う

`--model` を含まない場合は本節をスキップして 1.1 / 1.2 へ進む。

### 1.1 通常起動

`$ARGUMENTS` が空または空白のみの場合、`AskUserQuestion` で「実装したい要望を 1〜数行で教えてください」（自由記述）を尋ね、回答を要望文として採用する。

### 1.2 resume 起動

`$ARGUMENTS` の先頭が `--resume <path>` の場合:

1. `<path>` が `.usermemo/requirements-resume-*.md` パターンに一致するか確認。一致しない場合は処理中止
2. `Bash test -f <path>` で存在確認。存在しない場合は処理中止
3. `Read` で frontmatter / 「元の要望文」セクションから `topic_slug` と原要望文を抽出
4. 抽出した要望文を採用し、resume フラグと `<resume-file-path>` を保持してステップ 2 へ。新規 session-id を発行（前回の session-id は引き継がない）

### 1.3 checkpoint resume 起動

`$ARGUMENTS` の先頭が `--resume-checkpoint <session-id>` の場合（コンテキスト圧縮で途中停止したセッションを継続する経路）:

1. `<session-id>` バリデーション（`[A-Za-z0-9._-]+`、空でない）。不正なら処理中止
2. `Bash test -f .iterate-team/state/<session-id>/runlog.jsonl` で存在確認。存在しない場合は処理中止
3. `Bash tail -n 200 .iterate-team/state/<session-id>/runlog.jsonl | jq -c 'select(.event=="step_checkpoint")' | tail -n 1` で最終 checkpoint を取得。0 件なら処理中止（checkpoint 未生成のセッションは再開不可）
4. checkpoint payload の各キー（`step` / `topic_slug` / `plan_revision` / `integration_branch` / `current_task_id` / `current_attempt` / `completed_task_ids` / `wave_index` / `completed_wave_indices` / `advisor_pending` / `plan_review_round` / `next_step`）を in-memory 変数へ復元（`integration_branch` は team の HEAD 整合検証 (c) と worktree 操作で使用。`plan_review_round` は team の計画レビューループ上限判定に使用し、キーが無い旧 checkpoint との互換では 0 として扱う）
5. **state ファイル群の存在再認識**（in-memory に load せず、存在確認のみで Read は後続ステップ責務）:
   - `Bash test -f .iterate-team/tasks/<yyyyMMdd_topic-slug>/plan.json` で plan ファイル群存在確認。欠落なら処理中止
   - `Bash test -f .iterate-team/tasks/<yyyyMMdd_topic-slug>/plan-summary.md` 同上
   - 復元 `current_task_id` が非 null なら `Bash test -f .iterate-team/tasks/<yyyyMMdd_topic-slug>/<task-x_y_z>.md` で task ファイル存在確認
   - 復元 `current_attempt` が非 null かつ `current_task_id` が非 null なら、`Glob .iterate-team/state/<session-id>/tasks/<task-id>/eval-attempt-*.md` と `Glob .iterate-team/state/<session-id>/responses/{codex,code}-review-<task-id>-attempt-*.md` で **attempt 系列の最大値を再認識**（後続ステップ 5 のリトライカウンタに使う）
   - `advisor_pending=true` なら `Glob .iterate-team/state/<session-id>/requests/*.json`（`processed/` 除外）で **未処理 advisor request の有無を再認識**。出現していれば 5.2 advisor 招集経路へ合流する状態として in-memory フラグを立てる
   - **`completed_task_ids` に含まれる task は ステップ 5 のトポロジカルソート結果から skip**（再実行しない）。次に実行すべき task は plan.json の depends_on 順序のうち `completed_task_ids` に含まれない最初の要素
6. **team 限定: wave 状態の再認識**（`/iterate-team --resume-checkpoint` のみ）:
   - `Bash <plugin_root>/scripts/team-compute-waves.sh <plan-json-path>` を再実行し wave 列を再構築
   - 復元 `completed_wave_indices` に含まれる wave は **すべて完了済みとして skip**（同 wave_index を再度処理しない）。次に実行すべき wave は wave 列のうち `completed_wave_indices` に含まれない最小の index
   - 再開対象 wave 内 task の worktree 状態を `Bash git worktree list` で確認（既存 worktree は再利用、欠落 worktree のみ `team-worktree-setup.sh` で再生成）
   - branch ガード / モデル判定（preflight 0.1 / 0.2）は **再開時も必ず実行**（session-init は再取得済み）。preflight session-id 発行のみ skip
7. `<session-id>` をそのまま継続使用（**新規 session-id 発行はスキップ**）
8. runlog 追記 `session_resumed_from_checkpoint` / `{checkpoint_step, next_step, restored_task_id, restored_attempt, completed_task_ids, advisor_pending, restored_wave_index, completed_wave_indices}` → checkpoint の `next_step` が指すステップへ直接ジャンプ

詳細は本書末尾「コンテキスト圧縮（auto-compaction）対策と checkpoint resume」セクションを参照。

## ステップ 2: session-id の発行

- `<session-id>` = `YYYYMMDDHHmm_<topic-slug>`
- `<topic-slug>` は Planner が命名する（ステップ 3 で確定）。本ステップでは仮 ID として `YYYYMMDDHHmm_pending` を使い、Planner 完了後に正式名へリネームする。日時は `date +%Y%m%d%H%M` で取得
- ディレクトリ作成: `.iterate-team/state/<session-id>/{tasks,requests/processed,responses}`
- runlog 追記は **必ず `<plugin_root>/scripts/runlog-append.sh` 経由**（`Write` で `runlog.jsonl` を直接編集してはならない）:

  ```bash
  <plugin_root>/scripts/runlog-append.sh "<session-id>" session_start '{"request":"<要望文>"}'
  ```

  `ts` / `event` / `session_id` はスクリプトが自動付与するため payload に含めない。

  `--model` 指定時は payload に `model_override` を追加し、`session_start` 直後に `agent_decision` を記録:

  ```bash
  <plugin_root>/scripts/runlog-append.sh "<session-id>" session_start '{"request":"<要望文>","model_override":"<id>"}'
  <plugin_root>/scripts/runlog-agent-decision.sh "<session-id>" orchestrator invoked "--model <id> でユーザ明示指定"
  ```

  以降「runlog 追記: `{ "event": "<name>", ... }`」と書かれた箇所はすべて本スクリプト経由（event 名は第 2 引数、残りキーを JSON payload として第 3 引数）で実行する。

**ステップ 2 完了直後の `step_checkpoint` 追記**（本書「コンテキスト圧縮対策」規約 1 を本ステップでも実体化）:

```bash
<plugin_root>/scripts/runlog-append.sh "<session-id>" step_checkpoint '{"step":"2","topic_slug":"<topic-slug or pending>","plan_revision":0,"current_task_id":null,"current_attempt":null,"wave_index":null,"advisor_pending":false,"next_step":"2.5"}'
```

> **team 固有**:
>
> - `<session-id>` = `team_<YYYYMMDDHHmm>_<topic-slug>`（仮 ID は `team_<YYYYMMDDHHmm>_pending`）
> - runlog 追記は flock ガード適用済み（並列 append 対応）
> - **preflight session-id**（`team_<YYYYMMDDHHmm>_preflight`）をステップ 0 の環境ガード用に先行発行する（詳細: `iterate-team-runbook.md#ステップ-0-環境ガード-preflight`）

## ステップ 3: Planner 起動と研究ループ

### 3.1 初回起動

`Agent` ツールで `subagent_type: planner` を指定し、ステップ 2.5 で確定した `<summary_path>`（`requirements-summary.md` の絶対パス）をプロンプトに含めて起動する。Planner は最初に当該ファイルを `Read` してから本処理に入る。**要望文の原文は Planner に直接渡さない**（推測補完を防ぐため。原文は `requirements-summary.md` の「元の要望文」セクションに保持されている）。

### 3.2 戻り値の解析

Planner の戻り値テキストを末尾から走査し、JSON フェンス（` ```json ... ``` `）を探す。

#### パターン A: JSON フェンスあり（research / debug / trace / interview request）

JSON を parse し、共通必須フィールド（`request_id` `from=planner` `type` `created_at`）を検証。parse 失敗または共通フィールド欠落時はステップ 9。

**Planner 委譲累計カウンタ**: research / debug / trace / interview の 4 種を横断して 1 本に合算する。**累計が 5 回を超過した時点で強制終了しステップ 9 へ**。

各 type 別の処理（runlog 追記 → Agent 起動 → 応答 Write → Planner 再起動 → カウンタ +1）の詳細仕様は `iterate-team-runbook.md` を参照。

#### パターン B: JSON フェンスなし（計画完了）

Planner が `.iterate-team/tasks/<yyyyMMdd_topic-slug>/plan.md` / `plan-summary.md` / `plan.json` / `task-x_y_z.md` 群を書き終えた状態。

1. `<topic-slug>` を Planner 戻り値から取得（`plan.md` 本文は読まない）
2. `Read` で `plan.json` のみを読み込み、各 task エントリの `executor` が `generator`、`reviewer` が `codex | none` のいずれか、`id` / `depends_on` / `max_retries` / `required_advisors` の各キーが存在することを検証。`plan.md` / `plan-summary.md` / `task-x_y_z.md` は `Bash test -f` のみ
3. **`Bash <plugin_root>/scripts/validate-plan.sh <plan-json-path> <tasks-dir>`** を実行。`tasks[]` と各 `task-x_y_z.md` frontmatter（6 キー）の整合を検証。exit code != 0 ならステップ 9
4. 仮 session-id `<YYYYMMDDHHmm>_pending` を正式名へリネーム（初回のみ。`test -d` で確認後 `mv`）
5. runlog 追記: `plan_ready` / `{topic_slug, task_count}`
6. **Planner 出力コミットの発行**（後述）
7. **ステップ 3 完了 `step_checkpoint` 追記**: `<plugin_root>/scripts/runlog-append.sh "<session-id>" step_checkpoint '{"step":"3","topic_slug":"<topic-slug>","plan_revision":<rev>,"plan_review_round":<current_value>,"current_task_id":null,"current_attempt":null,"wave_index":null,"advisor_pending":false,"next_step":"3.5"}'`（`plan_review_round` は in-memory の現在値。初稿時は 0、REQUEST_CHANGES 起因の replan 後はインクリメント済み値 — ここで `null`/0 にすると resume で消費済みラウンドが失われ `>= 3` ループストッパーを回避できてしまう）
8. ステップ 3.5 へ進む

#### Planner 出力コミットの発行

1. **`plan_revision` カウンタ管理**: in-memory カウンタ。`/iterate-*` 起動時に 0 で初期化、Planner 出力コミット発行のたびに `+= 1`（初稿は 1）。resume 起動時も 0 から再開
2. **個別 `git add`** を実行（`git add -A` / `git add .` は禁止）:

   ```bash
   git add .iterate-team/tasks/<yyyyMMdd_topic-slug>/plan.md
   git add .iterate-team/tasks/<yyyyMMdd_topic-slug>/plan-summary.md
   git add .iterate-team/tasks/<yyyyMMdd_topic-slug>/plan.json
   git add .iterate-team/tasks/<yyyyMMdd_topic-slug>/task-*.md
   ```

3. コミット subject は `plan_revision` で切替:
   - `plan_revision == 1`: `docs: <topic-slug> の実装計画初稿を追加`（body に plan-summary 冒頭を 1〜2 行転記）
   - `plan_revision >= 2`: `docs: <topic-slug> の実装計画を修正（rev <plan_revision>）`（body に修正点要約 or「Codex/フォールバックレビュー rev <N> の指摘を反映（自動修正 round <R>）」）
   - フッタ共通: `Refs: plan-<yyyyMMdd_topic-slug>`

4. runlog 追記: `plan_drafted` / `{revision, commit}`
5. pre-commit hook 失敗時はステップ 9（`--no-verify` バイパス禁止）

> **team 固有**:
>
> - subagent 名は `team-planner`、共通必須フィールドの `from` は `from=team-planner`
> - **複数 request 並列起動**: 1 戻り値で複数の research / debug / trace request を同時発行可。Orchestrator は 1 メッセージ内に `min(N, team_max_parallel=4)` 個の Agent 呼びを並列発行（チャンク分割対応）。Planner 委譲累計カウンタは発行件数分インクリメント
> - パターン B step 3 は `Bash <plugin_root>/scripts/team-validate-plan.sh <plan-json-path> <tasks-dir>` を使用（validate-plan + compute-waves のサイクル/不明依存検出が併走）
> - 詳細: `iterate-team-runbook.md#ステップ-3-planner-起動と研究ループ`

## ステップ 4: 計画承認（AskUserQuestion）

`Read` で `plan-summary.md` のみを読み込み、ユーザに提示する（`plan.md` 本文は読まない）。続いて `AskUserQuestion` で以下を尋ねる:

- 質問: 「上記の計画で実行しますか？」
- 選択肢: `承認` / `修正` / `却下`

### 承認後の処理

原則として **`git commit` を発行しない**（plan ファイル群は「Planner 出力コミットの発行」で既に積まれている）。意思決定イベントは runlog で追跡する。

1. `git status --porcelain -- .iterate-team/tasks/<yyyyMMdd_topic-slug>/` で当該ディレクトリ配下に未コミット差分が無いことを確認
2. **差分なし**: runlog 追記 `plan_approved` / `{approved_revision}` のみで完結
3. **差分あり（例外、手動編集等）**: 「承認時補正」として追加コミット発行（個別 `git add`、subject `docs: <topic-slug> の実装計画 承認時補正`、フッタ `Refs: plan-<yyyyMMdd_topic-slug>`）。その後 runlog 追記 `plan_approved` / `{approved_revision, amend_commit}`
4. **ステップ 4 完了 `step_checkpoint` 追記**: `<plugin_root>/scripts/runlog-append.sh "<session-id>" step_checkpoint '{"step":"4","topic_slug":"<topic-slug>","plan_revision":<approved_rev>,"integration_branch":"<integration-branch>","from_branch":"<from_branch>","plan_approved":<true|false>,"current_task_id":null,"current_attempt":null,"wave_index":null,"advisor_pending":false,"next_step":"4.5"}'`（team は `4.5` を `next_step` に設定）。**`integration_branch` に正式名の統合ブランチ（ステップ 3.x で rename 済み）を必ず含める**（別セッションで `/iterate-build` が HEAD 整合検証 (c) と `team-worktree-setup.sh` 引数の確定に使用するため）。`plan_approved` は「本ステップ 4 で承認を取得済みか」を表す（team は環境分岐。後段 `/iterate-build` が二次承認の要否判定に参照する）。`from_branch` は team の派生元ブランチ（既定 `main`、`--from-branch` 指定値）。別セッションの `/iterate-build` が 4.5.A.3 の PR base に使用する

### 修正フロー

修正点を受け取ったら:

1. **`plan_review_round = 0` にリセット**（ユーザー修正フローは新しいレビュー系列として扱い自動修正予算 3 を再付与）
2. Planner を再起動（プロンプトに「修正点 + 既存 plan-summary.md / plan.json のパス」を渡す）
3. Planner が plan ファイル群を上書き Write 後、ステップ 3.2 パターン B から再走行（`validate-plan.sh` → Planner 出力コミット `plan_revision += 1`）
4. ステップ 3.5（計画レビュー）→ ステップ 4 を再度実行

ユーザの修正点指示は Orchestrator が in-memory に保持し、次回の Planner 出力コミット body に転記する。

**フィードバック捕捉（Phase 2）**: 修正点テキストに訂正・恒常的な是正が含まれる場合、上記の in-memory 保持に加えて `source=plan-approval` として [「フィードバック捕捉ステージング」節](#フィードバック捕捉ステージングcapture全コマンド共通) の手順でステージングする（`.agent-os/` への直接書き込みは行わない）。

> **修正フローは 2 経路ある（Planner 側からは同一処理に集約）**:
>
> - **経路 A: ユーザ修正点指示**（本節、ステップ 4 で「修正」が選択されたとき）
> - **経路 B: 計画レビュー応答**（ステップ 3.5、レビュアが REQUEST_CHANGES を返したとき）

### 却下フロー

runlog 追記 `rejected` / `{rejected_revision}`、その後終了。**初稿コミットは残す（revert / reset / ロールバックしない）**。生成済み plan ファイル群もそのまま保持し、ユーザー手動編集で継続可能な状態にする。

> **team 固有（承認は環境ごとに 1 回だけ。二重承認を廃止）**:
>
> - **`<is_dev_container>=true`**: 本ステップ 4 の `AskUserQuestion`（`承認`/`修正`/`却下`）を **唯一の承認**とする。dev container では Draft PR を作成できないため、ここで承認を取得する。承認後は `plan_approved=true` を checkpoint に記録し、ステップ 4.5（dev container 経路）では**二次承認を行わず**そのまま実装着手する。
> - **`<is_dev_container>=false`**: 本ステップ 4 では `AskUserQuestion` を**出さない**。`plan-summary.md` を提示し runlog 追記 `plan_presented` / `{presented_revision}` で通過する（`plan_approved=false`）。承認はステップ 4.5（host 経路）で Draft PR 作成後に **1 回だけ**行う（`承認`/`修正`/`却下` は 4.5 で受け付ける）。
> - いずれの経路も `step_checkpoint` に `plan_approved`(bool) を必ず含める（別セッションの `/iterate-build` が二重承認防止のため参照）。
> - 修正フローのカウンタ名は `plan_review_round`（Codex / フォールバック両経路で共通）
> - 詳細: `iterate-team-runbook.md#ステップ-45-承認環境分岐承認は通算-1-回`

## ステップ 6: 全タスク完了 — closer 委譲

全タスクが OK で完了したら:

1. `Agent` ツールで `subagent_type: closer` を起動。プロンプトに `<topic-slug>` / `<tasks-dir>`（絶対パス）/ `<plan-json-path>`（絶対パス）/ `<session-id>` を渡す
2. closer の戻り値からコミットハッシュ `<hash>` と更新タスク数 N を抽出。closer は内部でチェックリスト一括 Edit、個別 `git add`、1 コミット発行、`closer_completed` runlog 追記までを完結させる。**Orchestrator は `task-x_y_z.md` を直接 Edit しない**
3. runlog 追記: `all_tasks_completed` / `{total_attempts, checklist_commit}`
4. **ステップ 6 完了 `step_checkpoint` 追記**: `<plugin_root>/scripts/runlog-append.sh "<session-id>" step_checkpoint '{"step":"6","topic_slug":"<topic-slug>","plan_revision":<rev>,"current_task_id":null,"current_attempt":null,"wave_index":null,"advisor_pending":false,"next_step":"7"}'`（team / host 環境では `next_step:"6.5"`）
5. ステップ 7 へ進む

> **team 固有**:
>
> - subagent 名は `team-closer`。メイン worktree（統合ブランチ）でチェックリスト一括 Edit + 1 コミット集約（フッタ `Refs: plan-<topic-slug>`）
> - closer 完了後、host 環境のみステップ 6.5（実装コミット群 push）→ ステップ 7（PR Ready 化）。dev container 環境はステップ 7'（引き継ぎ案内）へ
> - 詳細: `iterate-team-runbook.md#ステップ-6-5-実装コミット群の-push`

## ステップ 8: 失敗時挙動

以下のいずれかに該当した場合、即座にステップ 9 へ:

- Planner / Generator の戻り値 JSON parse 失敗
- advisor request ファイルの必須フィールド欠落 / 値不正
- subagent 呼出が想定外のエラーで終了
- Planner 委譲（research / debug / trace / interview）累計呼出が 5 回超過（4 種横断で合算）
- Generator が advisor request 書込に失敗（権限・ディスク等）

> **team 固有の追加エラー**:
>
> - `team-worktree-setup.sh` / `team-worktree-merge.sh` / `team-worktree-cleanup.sh` のいずれかが想定外の exit code
> - team-publisher Agent が `validation_failed` で戻る（push 失敗）
> - PR 作成 / 本文更新 / Ready 化が失敗
> - merge conflict（team-worktree-merge.sh exit 1）
> - dirty task worktree（team-worktree-merge.sh exit 3 + `DIRTY_TASK_WORKTREE`）→ マージせずエスカレーション・クリーンアップ保留（未コミット差分の取りこぼし防止）
> - Codex MCP tool 経路固有: timeout / `codex_plan_review_invalid_format` / `codex_review_invalid_format`
> - フォールバック経路固有: `team-reviewer-plan` / `team-reviewer-code` 起動失敗 / `plan_review_invalid_format` / `code_review_invalid_format`
> - 詳細: `iterate-team-runbook.md#ステップ-8-失敗時挙動`

## ステップ 9: エスカレーション（max_retries 超過時など）

> **`<task-id>` の決定規則**: タスクループ（ステップ 5）以降での失敗時は当該 `task-x_y_z` をそのまま用いる。**タスクループ前のエスカレーション**（計画レビュー 4 連続 REQUEST_CHANGES などステップ 3.5 由来）の場合、実行中タスクが存在しないため疑似 task-id `plan-review` を用いる（`tasks/plan-review/` ディレクトリを `mkdir -p` してから escalation.md を生成）。Planner 委譲累計超過（ステップ 8）由来の場合は疑似 task-id `planner-loop`。

1. `.iterate-team/state/escalation-template.md` を `Read` し、雛形として `.iterate-team/state/<session-id>/tasks/<task-id>/escalation.md` を `Write`
2. 雛形のプレースホルダを埋める:
   - 症状: 直近の `eval-attempt-N.md` の要約 / または失敗イベント名
   - 試行履歴: 当該タスクの全 `eval-attempt-*.md` の要約
   - 推奨次手: Evaluator の最後のヒント or 「人間判断が必要」
3. runlog 追記: `escalated` / `{task_id, escalation_path}`
4. **当該タスク以降の自動進行を停止**し、ユーザーに以下を報告:
   - エスカレーション発生タスク / 理由 / `escalation.md` のパス
   - 既に完了したタスクは保持（ロールバックしない）

> **team 固有の疑似 task-id**:
>
> - 計画レビュー由来（Codex 経路 / フォールバック経路の両方）→ `plan-review`
> - コードレビュー由来 → 当該 `task-x_y_z`（タスクループ内のため）
> - Planner 委譲累計超過 → `planner-loop`
> - wave 計算失敗 → `wave-compute`
> - merge conflict → 当該 `<task-id>`
> - PR 作成失敗 → `pr-create`

## コンテキスト圧縮（auto-compaction）対策と checkpoint resume

### スコープと制約

Claude Code の **auto-compaction 発動タイミングそのものは Orchestrator から完全制御できない**（Claude Code 側のヒューリスティクスに従う）。したがって本セクションが提供するのは以下の 2 つのみ:

1. **発動時に被害を最小化する**: subagent 戻り値本文を context に残さず、応答ファイルパスのみを保持する（規約 3）→ context window 消費を抑え発動頻度を下げる
2. **発動して session が停止しても次セッションで途中再開できる**: 各ステップ完了直後に `step_checkpoint` を runlog に永続化し、`--resume-checkpoint <session-id>` で `next_step` から復元する（規約 1 / 2）

「ステップ途中で compaction が発動した瞬間に処理を継続できる」性質は本対策の射程外である。途中で停止した場合は、ユーザが手動で `/iterate-team --resume-checkpoint <session-id>` を再実行する運用を前提とする。

### 規約 1: 各ステップ完了直後に `step_checkpoint` を必ず追記

各ステップ（2 / 2.5 / 3 / 3.5 / 4 / 4.5 / 5.0 / 5.1 / 5.2 / 5.3（5.3.0〜5.3.4） / 5.4 / 6 / 6.5 / 7）が完了した直後に、以下を `runlog-append.sh` で必ず追記する:

```bash
<plugin_root>/scripts/runlog-append.sh "<session-id>" step_checkpoint '{
  "step": "<step-id>",
  "topic_slug": "<topic-slug>",
  "plan_revision": <int>,
  "integration_branch": "<integration-branch or null>",
  "from_branch": "<from_branch or null>",
  "plan_approved": <bool or null>,
  "current_task_id": "<task-x_y_z or null>",
  "current_attempt": <int or null>,
  "completed_task_ids": ["<task-x_y_z>", ...],
  "wave_index": <int or null>,
  "completed_wave_indices": [<int>, ...],
  "advisor_pending": <bool>,
  "plan_review_round": <int or null>,
  "next_step": "<step-id>"
}'
```

> **`next_step` の型**: 書き込み時は文字列（`"<step-id>"`）で統一する（例: `"6"` / `"4.5"` / `"3.5-replan"`）。ただし旧 runlog には数値（例: `6`）で書き込まれたレコードが存在し得るため（後方互換）、`--resume-checkpoint` 経路での `next_step` 照合は数値・文字列双方を許容する実装にすること。文字列専用識別子（`"3.5-replan"` 等）は数値表現が存在しないため文字列照合を維持する。

`plan_review_round` は 3.5 関連 checkpoint（3.5 ステップ完了 checkpoint・mid-loop checkpoint）に加え、**ステップ 3 完了 checkpoint でも必ず in-memory の現在値を記録する**（replan 後の Planner 出力直後〜3.5 再レビュー中のクラッシュで消費済みラウンドが 0 に戻るのを防ぐ）。ステップ 4 以降（`next_step` が 4.5 以上）の checkpoint では `null` で可（`--resume-checkpoint` の復元時に 0 フォールバック。3.5 系列へは戻らないため安全）。

未確定値は `null` または空配列で埋める。`from_branch`（team の派生元ブランチ、既定 `main`）と `plan_approved`（ステップ 4 で承認済みか）はステップ 4 以降の checkpoint に含め、`/iterate-build` が PR base と二次承認要否の判定に使用する。`completed_task_ids` / `completed_wave_indices` は **これまで OK 確定済みの集合**を表し、resume 時にこれらを skip して未完了分のみ実行する。**ステップ途中の subagent 戻り値処理が長くなる場合は、subagent 1 件ごとに mini-checkpoint を追記してもよい**（粒度はステップ責務範囲内で Orchestrator が判断）。

### 規約 2: `--resume-checkpoint <session-id>` 起動

ステップ 1 の引数処理に追加経路として、`--resume-checkpoint <session-id>` を許容する:

1. `<session-id>` バリデーション（`[A-Za-z0-9._-]+`、path traversal 防止）
2. `Bash test -f .iterate-team/state/<session-id>/runlog.jsonl` で存在確認
3. `Bash tail -n 200 .iterate-team/state/<session-id>/runlog.jsonl | jq -c 'select(.event=="step_checkpoint")' | tail -n 1` で最終 checkpoint を取得
4. checkpoint の `next_step` を起点に当該ステップへ直接ジャンプ（in-memory 変数は checkpoint payload から復元）
5. runlog 追記 `session_resumed_from_checkpoint` / `{checkpoint_step, next_step}`

`--resume-checkpoint` 取得時は **新規 session-id を発行せず既存 session-id を継続利用**する（task / responses / requests 構造を全継承）。`--resume <path>` との違い: `--resume <path>` は要件再開（新セッション）、`--resume-checkpoint <session-id>` は同一セッションのステップ再開。

### 規約 3: Orchestrator が context に保持する情報の最小化

`harness-common.md#不変条件` の「Orchestrator はパスのみを次の subagent 起動引数に渡す」を強化する形で:

- **subagent 戻り値の本文は context に残さず、必要な抽出値（status / sha / path）のみ in-memory 変数 + runlog に保存してから捨てる**
- 戻り値全文を再参照したい場合は `Read` で当該応答ファイルを読み直す（state に永続化されている前提）
- Researcher / Advisor / Evaluator / Code Review いずれも応答は state にファイルとして残るため、context 上の文字列保持は不要

### 規約 4: ステップ境界でのみ重い処理を行う

- 1 ステップ内で並列起動する subagent 数は `team_max_parallel = 4` を上限とする（既存）
- **ステップを跨いだ並列処理は禁止**（境界ごとに `step_checkpoint` を確実に書き出すため）
- Bash の `run_in_background` を Orchestrator が呼ぶ場合、当該ステップ完了前に foreground で結果取得を完了させる

## 不変条件

- Orchestrator は Researcher / Advisor / Evaluator / Code Review の応答**本体**を context に載せず、**パスのみ**を次の subagent 起動引数に渡す（トークン削減）
- Orchestrator は **`task-x_y_z.md` 本文を `Read` しない**。タスク本文を必要とするのは Generator / Evaluator / closer のみ。Orchestrator は `plan-summary.md`（ユーザ提示）と `plan.json`（実行制御）の 2 ファイルのみを参照する
- subagent → subagent の直接呼出は不可。すべて `request_*` 経由で Orchestrator が中継する
- 各イベントは必ず `runlog.jsonl` に追記する（後追い検証可能性）。追記は `<plugin_root>/scripts/runlog-append.sh` 経由のみで、`Write` で `runlog.jsonl` を直接編集してはならない（`ts` / `event` / `session_id` はスクリプトが自動付与）
- **`executor` の許容値は `generator` のみ**。`codex` は廃止済み値（bwrap sandbox 制約により Codex 経由のコード変更が反映に失敗するため）。`<plugin_root>/scripts/validate-plan.sh` が `INVALID_EXECUTOR` で blocking 検出
- **Codex MCP tool は計画レビュー（ステップ 3.5）とコードレビュー（ステップ 5.3.2、Evaluator 先行ゲートで APPROVED 時のみ起動）の 2 用途でのみ Orchestrator が直接呼び出す**。実装には用いない。sandbox は `read-only` 固定（`workspace-write` / `danger-full-access` 禁止）
- Planner 委譲累計カウンタは **research / debug / trace / interview の 4 種を横断して 1 本に合算** する。上限は累計 5 回
- **Plan コミットは「Planner 出力コミット（最大 3 段、`plan_revision = 1..3`、初稿 + 自動修正最大 2 回）」と「（差分時のみ例外的に）承認時補正コミット最大 1 段」の最大 4 段**。`plan_revision` は in-memory カウンタ管理。Plan コミットは `Refs: plan-<yyyyMMdd_topic-slug>` フッタで識別され、タスク実装コミット（`Refs: task-x_y_z`）とは別系統（`>= 3` 停止との整合: REQUEST_CHANGES ごとに +1 して 3 に達したときエスカレーション = 自動修正は最大 2 回）
- **計画レビューの status 抽出は `## status: APPROVED` または `## status: REQUEST_CHANGES` の厳密一致 + 単一行のみ許容**。N≠1 は契約違反として `*_invalid_format` を追記しステップ 9（複数 status 行併記時に先頭採用するとレビューゲートがバイパスされるため）
- **修正稿レビューは毎回新規 thread**（`mcp__codex__codex`）で評価する（context 累積による評価緩和を防ぐ）
- **計画レビューラウンドカウンタ（`plan_review_round`）は「ステップ 3.5 入口（= `/iterate-*` 起動時）」と「ステップ 4 ユーザー修正フロー起動時」の 2 タイミングのみ 0 へ初期化**する。自動修正ループ内（3.5 → 3.2 パターン B 再走行 → 3.5 再入）では **値を引き継ぐ**（再入のたびに 0 リセットすると上限に到達せず無限ループするため）。`--resume-checkpoint` で 3.5 に戻る場合は `step_checkpoint` payload の当該キーから値を復元し、in-memory 0 初期化で上書きしない（上限判定継続のため）
- **計画レビューによる Planner 再起動は Planner 委譲累計カウンタの 5 回上限に加算しない**（独立経路）
- **Orchestrator は `required_advisors` の残数監視を行わない**。`required_advisors` は Generator が自主消化する
- **`--model <id>` 指定時の Orchestrator モデル切替はユーザの事前 `/model <id>` 切替を前提とする**。`<id>` の実モデル妥当性検証は Claude Code に委譲し、本コマンドでは `[A-Za-z0-9._-]+` の形式チェックのみ。`--model` 未指定時は三次防御（Opus 拒否）が現状維持で動作する（後方互換）

> **team 固有の不変条件**:
>
> - 1 wave 内は並列、wave 間は順次。並列度上限は `team_max_parallel = 4`
> - worktree 内では `npm install` 禁止（`node_modules` は symlink 共有のため symlink 破壊防止）
> - **Orchestrator から `git push` を直接呼ばない**。push は `team-publisher` Agent 経由のみ（内部で `<plugin_root>/scripts/team-push-branch.sh` ラッパー）。`Bash(git push *)` は `permissions.deny` で完全遮断
> - **Draft PR の作成は同一 session 内で 1 回のみ**（再走行時は同一 PR の本文を更新）
> - **`<is_dev_container>=true` の場合、`team-publisher` を一切起動せず、PR 作成 / 本文更新 / Ready 化もすべて skip**。承認はステップ 4 で取得済みのため 4.5.B では承認を求めず（`plan_already_approved`）→ 5 → 6 → 7' 引き継ぎ案内で終了
> - **両経路（Codex / フォールバック）とも `## status: APPROVED|REQUEST_CHANGES` 単一行ガードを適用**。N≠1 は invalid_format
> - **フォールバック経路のサブエージェント（`team-reviewer-plan` / `team-reviewer-code`）は `permissionMode: plan` + tools から Write/Edit/MultiEdit/NotebookEdit/Bash を構造的に除外**した read-only 構成で起動
> - **`team-reviewer-code` は git コマンドを一切実行しない**（`Bash` を tools から除外）。差分情報は Orchestrator がステップ 5.3.B.0 で context ファイルへ書き出してから絶対パスを渡す
> - merge conflict は自動解決禁止（Planner depends_on 設計不備として人間レビューに上げる）
> - `.claude/settings.sandbox.json` は **無修正**（dev container 用 sandbox の `Bash(git push *)` deny を維持）
> - `permissions.allow` には **`<plugin_root>/scripts/team-push-branch.sh` ラッパーのみ登録**
> - 詳細: `iterate-team-runbook.md#不変条件`
