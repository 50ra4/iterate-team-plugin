# iterate-team

agent team 並列マルチエージェント・ハーネスの Claude Code プラグイン。要望文から計画を作成し、独立タスクを git worktree で分離して並列実装、検収は **Evaluator 先行 → APPROVED 後に Code Review** の逐次ゲート、PR を自動作成する。**特定の言語・フレームワーク・ディレクトリ構成に依存しない**汎用ニュートラル設計。

## 構成

```
iterate-team-plugin/
├── .claude-plugin/
│   ├── plugin.json        # プラグイン manifest（hooks 登録含む）
│   └── marketplace.json   # 単一プラグインのマーケットプレイス定義
├── commands/              # /iterate-team /iterate-plan /iterate-build /iterate-review
├── agents/                # team-* subagent 定義（生成物・手編集禁止）
├── templates/             # agents の生成元（_base/ + _partials/）と build 仕様
├── operations/            # 運用 runbook・スキーマ・障害対応
├── scripts/               # build-agents / session-start / runlog / worktree / state-prune ほか
├── assets/                # notify.wav（回答待ち通知音）
├── bin/cli.mjs            # 登録ヘルパ CLI（npm 経路）
├── settings.sample.json   # 対象リポへマージする権限サンプル
├── package.json           # npm 配布定義
├── CONTRIBUTING.md        # 開発・コントリビュートガイド
└── PUBLISHING.md          # 公開・リリース手順（メンテナ向け）
```

## インストール

### A. Claude Code プラグインとして（推奨）

```
/plugin marketplace add 50ra4/iterate-team-plugin
/plugin install iterate-team@iterate-team
```

（ローカルの clone を使う場合は `/plugin marketplace add /absolute/path/to/iterate-team-plugin` も可。）

### B. npm 経由

```
npm i -g iterate-team-plugin    # もしくは npx iterate-team-plugin
npx iterate-team-plugin         # 登録手順を表示
npx iterate-team-plugin path    # プラグインルートの絶対パスを表示
```

`bin` は資産を対象リポへコピーせず、登録手順の案内と agent 定義の再生成のみを行う（実体は Claude Code プラグインで、`${CLAUDE_PLUGIN_ROOT}` の解決は Claude Code に委ねる）。**権限設定だけは対象リポ側に手動で導入する必要がある**（次節）。

## 権限設定（対象リポジトリ）

ハーネスは対象リポジトリの `.claude/settings.json` に**特定の権限**が入っていることを前提に動く。Claude Code プラグインは `plugin.json` で `permissions` を宣言できない（同梱 `settings.json` も `agent` / `subagentStatusLine` キーのみ有効）ため、以下を**対象リポ側で手動設定**する。未設定だと、ハーネス用 Bash の都度プロンプトが多発し、かつ直接 `git push` を塞ぐ構造防御が効かない。

1. プラグインルートの絶対パスを取得する。この値は **ハーネスが実行時に使う `${CLAUDE_PLUGIN_ROOT}` と一致**させる必要がある。marketplace 経由（A）でインストールすると Claude Code はプラグインを `~/.claude/plugins/` 配下（キャッシュ）へコピーし、`${CLAUDE_PLUGIN_ROOT}` はそのコピー先を指す。これは npm パッケージのパス（`npx iterate-team-plugin path` が返す値）とは異なるため、marketplace インストールで後者を貼ると allow ルールが実行時のコマンド文字列に一致せず、push ラッパー／補助スクリプトがプロンプト化・失敗する。

   最も確実な取得方法は、**一度 Claude Code セッションを開始**（SessionStart hook が `init.json` を seed する。権限未設定でも hook は実行される）したうえで、記録された `plugin_root` を読むこと:

   ```
   jq -r '.plugin_root' .iterate-team/state/sessions/*/init.json | sort -u
   ```

   npm / ローカル clone を直接プラグインルートに指定する構成に限り、`npx iterate-team-plugin path` でも取得できる。`/plugin marketplace update` 等でインストール先が変わった場合は、この値を取り直して置換し直すこと。

