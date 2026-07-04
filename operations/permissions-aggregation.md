# ADR: `.claude/settings.json` permissions.allow 集約

## ステータス

採用 (2026-05-13、2026-05-19 改訂: git 系ワイルドカード狭め込み、2026-06-01 改訂: git 系追加統合 + show-toplevel 追加 + runlog-agent-decision.sh 削除、2026-07-04 改訂: runlog-agent-decision.sh 再追加 + knowledge fail-open のスクリプト集約（knowledge-recover.sh 追加、git restore/mv 個別許可・knowledge Edit 削除）+ git switch 引用符スコープ化・branch -D 追加 + `/iterate-retrospect` 用ラッパースクリプト 2 本（retrospect-list-sessions.sh / runlog-tail.sh）追加、52 エントリ)

## コンテキスト

`.iterate-team/tasks/20260513_audit-unused-and-perf/audit-report.md` Q3 ④ で `.claude/settings.json` の `permissions.allow` に冗長な個別列挙 (38〜39 エントリ) が存在することが指摘された。冗長要因は次の 3 種:

1. `./scripts/...` と `scripts/...` の二重登録 (9 対 18 エントリ)
2. `mcp__chrome-devtools__*` 配下ツールの個別列挙が `<plugin_root>/agents/team-evaluator.md` / `team-evaluator.md` の `tools:` 宣言と不一致 (旧設定は `list_pages` / `handle_dialog` を許可しつつ `close_page` / `resize_page` を許可していなかった)
3. `Bash(git worktree list)` と `Bash(git worktree list *)` の冗長

