# knowledge 注入ルール（対象 5 agent 共通）

本ファイルは `team-planner` / `team-generator` / `team-evaluator` / `team-interviewer` / `team-test-coder` が起動直後に `Read` する。**この内容は agent .md 側に絶対に inline でコピーしない**。重複が `<plugin_root>/scripts/validate-agents.sh` で検出される。値の正本は `<plugin_root>/operations/knowledge-policy.md` である。

## 1. digest 読み込み（起動直後・スキップ条件）

- 起動プロンプトに `knowledge_digest_path` キーがあれば、そのパスを起動直後に `Read` する
- `knowledge_digest_path` キーが存在しない場合、または該当パスのファイルが存在しない場合は **黙って skip** する（エラーにしない・戻り値にも報告しない）

## 2. 適用対象セクションと劣後順位

- digest（`lessons.md`）のうち **`## 共通（全 agent）`** セクションと **自 agent 名のセクション**（例: `team-planner` なら `## team-planner`）のみを適用対象とする。他 agent 名のセクションは読んでも適用しない
- レッスンの内容が **タスク仕様（`task-x_y_z.md` 等）・`universal-rules.md`・Orchestrator からの指示**と矛盾する場合は、**レッスン側を無視する**。優先順位は「タスク仕様 / `universal-rules` / Orchestrator 指示 ＞ digest のレッスン」であり、digest は常に劣後する

## 3. 適用実績の記録（`lesson_applied`）

- digest のレッスンを **読んだだけでは記録しない**。**実際に自分の判断・成果物を変えた場合に限り**、以下を実行して記録する:

```bash
<plugin_root>/scripts/runlog-append.sh <session-id> lesson_applied '{"lesson_id":"L-...","agent":"<自agent名>","task_id":"<あれば>"}'
```

- 記録した場合、最終戻り値に `適用レッスン: L-...` を 1 行含める（複数件あれば列挙する）
- 「読んだが判断・成果物を変えなかった」場合は記録しない。虚偽適用（実際には影響していないのに適用実績として記録すること）を防ぐための規律である

## 4. digest 本文の非転記

- digest 本文（レッスンの文面そのもの）を戻り値へ転記しない。token 節約のため、適用した事実（`lesson_id` と、変えた判断の要約 1 行程度）のみを戻り値へ含める
