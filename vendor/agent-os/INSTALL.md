# Agent OS 導入手順 (INSTALL)

対象プロジェクトに Agent OS を実際にインストールするための、具体的な手順書です。設計の背景や各層の責務については `README.md` を参照してください。

## 前提

- `agent-os/` はこのリポジトリの中にあり、対象プロジェクトは別ディレクトリ（`<TARGET>`）とします。
- 以下、`<TARGET>` は導入先プロジェクトのルートディレクトリの絶対パスを表します。

```bash
export TARGET=/path/to/your/project
```

## Claude Code 向けインストール

Claude Code では、次のファイルが対象プロジェクトの以下の場所に配置されます。

| 生成元 | 配置先 |
|---|---|
| `agent-os/project-adapter/CLAUDE.md`（`{{PROJECT_NAME}}` プレースホルダ入り） | `<TARGET>/CLAUDE.md` |
| `agent-os/claude/skills/*` | `<TARGET>/.claude/skills/*` |
| `agent-os/claude/agents/*.md` | `<TARGET>/.claude/agents/*.md` |
| `agent-os/project-adapter/.agent-os/*`（8つのアダプタ状態ファイル） | `<TARGET>/.agent-os/*` |
| `agent-os/GLOBAL_AGENTS.md`, `agent-os/GLOBAL_CLAUDE.md` | `<TARGET>/.agent-os/GLOBAL_AGENTS.md`, `<TARGET>/.agent-os/GLOBAL_CLAUDE.md` |
| `agent-os/skills/*`（10 の canonical スキル） | `<TARGET>/.agent-os/skills/*`（ベンダリング） |

`bootstrap-project.sh` を使えば、これらを一括で配置できます。**通常はこちらを使ってください** — 以下の手動手順はこのスクリプトが使えない場合の fallback です。

```bash
bash agent-os/scripts/bootstrap-project.sh --target "$TARGET" --for claude
```

手動で行う場合は次のようになります（`bootstrap-project.sh` の内部処理を再現したものです）。

```bash
cp agent-os/project-adapter/CLAUDE.md "$TARGET/CLAUDE.md"
mkdir -p "$TARGET/.claude/skills" "$TARGET/.claude/agents" "$TARGET/.agent-os/skills"
cp -r agent-os/claude/skills/. "$TARGET/.claude/skills/"
cp -r agent-os/claude/agents/. "$TARGET/.claude/agents/"
cp -r agent-os/project-adapter/.agent-os/. "$TARGET/.agent-os/"
cp agent-os/GLOBAL_AGENTS.md "$TARGET/.agent-os/GLOBAL_AGENTS.md"
cp agent-os/GLOBAL_CLAUDE.md "$TARGET/.agent-os/GLOBAL_CLAUDE.md"
cp -r agent-os/skills/. "$TARGET/.agent-os/skills/"
```

コピーした `$TARGET/CLAUDE.md` の中の `{{PROJECT_NAME}}` プレースホルダは、`bootstrap-project.sh` なら自動で置換される箇所です。手動で行った場合は自分でプロジェクト名に置き換えてください（例: `sed -i "s/{{PROJECT_NAME}}/my-project/g" "$TARGET/CLAUDE.md"`）。

（参考）`agent-os/claude/CLAUDE.md` は上記の配置対象には含まれません。これは Agent OS リポジトリ自身の中で作業する際のエントリポイントであり、任意でユーザーのグローバル設定の候補として使うものです。

既に `<TARGET>/CLAUDE.md` が存在する場合は上書きせず、冒頭に1行の参照を追加してください。

```markdown
See `.agent-os/GLOBAL_AGENTS.md` / `.agent-os/GLOBAL_CLAUDE.md`(このリポジトリからベンダリングした内容) for baseline agent principles.
```

## Codex 向けインストール

Codex では、次のファイルが対象プロジェクトの以下の場所に配置されます。

| 生成元 | 配置先 |
|---|---|
| `agent-os/project-adapter/AGENTS.md`（`{{PROJECT_NAME}}` プレースホルダ入り） | `<TARGET>/AGENTS.md` |
| `agent-os/codex/agents/*.toml` | `<TARGET>/.codex/agents/*.toml` |
| `agent-os/codex/skills/*` | `<TARGET>/.agents/skills/*` |
| `agent-os/project-adapter/.agent-os/*`（8つのアダプタ状態ファイル） | `<TARGET>/.agent-os/*` |
| `agent-os/GLOBAL_AGENTS.md` | `<TARGET>/.agent-os/GLOBAL_AGENTS.md` |
| `agent-os/skills/*`（10 の canonical スキル） | `<TARGET>/.agent-os/skills/*`（ベンダリング） |

`bootstrap-project.sh` を使えば、これらを一括で配置できます。**通常はこちらを使ってください** — 以下の手動手順はこのスクリプトが使えない場合の fallback です。

```bash
bash agent-os/scripts/bootstrap-project.sh --target "$TARGET" --for codex
```

手動で行う場合（同じくあくまで fallback です）:

```bash
cp agent-os/project-adapter/AGENTS.md "$TARGET/AGENTS.md"
mkdir -p "$TARGET/.codex/agents" "$TARGET/.agents/skills" "$TARGET/.agent-os/skills"
cp -r agent-os/codex/agents/. "$TARGET/.codex/agents/"
cp -r agent-os/codex/skills/. "$TARGET/.agents/skills/"
cp -r agent-os/project-adapter/.agent-os/. "$TARGET/.agent-os/"
cp agent-os/GLOBAL_AGENTS.md "$TARGET/.agent-os/GLOBAL_AGENTS.md"
cp -r agent-os/skills/. "$TARGET/.agent-os/skills/"
```

