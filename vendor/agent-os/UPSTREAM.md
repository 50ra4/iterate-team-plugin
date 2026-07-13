# Vendored: Fable Agent OS (UPSTREAM 出典情報)

このディレクトリ (`vendor/agent-os/`) は以下の upstream リポジトリから
`agent-os/` サブディレクトリを **そのまま (verbatim) 複製**したものです。

- Source repository: https://github.com/50ra4/fable-like-coding-agent-instruction-system
- Vendored subdirectory: `agent-os/`
- Upstream commit SHA: `f78aa363797b4bd1bf566f6d097e53583e584dac`
- Vendored date: 2026-07-07

## 重要: 手編集禁止 (Do NOT hand-edit)

`vendor/agent-os/` 配下のファイルは upstream からの verbatim コピーです。
このツリーには **手を加えないでください**。バグ修正・調整が必要な場合でも、
このツリー内で直接編集しないこと。

- Do NOT hand-edit any file under `vendor/agent-os/` (except this
  `UPSTREAM.md` file itself, which is iterate-team-plugin's own provenance
  record and not part of the upstream tree).
- 変更が必要な場合は upstream リポジトリ側で提案・修正し、その後再度
  vendoring し直してください（下記手順）。
- iterate-team 側の統合ロジック（テンプレ注入・オーケストレータ配線など）は
  `vendor/agent-os/` の外側 (`templates/`, `agents/`, `operations/`,
  `scripts/` のプラグイン本体側) に実装します。

## 再 vendoring 手順 (How to re-vendor)

1. upstream リポジトリを clone: `git clone --depth 1 https://github.com/50ra4/fable-like-coding-agent-instruction-system.git <tmpdir>`
2. `git -C <tmpdir> rev-parse HEAD` で新しい commit SHA を取得。
3. `<tmpdir>/agent-os/` の内容で `vendor/agent-os/` を丸ごと置き換える
   (`.git` ディレクトリはコピーしないこと。隠しディレクトリ
   `project-adapter/.agent-os/` は忘れずに含めること)。
4. 実行権限 (`chmod +x`) が `vendor/agent-os/scripts/*.sh` に付与されている
   ことを確認する。
5. この `UPSTREAM.md` の commit SHA と vendored date を更新する。
6. `bash vendor/agent-os/scripts/validate-agent-os.sh` を実行して構造検証。
7. `scripts/run-tests.sh` を実行して既存テストへの影響がないことを確認。
