# Agent OS

Claude Opus / Claude Sonnet / OpenAI Codex を、Fable のような高精度なコーディングエージェントとして動かすための、軽量な指示システムです。

## Agent OS の目的

このリポジトリの目的は、汎用の LLM コーディングエージェント（Opus / Sonnet / Codex）に、特定のプロダクトに特化して調整された「Fable のような」精度でコードを書かせることです。そのために巨大なプロンプトを1枚書くのではなく、常時読み込まれるファイルは短く保ち、長い手順は必要な時だけ読み込まれる `skills/` に切り出し、プロジェクト固有の事実は各プロジェクトの `.agent-os/` に外部化する、という軽量な構成を採用しています。

## なぜ project-specific ではなく adaptive にするのか

Agent OS は最初から特定プロジェクト用にチューニングされたルール集ではありません。最初は最小限の普遍的原則（Global Layer）だけを持ち、プロジェクトごとに次のループを回すことで育っていきます。

```
観測 (observe) → 学習 (learn) → 適応 (adapt) → 評価 (evaluate)
```

- **観測**: `project-bootstrap` スキルがコードやコマンド、リスクを読み取るだけで、プロジェクトの実態を記録する。
- **学習**: ユーザーからの修正やレビューコメントを `review-feedback-log.md` に逐語で記録する。
- **適応**: 繰り返し観測された事実やルールを `.agent-os/` 配下のアダプタファイルに反映する。
- **評価**: `run-agent-evals` スキルで、instructions を変更した後も精度が落ちていないかを継続的に確認する。

この4段階を回し続けることで、同じ Agent OS の雛形が、プロジェクトごとに異なる「その場に最適化された」振る舞いへと自然に分岐していきます。project-specific に固定してしまうと他プロジェクトへ再利用できず、逆に何も学習しないと Fable のような精度には到達できません。adaptive な設計はこの両立を狙ったものです。

## Fable にこのプロンプトを渡す理由

このリポジトリ自体（README を含むメタプロンプト群）は、Fable によって **一度だけ生成** されるためのものです。Fable が読むのはこの生成用メタプロンプト一式であり、Fable はこれを元に `claude/` や `codex/` 配下の軽量な成果物（CLAUDE.md、skills、agents ファイルなど）を生成します。

日常的にコードを書く Opus / Sonnet / Codex が読むのは、生成された後の軽量ファイルだけです。生成に使ったメタプロンプト（このリポジトリ全体の設計意図を説明する長大な指示）を、日常のコーディングセッションのたびに Opus / Sonnet / Codex に読ませることはありません。生成は一度きりのビルドプロセスであり、実行時の入力ではない、という区別が重要です。

## 3層構造の説明

Agent OS は責務の異なる3つの層で構成されます。

| 層 | 内容 | 置き場所 | 責務 |
|---|---|---|---|
| Global Layer | 全プロジェクト共通の最小限の普遍的原則 | `GLOBAL_AGENTS.md`, `GLOBAL_CLAUDE.md` | プロジェクトを問わず常に正しい振る舞い（安全性、diff の小ささ、事実と推測の区別など）だけを定義する。プロジェクト固有の事実は絶対に書かない。 |
| Project Adapter Layer | プロジェクトごとに観測・蓄積される事実とルール | 各プロジェクトの `.agent-os/`、および短い `CLAUDE.md` / `AGENTS.md` | そのプロジェクト固有のコマンド、アーキテクチャ、リスク、学習済みルールを保持し、時間とともに成長する。 |
| Learning Layer | 修正・レビュー・失敗からの外部記憶 | `.agent-os/failure-log.md`, `review-feedback-log.md`, `learned-rules.md`, `evals.md` | モデルの再学習ではなく、ログとルールファイルという「外部メモリ」によってエージェントの振る舞いを継続的に改善する。 |

Global Layer は他の層の内容を決して取り込まず、Project Adapter Layer は Global Layer の原則を繰り返さない、という分離が重要です。

## Claude Code での導入方法

`scripts/bootstrap-project.sh` を実行するのが正式な導入方法です（手動手順はあくまで fallback で、詳細な手順は `INSTALL.md` を参照してください）。

```bash
bash agent-os/scripts/bootstrap-project.sh --target /path/to/project --for claude
```

このコマンドは次を配置します。

