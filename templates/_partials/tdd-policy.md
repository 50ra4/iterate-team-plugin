# TDD ポリシー（test-coder / refactor / generator 共通）

本ファイルは `team-test-coder` / `team-refactor` / `team-generator` が起動直後に `Read` する。**この内容は agent .md 側に絶対に inline でコピーしない**。重複が `<plugin_root>/scripts/validate-agents.sh` で検出される。

## 適用ゲート（どのタスクで TDD を回すか）

- TDD（Red-Green-Refactor）を回すのは **コード変更を伴うタスク**（`task-x_y_z.md` フロントマター `reviewer: codex`）のみ。
- `reviewer: none`（docs / 設定 / チェックリストのみ）のタスクは TDD 対象外。Orchestrator は test-coder / refactor を起動しない。
- Orchestrator から `<tdd_enabled>` フラグで通知される。`tdd_enabled=false` のタスクでは本ポリシーを適用しない。
- テスト不能な変更（純粋な styling / 文言 / 定数など、観測可能な振る舞いを持たない）は test-coder / refactor が **no-op で復帰**してよい。

## Red の定義（test-coder）

- 受け入れ条件（EARS）ごとに、観測可能な振る舞いを検証するテストを、プロジェクトのテスト規約（配置・命名・スタイル。存在すれば）に準拠して作成する。
- pre-commit は型チェックコマンドを走らせるため、**テストは型が通る状態**でコミットする。未実装シンボルを参照する場合は本番ファイルに **最小スタブ**（未実装エラーを投げるだけの空実装）を併置して型を通し、**アサーション失敗**で Red を成立させる。
- 実装無しで緑になるテスト（自明・トートロジー）は Red 不成立であり禁止。
- test コミット: `test: <subject>` / フッタ `Refs: task-x_y_z`。

## Green の定義（team-generator フェーズ B / tdd_enabled）

- test-coder が作成したテストを **弱体化・skip 化・削除せず**、実装（スタブ本体の充足）でテストを緑にする。
- テスト自体に不備があると判断した場合もテストを直接書き換えず、`responses/test-defect-<task-id>-attempt-N.md` に不備内容を構造化 `Write` して Orchestrator へ戻し、**test-coder 差し戻し**の対象とする（generator は impl を commit しない）。
- impl コミット: `feat|fix: <subject>` / フッタ `Refs: task-x_y_z`。

## テスト不備差し戻しループ（test-coder remand）

- generator が Green モードでテスト不備を検出した場合、Orchestrator は **test-coder を差し戻しモードで再起動**し、test-coder が受け入れ条件に照らしてテストを是正（`test:` 追加コミット）→ generator フェーズ B 再起動、で Red-Green を再確立する。
- test-coder は是正時もカバレッジを下げる方向の修正を禁止（正しい期待値・適切なアサーションへ直す）。テストが実際には正しいと判断したら **no-op + 「不備なし」**を戻し、generator の通常 impl 修正に委ねる（generator ↔ test-coder の無限往復防止）。
- 差し戻し回数は Orchestrator 側で上限管理する（`test_remand_round`、上限到達は fail closed で NG/エスカレーション）。

## Refactor の定義（team-refactor）

- 対象は **当該タスクの変更ファイルのみ**。動作変更を伴う変更は禁止（公開 API シグネチャ変更・振る舞い変更は不可）。
- リファクタ前後で必ずテストを実行し、**緑を維持**する。緑を割る変更は revert する。
- 改善余地がなければ **no-op（コミットなし）** で復帰する。
- refactor コミット: `refactor: <subject>` / フッタ `Refs: task-x_y_z`。

## コミット構成（1 タスク 1 コミット原則の TDD 例外）

- 1 タスクは TDD で最大 3 コミット（test → impl → refactor）になり得る。**すべて `Refs: task-x_y_z`** を付ける。
- NG リトライ時は impl コミットが追加で積まれ得る（amend 禁止・新規コミットで反映）。
- 詳細なフッタ規約・禁止オプションは `git-commit-rules.md` に従う。
