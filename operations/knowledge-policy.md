# knowledge（クロスセッション自己学習）ポリシー

`.iterate-team/knowledge/` に永続化する「教訓（lesson）」の仕組みに関する**確定値の正本（SoT）**である。`knowledge-append.sh` / `knowledge-digest.sh` / `knowledge-prune.sh`（各スクリプト）と、team-retrospector agent、`templates/_partials/knowledge-injection.md`、`/iterate-retrospect` コマンドは、いずれも本書の確定値をそのまま実装する。値の変更・追加解釈は行わない。

## 1. 目的と位置づけ

`runlog.jsonl` に記録された失敗・差し戻し・エスカレーション・ユーザー対話を素材に、教訓（lesson）を抽出して永続化し、次回以降の実行でエージェントに注入する仕組みである。これにより、単一セッション内で閉じていた学習をセッションをまたいで蓄積する。

書き込み主体は **team-retrospector agent のみ** に限定する。

- ステップ 6.7 の軽量レトロスペクティブ（`mode=light`）
- `/iterate-retrospect` の deep レトロスペクティブ

上記以外のステップ・agent からの knowledge 書き込みは禁止する。tracked ファイル（後述）が意図しないタイミングで dirty 化することを防ぐためである。

## 2. ディレクトリレイアウト

対象リポジトリ直下に以下を配置する。

```
.iterate-team/knowledge/     # git-tracked（state/ と異なり commit 対象。tasks/・changes/ と同格）
  lessons.jsonl               # 構造化レコードの正本（append-only、同一 id は最終行勝ち）
  lessons.md                  # 注入用ダイジェスト（knowledge-digest.sh が決定的に再生成）
  proposals/                  # プラグイン改善提案レポート（人間向け、自動編集しない）
    YYYYMMDD_<slug>.md
    INDEX.md                  # deep レトロが更新する提案一覧
  .gitattributes               # "lessons.jsonl merge=union"（knowledge-append.sh が冪等 seed）
```

### tracked / untracked の対比

`.iterate-team/state/` は `session-start.sh` の exclude パターン（`/${prefix}.iterate-team/state/`）により git 除外されるのに対し、`.iterate-team/knowledge/` は git-tracked である。両者は同じ `.iterate-team/` 配下にありながら管理方針が正反対であることに注意する。`knowledge/` は `tasks/`・`changes/` と同格の commit 対象資産として扱う。

### state-prune.sh との関係

`state-prune.sh` は `.iterate-team/state/` 配下のみを prune スコープとする（[`state-retention-policy.md`](./state-retention-policy.md) 参照）。`.iterate-team/knowledge/` は state root の外にあるため、prune スコープに**構造的に含まれない**。knowledge 側の量的規律は本書 5 節・6 節が別途定める。

## 3. レッスンレコードスキーマ（`lessons.jsonl` の 1 行）

| フィールド        | 型             | 説明                                                                                                          |
| ----------------- | -------------- | --------------------------------------------------------------------------------------------------------------- |
| `id`              | string         | `L-<YYYYMMDDTHHmm>-<4hex>`。`knowledge-append.sh` が生成（時刻＋乱数 4hex で並走セッション衝突を回避）        |
| `ts`              | string         | ISO8601 UTC                                                                                                     |
| `session_id`      | string         | 記録元セッション                                                                                                |
| `source`          | enum           | `auto-retrospective` \| `deep-retrospect` \| `manual`                                                          |
| `category`        | enum           | `plan` \| `impl` \| `test` \| `review` \| `acceptance` \| `env` \| `process`                                    |
| `target_agents`   | string[]       | `team-*` agent 名、または共通を表す `["*"]`                                                                     |
| `trigger`         | string         | 状況説明 1〜2 行（何が起きたか）                                                                                |
| `lesson`          | string         | 命令形の教訓文。200 字以内                                                                                       |
| `evidence`        | array          | `[{"session_id": "...", "event": "要約文"}]`。パス参照にしない（state prune で消えても教訓文が自立するため）    |
| `status`          | enum           | `active` \| `deprecated` \| `merged`                                                                            |
| `merged_into`     | string \| null | `status=merged` 時の統合先 `id`                                                                                |
| `confidence`      | enum           | `low` \| `medium` \| `high`。初回記録は `low` 固定。deep レトロが適用実績で昇格                                 |
| `applied_count`   | number         | `lesson_applied` 集計値                                                                                        |
| `last_applied_ts` | string \| null | ISO8601 \| null                                                                                                 |

更新（hit-count 加算・deprecate・merge）は**同一 `id` の上書きレコードを append することで表現する**（rewrite しない）。これにより flock append のみで並走安全性を確保する。物理圧縮は `knowledge-prune.sh --compact` のみが行う。

