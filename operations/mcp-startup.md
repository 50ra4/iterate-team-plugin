# MCP サーバ起動方針

## 背景

`.claude/settings.json` に `enableAllProjectMcpServers: true` を設定していた期間、Claude Code はセッション開始時に `.mcp.host.json` に定義された全 MCP サーバを並走起動していた。未使用のサーバ起動はセッション起動レイテンシに寄与していた。

根拠レポート: [`.iterate-team/changes/20260611_harness-evolution-digest.md#audit-unused-and-perf`](../changes/20260611_harness-evolution-digest.md#audit-unused-and-perf) Q3 ③（旧 `tasks/20260513_audit-unused-and-perf/audit-report.md` はダイジェストに吸収済み）

## 採用方針

`enableAllProjectMcpServers: false` に変更し、Claude Code 側の lazy 起動機能を利用する。各ツール（`mcp__<server>__*`）が初めて呼び出された時点でサーバが自動起動する。

プロファイル分割（`.mcp.host-ui.json` や `.mcp.host-dev.json` などのファイル分割）は採用しない。理由: セッション起動コンテキストに応じた読み込みファイルの切り替えは設定管理の複雑化を招くため、lazy 起動による単一ファイル管理を優先する。

## サーバ別起動契機

| サーバ            | 起動契機                                                                                                      |
| ----------------- | ------------------------------------------------------------------------------------------------------------- |
| `chrome-devtools` | evaluator / team-evaluator が UI 検収時に `mcp__chrome-devtools__*` ツールを呼び出したとき                    |
| `codex`           | iterate-team step 3.5.B / 5.3.2.A で `mcp__codex__codex` を呼び出すとき（`<is_dev_container>=true` 環境のみ） |

## フォールバック整合

`<is_dev_container>=false` 環境では codex MCP が起動せず、`mcp__codex__codex` 呼び出しは失敗する。この場合、ハーネスは `team-reviewer-plan` / `team-reviewer-code` フォールバック経路に切り替える。

この設計は既存の codex フォールバック設計と完全に整合する。

関連先行 ADR: [`.iterate-team/changes/20260611_harness-evolution-digest.md#codex-fallback-review`](.iterate-team/changes/20260611_harness-evolution-digest.md#codex-fallback-review)

## 想定レイテンシ

実測なし（実測は smoke 検証フェーズで実施予定）。
