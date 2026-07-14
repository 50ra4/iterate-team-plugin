# Agent 定義の Single Source of Truth (SoT)

`agents/team-<name>.md` は、`scripts/build-agents.sh` が `templates/_base/<name>.md`（または `_base/team-<name>.md`）テンプレから生成する成果物である。**`agents/*.md` を直接編集してはならない**。

> squad 出力（`agents/<name>.md`）は恒久停止済（`/iterate-squad` は `/iterate-team` に置換）。`build-agents.sh` は team 出力（`team-<name>.md`）のみを生成し、`_base/` 配下の squad 名テンプレートは team 出力生成の SoT として保持する。

## ディレクトリ構成（プラグインルート基準）

```
<plugin-root>/
  agents/                         # 生成物（agent loader が読む / 手編集禁止・team 出力のみ）
    team-<name>.md                # team 用
    team-publisher.md             # team 専用（squad 版なし）
    team-reviewer-code.md         # team 専用（squad 版なし）
    team-reviewer-plan.md         # team 専用（squad 版なし）
  templates/
    _base/<name>.md               # team 出力の SoT（squad 名のまま保持・手編集対象）
    _base/team-<name>.md          # team 専用テンプレ（squad と本文が大きく異なる agent のみ）
    _base/team-publisher.md       # team 専用テンプレ（squad 版なし）
    _base/team-reviewer-code.md   # team 専用テンプレ（squad 版なし）
    _base/team-reviewer-plan.md   # team 専用テンプレ（squad 版なし）
    _partials/<x>.md              # 共通ルール（複数 agent から runtime Read 参照）
    README.md                     # 本ファイル
  scripts/
    build-agents.sh               # テンプレ展開
    validate-agents.sh            # ドリフト検出（pre-commit hook で実行）
```

## テンプレと出力の対応

| 出力                           | テンプレ                                                                        | 備考                                  |
| ------------------------------ | ------------------------------------------------------------------------------- | ------------------------------------- |
| `agents/team-<name>.md`        | `_base/team-<name>.md`（存在すれば）／なければ `_base/<name>.md`（team モード） | team 出力                             |
| `agents/team-publisher.md`     | `_base/team-publisher.md`                                                       | **team 専用テンプレ**（squad 版なし） |
| `agents/team-reviewer-code.md` | `_base/team-reviewer-code.md`                                                   | **team 専用テンプレ**（squad 版なし） |
| `agents/team-reviewer-plan.md` | `_base/team-reviewer-plan.md`                                                   | **team 専用テンプレ**（squad 版なし） |

squad 出力（`agents/<name>.md`）は恒久停止済のため対応表から除外する（`build-agents.sh` は squad 名テンプレからも team 出力のみを生成する）。

`_base/team-<name>.md` を別ファイルとして持つのは、squad と team で本文構造が大きく異なる agent（現状 `generator`）に限る。本文差分が小さい agent は `_base/<name>.md` から team 出力を生成する。

team 専用テンプレ（`_base/team-publisher.md` / `_base/team-reviewer-code.md` / `_base/team-reviewer-plan.md`）は対応する squad 側テンプレを持たない。`build-agents.sh` はこれらに対して squad 出力をスキップし、team 出力（`agents/team-*.md`）のみを生成する。

## \_partials 一覧

`_partials/` 配下の共通断片ファイルと、それを参照する `_base` テンプレの対応:

| partial                                      | 用途                                                    | 参照元 `_base` テンプレ                                                                      |
| -------------------------------------------- | ------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| `_partials/universal-rules.md`               | 全 agent 共通の回答スタイル・事実確認・ハーネス参照パス | 全テンプレ                                                                                   |
| `_partials/git-commit-rules.md`              | `git add` 個別指定・コミットメッセージ規約              | `closer.md` / `generator.md` / `team-generator.md`                                           |
| `_partials/planner-delegation.md`            | Planner の wave 分割・タスク委譲ルール                  | `planner.md`                                                                                 |
| `_partials/planner-policies.md`              | Planner の判断基準・エスカレーション条件                | `planner.md`                                                                                 |
| `_partials/generator-task-classification.md` | タスク分類（Trivial / Scoped / Complex）と探索深度      | `generator.md` / `team-generator.md`                                                         |
| `_partials/generator-pattern-detection.md`   | 既存コードパターン検出と適合規約                        | `generator.md` / `team-generator.md`                                                         |
| `_partials/generator-failure-mode.md`        | 実装失敗・リトライ時の挙動                              | `generator.md` / `team-generator.md`                                                         |
| `_partials/generator-prohibitions.md`        | Generator の禁止事項一覧                                | `generator.md` / `team-generator.md`                                                         |
| `_partials/advisor-common.md`                | Advisor 共通の回答フォーマット・品質基準                | `advisor-architect.md` / `advisor-security.md` / `advisor-tech-lead.md` / `advisor-ui-ux.md` |
| `_partials/knowledge-injection.md`           | knowledge digest の読込・適用対象・`lesson_applied` 記録規則 | `planner.md` / `team-generator.md` / `evaluator.md` / `interviewer.md` / `test-coder.md`      |
| `_partials/adapter-injection.md`             | `.agent-os/` adapter の読込・適用対象・`adapter_applied` 記録規則 | `planner.md` / `team-generator.md` / `evaluator.md` / `interviewer.md` / `test-coder.md`      |

## テンプレ文法

`_base/<name>.md` は次の 3 種のメタ記法を持つ:

### プレースホルダ

| プレースホルダ | squad 出力      | team 出力      |
| -------------- | --------------- | -------------- |
| `{{NAME}}`     | `<name>`        | `team-<name>`  |
| `{{HARNESS}}`  | `iterate-squad` | `iterate-team` |

### 条件ブロック（large-diff ペア向け）

```markdown
<!-- @if squad -->

squad 固有の説明文。team 出力では削除される。

<!-- @endif -->

<!-- @if team -->

team 固有の説明文。squad 出力では削除される。

<!-- @endif -->
```

ネストは未サポート。

### 共通断片の参照（@ref）

```markdown
<!-- @ref _partials/universal-rules.md -->
```

ビルド時に次の 1 行に展開される:

```markdown
本 agent は起動直後に `<plugin_root>/templates/_partials/universal-rules.md` を `Read` し、その内容を遵守すること。
```

agent loader は生成物をそのまま読むが、agent 起動時に LLM が partial を `Read` ツールで取得することで、共通ルール文を `agents/*.md` から物理的に削減する（`grep -c` で 1 出現を担保）。

## 新規 agent の追加手順

1. `templates/_base/<name>.md` を作成（プレースホルダ・@ref を使用）
2. `scripts/build-agents.sh` を実行 → `agents/team-<name>.md` が生成される（squad 出力は生成されない）
3. 生成物 1 件（team 出力）+ テンプレ 1 件を個別 `git add` でコミット

## ビルド

```bash
scripts/build-agents.sh           # 生成
scripts/build-agents.sh --check   # 整合性検査（pre-commit hook 用）
```

## 既知の制約

- `_base/` 配下のテンプレに `{{NAME}}` 以外の動的識別子は混入させない（ビルドが破綻するため）
- `@if squad` / `@if team` ブロック内で `@ref` を使う場合、ネストは正常動作するが視認性のため極力避ける
- team 専用 3 agents（`team-publisher` / `team-reviewer-code` / `team-reviewer-plan`）は対応する squad 版が存在しない。`_base/team-*.md` テンプレを持ち、`build-agents.sh` が team 出力のみを生成する