上書きレコードは部分フィールドではなく、**既存レコード（同一 `id` の最終レコード）を読み取って全フィールドを再発行し、変更するフィールドのみ差し替える**。`knowledge-append.sh` は上書きレコードにも新規と同一の必須キー検証を適用する。

## 4. ダイジェスト `lessons.md` の掲載規則

`knowledge-digest.sh` にハードコードされる確定値であり、以下の規則で決定的に再生成する。

- `status=active` のレコードのみ掲載する
- 全体最大 **20 件**、agent セクションあたり最大 **8 件**
- 選定順: `confidence desc → applied_count desc → ts desc`
- 1 件 1 行 `- [L-xxxx] <lesson>`
- セクション構成は以下の順とする。

  1. `# 知見ダイジェスト（自動生成）`
  2. `## 共通（全 agent）`
  3. `## team-planner`
  4. `## team-generator`
  5. `## team-evaluator`
  6. `## team-interviewer`
  7. `## team-test-coder`
  8. `<!-- manual:start -->` 〜 `<!-- manual:end -->`（手編集温存ブロック）

手編集は manual ブロック内のみ許可する。それ以外の箇所は再生成のたびに消える。

`target_agents` に複数の agent 名を持つレッスンは**該当する各セクションに掲載される**（全体最大 20 件のカウントには 1 回のみ計上する）。

## 5. 記録量の上限と品質規律

軽量レトロ（ステップ 6.7、`mode=light`）における 1 回あたりの記録上限は以下のとおり。

| 対象               | 上限   |
| ------------------ | ------ |
| 新規レッスン        | 最大 3 件 |
| プラグイン改善提案  | 最大 1 件 |

- `evidence` は必須とする
- `confidence` は `low` 始まりとする
- **重複排除**: 起票前に既存の digest（`lessons.md`）と `lessons.jsonl` を確認し、同趣旨のレッスンが既存であれば新規レコードではなく該当 `id` の更新レコードを積む

## 6. 減衰・統合（deep レトロのみが実施）

減衰・統合の判断は `/iterate-retrospect` の deep レトロスペクティブのみが行う。軽量レトロ（ステップ 6.7）は行わない。

- **減衰条件**: 「直近 5 セッションの runlog に `lesson_applied` なし **AND** 初回記録から 30 日超」に該当するレッスンは、`status: deprecated` の上書きレコードを append する
- **重複統合**: `evidence` が多い側を残し、他方を `status: merged` とし `merged_into` に残す側の `id` を設定する
- **降格・改訂**: 「適用されたのに同カテゴリの失敗が再発」した場合、`confidence` を降格するか教訓文（`lesson`）を改訂する
- **物理削除**: `knowledge-prune.sh --compact --apply` によってのみ実施する。同一 `id` の圧縮（最終レコードのみ残す）、および `status: deprecated` かつ初回記録から **90 日超**のレコードの削除を行う
- **上書きレコードの発行方式**: 上記「減衰条件」「重複統合」「降格・改訂」がいずれも発行する上書きレコードは §3 と同一の方式に従う。既存レコード（同一 `id` の最終レコード）を読み取って全フィールドを再発行し、変更するフィールドのみ差し替える。`knowledge-append.sh` は新規レコードと同一の必須キー検証をここでも適用する

## 7. 注入規約

注入対象 agent は以下の **5 種に限定**する（prompt bloat 抑制のため）。

- `team-planner`
- `team-generator`
- `team-evaluator`
- `team-interviewer`
- `team-test-coder`

Orchestrator は step 0.0 で `<knowledge_digest_path>`（`<repo-root>/.iterate-team/knowledge/lessons.md` の絶対パス）を保持し、上記 5 agent の起動プロンプトに `knowledge_digest_path=<絶対パス>` を注入する。これは `plugin_root` 注入と同じ規約に従う。

agent 側の適用規則は [`templates/_partials/knowledge-injection.md`](../templates/_partials/knowledge-injection.md) に定義する。

