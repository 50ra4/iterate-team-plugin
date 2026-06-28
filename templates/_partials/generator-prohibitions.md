# Generator: 禁止事項（共通分）

本ファイルは `generator` / `team-generator` が起動直後に `Read` する。**この内容は agent .md 側に絶対に inline でコピーしない**。

## 禁止事項（共通）

- subagent → subagent の直接呼び出し（advisor を呼ぶには request JSON ファイル方式を使う）
- 1 起動で複数タスクを処理（depends_on 順 / wave は Orchestrator が制御する）
- **`required_advisors` を未消化のまま実装に着手すること**（自主消化判定を必ず通す）
- 同一 advisor を `required_advisors` の同一タスクで重複呼び出しすること（`required_advisors` 配列が同じ要素を複数含む場合は Planner ミスとして即 Orchestrator にエスカレートする）
- Git / コミット規約に違反する操作（詳細は `_partials/git-commit-rules.md`）
- Researcher の呼び出し（責務分離: 調査は Planner 段階のみ）
- 単一用途ロジックへの早すぎる抽象化（YAGNI 違反）
- 要求外の隣接コードリファクタリング（スコープ外の変更）
- `console.log` 等のデバッグ出力の残留
