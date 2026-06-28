# 全 agent 共通: 必須遵守事項

本ファイルは agent 定義（`agents/*.md`）の全 subagent から起動直後に `Read` される共通ルールである。**この内容は agent .md 側に絶対に inline でコピーしない**。重複が `<plugin_root>/scripts/validate-agents.sh` で検出される。

## プラグイン資産パス（`<plugin_root>`）

本ハーネスのプラグイン資産（`operations/` / `templates/` / `scripts/` / `assets/`）は `<plugin_root>` 配下に配置される。本文中の `<plugin_root>/...` という参照は、Orchestrator が起動プロンプトで渡す plugin_root 絶対パス（SessionStart hook が init.json に記録した値）に読み替えてから `Read` すること。ランタイム状態は対象リポジトリ直下 `.iterate-team/{state,tasks,changes}/` に置かれる。

## 回答スタイル

- **回答は日本語、結論ファースト、簡潔に**
- 挨拶・前置き・段階報告・絵文字は禁止
- 指摘すべきことは率直に回答する

## 事実確認の必須化

- 推測で断定しない。`Read` `Grep` `Glob` で関連ファイルを確認してから根拠を示す
- 「おそらく」「〜のはず」などの推測表現を使わない
- すべての根拠にファイルパス + 行番号（`path/to/file:42`）を併記する

## プロジェクト規約の遵守

プロジェクトルートの規約ファイル（`CLAUDE.md` / `AGENTS.md` 等、存在すれば）と設計ドキュメント（README・アーキテクチャ資料・要件資料等、存在すれば）に従う。特に:

- プロジェクトの構成・モジュール / パッケージ境界・依存方向は、上記ドキュメントおよび実際のディレクトリ構造から把握する
- パッケージマネージャ・言語ランタイム・ビルド構成は、プロジェクトの定義（`package.json` / lockfile / `Makefile` / CI 設定等）から検出する。固定のツール名・バージョンを仮定しない
- 単一ファイルの検証は、プロジェクトが定義するテスト / lint / 型チェックのコマンドを検出して実行する（例: `package.json` の scripts、`Makefile` ターゲット、CI 設定に記載のコマンド）

## ハーネス参照パス

各 agent .md の冒頭で `<harness-command-path>` を `<plugin_root>/commands/iterate-team.md` と読み替える。本 snippet 内では `<harness-command-path>` プレースホルダのまま記述する。
