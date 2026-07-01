# 公開・リリース手順（メンテナ向け）

`iterate-team-plugin` を配布するときに owner が実行する手順書。配布チャネルは **npm** / **Claude Code plugin marketplace** / **GitHub Release** の 3 つが本筋で、**skills.sh** 系は任意（後述の適合性に注意）。

対象リポジトリ: `50ra4/iterate-team-plugin`

---

## 0. 公開前チェックリスト（全チャネル共通）

- [ ] **バージョン確定**: `package.json` と `.claude-plugin/plugin.json` の `version` が一致し、SemVer で妥当（初回は `0.1.0`）。
- [ ] **メタデータ確認**: `package.json` / `.claude-plugin/plugin.json` / `.claude-plugin/marketplace.json` の `author` / `owner` が実体（`50ra4`）になっている。`package.json` の `repository` / `homepage` / `bugs` の URL が正しい。
  - メールアドレスを載せる場合は owner が最終確認する（本リポジトリの初期値は氏名 + GitHub URL のみ）。
- [ ] **manifest の正が 1 箇所**: プラグイン manifest は `.claude-plugin/plugin.json` と `.claude-plugin/marketplace.json` のみ（リポジトリルートに `plugin.json` / `marketplace.json` を復活させない）。
- [ ] **LICENSE 確認**: `LICENSE` の年・氏名（`Copyright 2026 50ra4`）が正しい。
- [ ] **作業ツリーがクリーン**: `git status --porcelain` が空。
- [ ] **build ドリフト無し**: 生成物とテンプレが一致している。

  ```
  scripts/build-agents.sh --check
  scripts/validate-agents.sh
  bash scripts/__tests__/*.test.sh
  ```

- [ ] **JSON 妥当性**:

  ```
  jq . package.json .claude-plugin/plugin.json .claude-plugin/marketplace.json
  ```

---

## 1. npm 公開

パッケージ名: `iterate-team-plugin`（CLI は `bin/cli.mjs` = 登録ヘルパ。ライブラリではない）

1. 名前の空き確認（初回のみ）:

   ```
   npm view iterate-team-plugin
   ```

   `404` なら空き。既に使われている場合は scoped 名（例 `@50ra4/iterate-team-plugin`）へ変更する。

2. ログイン:

   ```
   npm login
   ```

3. **tarball の中身を確認**（`package.json` の `files` に列挙した資産のみが入り、ルートに manifest が混入しないこと）:

   ```
   npm pack --dry-run
   ```

   含まれるべき: `.claude-plugin/` `agents/` `commands/` `templates/` `operations/` `scripts/` `assets/` `bin/` `README.md` `settings.sample.json`（+ npm が自動で入れる `package.json` / `LICENSE`）。
   `CONTRIBUTING.md` / `PUBLISHING.md` は `files` に含めていないため tarball には入らない（git で参照できれば十分）。

4. 公開のドライラン → 本番:

   ```
   npm publish --dry-run
   npm publish            # scoped 名にした場合は: npm publish --access public
   ```

5. 公開後の確認:

   ```
   npx iterate-team-plugin path      # プラグインルートの絶対パスが表示される
   ```

---

## 2. Claude Code plugin marketplace 公開

このリポジトリ自体が単一プラグインの marketplace（`.claude-plugin/marketplace.json` の `source: "./"`）。git host（GitHub）に push 済みであれば利用者が直接追加できる。

1. `main` を GitHub へ push（公開リポジトリであること）。
2. 利用者側の導入コマンド（README にも記載）:

   ```
   /plugin marketplace add 50ra4/iterate-team-plugin
   /plugin install iterate-team@iterate-team
   ```

3. `.claude-plugin/marketplace.json` を更新したら、利用者は `/plugin marketplace update iterate-team` で反映できる。

### 公式 marketplace への掲載（任意）