コピーした `$TARGET/AGENTS.md` の中の `{{PROJECT_NAME}}` プレースホルダも、手動で行った場合は自分でプロジェクト名に置き換えてください。

（参考）`agent-os/codex/AGENTS.md` は上記の配置対象には含まれません。これは Agent OS リポジトリ自身の中で作業する際のエントリポイントであり、任意でユーザーのグローバル Codex 設定の候補として使うものです。

## Claude Code と Codex を両方使うプロジェクト

同じプロジェクトで Claude Code と Codex の両方を使う場合は、`--for both` を指定します。両方のファイル一式が配置され、`.agent-os/` は共通で1つだけ生成されます（Project Adapter Layer はツールを問わず共有されるためです）。

```bash
bash agent-os/scripts/bootstrap-project.sh --target "$TARGET" --for both
```

## `--force` と `--reset-adapter`（再インストール時の注意）

`--force` を付けて再実行しても、`<TARGET>/.agent-os/` 配下の8つのアダプタ状態ファイル（`project-profile.md`、`learned-rules.md`、`failure-log.md`、`review-feedback-log.md`、`evals.md`、`command-map.md`、`architecture-map.md`、`risk-map.md`）と、ルートの `CLAUDE.md` / `AGENTS.md` は**絶対に上書きされません**。これらはそのプロジェクトが学習・蓄積してきた状態（project-owned state）だからです。`--force` が上書きするのは skills・agents・ベンダリング済み `.agent-os/skills/`・`GLOBAL_*.md` など、Agent OS 自身が生成・管理する（OS-owned）ファイルだけです。既存の保護対象ファイルがある場合は `PROTECTED:` という行が表示され、そのまま保持されたことがわかります。

これらの学習状態を明示的に作り直したい場合だけ `--reset-adapter` を使います。実行前に既存の保護対象ファイルを `<TARGET>/.agent-os/backup-<タイムスタンプ>/` へ自動的にバックアップしたうえで、新しい雛形を再インストールします（`--force` を暗黙に含むわけではないので、OS-owned ファイルの更新には別途 `--force` が必要です）。

```bash
bash agent-os/scripts/bootstrap-project.sh --target "$TARGET" --for both --reset-adapter
```

## 初回実行手順（First-run procedure）

配置が終わっても、それだけではまだ「汎用の Global Layer」が置かれただけの状態です。**コードを一切変更する前に**、次の順序で `project-bootstrap` スキルを実行してください。

1. Claude Code / Codex のセッションを `<TARGET>` で開始する。
2. `project-bootstrap` スキルを呼び出す（例: Claude Code なら `.claude/skills/project-bootstrap/SKILL.md` が読み込まれる状態で「プロジェクトを bootstrap して」と依頼する）。
3. このスキルは観測専用（observe only）であり、コードは変更しません。実行が完了すると次が生成されます。
   - `<TARGET>/.agent-os/project-profile.md`
   - `<TARGET>/.agent-os/command-map.md`
   - `<TARGET>/.agent-os/risk-map.md`
4. これらのアダプタファイルが生成された後に、初めて `adapt-to-project` スキルを実行し、Global Layer の原則をこのプロジェクトに合わせて具体化します。

この順序（bootstrap → adapt）を守らずにいきなりコード変更のタスクを依頼すると、エージェントはプロジェクト固有のコマンドやリスクを知らないまま作業することになるため、必ず初回はこの手順を先に踏んでください。

## インストールの検証方法

配置が正しく行われたかどうかは、付属の検証スクリプトで確認します。

```bash
# Agent OS リポジトリ自体の構成を検証する
bash agent-os/scripts/validate-agent-os.sh

# 導入先プロジェクトのアダプタを検証する
bash agent-os/scripts/validate-agent-os.sh --adapter "$TARGET"
```

このスクリプトは以下を確認します。

- （デフォルト）`agent-os/` リポジトリ自体に必須ファイルがすべて存在し、常時読み込みファイルが肥大化していないか。
- （`--adapter` 指定時）`<TARGET>/.agent-os/` 配下に必須の8ファイル（`project-profile.md`、`learned-rules.md`、`failure-log.md`、`review-feedback-log.md`、`evals.md`、`command-map.md`、`architecture-map.md`、`risk-map.md`）と `GLOBAL_AGENTS.md` が存在するか。
- （`--adapter` 指定時）`learned-rules.md` の `Status:` の値が `candidate` / `active` / `deprecated` のいずれかになっているか。
- （`--adapter` 指定時、`.agent-os/rules/` が存在する場合）`scripts/split-learned-rules.sh` で分割済みのスコープ別ファイル（`global.md` / `project.md` / `directory.md` / `file-pattern.md`）についても同様に `Status:` の値をチェックします。分割後は `learned-rules.md` の `## Active rules index` がこれらのファイルを指し、CLAUDE.md/AGENTS.md や各 skill・subagent はそこも読む前提になっているため、この検証は分割前後どちらのレイアウトでも同じように機能します。

検証がすべて成功したら、通常のコーディングタスクを依頼して問題ありません。エラーが出た場合は、該当するコピー手順またはスキルの実行をやり直してください。

## トラブルシューティング

- `bootstrap-project.sh` がエラーになる場合は、`--target` に渡したパスが存在し、書き込み権限があることを確認してください。
- `.agent-os/` が生成されない場合は、先に配置手順（ファイルのコピー）が完了しているか、`project-bootstrap` スキルを実行し忘れていないかを確認してください。
- ルールの矛盾や肥大化に気づいた場合は、インストールのやり直しではなく `improve-instructions` スキルと `agent-os/scripts/detect-rule-conflicts.sh` の実行で対処してください（詳細は `README.md` を参照）。
