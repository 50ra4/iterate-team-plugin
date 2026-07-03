# state retention ポリシー

`.iterate-team/state/` 配下ハーネス成果物の保持・削除基準を定める。`state-prune.sh`（task-2_1_1 実装）はこの文書を唯一の参照元とし、ここで確定した具体値をそのまま実装する。

## 前提: 第 1 フェーズ証跡の確認

`state-prune.sh` は実行時に `docs/audits/20260612_claude-dir-audit/01-usage-inventory.md`（リポジトリルート `git rev-parse --show-toplevel` 基準）の存在を確認する。同ファイルが存在しない場合は第 1 フェーズ（`.claude/` 資産棚卸し調査）が未完了とみなし、処理を中断して非ゼロ終了コードを返す。

理由: `01-usage-inventory.md` は prune 対象全セッションのリソース利用状況を記録した証跡であり、証跡なしの prune 実行は後の ADR 追跡を困難にする。

## 運用前提: `--apply` はメイン checkout 上での実行に限定

`state-prune.sh --apply` による実削除は**メイン checkout 上でのみ実行可能**とし、git worktree（linked worktree）上での `--apply` は拒否して非ゼロ終了コードを返す。

理由: worktree 上で `--apply` を実行すると、並列実行中の他タスクの state が誤削除される危険がある。state の実体はメイン checkout 配下に存在するため、削除操作はメイン checkout 上で行う。

加えて `--apply` 時は、解決済み state root が**現在の checkout の `.iterate-team/state` と一致すること**を必須とする。一致しない `--state-root`（同名マーカー `escalation-template.md` を持つ別ディレクトリを含む）を渡した場合は実削除を拒否して非ゼロ終了コードを返す。dry-run（`--apply` なし）は実削除を伴わないため任意の `--state-root` を点検用途で許容する。

理由: `escalation-template.md` の存在確認だけでは、同名マーカーを置いた任意ディレクトリを `--apply` に渡されると誤削除が成立してしまう。実削除対象を checkout 配下の state 実体に固定することで誤削除を構造的に防ぐ。

## 保持対象（prune スコープ）

`.iterate-team/state/` 直下の以下 2 種類を保持・削除の対象とする。

1. **ハーネスセッションディレクトリ**（`team_*` / レガシー形式等、`sessions/<uuid>/` 以外の state 直下ディレクトリ）
2. **`sessions/<uuid>/`** 配下のエントリ（Claude セッション単位のランタイム状態）

`.iterate-team/knowledge/` は `.iterate-team/state/` 配下ではなく git-tracked 資産（`tasks/` / `changes/` と同格）であるため、本ポリシーおよび `state-prune.sh` の prune スコープに**構造的に含まれない**。保持・削除基準の正本は [`knowledge-policy.md`](./knowledge-policy.md)（`knowledge-prune.sh --compact --apply` が別途担う）。

## 保護対象（常に削除から除外）

以下は保持基準にかかわらず削除から除外する。

- **`escalation-template.md`**: state 直下の追跡ファイル。ハーネス全セッション共通テンプレートであり、削除不可
- **保持期間内のハーネスセッションディレクトリ**: 後述しきい値日数以内に更新されたセッション
- **`sessions/<uuid>/` の最新 N 件以内または grace period 以内のエントリ**: 後述の OR 条件で保護されるアクティブセッション

## 確定値（具体的保持基準）

以下の値は確定値であり、推奨・目安ではない。`state-prune.sh` はこの値をハードコードする。

| 保持対象                              | 保持基準                  | 判定キー                                                                        |
| ------------------------------------- | ------------------------- | ------------------------------------------------------------------------------- |
| ハーネスセッションディレクトリ        | 最終更新から **30 日**    | `runlog.jsonl` の mtime（欠落時は dir mtime フォールバック）                    |
| `sessions/<uuid>/` のエントリ（件数） | 最新 **20 件**            | `init.json` の `created_at`（ISO8601）降順（欠落時は dir mtime フォールバック） |
| `sessions/<uuid>/` のエントリ（時間） | **30 日**（grace period） | `init.json` の `created_at`（ISO8601）（欠落時は dir mtime フォールバック）     |

### 採用根拠

- **30 日（ハーネスセッション保持）**: `/iterate-team` の 1 タスクサイクルが最長でも数日以内に完結する実績を踏まえ、長期ブランチ作業（最長 2 週間程度）に対して安全マージンを取り 30 日を採用した。60 日以上は不要なディスク消費を招くため採用しなかった。
- **最新 20 件（`sessions/<uuid>/` 件数保持）**: `01-usage-inventory.md` による実績調査で期間内の並列セッション最大値が 10 件前後であったことから、2 倍のマージンを取り 20 件とした。10 件では連続実行時にアクティブセッションを誤削除するリスクがある。50 件以上は保持コストに対して効果が薄い。
- **30 日（grace period）**: 件数だけで prune するとアクティブセッション（バックグラウンドで待機中の Claude セッション）が N 件を超えた際に誤削除される。時間ベースの grace period を件数保護に OR 条件で重ねることでアクティブセッションの誤削除を防ぐ。grace period 値は件数保持期間に合わせ 30 日で統一した。

## `sessions/<uuid>/` の保護条件（OR 条件）

`sessions/<uuid>/` 配下の各エントリは、以下の **いずれか一方** に該当する場合に保護し、削除対象から除外する。

- **(a) 最新 20 件以内**: `init.json` の `created_at` の降順で上位 20 件に入るエントリ
- **(b) grace period（30 日）以内**: `init.json` の `created_at` が現在時刻から 30 日以内のエントリ

削除対象は「最新 20 件に含まれない **かつ** 作成から 30 日を超えている」エントリのみ。

件数だけで prune するとバックグラウンド待機中のアクティブな Claude セッションを誤削除し得るため、grace period を OR 条件で併用する。

## 順序判定キー（`sessions/<uuid>/`）

「最新 20 件」の判定および grace period の判定は**同一のキー**（`init.json` の `created_at`）を用いる。これにより件数保護と時間保護の境界が一意に決まる。

- **正常時**: `init.json` の `created_at`（ISO8601 文字列、降順で最新判定）
- **`init.json` 欠落または `created_at` 未取得時**: ディレクトリ mtime をフォールバックキーとして使用

`init.json` が存在しない場合（セッション初期化が完了していないエントリ、またはレガシーエントリ）は mtime フォールバックを適用し、両者の順序判定が同一フォールバックキーで統一される。

## 保持期間判定キー（ハーネスセッションディレクトリ）

ハーネスセッションディレクトリ（`team_*` 等）の「最終更新から 30 日」判定は以下のキーを用いる。

- **正常時**: `runlog.jsonl` の mtime
- **`runlog.jsonl` 欠落時**: ディレクトリ mtime をフォールバックキーとして使用

state 実体には `runlog.jsonl` を持たないレガシー／中断セッションが相当数存在する（`01-usage-inventory.md` 5.2 節「主要な限界」参照）。`runlog.jsonl` 欠落時にフォールバックを実装しないと、これらセッションの保持期間判定が不能になりすべて削除候補に誤分類される。欠落時フォールバックを必ず実装する。

## 関連ドキュメント

- 実装スクリプト: `<plugin_root>/scripts/state-prune.sh`（task-2_1_1 で実装）
- 第 1 フェーズ証跡: `docs/audits/20260612_claude-dir-audit/01-usage-inventory.md`
- ハーネス内部状態の概要: [`<plugin_root>/README.md`](../README.md)
