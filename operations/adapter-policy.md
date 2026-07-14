# adapter（プロジェクト適応レイヤ）ポリシー

対象リポジトリ直下 `.agent-os/` に永続化する「プロジェクト適応（adapter）」の仕組みに関する**確定値の正本（SoT）**である。`templates/_partials/adapter-injection.md`、`agents/team-profiler.md`、`agents/team-adapter.md`（Phase 2）、`scripts/adapter-bootstrap.sh`、`commands/iterate-adapt.md`、および vendored エンジン `vendor/agent-os/scripts/bootstrap-project.sh` / `validate-agent-os.sh` / `detect-rule-conflicts.sh` / `split-learned-rules.sh` は、いずれも本書の確定値をそのまま実装する。値の変更・追加解釈は行わない。

## 1. 目的と位置づけ

`operations/knowledge-policy.md` が扱う学習軸は「**ハーネスの回し方をどう良くするか**」（`runlog.jsonl` → team-retrospector → `.iterate-team/knowledge/` → 5 agent 注入）という内部オーケストレーション軸である。これに対し本書が扱う学習軸は「**対象プロジェクトについての事実**」と「**ユーザーの恒常的な訂正**」という直交する軸であり、対象は agent の回し方ではなく対象コードベースそのものである。

両者は主題・読者・保存形式・マージ戦略のいずれも異なるため、**物理的・手続き的に分離した並行ストア**として扱う。統合しない。

| 観点               | `knowledge/`（`knowledge-policy.md`）                          | `.agent-os/`（本書）                                        |
| ------------------ | ---------------------------------------------------------------- | -------------------------------------------------------------- |
| 学習軸             | ハーネス自己改善（agent の判断ミスからの教訓）                    | 対象プロジェクトの事実 + ユーザーの恒常的な訂正                 |
| 読者               | ハーネス agent（機械可読 JSONL 前提）                              | ハーネス agent **かつ**人間（ユーザーが直接読む・手編集する）    |
| 保存形式           | `lessons.jsonl`（構造化レコード）+ 非追跡ダイジェスト `lessons.md` | `.agent-os/*.md`（人間可読 Markdown、fable の scope 分割前提）  |
| マージ戦略         | `merge=union`（`.gitattributes`）                                 | 手書きブロックの通常マージ（fable の split-by-scope が前提）    |
| 単一書き手         | `team-retrospector` のみ                                          | `team-profiler`（観測）/ `team-adapter`（学習）のみ（§6）        |

**deep レトロスペクティブ（`/iterate-retrospect`）は `.agent-os/` のルールを「証拠として引用」してよいが、`.agent-os/` へは一切書き込まない。** 逆に `team-profiler`/`team-adapter` も `.iterate-team/knowledge/` へは書き込まない。書き手隔離は両ストアで独立に成立する不変条件である。

## 2. ディレクトリレイアウト

対象リポジトリ**直下**（`<project_dir>/.agent-os/`、`.iterate-team/` 配下ではない）に以下を配置する。

```
.agent-os/                        # git-tracked（.iterate-team/state/ の除外と対比・.iterate-team/knowledge/ の追跡と並行）
  project-profile.md              # プロジェクト像の正本（tech stack・ディレクトリ構成・検証済み事実・仮説）
  command-map.md                  # 検証済み build/test/lint/typecheck/run コマンドの allow-list（出典付き）
  risk-map.md                     # 危険領域・要承認箇所・既知の脆弱ポイント・secrets の所在（パスのみ）
  architecture-map.md             # 層・依存方向・境界・拡張ポイント
  learned-rules.md                # candidate/active/deprecated ルール（§3）+ split 時の Active rules index
  failure-log.md                  # 失敗の逐語記録（Learning Layer の生素材）
  review-feedback-log.md          # ユーザー訂正・レビューコメントの逐語記録（Learning Layer の生素材）
  evals.md                        # instructions/learned-rules 変更の回帰チェック（シナリオ + 結果表）
  GLOBAL_AGENTS.md                 # vendored。upstream からの複製そのもの（手編集禁止。UPSTREAM.md 参照）
  rules/                          # 任意（split-learned-rules.sh 実行後のみ存在）
    global.md / project.md / directory.md / file-pattern.md
```

