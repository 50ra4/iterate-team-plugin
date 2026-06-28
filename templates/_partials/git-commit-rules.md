# Git / コミット規約（生成系 agent 共通）

本ファイルは `closer` / `generator` / `team-closer` / `team-generator` が起動直後に `Read` する。**この内容は agent .md 側に絶対に inline でコピーしない**。

## 個別 `git add` の徹底

- `git add -A` / `git add .` は**禁止**（`.claude/settings.json` の `permissions.deny` で構造的に遮断済み）
- 変更ファイルを **個別に `git add <file>`** で指定する
- 意図しないファイル（.env / 認証情報 / 大きなバイナリ / 別タスクの変更）を巻き込まないため

## コミットメッセージ規約（Why ファースト）

```
<type>: <subject>

<body>  ← Why（変更理由・背景）

<footer>
```

- Type: `feat` / `fix` / `docs` / `style` / `refactor` / `test` / `chore`
- subject は 50 文字以内、命令形・現在形
- body は **Why**（なぜその変更が必要か・背景・代替案を採らなかった理由）を記述する
- 単一ファイル変更でも 1 行 body は省略しない

## フッタの規約

- タスク実装コミット: `Refs: task-x_y_z`
- Plan コミット: `Refs: plan-<yyyyMMdd_topic-slug>`
- チェックリスト一括コミット（closer）: `Refs: plan-<yyyyMMdd_topic-slug>`

## 禁止オプション

- `--no-verify`（pre-commit hook のスキップ）禁止
- `--no-gpg-sign` / `-c commit.gpgsign=false` 禁止
- `git push --force` 禁止。force push が必要な場合は `--force-with-lease` のみ
- `git rebase -i` / `git add -i` など対話モード禁止

## 1 タスク 1 コミットの原則

- task コミット（`Refs: task-x_y_z`）は 1 タスク 1 コミットを原則とする
- **TDD 例外（iterate-team）**: `reviewer: codex` のコード変更タスクは test-coder / generator / refactor が test → impl → refactor の最大 3 コミットを積み得る（NG リトライ時は impl コミットが追加されることもある）。**いずれも `Refs: task-x_y_z`** を付ける。詳細は `tdd-policy.md` を参照
- Plan コミット（`Refs: plan-*`）は初稿・修正稿・承認時補正で複数になり得る（Closer/Generator の対象外）

## 検証ループ

コミット前に以下を順に確認する:

1. `git status` で意図しないファイルが含まれていないか確認
2. `git diff --cached` で staged 内容を確認
3. pre-commit hook が走り、`<plugin_root>/scripts/validate-agents.sh`（agent 定義変更時）/ lint コマンド / 型チェックコマンドが pass すること