エントリ数が多いほど Claude Code 起動時の permissions マッチング処理と人間レビューのコストが増大する。一方で chrome-devtools 配下を `mcp__chrome-devtools__*` ワイルドカードに集約する案は、後続 PR レビュー (#59) で **権限拡大に該当する** と指摘された。chrome-devtools-mcp 0.23.0 の tool reference には `upload_file` (任意のローカル `filePath` をページへアップロード) / `install_extension` / trace・network response のファイル書き出し系など、旧 allow に含まれていなかったツールが追加されている。`permissions.deny` 側の `Read(~/.ssh/**)` などは MCP ツール内のローカルファイル参照に効かないため、ワイルドカード集約は採用しない。

## 決定

`permissions.allow` を **52 エントリ** へ集約する (旧 39 エントリ → 1 次集約 29 → 2 次狭め込み 36 → 3 次 `--grep` プレフィックス限定 40 → 4 次 `--verify` 引用符付き 41 → 5 次 `switch -c` / `branch -m` 引用符付き 43 → 6 次 `iterate-validate-session` 追加 44 → 7 次 git 追加統合 41 → 8 次 `runlog-agent-decision.sh` 削除 40 → 9 次 (2026-07-04) `runlog-agent-decision.sh` 再追加 + knowledge 機構スクリプト 4 本追加 + `branch -D` 2 種追加 50 → 10 次 (2026-07-04 内訳確定) `/iterate-retrospect` 用ラッパースクリプト 2 本（`retrospect-list-sessions.sh` / `runlog-tail.sh`）追加 + `switch *` を引用符始まりの `switch "*` へ絞り込み `switch -c claude/*` 系 2 種を復元（三分割）+ `find .iterate-team/state *` / `tail -n *` を撤去 52)。chrome-devtools 配下は agents の `tools:` 宣言と一致する 12 ツールを明示列挙する。git 系は **2026-05-19 のセキュリティレビュー** および **2026-06-01 の task-3_1_1 追加統合** を受け、ワイルドカードをサブセット統合する (`git rev-parse --verify HEAD` / `origin/main` / `claude/*` / `"claude/*` → `--verify *` / `--verify "*` の 2 種に統合、`git log -1 --format=%H` / `%s` / `%B` → `--format=*` の 1 種に統合、`git rev-parse --show-toplevel` を新規追加)。集約後の構造は意味カテゴリで並べる:

```jsonc
"allow": [
  // (1) MCP ツール: chrome-devtools は agents 宣言と一致する 12 ツールを明示列挙、codex は 2 ツール精密指定
  "mcp__chrome-devtools__navigate_page",
  "mcp__chrome-devtools__take_snapshot",
  "mcp__chrome-devtools__take_screenshot",
  "mcp__chrome-devtools__click",
  "mcp__chrome-devtools__fill",
  "mcp__chrome-devtools__list_console_messages",
  "mcp__chrome-devtools__list_network_requests",
  "mcp__chrome-devtools__wait_for",
  "mcp__chrome-devtools__new_page",
  "mcp__chrome-devtools__close_page",
  "mcp__chrome-devtools__resize_page",
  "mcp__chrome-devtools__evaluate_script",
  "mcp__codex__codex",

  // (2) ハーネス補助スクリプト (Bash ラッパー): 16 スクリプト (2026-07-04 改訂: runlog-agent-decision.sh 再追加 +
  // iterate-validate-session.sh 追加 + knowledge 機構 4 本 (append/digest/prune/recover) 追加 +
  // /iterate-retrospect 用ラッパー 2 本 (retrospect-list-sessions.sh / runlog-tail.sh) 追加)
  "Bash(<plugin_root>/scripts/runlog-append.sh *)",
  "Bash(<plugin_root>/scripts/runlog-agent-decision.sh *)",
  "Bash(<plugin_root>/scripts/iterate-validate-session.sh *)",
  "Bash(<plugin_root>/scripts/validate-plan.sh *)",
  "Bash(<plugin_root>/scripts/team-compute-waves.sh *)",
  "Bash(<plugin_root>/scripts/team-validate-plan.sh *)",
  "Bash(<plugin_root>/scripts/team-worktree-setup.sh *)",
  "Bash(<plugin_root>/scripts/team-worktree-merge.sh *)",
  "Bash(<plugin_root>/scripts/team-worktree-cleanup.sh *)",
  "Bash(<plugin_root>/scripts/team-push-branch.sh *)",
  "Bash(<plugin_root>/scripts/knowledge-append.sh *)",
  "Bash(<plugin_root>/scripts/knowledge-digest.sh *)",
  "Bash(<plugin_root>/scripts/knowledge-prune.sh *)",
  "Bash(<plugin_root>/scripts/knowledge-recover.sh *)",
  "Bash(<plugin_root>/scripts/retrospect-list-sessions.sh *)",
  "Bash(<plugin_root>/scripts/runlog-tail.sh *)",

  // (3) git read-only / ブランチ操作系: 19 種 (2026-07-04 改訂: switch を引用符スコープの 3 パターンへ
  // 分割 (switch -c claude/* 系 2 種を復元 + 素の switch は switch "* の引用符始まりのみ許可)、
  // branch -D claude/knowledge-retrospect-* 2 種を追加。旧 find .iterate-team/state * / tail -n *
  // は (2) のラッパースクリプト 2 本へ置換したため本枠から撤去)
  "Bash(git worktree list*)",
  "Bash(git symbolic-ref --short HEAD)",
  "Bash(git remote get-url origin)",
  "Bash(git rev-parse HEAD)",
  "Bash(git rev-parse --show-toplevel)",
  "Bash(git rev-parse --verify *)",
  "Bash(git rev-parse --verify \"*)",
  "Bash(git fetch origin main)",
  "Bash(git status --porcelain*)",
  "Bash(git switch -c claude/*)",
  "Bash(git switch -c \"claude/*)",
  "Bash(git switch \"*)",
  "Bash(git branch -m claude/*)",
  "Bash(git branch -m \"claude/*)",
  "Bash(git branch -D claude/knowledge-retrospect-*)",
  "Bash(git branch -D \"claude/knowledge-retrospect-*)",
  "Bash(git log -1 --format=*)",
  "Bash(git log --grep=Refs:*)",
  "Bash(git log --grep=\"Refs:*)",

  // (4) ハーネス状態の書き込み (.iterate-team/state/<session-id>/ 配下): 3 種
  // (2026-07-04 改訂: preflight / retro セッションディレクトリ作成用の mkdir -p を追加)
  "Write(.iterate-team/state/*/**)",
  "Edit(.iterate-team/state/*/**)",
  "Bash(mkdir -p .iterate-team/state/*)",

  // (5) knowledge (クロスセッション自己学習、git-tracked) の書き込み: 1 種
  // (2026-07-04 改訂: Write のみ。Edit は knowledge-policy.md の直接編集禁止ポリシーと
  // team-retrospector の tools 構成に合わせ付与しない)
  "Write(.iterate-team/knowledge/**)"
]
```

### 個別の決定根拠

- **chrome-devtools は agents `tools:` 宣言と一致する 12 ツールを明示列挙**:
  - `<plugin_root>/agents/team-evaluator.md` / `<plugin_root>/agents/team-evaluator.md` の `tools:` 宣言で許可されているのは 12 ツール (`navigate_page` / `take_snapshot` / `take_screenshot` / `click` / `fill` / `list_console_messages` / `list_network_requests` / `wait_for` / `new_page` / `close_page` / `resize_page` / `evaluate_script`)。旧 `permissions.allow` はこの集合と不一致 (`list_pages` / `handle_dialog` を許可しつつ `close_page` / `resize_page` を未許可) だったため、Orchestrator が agent 経由で `close_page` を呼ぶたびに permission ask が発生していた可能性がある。今回の改訂で agents 宣言と完全一致させる。
  - ワイルドカード `mcp__chrome-devtools__*` への集約は採用しない (PR #59 Codex Review P1 指摘)。chrome-devtools-mcp の今後のバージョンアップで `upload_file` (任意ローカルファイルをページへアップロード) / `install_extension` / trace・network response の書き出し系などが追加された場合に、レビューなしで自動許可されるリスクを避けるため。`permissions.deny` の `Read(~/.ssh/**)` などは MCP ツール内のローカル参照には効かず、deny 側で防御線を張れない領域である。

- **codex は精密指定を維持**:
  - codex MCP は `codex` (新規スレッド) のみ利用する。ワイルドカード `mcp__codex__*` でも実質同義だが、明示性 (read-only sandbox 設計の意図を allowlist から読み取れる) を優先して個別列挙を維持。

- **`./scripts/...` 形式は削除**:
  - Orchestrator / agents が現行コマンドファイルで使う呼び出しは `scripts/...` (相対) 形式のみ。`./` プレフィックス形式は冗長で、削除しても既存呼び出しは影響を受けない。

- **`Bash(scripts/*.sh *)` のような全スクリプトワイルドカードは採用しない**:
  - 採用すれば 8 → 1 エントリに圧縮できるが、`scripts/` 配下に将来追加される未レビューのスクリプトを暗黙に許可してしまう。team-publisher の push ラッパー (`<plugin_root>/scripts/team-push-branch.sh`) のような **allowlist 検証で安全性を担保している経路** に対し、新規スクリプトの自動許可は設計意図 (構造的拒否) を弱める。8 エントリ維持はメンテナンスコストよりセキュリティの精密性を優先した判断。

- **`Bash(<plugin_root>/scripts/runlog-agent-decision.sh *)` の削除 (2026-06-01 改訂)**:
  - `<plugin_root>/scripts/runlog-agent-decision.sh` は `<plugin_root>/scripts/runlog-append.sh` を `event=agent_decision` で呼び出す薄いラッパーだが、`<plugin_root>/commands/` / `<plugin_root>/agents/` / `<plugin_root>/operations/` 配下のどのファイルからも直接呼び出されていないことを grep で確認した。allowlist にある権限が実際に使用されないのであれば削除してエントリ数を削減する。将来 agent_decision ログが必要になった場合は `runlog-append.sh` を直接呼ぶか、その時点で allowlist に再追加する。

- **`Bash(git worktree list*)` への統合**:
  - `Bash(git worktree list)` と `Bash(git worktree list *)` を `Bash(git worktree list*)` (末尾ワイルドカード) に統合。後者は前者を完全に包含する。`git worktree list --porcelain` 等のサブオプション付き呼び出しも一括許可される。

- **git 系ワイルドカードの狭め込み (2026-05-19 改訂)**:
  - セキュリティレビューで `git rev-parse --verify *` / `git fetch origin *` / `git log -1 --format=*` / `git log --format=*` のワイルドカードが「任意 ref 解決による情報探索」「リモート任意 ref 取得」「履歴・コミット本文の大量抽出」を許す広さと指摘された。実コード使用箇所 (`<plugin_root>/commands/iterate-team.md` / `team-publisher` agent) を grep 確認し、必要な引数のみを残す形に細分化する:
    - `git rev-parse --verify *` → `HEAD` (一般 HEAD 検証) / `origin/main` (`/iterate-team` の bootstrap) / `claude/*` (rename 衝突検査) の 3 エントリへ分割。さらに、`/iterate-team` 手順 3.x が `git rev-parse --verify "<target-branch>"` (引用符付き) で衝突検査する実装に合わせ、`Bash(git rev-parse --verify "claude/*)` を併記する (Claude Code Bash permission はコマンド文字列に対してマッチングするため、引用符の有無で別パターン扱いになる)。
    - `git fetch origin *` → `git fetch origin main` のみ。bootstrap の既定派生元は `main`。**ただし `--from-branch <branch>` 追加（2026-06-03）以降、`main` 以外を指定する経路が存在する**。この場合 host では `git fetch origin <branch>` が allowlist 未一致となり permission prompt が 1 回出る（意図的な opt-in 操作のため許容。allowlist を `git fetch origin *` へ広げると任意 ref の取得を許す広さに戻るため、既定 `main` のみ静的許可とし、非既定はプロンプト承認に委ねる設計）。dev container は `settings.sandbox.json` の `Bash(git fetch *)` + `bypassPermissions` で無プロンプト。
    - `git log -1 --format=*` → `%H` / `%s` / `%B` の 3 エントリへ列挙。コミットハッシュ / subject / body の 3 種で実用上十分であり、`%ae` / `%an` 等のメール・氏名抽出経路を排除する。
    - `git log --format=*` → **削除**。単独形式の使用は実コードに無く、`git log --grep="Refs: ..." --format="..."` は後述の `--grep=Refs:*` / `--grep="Refs:*` パターン側で吸収される (Claude Code の Bash パターンは先頭一致でコマンドライン全体を `*` が貪欲マッチする)。
    - `git log --grep=*` → `git log --grep=Refs:*` (引用符なし) / `git log --grep="Refs:*` (引用符あり) の 2 エントリへ限定。実コード使用 (`<plugin_root>/commands/iterate-team.md` L150 / `<plugin_root>/README.md` L65) は全て `--grep="Refs: task-"` / `--grep="Refs: plan-"` 形式であり、`Refs:` プレフィックスの絞り込みで完全カバーできる。`git log --grep= --all --format=%B` のように `--grep` の引数を空にして任意オプションを連結する経路 (PR #94 P1 指摘) は、プレフィックス強制で構造的に閉じる。

- **git 系追加統合 (2026-06-01 改訂: task-3_1_1)**:
  - task-3_1_1 の security advisor レビューを受け、`--verify` 系エントリの逆方向統合（サブセット→ワイルドカード）と `log -1 --format` の統合、`--show-toplevel` 追加を実施:
    - `Bash(git rev-parse --verify HEAD)` / `Bash(git rev-parse --verify origin/main)` / `Bash(git rev-parse --verify claude/*)` / `Bash(git rev-parse --verify "claude/*)` (4 件) → `Bash(git rev-parse --verify *)` + `Bash(git rev-parse --verify "*)` (2 件) に統合。`team-task/` ブランチの衝突検査 (`iterate-team.md` L91) も `--verify *` でカバーされ、引用符の有無 2 パターンを維持。
    - `Bash(git log -1 --format=%H)` / `Bash(git log -1 --format=%s)` / `Bash(git log -1 --format=%B)` (3 件) → `Bash(git log -1 --format=*)` (1 件) に統合。`git log -1 --format=` プレフィックスにより `-1` (最新 1 件) の単一コミット参照のみ許可されるため、履歴大量抽出経路は閉じたまま。
    - `Bash(git rev-parse --show-toplevel)` を新規追加。`team-generator` / `team-evaluator` が worktree 検証で使用しているが allowlist 未登録だった漏れを修正。

  - 一方、レビューが「外す推奨」とした以下は **設計意図と実使用を踏まえて維持**:
    - `Bash(<plugin_root>/scripts/team-push-branch.sh *)`: `Bash(git push *)` を `permissions.deny` で完全遮断した上で、ラッパー内部で `-f` / `--force` / `--force-with-lease` / `--mirror` / `--delete` / refspec / `refs/` / `main` / `master` / path traversal を allowlist 方式で構造的に拒否する設計の核。ラッパー経由のみを allow するからこそ destructive push を構造的に阻止できる。外すと `/iterate-team` の plan / wave merge / closer commit を remote に同期する経路が全て失われる。
    - `Bash(git branch -m claude/*)` / `Bash(git branch -m "claude/*)`: プレフィックス `claude/` 限定。`/iterate-team` の `claude/*-pending` → `claude/*` rename 経路 (`iterate-team.md` L92 `git branch -m "<integration-branch>" "<target-branch>"`) で必須。実コードは引用符付きで実行するため、引用符の有無 2 パターンを併記して `dontAsk` 経路を維持する (PR #94 再レビュー P1 で `--verify` 同様の構造的問題が判明したため予防的に併記)。人手作成ブランチ (通常 `feature/` / `fix/` 等) には影響しない。
    - `Bash(git switch -c claude/*)` / `Bash(git switch -c "claude/*)`: 同上。`/iterate-team` 手順 3.x が `git switch -c "<integration-branch>" origin/main` (`iterate-team.md` L42) と引用符付きで実行するため、`claude/` プレフィックス限定で引用符の有無 2 パターンを併記。人手ブランチを上書きしない設計は維持する。
    - `Bash(git log --grep=Refs:*)` / `Bash(git log --grep="Refs:*)`: `Refs: task-` / `Refs: plan-` 追跡が `<plugin_root>/commands/iterate-team.md` で前提化されており、`Refs:` プレフィックスへ限定することで Refs フッタ検索専用に絞り込む。`--grep=` をワイルドカード単独で許可していた旧パターンを廃止し、grep パターンを空にして履歴全件抽出する経路を構造的に塞ぐ (PR #94 P1)。
    - `Bash(git remote get-url origin)`: `team-publisher` の owner/repo 一致検証 (fork や別 repo への push 拒否) に必須。本リポジトリは公開 GitHub HTTPS で `git remote` にトークン埋め込みする運用が無いため、URL 漏洩リスクは限定的。

- **`Bash(<plugin_root>/scripts/runlog-agent-decision.sh *)` の再追加 (2026-07-04 改訂)**:
  - 2026-06-01 改訂は「どのファイルからも直接呼び出されていない」ことを根拠に削除した。本 PR のステップ 6.7.1 で `<plugin_root>/commands/iterate-team.md` / `<plugin_root>/commands/iterate-review.md` / `<plugin_root>/operations/iterate-team-runbook.md` が `runlog-agent-decision.sh` を直接呼び出すようになったため、削除の前提が失効した。allowlist に再追加する。

- **knowledge 機構スクリプト 4 本 (`knowledge-append.sh` / `knowledge-digest.sh` / `knowledge-prune.sh` / `knowledge-recover.sh`) の追加 (2026-07-04 改訂)**:
  - knowledge（クロスセッション自己学習、[`knowledge-policy.md`](./knowledge-policy.md) 参照）の記録・再生成・圧縮・fail-open 復旧を、手順書に記述された散文シェル手順（`git restore --staged --worktree` の個別許可 2 種 + `mv` による退避コマンドの個別許可 2 種など）からスクリプトへ集約した。個別 git サブコマンドを allowlist に列挙する方式は文言の変更ごとに allowlist 側の追従が必要で事故りやすく、スクリプト集約によって allowlist は「このスクリプトを実行してよいか」の1点に単純化される。

- **`Bash(git status --porcelain)` → `Bash(git status --porcelain*)` への拡張**:
  - `.iterate-team/knowledge/` 配下の差分確認のように pathspec 付き呼び出し (`git status --porcelain -- .iterate-team/knowledge/`) が必要になったため、末尾ワイルドカードへ拡張した。`--porcelain` は非破壊の read-only 診断コマンドであり、pathspec の追加はスコープを狭める方向にしか働かないため権限拡大には該当しない。

- **`Bash(mkdir -p .iterate-team/state/*)` / `Write(.iterate-team/knowledge/**)` の追加、`Edit(.iterate-team/knowledge/**)` を追加しない判断**:
  - `mkdir -p .iterate-team/state/*` は preflight / retro セッションディレクトリの作成に必須（`knowledge-recover.sh` 自体の呼び出しには不要だが、fail-open 手順が呼び出す前段で必要になる）。`Write(.iterate-team/knowledge/**)` は team-retrospector が `proposals/*.md` / `proposals/INDEX.md` を新規作成するために必須。一方 `Edit(.iterate-team/knowledge/**)` は付与しない: [`knowledge-policy.md`](./knowledge-policy.md) が `lessons.jsonl` / `lessons.md` への直接編集を禁止し（更新は `knowledge-append.sh` の append のみで表現し、`lessons.md` は `knowledge-digest.sh` が再生成する）、`team-retrospector` agent の `tools:` 宣言にも `Edit` は含まれない。どの主体も使わない権限は付与しない。

- **`Bash(git switch "*)` の追加（引用符始まり限定）+ `Bash(git switch -c claude/*)` / `Bash(git switch -c "claude/*)` の復元、`Bash(git branch -D claude/knowledge-retrospect-*)` 系の追加 (2026-07-04 改訂)**:
  - `/iterate-retrospect` が deep レトロ完了後に元ブランチへ戻る際、新規ブランチ作成を伴わない素の `Bash git switch "<original-branch>"` を使う。2026-06-01 時点の `switch -c claude/*` 限定パターンはこの呼び出しに一致せず、都度 permission ask が発生していた。当初は `Bash(git switch *)`（ワイルドカード 1 種）へ統合する案を検討したが、これは `git switch -f` / `git switch -C <branch>` / `git switch --discard-changes` のような**未コミット変更を破棄しうるフラグ形**（引用符なしで始まる任意引数）も無条件許可してしまい、2026-05-19 改訂の「ワイルドカードの広さを実使用パターンへ狭める」方針（本書該当節）と逆行する。このため `switch *` は採用せず、`Bash(git switch "*)`（**引用符で始まる引数のみ**を許可）へ絞り込む。`git switch "<original-branch>"` のように呼び出し元が二重引用符で始める限りこのパターンに一致し、`-f` 等の非引用フラグ形は構造的に allowlist から除外される（コマンド側 `iterate-retrospect.md` も二重引用符付きの `git switch "<original-branch>"` を規定しており、両者が対になって安全性を担保する）。`switch -c claude/*` / `switch -c "claude/*` の 2 種はブランチ新規作成用として独立に必要なため、`switch *` への統合前の形へ復元する。
  - `Bash(git branch -D claude/knowledge-retrospect-*)` / `Bash(git branch -D "claude/knowledge-retrospect-*)` は `/iterate-retrospect` の fail-open（deep レトロでコミットが 1 件も無い場合）で使う retro ブランチ削除用。対象を `claude/knowledge-retrospect-*` に限定し、他の `claude/*` ブランチの削除は依然 ask に委ねる。

- **`Bash(find .iterate-team/state *)` / `Bash(tail -n *)` を撤去し、`Bash(<plugin_root>/scripts/retrospect-list-sessions.sh *)` / `Bash(<plugin_root>/scripts/runlog-tail.sh *)` へ置換 (2026-07-04 改訂)**:
  - `find` は `-exec` / `-delete` オプションにより任意コマンド実行・任意ファイル削除が可能な昇格プリミティブであり、`Bash(find .iterate-team/state *)` のように起点パスを固定してもオプション部分はワイルドカードで素通しになるため、`find .iterate-team/state -exec rm -rf / \;` のような呼び出しを字面上排除できない。`tail -n *` も同様に、`-n` 以降の引数（対象パス）を検証しないため `tail -n 1 ~/.ssh/id_rsa` のように任意パスを読み取れ、Bash 経由で `permissions.deny` の `Read(~/.ssh/**)` / `Read(~/.aws/**)` を迂回する。いずれも生コマンドの allow は採用しない。
  - 代替として `<plugin_root>/scripts/retrospect-list-sessions.sh <N>`（`.iterate-team/state/` 配下のセッション列挙専用。`retro_*` を除外し mtime 降順で最大 N 件のセッション id のみを出力）と `<plugin_root>/scripts/runlog-tail.sh <session-id> [<lines>]`（session-id のパス安全性を検証した上で当該セッションの runlog.jsonl 末尾のみを bounded read）の 2 本のラッパースクリプトへ置換する。引数検証つきラッパースクリプトを allowlist に個別列挙する方式は、`team-push-branch.sh`（push の force/refspec 等を内部で拒否）や `knowledge-recover.sh`（fail-open 復旧手順を集約）と同様、本 ADR がすでに採用している確立パターンである（前掲「knowledge 機構スクリプト 4 本の追加」節）。生コマンドの allow を維持したまま用途を狭めるより、検証ロジックをスクリプト側に閉じ込め allowlist は「このスクリプトを実行してよいか」の1点に単純化する方が安全である。
  - 両スクリプトは `<plugin_root>/scripts/` 配下に置かれるため group (2)（ハーネス補助スクリプト）へ追加し、削除した `find` / `tail` の元の枠であった group (3) からは撤去する。

### 棄却した代替案

| 案                                                    | 棄却理由                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| ----------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `mcp__chrome-devtools__*` で chrome-devtools 一括許可 | PR #59 Codex Review P1 指摘。chrome-devtools-mcp 0.23.0 以降に `upload_file` / `install_extension` / trace・network response の書き出し系など、旧 allow に無かったツールが含まれる。プロンプトインジェクションや誘導された検証対象ページからレビュー無しでローカルファイルを外部送信される経路を許してしまう。`permissions.deny` の `Read(~/.ssh/**)` 等は MCP ツール内のローカル参照には効かないため、ワイルドカード許可は実質的な権限拡大に該当する |
| `Bash(scripts/*.sh *)` で全スクリプト一括許可         | 新規スクリプト自動許可による設計意図の弱体化 (上記参照)                                                                                                                                                                                                                                                                                                                                                                                               |
| `mcp__*` で全 MCP ワイルドカード許可                  | 必要な MCP ツール（chrome-devtools / codex）は agent 単位で明示宣言する設計のため、Orchestrator/その他 agent への暗黙許可は避ける                                                                                                                                                                                                                                                                                                                     |
| `./` 形式を残す                                       | 現行呼び出しが `scripts/...` のみのため、`./` 形式の保持は無効エントリの放置に等しい                                                                                                                                                                                                                                                                                                                                                                  |
| `Bash(git *)` で git 一括許可                         | `git push -f` 等の deny ルールを `deny` で個別維持しているが、`allow` 側で広域許可すると評価順序の事故 (deny が先に評価されるか allow が先かはツール側仕様依存) を生む可能性がある。最小権限を維持                                                                                                                                                                                                                                                    |

## 結果

### 初回集約 (2026-05-13) + git 系狭め込み (2026-05-19)

| 指標                               | Before                       | After                  |
| ---------------------------------- | ---------------------------- | ---------------------- |
| allow エントリ数                   | 39                           | 43                     |
| MCP chrome-devtools 個別列挙       | 12 (旧: agents 宣言と不一致) | 12 (agents 宣言と一致) |
| `scripts/...` `./scripts/...` 二重 | 18                           | 9                      |
| git worktree list 重複             | 2                            | 1                      |

### 追加統合 (2026-06-01: task-3_1_1)

| 指標                                                                  | Before (44 件) | After (40 件) | 変化 |
| --------------------------------------------------------------------- | -------------- | ------------- | ---- |
| allow エントリ数                                                      | 44             | 40            | -4   |
| `git rev-parse --verify` 個別エントリ                                 | 4              | 2             | -2   |
| `git log -1 --format=` 個別エントリ                                   | 3              | 1             | -2   |
| `git rev-parse --show-toplevel` (未登録)                              | 0              | 1             | +1   |
| `<plugin_root>/scripts/runlog-agent-decision.sh` (未使用エントリ削除) | 1              | 0             | -1   |

### knowledge fail-open スクリプト集約 + git switch 引用符スコープ化 + find/tail のラッパースクリプト化 (2026-07-04)

| 指標                                                                                     | Before (40 件) | After (52 件) | 変化 |
| ---------------------------------------------------------------------------------------- | -------------- | ------------- | ---- |
| allow エントリ数                                                                          | 40             | 52            | +12  |
| `<plugin_root>/scripts/runlog-agent-decision.sh` (再追加)                                | 0              | 1             | +1   |
| knowledge 機構スクリプト (`append`/`digest`/`prune`/`recover`)                            | 0              | 4             | +4   |
| `/iterate-retrospect` 用ラッパー (`retrospect-list-sessions.sh`/`runlog-tail.sh`) (新規)  | 0              | 2             | +2   |
| `Bash(mkdir -p .iterate-team/state/*)`                                                   | 0              | 1             | +1   |
| `Write(.iterate-team/knowledge/**)`                                                      | 0              | 1             | +1   |
| `git switch` 系 (`switch -c claude/*` 2 種 + `switch "*` 1 種)                            | 2              | 3             | +1   |
| `git branch -D claude/knowledge-retrospect-*` 系 (新規)                                  | 0              | 2             | +2   |
| `Bash(find .iterate-team/state *)` (検討したが不採用。`-exec`/`-delete` の昇格リスクのため) | 0              | 0             | 0    |
| `Bash(tail -n *)` (検討したが不採用。任意パス読み取りで `Read` deny を迂回するため)         | 0              | 0             | 0    |
| `git status --porcelain` → `git status --porcelain*`（エントリ数不変）                    | 1              | 1             | 0    |
| `Edit(.iterate-team/knowledge/**)`（付与しない判断。40 件時点で未登録）                    | 0              | 0             | 0    |

## リスク評価

- **広すぎる権限の付与**: 今回の改訂では chrome-devtools 配下を agents `tools:` 宣言と一致する 12 ツールの明示列挙に保つため、新たな権限拡大は発生しない。旧 allow との差分は `list_pages` / `handle_dialog` を削除、`close_page` / `resize_page` を追加。`close_page` / `resize_page` は agents 側で既に許可されていた browser sandbox 内操作のため、許可漏れの整合を取った形であり権限拡大には該当しない。
- **2026-06-01 追加統合のリスク**: `Bash(git rev-parse --verify *)` への統合により、`HEAD` / `origin/main` / `claude/*` 以外の任意 ref 検証が可能になる。ただし `--verify` は ref が実在するかの検証のみ（破壊的操作なし）であり、リードオンリー操作の範囲内。`git rev-parse --show-toplevel` は worktree ルート取得のみで情報漏洩リスクは限定的。`Bash(git log -1 --format=*)` への統合では `%ae` 等のメールアドレス抽出も理論上可能になるが、`-1` 制約で最新 1 件のみに限定される。
- **2026-07-04 追加統合のリスク**: `git switch` は素のワイルドカード `Bash(git switch *)` への統合を検討したが不採用とした。`switch -f` / `switch -C <branch>` / `switch --discard-changes` のような未コミット変更を破棄しうるフラグ形を非引用のまま無条件許可してしまい、2026-05-19 改訂の「ワイルドカードの広さを実使用パターンへ狭める」方針（本書上記節）に反するためである。代わりに `Bash(git switch "*)`（引用符で始まる引数のみ許可）へ絞り込み、コマンド側（`iterate-retrospect.md`）が規定する二重引用符付き呼び出し `git switch "<original-branch>"` のみを構造的に通す。`switch -c claude/*` 系 2 種は `claude/` 接頭辞限定のブランチ新規作成用として維持し、ブランチ切替自体は内容の破壊を伴わない（dirty worktree への切替は git 自身が拒否し、`-c` の新規作成も reflog で復元可能）。`Bash(git branch -D claude/knowledge-retrospect-*)` は削除対象を deep レトロ専用ブランチ名に限定しており、人手ブランチや `claude/*-pending` 等の他用途ブランチは対象外。`find` / `tail` の生コマンド allow（`Bash(find .iterate-team/state *)` / `Bash(tail -n *)`）は検討したが不採用とした: `find` は `-exec` / `-delete` により任意コマンド実行・削除が可能な昇格プリミティブであり、`tail -n *` は対象パスを検証しないため Bash 経由で `permissions.deny` の `Read(~/.ssh/**)` 等を迂回できる。代わりに引数検証つきラッパースクリプト `<plugin_root>/scripts/retrospect-list-sessions.sh` / `<plugin_root>/scripts/runlog-tail.sh` を group (2) に追加した。これは `team-push-branch.sh` 以来、本 ADR が採用している「検証ロジックをスクリプト側に閉じ込め、allowlist は実行可否の1点に単純化する」確立パターンの適用である。`Edit(.iterate-team/knowledge/**)` を付与しない判断により、knowledge-policy.md の直接編集禁止ポリシーが allowlist レベルでも構造的に裏付けられる。
- **deny / ask との整合**: push 経路は team-publisher 経由の `<plugin_root>/scripts/team-push-branch.sh` ラッパー（`claude/` 接頭辞限定 + force/refspec/特殊 ref を allowlist 拒否）のみが無プロンプト allow されている設計を継続。直接 `git push` は主要な破壊的形態（force / `--force-with-lease` / `--mirror` / `--delete` / `+refspec` 等）を `permissions.deny` で遮断し、残りは `permissions.ask` の `Bash(git push *)` で人間確認に回す。短縮結合フラグ（`git push -uf` 等）は glob 列挙では branch 名衝突なしに塞げないため deny ではなく ask に委ねる（Claude Code on web は terminal が無く直接 push の唯一の対話手段が ask のため、全面 deny は採らない）。
- **後方互換**: 削除した `./scripts/...` 形式を実行する呼び出しは現行コードに存在しない (`<plugin_root>/commands/*.md` / `<plugin_root>/agents/*.md` を grep 確認済み)。

## 参照

- 起票 spec: `.iterate-team/tasks/20260513_harness-settings-refactor/spec.md`
- 監査根拠: `.iterate-team/tasks/20260513_audit-unused-and-perf/audit-report.md` Q3 ④
