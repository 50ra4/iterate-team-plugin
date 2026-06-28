# Planner: 委譲 (delegation) request 仕様

本ファイルは `planner` / `team-planner` が起動直後に `Read` する。**この内容は agent .md 側に絶対に inline でコピーしない**。

## 委譲の運用ルール

委譲は **戻り値テキスト末尾に JSON フェンスで request を埋め込んで終了する**。1 起動につき最大 1 件のみ。複数必要なら逐次再起動で処理する。並列上限: 同時 1 / Planner 1 回あたり累計 5 件（超過時は強制終了されエスカレートされる）。

## 委譲の判断基準

| 状況                                                             | 委譲先      |
| ---------------------------------------------------------------- | ----------- |
| コードベースの事実・外部情報が不足している                       | researcher  |
| バグ修正・障害調査・スタックトレース解析が必要                   | debugger    |
| 原因不明な振る舞い・因果関係の解明が必要                         | tracer      |
| `requirements-summary.md` の未確定論点（要件レベル）の解消が必要 | interviewer |

## Research request（researcher 呼び出し）

```json
{
  "request_id": "<yyyyMMddHHmmss>_planner_<task-id|init>",
  "from": "planner",
  "type": "research",
  "topic": "<調査題目>",
  "context": "<なぜ必要か / 現在地>",
  "created_at": "<ISO8601>"
}
```

## Debug request（debugger 呼び出し）

バグ修正・障害調査の計画では以下を plan.md に含めること:

- **再現手順の明記**（step-by-step で再現できる状態）
- **症状と根本原因の分離**（観測された症状と推定原因を区別して記載）
- **最小修正の原則**（修正スコープをバグに対して最小限に絞る）
- **仮説の競合検討**（少なくとも 2 つの根本原因仮説を列挙し採否根拠を示す）

```json
{
  "request_id": "<yyyyMMddHHmmss>_planner_<task-id|init>",
  "from": "planner",
  "type": "debug",
  "symptoms": "<観測された症状・エラーメッセージ>",
  "reproduction_steps": "<再現手順>",
  "context": "<影響コードファイル・関連背景>",
  "created_at": "<ISO8601>"
}
```

## Trace request（tracer 呼び出し）

原因不明な振る舞いや予期しない結果について因果分析が必要な場合に使用する。

```json
{
  "request_id": "<yyyyMMddHHmmss>_planner_<task-id|init>",
  "from": "planner",
  "type": "trace",
  "topic": "<説明が必要な観測された動作・成果物・結果>",
  "context": "<観測内容・関連ログ・前提条件>",
  "created_at": "<ISO8601>"
}
```

## Interview request（interviewer 呼び出し）

`requirements-summary.md` の未確定論点（要件レベルの曖昧さ）を Interviewer 経由でユーザに壁打ちし直して解消したい場合に使用する。`open_questions` 配列の各要素は **計画レベルで確定済みの構造 `{ "question": string, "why": string }`** とし、文字列単独形式は採用しない（`why` を Interviewer に渡せず質問品質が下がるため）。詳細は計画書の「open_questions 要素構造」節を参照。

```json
{
  "request_id": "<yyyyMMddHHmmss>_planner_<task-id|init>",
  "from": "planner",
  "type": "interview",
  "topic": "<壁打ち題目 / 解消したい要件論点の総括>",
  "context": "<requirements-summary.md の該当箇所・なぜ計画段階で解消が必要か>",
  "open_questions": [
    {
      "question": "<論点の概要 / 1 文>",
      "why": "<なぜ未確定か / Planner が解消したい理由>"
    }
  ],
  "created_at": "<ISO8601>"
}
```

## 応答ファイル

- Orchestrator がこの JSON を parse して対応 subagent を呼び、応答を `.iterate-team/state/<session-id>/responses/<request-id>.md` に書く
- あなたは再起動時に当該パスを引数で受け取り、最初に `Read` で読んでから本処理を再開する
- ただし `type=interview` のみ例外で、Interviewer 完了後は `<summary_path>` 自体が上書き更新されるため、別途 `responses/<request-id>.md` は渡されない（再起動形式 5 を参照）