### tracked / untracked の対比

`.iterate-team/state/` は git 除外、`.iterate-team/knowledge/` は git 追跡——という `knowledge-policy.md` §2 の対比構造と**並行**して、`.agent-os/` も git-tracked である。`.agent-os/` は対象リポの通常ソースと同じく `git add`/コミットの対象であり、`state/` のような一時領域ではない。

### 対象ファイルの内訳（`validate-agent-os.sh` の `ADAPTER_FILES` と一致）

上記 8 つの `.md`（`project-profile` / `command-map` / `risk-map` / `architecture-map` / `learned-rules` / `failure-log` / `review-feedback-log` / `evals`）が「8 required files」であり、`GLOBAL_AGENTS.md` は `bootstrap-project.sh` が**常に**（`--for claude`/`codex`/`both` いずれでも）追加で vendoring する必須ファイルである（`GLOBAL_CLAUDE.md` は `--for claude|both` 時のみで、iterate-team の最小構成では対象外。後述）。`rules/` は split-by-scope レイアウト採用後のみ存在し、ファイル名は `global.md`/`project.md`/`directory.md`/`file-pattern.md` の 4 つに限定する（`validate-agent-os.sh` はそれ以外の命名を警告する）。

### iterate-team 最小構成（`--adapter-only`）の範囲

fable 本体の `bootstrap-project.sh --for claude` は `.agent-os/` に加えて `.claude/skills/*`・`.claude/agents/*`・root `CLAUDE.md`/`AGENTS.md` も設置する。**iterate-team の `scripts/adapter-bootstrap.sh` は既定で `--adapter-only` とし、`.agent-os/` + `GLOBAL_AGENTS.md` のみを対象リポに設置する。** root `CLAUDE.md`/`AGENTS.md`・`.claude/skills`・`.claude/agents/*` は最小構成では**書かない**（中立設計を維持するための計画上の決定。§9 参照）。

## 3. ルールレコードスキーマ

`learned-rules.md`（および split 後の `rules/*.md`）内の 1 ルールは、fable の `learn-from-feedback` skill が定義する以下の形式を**そのまま**用いる（見出し・フィールド名・区切りとも変更しない）。

```md
## Rule: <short name>

Status: candidate | active | deprecated
Source: user-feedback | failure | review | eval
Scope: global | project | directory | file-pattern
Applies to:
- <path or task type>

Rule:
- <observable instruction>

Rationale:
- <why this prevents failure>

Examples:
- Do: <example>
- Do not: <example>

Validation:
- <command or checklist>
```

- `Status` は `candidate | active | deprecated` の 3 値のみ。**`vendor/agent-os/scripts/validate-agent-os.sh` が `Status:` 行を正規表現でこの 3 値に強制する**（HTML コメントで囲われた説明用サンプルは除外して検査する）ため、この enum を変更・追加する場合は本書と `validate-agent-os.sh` の両方を同時に改める。
- `Source` は `user-feedback | failure | review | eval` の 4 値。
- `Scope` は `global | project | directory | file-pattern` の 4 値（split レイアウトの `rules/<scope>.md` のファイル名と 1:1 対応する）。
- ルールは「観測可能で曖昧さのない指示」でなければならない。`appropriately`/`properly`/`as needed` のような曖昧語を用いた指示は禁止する（fable 側の規律をそのまま踏襲）。
- **`Status: active` のルールのみが拘束力を持つ。`Status: candidate` は助言であり、5 injected agent（§5）に対して強制力を持たない。** `Status: deprecated` は履歴保持のためのみに残り、いずれの agent への拘束力もない。

## 4. 昇格・減衰規則

