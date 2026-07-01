# コントリビュートガイド

`iterate-team-plugin` の開発・変更を行う人向けのドキュメント。利用者向けの導入・使い方は [`README.md`](./README.md) を参照。

## 前提

- `bash` / `jq` / `git`（scripts が利用する）
- Node.js **>= 18**（`bin/cli.mjs` と npm 経路）
- Claude Code（プラグイン機構の動作確認に使用）

## セットアップ

```
git clone https://github.com/50ra4/iterate-team-plugin.git
cd iterate-team-plugin
```

追加の依存インストールは不要（本体はシェルスクリプトと markdown で構成される）。

## Agent 定義の生成規約（最重要）

`agents/team-*.md` は **生成物**であり、`templates/_base/*.md`（+ `templates/_partials/`）を Single Source of Truth (SoT) として `scripts/build-agents.sh` が生成する。

**`agents/*.md` を直接編集してはならない。** 変更は必ずテンプレート側（`templates/_base/` / `templates/_partials/`）に加え、build で `agents/` を再生成する。

```
scripts/build-agents.sh           # templates/ から agents/ を生成
scripts/build-agents.sh --check   # ドリフト検出（pre-commit 用・生成物とテンプレの不一致を検査）
scripts/validate-agents.sh        # ドリフト + 共通句重複検査
scripts/run-tests.sh              # シェルユニットテストを全件個別実行（1 本でも落ちれば非ゼロ終了）
```

- テンプレ文法（プレースホルダ `{{NAME}}` / `{{HARNESS}}`、条件ブロック `@if`、共通断片 `@ref`）と新規 agent の追加手順は [`templates/README.md`](./templates/README.md) を参照。
- ハーネスの処理仕様・運用 runbook・スキーマ定義は [`operations/`](./operations/)（[`operations/README.md`](./operations/README.md) が索引）を参照。

## 変更の出し方

1. 作業ブランチを切る（`main` へ直接コミットしない）。
2. テンプレート（`templates/`）を編集し、`scripts/build-agents.sh` で `agents/` を再生成する。
3. コミット前に `scripts/build-agents.sh --check` と `scripts/validate-agents.sh` を通し、ドリフトが無いことを確認する。
4. `scripts/run-tests.sh` でシェルユニットテスト（全件）を通す。
5. **`git add` はファイル個別指定**で行う（`git add .` / `git add -A` は使わない）。生成物 1 件とテンプレ 1 件をセットでコミットする。
6. コミットメッセージは既存の履歴（`add:` / `fix:` 等の接頭辞）に倣う。

## コミット前チェックリスト

- [ ] `scripts/build-agents.sh --check` が green（生成物とテンプレが一致）
- [ ] `scripts/validate-agents.sh` が green
- [ ] `scripts/run-tests.sh` が green（全 test を個別実行）
- [ ] `agents/*.md` を手編集していない（テンプレ経由の再生成のみ）

## 公開・リリース

npm publish / plugin marketplace 公開 / GitHub Release などの公開作業はメンテナ（owner）の担当。手順は [`PUBLISHING.md`](./PUBLISHING.md) にまとめている。
