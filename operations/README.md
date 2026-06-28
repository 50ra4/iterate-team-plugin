# operations/（運用ドキュメント）

Claude Code ハーネス（`/iterate-team` 並列版 / `/iterate-plan` + `/iterate-build` + `/iterate-review` 責務分割版）の運用ドキュメント集。プロジェクトのプロダクト仕様ドキュメントとは別に、本ディレクトリは「ハーネスをどう動かすか」の処理仕様・障害対応・スキーマ定義を扱う。

## 索引

| ファイル                                                 | 役割                                                                                                                                                                                                                                                                                                                          |
| -------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`harness-common.md`](./harness-common.md)               | ハーネス共通の手順 SoT。引数処理 / session-id 発行 / Planner ループ / 計画承認 / closer 委譲 / 失敗時挙動 / 不変条件                                                                                                                                                                                                          |
| [`iterate-team-runbook.md`](./iterate-team-runbook.md)   | team 固有の運用詳細・環境前提・wave 並列スケジューリング・worktree 管理・dev container 経路・PR Ready 化。[「3 コマンド分割と session-id 引継ぎプロトコル」章](./iterate-team-runbook.md#3-コマンド分割と-session-id-引継ぎプロトコル)（`/iterate-plan` / `/iterate-build` / `/iterate-review` の責務境界・引継ぎ仕様の SoT） |
| [`agent-decision-schema.md`](./agent-decision-schema.md) | `state/runlogs/<session-id>.jsonl` のスキーマ定義と発火点棚卸し                                                                                                                                                                                                                                                               |

## 使い分け

- **共通章を変更したい**: `harness-common.md` を SoT として編集。team 固有挙動は本書の各 h2 末尾の `> **team 固有**:` 引用ブロックで併記しているため、共通章を編集する際は team 側を壊さないよう確認する
- **team の挙動だけ変更したい**: `iterate-team-runbook.md` を編集
- **runlog の新規イベント種別を追加したい**: `agent-decision-schema.md` のスキーマ表に追加し、各 runbook の発火点表にも反映

## 参照元

- `<plugin_root>/commands/iterate-team.md` — 引数定義 + ステップ概要 + 本ディレクトリへの参照リンク
- `<plugin_root>/commands/iterate-plan.md` — 計画フェーズ専用ハーネス（ステップ 0〜4）
- `<plugin_root>/commands/iterate-build.md` — 実装フェーズ専用ハーネス（ステップ 4.5〜5）
- `<plugin_root>/commands/iterate-review.md` — レビューフェーズ専用ハーネス（ステップ 6〜7'）
- `<plugin_root>/README.md` — `.claude/` 配下構成案内 + 本ディレクトリへの参照リンク

## 関連

- ハーネス基盤ドキュメント: `<plugin_root>/operations/`（mcp-startup / permissions-aggregation / session-start-hook / agents/）
- ハーネス内部状態: `.iterate-team/state/`（sessions / runlogs / plans）
- タスク管理: `.iterate-team/tasks/` / `.iterate-team/changes/`