- **candidate → active**: 同趣旨のフィードバック・失敗が独立に **2 回以上**観測された場合に昇格する（1 回目は `candidate` として記録、2 回目以降で `Status:` を書き換えて `active` に昇格する。既存レコードを複製せず、同一ルールブロックの `Status:` を上書きする）。
- **active/candidate → deprecated**: ルールが陳腐化・新しい観測により上書きされた（superseded）・矛盾が生じた場合に `deprecated` へ遷移する。**物理削除は行わない**（`knowledge-policy.md` の `deprecated` と異なり、`.agent-os/` には `knowledge-prune.sh --compact --apply` に相当する物理圧縮スクリプトは Phase 1〜2 の対象に含まれない。変遷の履歴を人間が読めることを優先するため、削除は将来にわたっても既定では行わない）。
- **昇格・減衰の判定は日数ベースの自動しきい値を持たない**。`knowledge-policy.md` §6 の「30 日超」「90 日超」のような数値基準は `.agent-os/` には適用しない——`.agent-os/` はユーザー自身が直接読み・手編集する人間可読資産であり、機械的な時間経過のみで内容を陳腐化扱いにすると手編集と衝突するためである（判断根拠: 本書執筆時点の設計判断。将来 team-adapter の実装で数値基準が必要になった場合は本書を改訂して追記する）。
- **競合は必ず表面化し、サイレントに上書きしない**。新しいフィードバック・失敗が既存の `active` ルールと矛盾する場合、`rule_candidate_recorded`/`rule_promoted` を行わず、`adapter_conflict`（§8）を記録した上でユーザーに提示し、どちらを残すか判断を仰ぐか、両方を競合注記付きで記録する。これは fable `learn-from-feedback` skill の Forbidden 節「Silently overwriting a conflicting existing rule — the conflict must be surfaced.」をそのまま踏襲する規律であり、`vendor/agent-os/scripts/detect-rule-conflicts.sh`（`DUPLICATE RULE NAME` / `OVERLAP` / `POSSIBLE CONFLICT` / `MALFORMED` の 4 種の findings、read-only）が機械的な一次検出を担う。
- 単一の一回限りの好みを `active`（まして `global` scope）に昇格させることは禁止する（fable 側 Forbidden 節と同一の規律）。

## 5. 注入規約

注入対象 agent は `knowledge-policy.md` と同じ **5 種**に限定する。

- `team-planner`
- `team-generator`
- `team-evaluator`
- `team-interviewer`
- `team-test-coder`

Orchestrator は step 0.0 で `adapter_dir`（`<project_dir>/.agent-os` の絶対パス）を保持し、上記 5 agent の起動プロンプトへ存在チェックなしで注入する（`knowledge_digest_path`/`plugin_root` と同じ注入規約）。

### 優先順位

```
タスク仕様 / universal-rules / Orchestrator 指示
  ＞ command-map.md / risk-map.md / architecture-map.md の事実
    ＞ Status: active ルール
      ＞ Status: candidate ルール
```

adapter は常に劣後する。タスク仕様・`universal-rules.md`・Orchestrator からの指示と矛盾する場合は adapter 側（事実・ルールいずれも）を無視する。

### agent 別の意味づけ

| ファイル               | 対象 agent                          | 効果                                                                                                                     |
| ---------------------- | ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------ |
| `command-map.md`        | `team-generator` / `team-evaluator`   | build/test/lint/typecheck/run コマンドを検証済み allow-list に制約する。未収載のコマンドは生成・実行せず、verify-then-record するかエスカレーションする。**read-only 調査**（`ls`/`cat`/`grep`/`find`/`git status`/`log`/`diff` 等）は allow-list の対象外であり常に無制約 |
| `risk-map.md`           | `team-planner`（+ advisor 相当の助言経路） | 危険領域・要承認箇所を伝え、`team-planner` の計画立案と `team-generator` の実装ゲートに反映する                            |
| `architecture-map.md`   | `team-planner`                        | 依存方向・境界・拡張ポイントを伝え、タスク分解と実装方針に反映する                                                        |
| `learned-rules.md`（`Status: active` のみ）/ `rules/*.md`（split 時） | 5 agent 全体 | scope に応じて拘束。`global`/`project` scope は常に適用、`directory`/`file-pattern` scope は `Applies to:` に一致する場合のみ適用 |

`.agent-os/rules/` が存在する（split-by-scope レイアウト）場合、5 agent は `learned-rules.md` の `## Active rules index` を辿って該当する `rules/<scope>.md` も読む。index のポインタが指すルール本文は `learned-rules.md` 内に直接書かれたルールと**同等の拘束力**を持つ。