1. `project-adapter/CLAUDE.md`（`{{PROJECT_NAME}}` などのプレースホルダ入り）を対象プロジェクトのルートに `CLAUDE.md` としてコピーする（既に `CLAUDE.md` が存在する場合は上書きせず、そのまま保持する）。
2. `claude/skills` を対象プロジェクトの `.claude/skills/` にコピーする。
3. `claude/agents` を対象プロジェクトの `.claude/agents/` にコピーする。
4. `GLOBAL_AGENTS.md` / `GLOBAL_CLAUDE.md` と canonical スキル一式（`skills/`）を、それぞれ `.agent-os/GLOBAL_AGENTS.md` / `.agent-os/GLOBAL_CLAUDE.md` / `.agent-os/skills/` としてベンダリング（コピー）する。
5. プロジェクト固有の `.agent-os/` アダプタ状態ファイル一式を生成する。

## Codex での導入方法

`scripts/bootstrap-project.sh` を実行するのが正式な導入方法です（手動手順はあくまで fallback で、詳細な手順は `INSTALL.md` を参照してください）。

```bash
bash agent-os/scripts/bootstrap-project.sh --target /path/to/project --for codex
```

このコマンドは次を配置します。

1. `project-adapter/AGENTS.md`（`{{PROJECT_NAME}}` などのプレースホルダ入り）を対象プロジェクトのルートに `AGENTS.md` としてコピーする（既に `AGENTS.md` が存在する場合は上書きせず、そのまま保持する）。
2. `codex/agents/*.toml` を対象プロジェクトの `.codex/agents/` にコピーする。
3. `codex/skills` を対象プロジェクトの `.agents/skills/` にコピーする。
4. `GLOBAL_AGENTS.md` と canonical スキル一式（`skills/`）を、それぞれ `.agent-os/GLOBAL_AGENTS.md` / `.agent-os/skills/` としてベンダリング（コピー）する。
5. プロジェクト固有の `.agent-os/` アダプタ状態ファイル一式を生成する。

`bootstrap-project.sh` はこのとき Global Layer の `GLOBAL_AGENTS.md`（`--for` を問わず常に）と `GLOBAL_CLAUDE.md`（`--for claude` / `both` のとき）も `<TARGET>/.agent-os/` 配下にベンダリング（コピー）し、生成された `CLAUDE.md`/`AGENTS.md` やスキルはそのベンダリング済みパスを参照します。

## `--force` と `--reset-adapter`

`--force` は skills・agents・ベンダリング済み `.agent-os/skills/`・`GLOBAL_*.md` など Agent OS 自身が管理する（OS-owned）ファイルだけを上書きします。**`project-profile.md` / `learned-rules.md` / `failure-log.md` / `review-feedback-log.md` / `evals.md` / `command-map.md` / `architecture-map.md` / `risk-map.md` の8ファイルと、ルートの `CLAUDE.md` / `AGENTS.md` は、たとえ `--force` を指定しても絶対に上書きされません**（学習によって蓄積された、そのプロジェクト固有の状態のため）。既存のファイルがある場合は `PROTECTED:` 行が表示され、そのまま保持されます。

これらの学習状態を明示的にリセットしたい場合は `--reset-adapter` を使います。既存の保護対象ファイルを `.agent-os/backup-<タイムスタンプ>/` に自動でバックアップしたうえで、新しい雛形を再インストールします。

```bash
bash agent-os/scripts/bootstrap-project.sh --target /path/to/project --for both --reset-adapter
```

対象プロジェクト配下の `.agent-os` / `.claude` / `.codex` / `.agents` がシンボリックリンクの場合（あるいはその配下の途中経路がシンボリックリンクの場合）、コピー・ディレクトリ作成・`--reset-adapter` のバックアップ移動のいずれも、対象プロジェクトの外側に書き込むことのないよう明示的に拒否されます（エラー終了し、何も移動・作成されません）。

## 新規プロジェクトでの bootstrap 手順

新しいプロジェクトに Agent OS を導入したら、コードを変更する前に必ず次の順序で実行します。

1. **`project-bootstrap` スキルを最初に実行する。** このスキルは観測専用（observe only）であり、コードは一切変更しません。リポジトリを読み取り、`.agent-os/project-profile.md`（プロジェクトの概要）、`command-map.md`（検証済みのビルド/テスト/lint コマンド）、`risk-map.md`（触ってはいけない領域や壊れやすい箇所）を生成します。この段階では `command-map.md` はまだ空の雛形ですが、`ls`・`cat`・`grep`・`find`・`git status`/`log`/`diff` のような読み取り専用の調査コマンドは常に実行してよいものです（`command-map.md` はビルド/テストなど状態を変更するコマンドのみを対象とする allow-list であり、読み取り専用の調査はその対象外です）。
2. 上記のアダプタファイルが揃ったら、`adapt-to-project` スキルを実行し、Global Layer の原則をそのプロジェクトの実情に合わせて具体化・接続します。

