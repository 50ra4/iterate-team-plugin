# Generator: 失敗時挙動

本ファイルは `generator` / `team-generator` が起動直後に `Read` する。**この内容は agent .md 側に絶対に inline でコピーしない**。

## 失敗時挙動

- advisor request の Write が失敗（権限・ディスク等）した場合、advisor を諦め通常応答に切り替え、Orchestrator に「advisor request 書込失敗。人間にエスカレート」と明記する
- 実装中の例外は隠さず戻り値で報告する
- **同一エラーが 3 回連続して解消できない場合は実装を中断し、Orchestrator に状況を報告してエスカレーションを要請する**

## 差し戻し再起動時の advisor 強制相談（必須）

Evaluator NG（`eval-attempt-N.md`）または Code Reviewer NG（`responses/codex-review-<task-id>-attempt-N.md` / `responses/code-review-<task-id>-attempt-N.md`）または **Refactor 失敗（`responses/refactor-failed-<task-id>-attempt-N.md`、team ハーネスの TDD タスク限定）** を受領して再起動された場合、再実装の前に **必ず本セクションの判定を通す**。判定をスキップして再実装に着手することは禁止。

> **Refactor 失敗 artifact の扱い**: `refactor-failed-<task-id>-attempt-N.md` も有効な差し戻し成果物であり、本ファイルの「成果物 0 件 = `restart_without_artifact`」契約を満たす。本文の理由（`baseline not green` = 失敗テストを緑にする impl 修正が必要 / `cannot keep green` = refactor が緑を保てるよう impl を整える）に従って再実装する。

### 判定手順

1. 受領した差し戻し成果物（`eval-attempt-N.md` / Code Review 応答 / `refactor-failed-<task-id>-attempt-N.md`）を **すべて `Read`** する
2. **現 attempt 番号 `N` の確定**: 以下の優先順で導出する（Code Review NG 単独経路では `eval-attempt-N.md` が未生成のため、ファイル名末尾の `-attempt-N` から確定する必要がある）:
   - (a) プロンプトで受領したパス群のうち、最も新しい成果物のファイル名末尾 `-attempt-<N>.md` から `N` を抽出する（`eval-attempt-N.md` / `codex-review-<task-id>-attempt-N.md` / `code-review-<task-id>-attempt-N.md` / `refactor-failed-<task-id>-attempt-N.md` 共通）
   - (b) 念のため `tasks/<task-id>/eval-attempt-*.md` と `<state-root>/responses/{codex,code}-review-<task-id>-attempt-*.md` と `<state-root>/responses/refactor-failed-<task-id>-attempt-*.md` を `Glob` し、得られた `attempt-N` の最大値と (a) が一致することを確認する。不一致なら `attempt_number_mismatch` エラーで処理停止し Orchestrator に通知する
   - (c) `eval-attempt-*.md` も Code Review 応答も `refactor-failed-*.md` も 0 件の場合は契約違反（差し戻し再起動なのに成果物が存在しない）として `restart_without_artifact` エラーで処理停止
3. `<state-root>/responses/*_team_generator_<task-id>_*.md` を `Glob` で列挙し、当該タスクで既に消化した advisor 集合 `S` を取得
4. 後述の「指摘カテゴリ → advisor マッピング」で差し戻し本文（`eval-attempt-N.md` と Code Review 応答の **両方**、片方しか無い場合は存在する方）から該当カテゴリを抽出し、必要 advisor 集合 `R` を算出
5. **強制相談判定**: 以下のいずれかを満たす場合、advisor request を発行して 1 起動を完了する（再実装には進まない）。判定は **受領した差し戻し artifact 番号 `N` の次試行番号 `next_attempt = N + 1`** に対して行う（artifact `N` は直近失敗の証拠、これから着手するのは試行 `N+1` であり、`max_retries: 2` のタスクは `next_attempt >= 2` の時点で残リトライ枠が 1 回しかない最後のチャンスとなるため）:
   - **`next_attempt >= 2`**（= `N >= 1`）かつ `R \ S` が非空（初回差し戻しから advisor 強制相談する。これにより `max_retries: 2` のタスクでも残り 1 回のリトライ前に advisor を必ず通せる）
   - **同一カテゴリの指摘が 2 回以上連続している**: 判定手順は以下（`N >= 2` 時のみ実施可能。`N == 1` ではそもそも前 attempt が存在しない）:
     1. `N >= 2` の場合、直前 attempt の成果物を `Read` する。具体的には `tasks/<task-id>/eval-attempt-<N-1>.md` と `<state-root>/responses/{codex,code}-review-<task-id>-attempt-<N-1>.md` のうち存在するものすべて
     2. 直前 attempt 本文から「指摘カテゴリ → advisor マッピング」のキーワードを `Grep` 相当でカテゴリ抽出し、集合 `C_prev` を得る
     3. 現 attempt のカテゴリ集合 `C_curr`（手順 4 で算出した `R` と等価）と `C_prev` の積集合が非空であれば「同一カテゴリ 2 回以上連続」とみなし、当該カテゴリの advisor を `R` から優先的に request 発行する
   - 差し戻し本文が後述の「強制トリガ語」を含む
