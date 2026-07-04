# knowledge 注入ルール（対象 5 agent 共通）

本ファイルは `team-planner` / `team-generator` / `team-evaluator` / `team-interviewer` / `team-test-coder` が起動直後に `Read` する。**この内容は agent .md 側に絶対に inline でコピーしない**。重複が `<plugin_root>/scripts/validate-agents.sh` で検出される。値の正本は `<plugin_root>/operations/knowledge-policy.md` である。

## 1. digest 読み込み（起動直後・スキップ条件）

- 起動プロンプトに `knowledge_digest_path` キーがあれば、そのパスを起動直後に `Read` する
- `knowledge_digest_path` キーが存在しない場合、または該当パスのファイルが存在しない場合は **黙って skip** する（エラーにしない・戻り値にも報告しない）

## 2. 適用対象セクションと劣後順位

- digest（`lessons.md`）のうち **`## 共通（全 agent）`** セクションと **自 agent 名のセクション**（例: `team-planner` なら `## team-planner`）のみを適用対象とする。他 agent 名のセクションは読んでも適用しない
- レッスンの内容が **タスク仕様（`task-x_y_z.md` 等）・`universal-rules.md`・Orchestrator からの指示**と矛盾する場合は、**レッスン側を無視する**。優先順位は「タスク仕様 / `universal-rules` / Orchestrator 指示 ＞ digest のレッスン」であり、digest は常に劣後する

## 3. 適用実績の記録（`lesson_applied`）

- digest のレッスンを **読んだだけでは記録しない**。**実際に自分の判断・成果物を変えた場合に限り**記録する。記録経路は自 agent の `tools` に応じて以下の二経路に分かれる:

  - **(a) `tools` に `Bash` がある agent**（`team-generator` / `team-evaluator` / `team-test-coder`）: 自分で以下を実行して記録する:

    ```bash
    <plugin_root>/scripts/runlog-append.sh <session-id> lesson_applied '{"lesson_id":"L-...","agent":"<自agent名>","task_id":"<あれば>"}'
    ```

  - **(b) `tools` に `Bash` がない agent**（`team-planner` / `team-interviewer`）: `Bash` 実行を**試みない**。代わりに、最終戻り値に `適用レッスン: L-...` 行（複数件は列挙）を正確に出力することが記録手段であり、**Orchestrator がその行を読み取って `lesson_applied` を代理記録する**（代理記録の規約は `<plugin_root>/operations/harness-common.md` の「knowledge ダイジェスト注入」節が正本）。(a) の agent が自ら記録した戻り値行を Orchestrator が二重記録しないことも同節側で規定される

- (a) (b) いずれの経路でも、記録した場合は最終戻り値に `適用レッスン: L-...` を 1 行含める（複数件あれば列挙する）
- 「読んだが判断・成果物を変えなかった」場合は記録しない。虚偽適用（実際には影響していないのに適用実績として記録すること）を防ぐための規律である

## 4. digest 本文の非転記

- digest 本文（レッスンの文面そのもの）を戻り値へ転記しない。token 節約のため、適用した事実（`lesson_id` と、変えた判断の要約 1 行程度）のみを戻り値へ含める