本書は adapter 注入の**値の正本**である。注入時の具体的な読み込み手順・skip 条件・`adapter_applied` 記録経路といった**挙動の正本**は [`templates/_partials/adapter-injection.md`](../templates/_partials/adapter-injection.md) が担う（値は本書と一致させ、`validate-agents.sh` の重複検出により inline コピーを禁止する構造は `knowledge-injection.md` と同じ）。

## 6. 書き手隔離

`.agent-os/` への書き込み主体は以下の **2 agent のみ**に限定する。5 injected agent（§5 の `team-planner`/`team-generator`/`team-evaluator`/`team-interviewer`/`team-test-coder`）は read-only consumer であり、`.agent-os/` へは一切書き込まない。

| 書き手           | 役割       | 書き込み対象ファイル                                                                 |
| ---------------- | ---------- | -------------------------------------------------------------------------------------- |
| `team-profiler`   | 観測       | `project-profile.md` / `command-map.md` / `risk-map.md` / `architecture-map.md`         |
| `team-adapter`（Phase 2） | 学習       | `learned-rules.md` / `failure-log.md` / `review-feedback-log.md` / `evals.md` / `rules/*.md`（split 時） |

fable 本来の canonical skills では任意の assistant agent が `failure-log.md`/`review-feedback-log.md` に直接追記できるが、**iterate-team のネイティブ配線ではこれを行わない**。5 injected agent は失敗・ユーザー訂正を検知した場合、戻り値にその旨を報告するに留め（`team-generator`/`team-evaluator`/`team-test-coder` が Bash 経由で自ら `.agent-os/` を書くことも禁止する）、実際の記録は直列 step で走る `team-adapter` が代行する。これは `knowledge-policy.md` の「書き込み主体は team-retrospector のみ」という単一書き手不変条件と同型の規律である。

deep レトロ（`team-retrospector`）は `.agent-os/` のルールを証拠として**引用**できるが、書き込みは行わない（§1 参照）。

## 7. コミット・push フロー / fail-open

### コミット

1. Orchestrator が `git status --porcelain -- .agent-os/` で差分を確認する
2. 個別 `git add`（`.agent-os/` 配下の各ファイルを 1 件ずつ。`git add -A`/`git add .` 禁止の既存規律に従う）
3. 1 コミットにまとめる。subject・フッタの規約は呼び出し元コマンドに従う（例: `/iterate-adapt` の初回設置は `docs: .agent-os アダプタを初期化` / `Refs: adapter-<topic>`。`team-adapter` によるルール記録は別コミット・別 `Refs:` とし、`team-retrospector` のコミットと衝突させない — 「既存 knowledge 機構との衝突リスク」参照）
4. agent 自身は git 操作を行わない。コミットは常に Orchestrator が行う（`knowledge-policy.md` §9 と同じ規律）

`.agent-os/` への書き込みは常に `claude/*` ブランチ上に載るユーザー可視の変更として扱う。サイレント編集にしない。

### fail-open

`.agent-os/` へのコミットが失敗した場合、`knowledge-recover.sh` と同型構造の **`adapter-recover.sh`**（Phase 1〜2 で新規追加）により fail-open する:

1. `<plugin_root>/scripts/adapter-recover.sh "<session-id>"` を実行する。(a) staged 変更を unstage してから HEAD 追跡ファイルの worktree を復元する（tracked/staged が皆無の初回設置時は復元を skip する）。(b) 残る untracked 生成物を `.iterate-team/state/<session-id>/failed-adapter/` へ退避して作業ツリーを clean に戻す（`git clean` は使わない）
2. runlog に失敗を記録した上でステップを続行する（PR 完了を阻害しない）
3. 未コミットの `.agent-os/` 変更は次回 `/iterate-adapt` 実行時に再設置候補として扱われる

## 8. runlog イベント

`agent-decision-schema.md` と相互参照する。以下 8 種の新規イベントを追加する。