6. 上記いずれにも該当しない（自力で解消可能と判断できる）場合のみ、advisor 相談を skip して再実装に進む。**skip した場合は戻り値に `advisor_consultation_skipped: <理由>` を明記**する（Orchestrator が runlog 追跡用にレビュー）

### 指摘カテゴリ → advisor マッピング

| カテゴリ  | キーワード（差し戻し本文を grep 相当で判定）                                                                                             | 推奨 advisor |
| --------- | ---------------------------------------------------------------------------------------------------------------------------------------- | ------------ |
| security  | 認証 / 認可 / 認可ポリシー / データアクセス制御 / XSS / SQLi / CSRF / 秘密情報 / OWASP / トークン漏洩 / セッション固定 / 入力検証        | security     |
| architect | feature 境界 / モジュール責務 / 依存関係循環 / DB スキーマ / マイグレーション / データフロー / レイヤ違反 / package 構成                 | architect    |
| ui-ux     | アクセシビリティ / a11y / コントラスト / カラー / レイアウト崩れ / 遷移フロー / インタラクション / フォーカス / キー操作                 | ui-ux        |
| tech-lead | 実装パターン / アプリケーション / UI フレームワーク / サーバー側・クライアント側の実行境界 / テスト戦略 / 型設計 / 性能最適化 / 状態管理 | tech-lead    |

複数カテゴリに該当する場合は **`R = { 該当 advisor 全件 }`** とする。`R \ S` の選定は `required_advisors` 配列順を踏襲し、それ以外（required 外）の advisor は本セクションで初めて消化候補となる。

### 強制トリガ語（語が含まれていれば `N == 1` でも advisor 相談を強制）

- `セキュリティ` / `security` / `脆弱性` / `vulnerab` / `権限漏れ` — security 強制
- `feature 境界` / `モジュール責務` / `依存循環` / `スキーマ不整合` — architect 強制
- `アクセシビリティ違反` / `WCAG` / `a11y` — ui-ux 強制
- `サーバー / クライアント境界` / `実行境界` / `状態管理境界` — tech-lead 強制

### advisor request 発行時の追加要件

- request JSON の `question` フィールドに **差し戻し attempt 番号 `N` と、差し戻し本文から抜粋した該当指摘** を含める（advisor が背景文脈を把握できるようにする）
- request JSON の `current_approach` フィールドに **直前コミットの sha と修正方針案** を記載する
- request JSON の `context_files` には差し戻し成果物のパス（`eval-attempt-N.md` 等）を **必ず** 含める
- team-generator は `R \ S` が複数件あればフェーズ A の一括 Write 方式で同時発行する（1 起動内で複数 request を出す）

### 戻り値テンプレ

advisor 相談を発行した場合の戻り値:

```
差し戻し再起動: advisor 相談を発行（attempt=<N>, advisors=<列挙>）。
Orchestrator は advisor 応答取得後に Generator を再起動してください。
```

advisor 相談を skip した場合の戻り値（実装着手後の通常フローへ移行）:

```
差し戻し再起動: advisor 相談 skip（理由=<advisor_consultation_skipped 詳細>）。
N=<N>, R\S=<残カテゴリ>。自力解消で進行します。
```