## フィードバックを学習させる方法

ユーザーからの訂正やレビューコメントは `learn-from-feedback` スキルで処理します。

- ユーザーの発言は要約・言い換えせず、**逐語（verbatim）** で `.agent-os/review-feedback-log.md` に記録する。
- 記録した内容は次のカテゴリのいずれかに分類する: `convention`（命名・スタイル等の規約）、`architecture`（設計・構造）、`testing`（テスト方針）、`security`（セキュリティ）、`workflow`（作業手順）、`communication`（報告の仕方）、`forbidden-action`（絶対に行ってはいけない操作）。
- 分類後、そのルールが何回観測されたかを記録し、昇格基準（下記）に従って `learned-rules.md` に反映する。

## learned rule の昇格基準

- **1回の指摘・修正** → `candidate`（候補ルール）として記録するのみ。まだ確定した振る舞いには反映しない。
- **2回以上、同趣旨の指摘・修正が繰り返された** → `active`（有効ルール）に昇格し、以後のセッションで実際に適用する。
- **古くなった、または他のルールと矛盾するルール** → `deprecated` として明示的にマークし、削除はせず理由とともに残す。
- 一度きりの個人的な好み（one-off preference）を Global Layer のルールに昇格させてはいけません。Global Layer はあくまで普遍的な原則のためのものです。

## eval の実行方法

`run-agent-evals` スキルを使い、`.agent-os/evals.md` に保存された評価シナリオに対してエージェントの振る舞いを実行・採点します。instructions（CLAUDE.md、skills、learned-rules など）を変更したときは必ずこれを実行し、変更前後で精度が劣化していないか（precision regression）を確認します。回帰が見つかった場合は、直前の instructions の変更を疑い、`improve-instructions` スキルで修正します。

半自動化のため `scripts/run-agent-evals.sh` を使います。エージェント自身がタスクを実行する部分は自動化されません（あくまでエージェントの仕事です）が、一覧・表示・検証・記録は次のように補助されます。

```bash
# 1. eval 一覧と直近の結果を確認する
bash agent-os/scripts/run-agent-evals.sh --adapter "$TARGET" --list

# 2. 対象 eval の全文を確認する
bash agent-os/scripts/run-agent-evals.sh --adapter "$TARGET" --show <eval-name>

# 3. （ここでエージェントが Task を実際に実行する）

# 4. Validation command を確認する（--exec は command-map.md に
#    記載されたコマンドのみ、--adapter で指定したディレクトリを
#    カレントディレクトリとして実行し、それ以外は拒否する。
#    "Manual review" は常に手動確認）
bash agent-os/scripts/run-agent-evals.sh --adapter "$TARGET" --check <eval-name> [--exec]

# 5. 結果を Results テーブルに記録する
bash agent-os/scripts/run-agent-evals.sh --adapter "$TARGET" --record <eval-name> --result pass|fail --model <model-name> [--notes <text>]
```

## global layer と project adapter の責務分離

- **Global Layer** には、プロジェクトを問わず常に成り立つ最小限の原則だけを書きます。特定の言語・フレームワーク・ディレクトリ構成・コマンドは絶対に書きません。
- **Project Adapter** には、観測によって確認された、そのプロジェクト固有の事実だけを書きます。一般化した「べき論」や、他プロジェクトにも当てはまりそうな原則は書きません。
- 両者を混ぜてはいけません。Global Layer にプロジェクト固有の記述が混入すると他プロジェクトへの再利用性が失われ、Project Adapter に普遍的な原則を書くと Global Layer との重複・矛盾が発生します。

## ルールが肥大化したときの整理方法

CLAUDE.md、skills、learned-rules.md 等が増えすぎて読みにくくなったら `improve-instructions` スキルを実行します。このスキルは次を行います。

- 重複しているルールをマージする。
- `scripts/detect-rule-conflicts.sh` を実行し、矛盾するルールを検出する。
- 古くなった・使われなくなったルールを `deprecated` として整理する（削除ではなくマーク）。
- 数行を超える手順が常時読み込みファイル（CLAUDE.md / AGENTS.md）に紛れ込んでいたら、`skills/` へ移動し、元の場所には一行のポインタだけを残す。