Anthropic 管理の [`anthropics/claude-plugins-official`](https://github.com/anthropics/claude-plugins-official) に載せたい場合は、同リポの `marketplace.json` にエントリを追加する PR を出す（受け入れ基準・レビューは先方に従う）。掲載は必須ではなく、自リポジトリ marketplace 単独でも配布できる。

---

## 3. GitHub Release / タグ

SemVer でバージョンタグを打ち、Release notes を CHANGELOG 代わりにする。

> **重要**: `npm version <patch|minor|major>` は既定で `package.json` の書き換えと**同時にコミットとタグを作成**する（`--no-git-tag-version` を付けない限り）。そのため後から `.claude-plugin/plugin.json` を同じコミットへ含められず、npm のバージョン/タグだけが進んで plugin manifest が古いまま取り残されうる。plugin marketplace が利用者へ更新を配るかは `plugin.json` の `version` で決まるので、**両 manifest を揃えてから**コミット/タグを打つこと。以下は `--no-git-tag-version` でタグを作らずに `package.json` だけ更新し、`plugin.json` を合わせてから手動でコミット/タグする手順。

1. `package.json` の `version` だけを更新する（コミット・タグはまだ作らない）:

   ```
   npm version <patch|minor|major> --no-git-tag-version
   ```

2. `.claude-plugin/plugin.json` の `version` を `package.json` と同じ値に合わせる（`npm version` は plugin.json を更新しない）:

   ```
   VERSION=$(node -p "require('./package.json').version")
   jq --arg v "$VERSION" '.version = $v' .claude-plugin/plugin.json > .claude-plugin/plugin.json.tmp \
     && mv .claude-plugin/plugin.json.tmp .claude-plugin/plugin.json
   ```

3. 両 manifest をまとめてコミットし、同じ version で**注釈付きタグ**を打つ（`--follow-tags` は注釈付きタグのみ push するため）:

   ```
   git add package.json .claude-plugin/plugin.json
   git commit -m "release: v$VERSION"
   git tag -a "v$VERSION" -m "v$VERSION"
   ```

4. push:

   ```
   git push --follow-tags
   ```

5. GitHub でタグから Release を作成し、変更点を記述する。

**リリースの推奨順序**: `0` のチェック → `package.json` / `plugin.json` の version を揃える（`--no-git-tag-version`）→ コミット + 注釈付きタグ → `git push --follow-tags` → npm publish → GitHub Release 作成。これで「npm 上のバージョン」「git タグ」「`plugin.json`」「Release」がすべて揃う。

---

## 4. skills.sh / add-skill（任意）

> **注意（適合性）**: 本リポジトリは単一 `SKILL.md` 型の「スキル」ではなく、commands / agents / hooks 一式からなる **Claude Code plugin** である。`skills.sh`（`npx add-skill`）系のレジストリは主に skill 配布を対象とするため、plugin としての本筋は **npm** と **plugin marketplace**。

掲載を検討する場合:

1. 対象レジストリが plugin（`.claude-plugin/` 構成）を受け付けるか、受け入れ形式を確認する。
2. 受け付ける場合は各レジストリの登録手順（多くは PR / エントリ追加）に従う。
3. 受け付けない場合は無理に skill 形式へ分解せず、marketplace / npm 経路を案内する。

---

## 5. リリース後の動作確認

- クリーンな作業ディレクトリで:

  ```
  /plugin marketplace add 50ra4/iterate-team-plugin
  /plugin install iterate-team@iterate-team
  /iterate-team <簡単な要望文>        # 疎通確認
  ```

- npm 経路:

  ```
  npx iterate-team-plugin             # 登録手順が表示される
  npx iterate-team-plugin path        # プラグインルートが表示される
  ```

- 対象リポ側の権限設定（[`settings.sample.json`](./settings.sample.json) のマージ）が必要な点を、リリースノート/README で改めて案内する。

## 6. バージョン更新時の再公開フロー

1. テンプレ/スクリプト等を変更し、`scripts/build-agents.sh` で `agents/` を再生成（詳細は [`CONTRIBUTING.md`](./CONTRIBUTING.md)）。
2. 本書「0. 公開前チェックリスト」を再度通す。
3. 「3. GitHub Release / タグ」でバージョンを上げ、「1. npm 公開」で再 publish。