| event                      | detail フィールド例                                                                                          |
| -------------------------- | --------------------------------------------------------------------------------------------------------------- |
| `adapter_observed`         | `{"files": ["project-profile.md","command-map.md","risk-map.md","architecture-map.md"]}`（`team-profiler` の初回観測完了時） |
| `adapter_updated`          | `{"files": ["command-map.md"], "reason": "build ツール変更を検知"}`（`team-profiler`/`team-adapter` による再観測・更新時） |
| `feedback_recorded`        | `{"category": "architecture"}`（`review-feedback-log.md` への逐語記録時。`category` は fable の 7 分類のいずれか） |
| `rule_candidate_recorded`  | `{"rule": "Never mock the payments gateway in integration tests", "source": "failure"}`                          |
| `rule_promoted`            | `{"rule": "Never mock the payments gateway in integration tests", "occurrences": 2}`                             |
| `rule_deprecated`          | `{"rule": "<short name>", "reason": "superseded"}`                                                                |
| `adapter_applied`          | 自己記録: `{"rule": "<short name>", "agent": "team-generator"}` / 代理記録: `{"rule": "<short name>", "agent": "team-planner", "recorded_by": "orchestrator"}`（`lesson_applied` の二経路モデルをそのまま踏襲。§5 の agent 別 tools 構成に従い Bash 有 agent は自己記録、Bash 無 agent は戻り値の `適用ルール: <rule-name>` 行を Orchestrator が代理記録する） |
| `adapter_conflict`         | `{"rule": "<new candidate>", "conflicts_with": "<existing active rule>"}`（§4 の競合表面化規律の発火点）           |

## 9. 関連スクリプト一覧

| スクリプト                                          | 役割                                                                                                     |
| ---------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `vendor/agent-os/scripts/bootstrap-project.sh`        | 対象リポへの canonical インストーラ（vendored・verbatim・手編集禁止）。OS-owned/project-owned 分離・symlink 安全・`--force`/`--reset-adapter` |
| `scripts/adapter-bootstrap.sh`（新規・wrapper）        | `CLAUDE_PROJECT_DIR` から `project_dir` を解決し、既定 `--adapter-only`（`.agent-os/` + `GLOBAL_AGENTS.md` のみ）で内部的に `bootstrap-project.sh --target "$project_dir" --for claude` を呼ぶ |
| `vendor/agent-os/scripts/validate-agent-os.sh --adapter <dir>` | 8 必須ファイル + `GLOBAL_AGENTS.md` の存在確認、`learned-rules.md`（および `rules/*.md`）の `Status:` enum 検証        |
| `vendor/agent-os/scripts/detect-rule-conflicts.sh --adapter <dir>` | read-only の重複/重複範囲/競合/欠落フィールド検出（`DUPLICATE RULE NAME`/`OVERLAP`/`POSSIBLE CONFLICT`/`MALFORMED`）。exit 1 で findings あり |
| `vendor/agent-os/scripts/split-learned-rules.sh`      | `learned-rules.md` が概ね 10 active ルール超・300 行超になった際に `active` ルールを `rules/<scope>.md` へ分割         |
| `scripts/adapter-recover.sh`（Phase 2・新規）          | `knowledge-recover.sh` 構造クローンの fail-open 復旧（§7）                                                  |
| `scripts/adapter-record-feedback.sh`（Phase 2・新規）  | flock 安全に `review-feedback-log.md` へ逐語 1 件 append                                                    |

## 10. 関連ドキュメント

- 対比軸（ハーネス自己改善 vs プロジェクト適応）: [`knowledge-policy.md`](./knowledge-policy.md)
- runlog スキーマ: [`agent-decision-schema.md`](./agent-decision-schema.md)
- ハーネス共通手順（adapter 注入配線）: [`harness-common.md`](./harness-common.md)
- team 固有運用: [`iterate-team-runbook.md`](./iterate-team-runbook.md)
- agent 側の注入規則（挙動の正本）: `<plugin_root>/templates/_partials/adapter-injection.md`
- vendoring 出典・再 vendoring 手順: `<plugin_root>/vendor/agent-os/UPSTREAM.md`
- operations 配下の位置づけ: [`README.md`](./README.md)