`learned-rules.md` 自体が肥大化した場合（目安: active なルールが10件を超える、またはファイルが300行を超える）は、`scripts/split-learned-rules.sh` で `Status: active` のルールをスコープ別ファイル（`.agent-os/rules/global.md` / `project.md` / `directory.md` / `file-pattern.md`、各ルールの `Scope:` フィールドに従う）へ分割できます。`learned-rules.md` には各ルールへのポインタとなる `## Active rules index` が残り、candidate・deprecated のルールは常に `learned-rules.md` に残ります。分割後は、`CLAUDE.md` / `AGENTS.md` などの常時読み込みチェックリストや各 skill・subagent も、`## Active rules index` が指す `.agent-os/rules/*.md` を読むよう指示されます。分割前と同じく `Status: active` のルールとして拘束力を持つため、`learned-rules.md` だけを読んで分割済みのルールを見落とすことはありません。

```bash
# 移動計画だけを確認する（ファイルは変更しない）
bash agent-os/scripts/split-learned-rules.sh --adapter "$TARGET" --dry-run

# 実際に分割する
bash agent-os/scripts/split-learned-rules.sh --adapter "$TARGET"
```

分割は任意（optional）です。初期状態は単一ファイルのままで問題なく、`detect-rule-conflicts.sh` / `summarize-learning-log.sh` / `validate-agent-os.sh` はいずれのレイアウトにも対応しています。

## ディレクトリ構成の一覧

```
agent-os/
├── README.md                  # 本ドキュメント（日本語）
├── GLOBAL_AGENTS.md            # Global Layer: 全エージェント共通の最小原則
├── GLOBAL_CLAUDE.md            # Global Layer: Claude Code 固有の差分
├── INSTALL.md                  # 導入手順（日本語）
├── templates/                   # 各種テンプレート
├── skills/                      # 10 の canonical スキル
│   ├── project-bootstrap/
│   ├── project-profile/
│   ├── adapt-to-project/
│   ├── learn-from-feedback/
│   ├── improve-instructions/
│   ├── generate-agent-files/
│   ├── run-agent-evals/
│   ├── fix-bug-safely/
│   ├── implement-feature-safely/
│   └── review-changes/
├── claude/                      # Claude Code 向け生成物
│   ├── CLAUDE.md
│   ├── skills/
│   └── agents/*.md
├── codex/                        # OpenAI Codex 向け生成物
│   ├── AGENTS.md
│   ├── agents/*.toml
│   └── skills/
├── project-adapter/              # Project Adapter Layer の雛形
│   ├── AGENTS.md
│   ├── CLAUDE.md
│   └── .agent-os/
└── scripts/
    ├── bootstrap-project.sh
    ├── validate-agent-os.sh
    ├── summarize-learning-log.sh
    ├── detect-rule-conflicts.sh
    ├── run-agent-evals.sh
    └── split-learned-rules.sh
```

## `claude/CLAUDE.md` と `codex/AGENTS.md` は何のためにあるか

`claude/CLAUDE.md` と `codex/AGENTS.md` は、**このリポジトリ（Agent OS の開発元）自身の中で** Claude Code / Codex を使って作業するときのエントリポイントです。`bootstrap-project.sh` はこの2ファイルをどこにもインストールしません — 対象プロジェクトの `CLAUDE.md` / `AGENTS.md` として実際にコピーされるのは `project-adapter/CLAUDE.md` / `project-adapter/AGENTS.md` の方です（前述の各インストール手順を参照）。この2ファイルはそれとは別に、任意でユーザーのグローバル設定（例: `~/.claude/CLAUDE.md` や Codex のグローバル設定）の候補として使うこともできますが、必須ではありません。導入先プロジェクトの成果物と混同しないよう注意してください。

## 注意: メタプロンプトを Opus / Sonnet / Codex に毎回渡さないこと

このリポジトリ（`agent-os/` 全体、特にこの README のようなメタ文書）は、Fable がこのシステムを生成するための素材です。**日常のコーディングセッションで Opus / Sonnet / Codex に渡してよいのは、生成後の軽量ファイル（`CLAUDE.md` / `AGENTS.md` / `skills/` / `agents/` / `.agent-os/` の中身）だけです。** この生成用メタプロンプト一式を毎回のセッションで読み込ませることは、常時読み込みコストを不必要に増大させ、Agent OS が目指す「軽量な指示システム」という設計原則そのものに反します。