2. 同梱の [`settings.sample.json`](./settings.sample.json) を対象リポの `.claude/settings.json`（または `settings.local.json`）の `permissions` へマージする。サンプル内の `<PLUGIN_ROOT>` を手順 1 の絶対パスに置換する。

導入される主な権限と意図:

- **push 経路の構造防御**: push は `<PLUGIN_ROOT>/scripts/team-push-branch.sh` ラッパー経由のみを無プロンプト allow する（`claude/` 接頭辞限定 + `-f` / `--force` / `--mirror` / `--delete` / refspec / `refs/` / 特殊 ref(`HEAD`) / `main` / `master` / path traversal を allowlist 拒否）。直接 `git push` は主要な破壊的形態（force / `--mirror` / `--delete` / `+refspec` 等）を `deny` し、残りは `ask`（プロンプト）で人間確認に回す。短縮結合フラグ（`git push -uf` 等）は glob 列挙で branch 名衝突なしに塞げないため `ask` で確認する設計。Claude Code on web は terminal が無く直接 push の唯一の対話手段が `ask` のため、全面 deny ではなく `ask` を維持する。
- **補助スクリプト allow**: `runlog-append` / `iterate-validate-session` / `team-worktree-*` / `team-compute-waves` / `validate-plan` 等を都度プロンプトなしで実行する。
- **状態書き込み allow**: 対象リポ直下 `.iterate-team/state/` 配下への Write/Edit。
- **MCP（任意）**: Codex レビュー / Chrome DevTools UI 検収を使う場合のみ。未使用なら該当行は削除してよい。

## 使い方

```
/iterate-team <要望文>                       # 計画→並列実装→検収→PR を一括実行
/iterate-plan  <要望文>                       # 計画フェーズのみ（session-id を発行）
/iterate-build --session <session-id>         # 実装フェーズ
/iterate-review --session <session-id>        # レビュー / PR Ready 化フェーズ
```

## 仕組み（パス規約）

- **プラグイン資産**（commands / agents / templates / operations / scripts / assets）はプラグインルート配下に置かれ、本文中では `<plugin_root>/...` で参照する。
- **`<plugin_root>` の解決**: `${CLAUDE_PLUGIN_ROOT}` は hook / MCP コマンドの実行 env でのみ展開が保証され、agent / command の本文テキストでは展開されない。そのため SessionStart hook が `${CLAUDE_PLUGIN_ROOT}` を `init.json` の `plugin_root` に記録し、Orchestrator が step 0 で読み取って各 subagent プロンプトへ絶対パスを注入する。
- **ランタイム状態**は対象リポジトリ直下 `.iterate-team/{state,tasks,changes}/` に作成される（SessionStart hook が seed）。このうちセッション固有の `.iterate-team/state/` は SessionStart hook が `.git/info/exclude` へ自動登録するため、初回インストールのクリーンな checkout でも `git status` を汚さず `/iterate-team` step 0 の dirty check を誤発火させない（`tasks/` / `changes/` は計画・ADR を含む追跡対象）。チームで共有したい場合は別途 `.gitignore` に `.iterate-team/state/` を追加してもよい（自動登録と重複しても害はない）。

## 前提

- Claude Code（プラグイン機構が `${CLAUDE_PLUGIN_ROOT}` / `${CLAUDE_PROJECT_DIR}` を hook へ供給する）。
- `bash` / `jq` / `git`（scripts が利用）。
- ハーネスは Sonnet 系モデルで検証されている（SessionStart hook が Opus 系を検出すると警告）。
- Codex MCP（`mcp__codex__codex`）と Chrome DevTools MCP は任意。利用可能なら計画 / コードレビューと UI 検収で使われ、無ければサブエージェント（`team-reviewer-plan` / `team-reviewer-code`）で代替する。

## ドキュメント

- **開発・コントリビュート**: [`CONTRIBUTING.md`](./CONTRIBUTING.md)（agent 定義の生成規約・build/validate・テスト・変更の出し方）
- **公開・リリース手順（メンテナ向け）**: [`PUBLISHING.md`](./PUBLISHING.md)（npm / plugin marketplace / GitHub Release）
- **build 機構の詳細**: [`templates/README.md`](./templates/README.md)
- **運用 runbook・スキーマ・障害対応**: [`operations/`](./operations/)
