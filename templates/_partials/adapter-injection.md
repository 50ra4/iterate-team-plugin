# adapter 注入ルール（対象 5 agent 共通）

本ファイルは `team-planner` / `team-generator` / `team-evaluator` / `team-interviewer` / `team-test-coder` が起動直後に `Read` する。**この内容は agent .md 側に絶対に inline でコピーしない**。重複が `<plugin_root>/scripts/validate-agents.sh` で検出される。値の正本は `<plugin_root>/operations/adapter-policy.md` である。

## 1. adapter 読み込み（起動直後・スキップ条件）

- 起動プロンプトに `adapter_dir` キーがあれば、そのパス配下の `command-map.md` / `risk-map.md` / `architecture-map.md` を起動直後に `Read` する
- 加えて `learned-rules.md` のうち **`Status: active` のルールのみ**を `Read` する（`Status: candidate` / `Status: deprecated` のルールは本節の読込対象に含めない・適用しない）
- `adapter_dir` 配下に `rules/` ディレクトリが存在する（split-by-scope レイアウト）場合、`learned-rules.md` の `## Active rules index` を辿って該当する `rules/<scope>.md` も読む。index が指すルール本文は `learned-rules.md` 内に直接書かれたルールと同等の拘束力を持つ
- `adapter_dir` キーが起動プロンプトに存在しない場合、または該当パスのファイルが存在しない場合は **黙って skip** する（エラーにしない・戻り値にも報告しない）

## 2. 適用対象と優先順位

優先順位は以下の通りであり、adapter は常に劣後する:

```
タスク仕様 / universal-rules / Orchestrator 指示
  ＞ command-map.md / risk-map.md / architecture-map.md の事実
    ＞ Status: active ルール
      ＞ Status: candidate ルール
```

- adapter の内容（事実・ルールいずれも）が **タスク仕様（`task-x_y_z.md` 等）・`universal-rules.md`・Orchestrator からの指示**と矛盾する場合は、adapter 側を無視する
- `Status: active` のルールのみが拘束力を持つ。`Status: candidate` は助言であり強制力を持たない（読んでもよいが従う義務はない）
- `Status: deprecated` のルールは§1の読込対象外（そもそも読まない）

### agent 別の意味づけ

| ファイル                                                             | 対象 agent                                    | 効果                                                                                                                                                            |
| --------------------------------------------------------------------- | ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `command-map.md`                                                       | `team-generator` / `team-evaluator`             | build/test/lint/typecheck/run コマンドを検証済み allow-list に制約する。未収載のコマンドは生成・実行せず、verify-then-record するかエスカレーションする。**read-only 調査**（`ls`/`cat`/`grep`/`find`/`git status`/`log`/`diff` 等）は allow-list の対象外であり常に無制約 |
| `risk-map.md`                                                          | `team-planner`（+ `team-generator` の実装ゲート） | 危険領域・要承認箇所を伝え、`team-planner` の計画立案と `team-generator` の実装ゲートに反映する                                                                    |
| `architecture-map.md`                                                  | `team-planner`                                  | 依存方向・境界・拡張ポイントを伝え、タスク分解と実装方針に反映する                                                                                                |
| `learned-rules.md`（`Status: active` のみ）/ `rules/*.md`（split 時） | 5 agent 全体                                    | scope に応じて拘束。`global`/`project` scope は常に適用、`directory`/`file-pattern` scope は `Applies to:` に一致する場合のみ適用                              |

## 3. `adapter_applied` 記録（二経路）

- adapter の事実・ルールを **読んだだけでは記録しない**。**実際に自分の判断・成果物を変えた場合に限り**記録する。記録経路は自 agent の `tools` に応じて以下の二経路に分かれる:

  - **(a) `tools` に `Bash` がある agent**（`team-generator` / `team-evaluator` / `team-test-coder`）: 自分で以下を実行して記録する:

    ```bash
    <plugin_root>/scripts/runlog-append.sh <session-id> adapter_applied '{"rule":"<short name>","agent":"<自agent名>","task_id":"<あれば>"}'
    ```

  - **(b) `tools` に `Bash` がない agent**（`team-planner` / `team-interviewer`）: `Bash` 実行を**試みない**。代わりに、最終戻り値に `適用ルール: <rule-name>` 行（複数件は列挙）を正確に出力することが記録手段であり、**Orchestrator がその行を読み取って `adapter_applied` を代理記録する**（代理記録の規約は `<plugin_root>/operations/harness-common.md` の「adapter 注入」節が正本）。(a) の agent が自ら記録した戻り値行を Orchestrator が二重記録しないことも同節側で規定される

- (a) (b) いずれの経路でも、記録した場合は最終戻り値に `適用ルール: <rule-name>` を 1 行含める（複数件あれば列挙する）
- 「読んだが判断・成果物を変えなかった」場合は記録しない。虚偽適用（実際には影響していないのに適用実績として記録すること）を防ぐための規律である

## 4. adapter 本文の非転記

- adapter ファイル本文（`command-map.md` / `risk-map.md` / `architecture-map.md` / `learned-rules.md` の文面そのもの）を戻り値へ転記しない。token 節約のため、適用した事実（ルール名・コマンド名等と、変えた判断の要約 1 行程度）のみを戻り値へ含める