- ファイル不在時は黙って skip する
- タスク仕様・`universal-rules` と矛盾する場合はレッスン側を無視する
- 実際に判断を変えた場合のみ `lesson_applied` を記録する。記録経路は agent の tools 構成により **2 経路**に分岐する:
  - **Bash を持つ agent**（`team-generator` / `team-evaluator` / `team-test-coder`）: 自身が `<plugin_root>/scripts/runlog-append.sh` を呼び出して自己記録する
  - **Bash を持たない agent**（`team-planner` / `team-interviewer`）: 戻り値テキストに `適用レッスン: L-...` 行で報告し、**Orchestrator が代理記録する**（detail に `"recorded_by":"orchestrator"` を含める）。手順の正本は [`harness-common.md#knowledge-ダイジェスト注入全コマンド共通`](./harness-common.md#knowledge-ダイジェスト注入全コマンド共通)

対象 agent を拡張する際の目安は「そのエージェントの判断ミスがレッスン化された実績が 3 件以上」であることとする。

## 8. repo 固有レッスン vs プラグイン改善提案の判別ルーブリック

- 是正アクションが**対象リポジトリの規約・ツール・ドメイン**に依存する → lesson として `knowledge/` へ記録する
- 失敗の根因が**ハーネス側資産**にある兆候（以下のいずれか）が見られる → proposal として `proposals/YYYYMMDD_<slug>.md` にレポートする
  - 同種の `agent_decision` `rejected` がトピック非依存に反復している
  - agent が partial の指示を誤解している
  - `<plugin_root>/templates` または `<plugin_root>/operations` の記述を引用して初めて説明できる

proposal は**レポートのみ**とする。**プラグイン資産（`<plugin_root>` 配下）への Write/Edit は禁止**である。

proposal レポートの構成は以下のとおり。

1. 対象資産
2. 症状
3. 根拠（runlog 抜粋 + `session_id`）
4. 提案変更
5. 期待効果
6. 再現セッション数

## 9. コミット・push フロー

### ステップ 6.7（軽量レトロ）

1. Orchestrator が `git status --porcelain -- .iterate-team/knowledge/` で差分を確認する
2. 個別 `git add`（`git add .` 禁止の既存規律に従う）
3. 1 コミットにまとめる。subject は `docs: セッションレトロスペクティブ知見を記録`、フッタは `Refs: retrospective-<session-id>`
4. host 環境では team-publisher の 2 回目 push に含める（PR Ready 化前のため同一 PR に含まれる）。dev container では commit のみ行う

### fail-open

レトロスペクティブが失敗した場合は以下のとおり fail-open する。

1. `git restore -- .iterate-team/knowledge/` で復元する
2. runlog に `retrospective_failed` を記録する
3. ステップ 7 へ続行する（PR 完了を阻害しない）

### deep レトロ（`/iterate-retrospect`）

- clean tree を必須とする
- `claude/knowledge-retrospect-<ts>` ブランチ上でコミットする
- フッタは `Refs: retrospective-deep-<YYYYMMDDHHmm>`

未マージ PR 上に取り残されたレッスンは許容する。runlog 側に `lesson_recorded` が残るため、deep レトロが再記録を提案できる。

## 10. runlog イベント

`agent-decision-schema.md` と相互参照する。以下 6 種の新規イベントを追加する。

| event                       | detail フィールド例                                                   |
| --------------------------- | ---------------------------------------------------------------------- |
| `retrospective_started`     | `{"mode": "light"}`（`session_id` は `runlog-append.sh` が top-level に自動付与するため detail には含めない）|
| `retrospective_completed`   | light: `{"mode": "light", "lessons_recorded": 2, "proposals_recorded": 0}` / deep（変更あり）: `{"mode":"deep","new_lessons":N,"updated_lessons":N,"deprecated":N,"proposals":N}` / deep（変更なし）: `{"mode":"deep","lessons_recorded":0,"changed":false}` |
| `retrospective_failed`      | `{"mode": "light", "reason": "git restore 実行、要因: ..."}`           |
| `lesson_recorded`           | `{"lesson_id": "L-20260703T0930-a1b2", "category": "review"}`           |
| `lesson_applied`            | 自己記録: `{"lesson_id": "L-20260703T0930-a1b2", "agent": "team-planner"}` / 代理記録: `{"lesson_id": "L-20260703T0930-a1b2", "agent": "team-planner", "recorded_by": "orchestrator"}` |
| `plugin_proposal_recorded`  | `{"path": "proposals/20260703_xxx.md", "target_asset": "..."}`          |

## 11. 関連スクリプト一覧

| スクリプト             | 役割                                                     |
| ---------------------- | -------------------------------------------------------- |
| `knowledge-append.sh`  | flock append + 検証 + `id` 生成                          |
| `knowledge-digest.sh`  | `lessons.md` の決定的再生成                               |
| `knowledge-prune.sh`   | dry-run 既定の圧縮（`--compact --apply` でのみ物理削除）  |

## 12. 関連ドキュメント

- runlog スキーマ: [`agent-decision-schema.md`](./agent-decision-schema.md)
- state 側の保持基準（対比参照）: [`state-retention-policy.md`](./state-retention-policy.md)
- ハーネス共通手順: [`harness-common.md`](./harness-common.md)
- agent 側の注入規則: `<plugin_root>/templates/_partials/knowledge-injection.md`
- operations 配下の位置づけ: [`README.md`](./README.md)
