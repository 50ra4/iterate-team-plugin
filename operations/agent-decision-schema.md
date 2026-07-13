# agent_decision runlog イベントスキーマ定義と発火点棚卸し

> 本ドキュメントは `agent_decision` runlog イベントのスキーマと発火点棚卸しの正本である。

## 1. agent_decision イベントスキーマ

`agent_decision` は `/iterate-team` の Agent 呼出・スキップ・採否を構造化記録するための新規 runlog イベントである。既存イベント（`*_requested` / `*_completed` 等）は無変更のまま維持し、本イベントを追加する。

### 1.1 キー定義

| キー         | 必須 | 値域 / 説明                                                                                                                                                                                                              |
| ------------ | ---- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `agent`      | 必須 | 対象 Agent 名（`researcher` / `debugger` / `tracer` / `advisor-architect` / `advisor-ui-ux` / `advisor-security` / `advisor-tech-lead` / `evaluator` / `codex-plan-review` / `codex-code-review` / `team-publisher` / `team-retrospector` / `team-profiler`（Phase 1・`.agent-os/` 観測、`/iterate-adapt` から起動） / `team-adapter`（Phase 2・`.agent-os/` 学習、`/iterate-review` ステップ 6.8 から `mode=feedback` で起動） 等） |
| `decision`   | 必須 | `invoked` / `skipped` / `adopted` / `rejected` のいずれか（4 種のみ許容）                                                                                                                                                |
| `reason`     | 必須 | 自然文 1〜2 行。スキップ時は必須記録                                                                                                                                                                                     |
| `task_id`    | 任意 | タスクループ内発火時のみ（例: `task-1_2_3` / `plan-review` / `planner-loop`）                                                                                                                                            |
| `attempt`    | 任意 | リトライ番号（例: Codex code review attempt-2）                                                                                                                                                                          |
| `request_id` | 任意 | 既存 `*_requested` イベントとの紐付け用                                                                                                                                                                                  |

### 1.2 decision の値域

`decision` フィールドは以下の 4 値のみを許容する。

| 値         | 意味                                                          |
| ---------- | ------------------------------------------------------------- |
| `invoked`  | Agent を起動した                                              |
| `skipped`  | 条件（reviewer: none / dev container 等）により起動を省略した |
| `adopted`  | Agent の出力を採用した（Evaluator OK 等）                     |
| `rejected` | Agent の出力を棄却した（max_retries 到達 / NG 等）            |

### 1.3 追記書式

`<plugin_root>/scripts/runlog-agent-decision.sh`（task-1_2_1 で実装）経由で追記する。直接 `runlog.jsonl` に書き込むことは禁止。

```
<plugin_root>/scripts/runlog-agent-decision.sh "<session-id>" <agent> <decision> "<reason>" [--task-id <id>] [--attempt N] [--request-id <id>]
```

内部では `<plugin_root>/scripts/runlog-append.sh` を呼び `event=agent_decision` で追記する。

### 1.4 runlog 上の表現

既存の `runlog.jsonl`（JSON Lines 形式）に `event: "agent_decision"` として追記される。

```json
{
  "event": "agent_decision",
  "agent": "researcher",
  "decision": "invoked",
  "reason": "Planner 要求: <topic>",
  "task_id": "task-1_2_3",
  "attempt": 1,
  "request_id": "20260511120000_researcher_task-1_2_3"
}
```

フィルタリングには `jq 'select(.event == "agent_decision")'` を使用する。

---

## 2. 発火点棚卸し

### 2.1 /iterate-team の発火点

| 発火点                               | agent                 | decision   | 典型 reason                                        |
| ------------------------------------ | --------------------- | ---------- | -------------------------------------------------- |
| ステップ 3.2 type=research 起動時    | `team-researcher`     | `invoked`  | 「Planner 要求: &lt;topic&gt;」                    |
| ステップ 3.2 type=debug 起動時       | `team-debugger`       | `invoked`  | 「Planner 要求: &lt;symptoms&gt;」                 |
| ステップ 3.2 type=trace 起動時       | `team-tracer`         | `invoked`  | 「Planner 要求: &lt;topic&gt;」                    |
| ステップ 3.2 type=interview 起動時   | `team-interviewer`    | `invoked`  | 「Planner 再委譲: &lt;topic&gt;」                  |
| ステップ 3.5.1 起動時                | `codex-plan-review`   | `invoked`  | 「plan_revision &lt;N&gt; レビュー」               |
| ステップ 4.5.A.3 PR 作成             | `team-publisher`      | `invoked`  | 「host 環境 + 初回起動」                           |
| ステップ 4.5.B.1 PR skip             | `team-publisher`      | `skipped`  | 「dev container のため」                           |
| ステップ 5.1.1 advisor 並列起動      | `team-advisor-<name>` | `invoked`  | 「Generator フェーズ A request」                   |
| ステップ 5.1.5 test-coder 起動       | `team-test-coder`     | `invoked`  | 「TDD: Red 先行（reviewer: codex）」               |
| ステップ 5.1.5 test-coder skip       | `team-test-coder`     | `skipped`  | 「テスト対象なし (no-op)」                         |
| ステップ 5.2.5 refactor 起動         | `team-refactor`       | `invoked`  | 「TDD: refactor（/simplify + /code-review）」      |
| ステップ 5.3.2 起動時                | `codex-code-review`   | `invoked`  | 「Evaluator OK かつ reviewer: codex のため起動」   |
| ステップ 5.3.2 skip 時               | `codex-code-review`   | `skipped`  | 「reviewer: none のため skip」                     |
| ステップ 5.3.2 Codex serial fallback | `codex-code-review`   | `skipped`  | 「並列実行 disabled / 直前 timeout」（残 wave 分） |
| ステップ 5.4 NG 試行最大到達         | `team-evaluator`      | `rejected` | 「max_retries 到達」                               |
| ステップ 6.5 push skip               | `team-publisher`      | `skipped`  | 「dev container のため」                           |
| ステップ 6.7 起動時                  | `team-retrospector`   | `invoked`  | 「軽量レトロスペクティブ（mode=light）」           |
| ステップ 7 Ready 化 skip             | `team-publisher`      | `skipped`  | 「dev container のため」                           |

> **TDD 関連の追加 runlog イベント**（`agent_decision` とは別の event 種別）: `test_first_red_committed` / `test_first_skipped`（5.1.5）、`refactor_committed` / `refactor_noop` / `refactor_failed`（5.2.5）。`refactor_failed` は fail closed で 5.4 NG 経路に連携する（20260526 ADR 事項7）。いずれも `<plugin_root>/scripts/runlog-append.sh` 経由で追記する。

> **knowledge 関連の追加 runlog イベント**（`agent_decision` とは別の event 種別、ステップ 6.7 / `/iterate-retrospect`）: `retrospective_started` / `retrospective_completed` / `retrospective_failed` / `lesson_recorded` / `lesson_applied` / `plugin_proposal_recorded` の 6 種。`retrospective_failed` はステップ 6.7 の fail-open 時に記録され、`agent_decision` の追加発行は伴わない（ステップ 9 のエスカレーションにも遷移しない、ハーネス唯一の fail-open ステップ）。detail フィールドの構成例（`lesson_id` キーを正とする）は [`knowledge-policy.md` §10](./knowledge-policy.md#10-runlog-イベント) を正本として参照する。いずれのイベントも `<plugin_root>/scripts/runlog-append.sh` 経由で追記する。

> **adapter 関連の追加 runlog イベント**（`agent_decision` とは別の event 種別、`.agent-os/` プロジェクト適応レイヤ）: 8 種のうち **Phase 1**（`/iterate-adapt` + 5 agent 注入配線で使用）は `adapter_observed`（`team-profiler` の初回観測完了時、自己記録） / `adapter_updated`（`team-profiler`/`team-adapter` による再観測・更新時、`/iterate-adapt` の Orchestrator がコミット成功時に記録） / `adapter_applied`（5 injected agent の自己記録、または Bash を持たない agent の戻り値を Orchestrator が代理記録）の 3 種。**Phase 2**（`team-adapter` によるフィードバック捕捉・learned-rules 昇格ループ、`/iterate-review` ステップ 6.8 で配線済み）は `feedback_recorded` / `rule_candidate_recorded` / `rule_promoted` / `rule_deprecated` / `adapter_conflict` の 5 種（いずれも `team-adapter` の自己記録、`agent-decision-schema.md` §1 の Bash 経由記録と同型）。detail フィールドの構成例は [`adapter-policy.md` §8](./adapter-policy.md#8-runlog-イベント) を正本として参照する。いずれのイベントも `<plugin_root>/scripts/runlog-append.sh` 経由で追記する。
>
> **capture マーカーイベント `feedback_staged`**（`agent_decision` とも adapter-policy.md §8 の上記 8 種とも異なる、Phase 2 で追加する capture 専用イベント）: `.iterate-team/state/<session-id>/pending-feedback/` への捕捉ステージング時（interviewer step 2.5 / 計画承認 step 4 / review）に **Orchestrator** が記録する軽量マーカーで、detail は `{"source":"<interviewer|plan-approval|review>","seq":<n>}` のみを持つ（**逐語テキストは含めない**。逐語テキストは学習ステップ（ステップ 6.8）で `team-adapter` が `.agent-os/review-feedback-log.md` へ記録して初めて永続化される）。手順の正本は [`harness-common.md#フィードバック捕捉ステージングcapture全コマンド共通`](./harness-common.md#フィードバック捕捉ステージングcapture全コマンド共通) を参照。

---

## 3. 関連ドキュメント

- 追記スクリプト仕様: `<plugin_root>/scripts/runlog-agent-decision.sh`（task-1_2_1 で実装）
- 基盤スクリプト: `<plugin_root>/scripts/runlog-append.sh`
