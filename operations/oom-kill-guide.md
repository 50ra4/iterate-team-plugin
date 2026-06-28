# Claude Code OOM Kill 運用ガイド

## 背景

Linux の cgroup メモリ管理機構は、コンテナ（Dev Container を含む）のメモリ使用量が上限に達すると、カーネルの OOM Killer が介入してプロセスを強制終了（`SIGKILL`）する。この場合、プロセスは終了コードなしに即座に停止するため、通常のエラーログが残らない。

痕跡は cgroup の `memory.events` ファイルに記録される。`oom_kill` カウンタが増加していれば OOM Kill が発生したことを示す。Claude Code が突然 `Killed` で終了する場合、この OOM Kill が原因であることが多い。

---

## 目次

1. [背景](#背景)
2. [OOM Kill 診断手順](#2-oom-kill-診断手順)
3. [Killed 終了時の切り分け手順](#3-killed-終了時の切り分け手順)
4. [低並列運用手順](#4-低並列運用手順)
5. [重畳時の注意点](#5-重畳時の注意点)
6. [常駐プロセス確認/停止手順](#6-常駐プロセス確認停止手順)
7. [Dev Container メモリ増設判断基準](#7-dev-container-メモリ増設判断基準)

---

## 2. OOM Kill 診断手順

### Dev Container 内で実行するコマンド

**memory.events の oom_kill カウンタ確認**

```bash
# cgroup v2 の場合（Dev Container では通常こちら）
cat /sys/fs/cgroup/memory.events

# oom_kill の値が 0 より大きければ OOM Kill が発生済み
# 例: oom_kill 3
```

```bash
# カウンタの差分を確認する場合（作業前後で比較）
cat /sys/fs/cgroup/memory.events | grep oom_kill
```

**空きメモリおよび swap 残量の確認**

```bash
free -h
```

出力例:

```
               total        used        free      shared  buff/cache   available
Mem:           3.8Gi       3.5Gi        50Mi        10Mi       300Mi       200Mi
Swap:            0B          0B          0B
```

- `available` が極端に少ない（数十 MB 以下）場合、OOM Kill のリスクが高い
- `Swap` が `0B` の場合、メモリ枯渇時に即 OOM Kill となる

**RSS 上位プロセスの確認**

```bash
ps aux --sort=-%mem | head -20
```

`RSS` 列（実メモリ使用量 KB）が大きいプロセスを特定する。ビルド系プロセスが上位に複数並ぶ場合、プロジェクトのビルドやテストの並列実行が原因の可能性がある。

### ホスト側で実行するコマンド

**Dev Container のメモリ割当確認**

```bash
# コンテナの実際のメモリ使用量と上限を確認
docker stats --no-stream

# 出力例:
# CONTAINER ID   NAME        CPU %   MEM USAGE / LIMIT    MEM %
# abc123def456   my-devcont  45.2%   3.72GiB / 4GiB       93.0%
```

```bash
# コンテナに設定されているメモリ上限を確認
docker inspect <container-name-or-id> | grep -i memory
```

- `MEM %` が 90% を超えている場合、OOM Kill の直前状態と判断できる
- `LIMIT` が意図より低い場合、Docker Desktop の設定でメモリ上限を引き上げる必要がある

---

## 3. `Killed` 終了時の切り分け手順

Claude Code が `Killed` で終了した場合、以下の順で原因を切り分ける。

### ステップ 1: OOM Kill か否かを memory.events で判定（Dev Container 内）

`memory.events` の `oom_kill` は **コンテナ起動以降の累積カウンタ**であり、既存の履歴を含む。現在発生した `Killed` を判定するには、**作業前後の値を比較して増分があった場合のみ** OOM Kill と判断する必要がある（絶対値が 1 以上であっても、それが過去の事象であれば今回とは無関係）。

```bash
# 事前: 重い処理（/iterate-team / プロジェクトのビルドコマンド 等）を実行する前に値を記録
cat /sys/fs/cgroup/memory.events | grep oom_kill | tee /tmp/oom_kill.before
```

```bash
# 事後: Claude Code が `Killed` で終了した直後に値を確認し、事前値と比較
cat /sys/fs/cgroup/memory.events | grep oom_kill | tee /tmp/oom_kill.after
diff /tmp/oom_kill.before /tmp/oom_kill.after
```

- 事前値と比較して **`oom_kill` が増加した** → 今回の終了は OOM Kill。[章 2](#2-oom-kill-診断手順) の手順でメモリ状況を調査し、章 4〜7 の対処手順に進む
- 増分が **0**（事前値と事後値が一致）→ 今回の終了は OOM Kill ではない。次のステップへ進む
- 事前値の記録を忘れた場合 → `memory.events` 単独では今回事象の判定は不可能。ステップ 2（`dmesg` のタイムスタンプ）とステップ 3（終了コード）で切り分ける

### ステップ 2: カーネルログで SIGKILL の発行元を確認（ホスト側）

```bash
# OOM Killer のメッセージが残っている場合がある
dmesg | grep -i "oom\|killed\|out of memory" | tail -20
```

- `Out of memory: Killed process` のメッセージがあれば OOM Kill（`memory.events` に記録されない場合も稀にある）
- メッセージがない場合、OOM Kill 以外の要因を疑う

### ステップ 3: プロセス終了コードの確認

シェルから Claude Code を起動していた場合:

```bash
echo $?
```

| 終了コード | 意味                                             |
| ---------- | ------------------------------------------------ |
| `137`      | `SIGKILL` 受信（OOM Kill または外部からの kill） |
| `143`      | `SIGTERM` 受信（明示的な停止要求）               |
| `1`        | 通常のエラー終了（クラッシュ、例外など）         |

- 終了コード `137` で `dmesg` にも記録なし → Docker ホストや CI/CD が明示的に `kill -9` した可能性
- 終了コード `143` → 明示的な `SIGTERM`（Docker stop / OS シャットダウン等）

### ステップ 4: Claude Code 側ログの確認（Dev Container 内）

```bash
# Claude Code のログディレクトリを確認
ls ~/.claude/logs/ 2>/dev/null | tail -5

# 直近のログを確認
tail -100 ~/.claude/logs/$(ls -t ~/.claude/logs/ | head -1) 2>/dev/null
```

ログにクラッシュスタックトレースや `Error:` メッセージが残っている場合、OOM Kill ではなくアプリケーション側の問題（バグ・依存ライブラリのクラッシュ等）の可能性がある。

---

## 4. 低並列運用手順

OOM Kill が頻発する場合、`/iterate-team` の同時実行 Agent 数を減らす（並列度を下げる / 実質的に逐次へ寄せる）ことでメモリ消費を抑えられる。**ハーネスコード（`iterate-team.md` 等）への設定変更は行わない**。すべて運用側の判断で対処する。

### /iterate-team の並列度を下げる方法

`/iterate-team` はタスクを wave（波）に分割して並列実行する。並列度を下げるには以下の運用を選ぶ。

**同時起動 Agent 数の絞り込み**

Orchestrator が wave 内のタスクを一括起動する際、依存関係のない複数タスクが同一 wave に入る。Planner へのプロンプトで `max_parallel` 相当の意図を伝えるか、タスク数の多い wave を手動で分割依頼する。

**フェーズ分割実行**

wave ごとに Orchestrator を一時停止し、前の wave のメモリが解放されてから次の wave を起動する。Claude Code を再起動した後に次 wave のみを指定して再開するパターンが最も確実にメモリを解放できる。

**max_retries を下げる**

タスクファイルの `max_retries` を 1 に下げると、リトライによる並列 subagent の多重起動を抑制できる。失敗時はエスカレーションして人間が介入するトレードオフになる。

### 並列度を最小（実質逐次）にする判断基準

以下の条件に該当する場合は、wave 内の同時起動を 1 タスクずつに絞る（実質逐次）運用を選ぶ。

| 条件                                     | 理由                                         |
| ---------------------------------------- | -------------------------------------------- |
| Dev Container の空きメモリが 1 GiB 未満  | 並列 subagent 1 体あたり数百 MB 消費するため |
| タスク数が少ない（3 件以下）             | 並列化の効果より安定性を優先                 |
| OOM Kill が直近で発生した                | 環境が不安定な状態で並列化しない             |
| 依存チェーンが直線的でほぼ並列化できない | 並列化のメリットがない                       |

同時起動を 1 体に絞ると、合計所要時間は増えるが、メモリ消費のピークを大幅に下げられる。

---

## 5. 重畳時の注意点

Claude Code の subagent 実行中に別プロセスを起動すると、メモリ消費が重畳してOOM Kill のリスクが急増する。

### ビルド / テストとの並走

プロジェクトのビルドコマンドとテストコマンドは、並列実行時に複数のプロセスを起動する。

**合計メモリの目安（プロジェクト規模による概算）**

| プロセス                      | 消費メモリの目安 |
| ----------------------------- | ---------------- |
| Claude Code 本体 + 1 subagent | 1〜2 GiB         |
| ビルドコマンド（並列）        | 0.5〜1.5 GiB     |
| テストコマンド（ワーカー）    | 0.5〜1 GiB       |
| **合計（並走時）**            | **2〜4.5 GiB**   |

4 GiB 制限の Dev Container では並走すると OOM Kill ラインに達する可能性がある。

**推奨運用**: 重い検証コマンド（プロジェクトのビルド / テストコマンド）は Claude Code の実行が完全に終了した後に別ターミナルで実行する。どうしても並走させる場合は章 6（常駐プロセス停止）を先に実施してメモリに余裕を作る。

### Chrome DevTools MCP との重畳

Chrome DevTools MCP は Chromium のヘッドレスインスタンスを常駐させる。Chromium プロセスはページを開くだけで 200〜400 MB のメモリを消費し、複数タブや JavaScript を多用するページではさらに増加する。

- Claude Code 実行中は Chrome DevTools MCP セッションを最小化する（不要なタブを閉じる）
- MCP 経由のブラウザ操作タスクが終わったら Chromium プロセスを明示的に終了してからサブエージェントを起動する
- MCP の停止手順は章 6 を参照

### Codex MCP（OpenAI Codex app server）との重畳

Codex MCP は OpenAI Codex のローカル app server をバックグラウンドで常駐させる。Node.js または Python ベースのサーバープロセスが常時起動しており、リクエストがない状態でも数百 MB を消費する場合がある。

**重畳リスク**: Claude Code の subagent 群（iterate-team では複数同時）と Codex MCP が同一コンテナで動くと、メモリ消費が累積して章 2 で確認した OOM Kill ラインを超えやすくなる。

**推奨**: iterate-team を実行する際は Codex MCP を一時停止する。停止手順は章 6 を参照。

---

## 6. 常駐プロセス確認/停止手順

> **方針**: `.mcp.devcontainer.json` / `.mcp.host.json` の設定ファイルは変更しない。lazy 起動方針（必要になった時点で初めて起動）と矛盾させないため、**設定変更は禁止**とし、運用上の一時停止のみを行う。

### 6.1 VS Code extension host の確認と一時無効化

**プロセスの確認**

```bash
# Dev Container 内で実行
ps aux | grep -E "Code Helper \(Plugin\)|extension-host" | grep -v grep
```

`Code Helper (Plugin)` または `--type=extensionHost` を含む行がヒットすれば VS Code extension host が動作中。

**一時無効化の方法**

拡張機能をウィンドウ単位で無効化する（拡張機能のアンインストールではない）。

1. VS Code の拡張機能パネル（`Ctrl+Shift+X`）を開く
2. 各拡張機能のコンテキストメニュー → **「このワークスペースで無効にする」** を選択
3. Dev Container をリロードする（コマンドパレット → `Dev Containers: Rebuild Container` または `Developer: Reload Window`）

メモリを最も消費する拡張機能の候補: lint / format / git 連携など、常時ファイル監視を行うもの。

### 6.2 言語サーバー（LSP）の確認と停止判断

**プロセスの確認**

```bash
# プロジェクトで使用する言語サーバー（LSP）のプロセス名で検索する
ps aux | grep -E "language-server|langserver|lsp" | grep -v grep
```

言語サーバー（LSP）が常駐している場合、数十〜数百 MB を消費する。

**停止判断**

- `iterate-team` を実行する前後にメモリが逼迫している場合は無効化を検討する
- VS Code の拡張機能パネルで対応する IDE 拡張を「このワークスペースで無効にする」を選択し、ウィンドウをリロードすると language server が停止する

### 6.3 chrome-devtools MCP の確認と一時停止

**プロセスの確認**

```bash
# Chromium / chrome プロセスを確認
ps aux | grep -E "chromium|chrome" | grep -v grep
```

ヒットした行の RSS 列（KB 単位）の合計が大きい場合、chrome-devtools MCP が Chromium を常駐させている。

**セッション中の一時停止手順**

`.mcp.devcontainer.json` / `.mcp.host.json` は変更しない。Claude Code セッション内での停止は以下のいずれかで行う:

1. MCP を経由したブラウザ操作が完了したら、Claude Code のプロンプトで **「chrome-devtools MCP を停止してください」** と依頼し、Chromium プロセスを明示的に終了させる
2. 直接 `kill` でプロセスを停止する場合（Dev Container 内）:

```bash
pkill -f chromium
```

3. 次の Claude Code セッション開始時には MCP は再び必要になった時点で起動されるため、設定ファイルの変更は不要。

### 6.4 Codex app server / Codex MCP の確認と停止判断

**プロセスの確認**

```bash
# Node.js / Python ベースの Codex サーバプロセスを確認
ps aux | grep -E "codex|openai" | grep -v grep
```

**停止判断と手順**

Codex app server は Claude Code との重畳でメモリ消費が累積するため、`iterate-team` の実行前に停止を検討する。

セッション中の一時停止:

```bash
# プロセス ID を特定してから停止
ps aux | grep codex | grep -v grep
kill <PID>
```

設定ファイル（`.mcp.devcontainer.json` / `.mcp.host.json`）の `start` コマンドや `alwaysAllow` は変更しない。次回の Claude Code セッション開始時にサーバが必要になった時点で再起動される。

---

## 7. Dev Container メモリ増設判断基準

### 7.1 増設を検討すべき観測指標

以下のいずれかに該当する場合、メモリ増設を検討する。

| 観測指標                      | 確認コマンド                                        | 増設検討の閾値                              |
| ----------------------------- | --------------------------------------------------- | ------------------------------------------- |
| `oom_kill` カウンタの増加頻度 | `cat /sys/fs/cgroup/memory.events \| grep oom_kill` | 短期間（1 作業セッション内）に 2 回以上増加 |
| `free -h` の `available`      | `free -h`                                           | 常時 500 MB 以下が継続する                  |
| `docker stats` の `MEM %`     | `docker stats --no-stream`                          | 常時 85% 以上で推移する                     |
| 重畳時のメモリ不足頻度        | 上記を組み合わせて確認                              | 低並列運用・常駐停止後も改善しない          |

### 7.2 緩和策の優先順位（増設前に試すこと）

増設はコストが高い変更のため、以下の順で緩和策を試してから判断する。

1. **低並列運用に切り替える**（章 4 参照）
   - `/iterate-team` の並列度を最小（実質逐次）に下げる
   - wave 間に Claude Code セッションを再起動してメモリを解放

2. **常駐プロセスを停止する**（章 6 参照）
   - VS Code extension host の不要な拡張を無効化
   - 言語サーバー（LSP）の無効化
   - chrome-devtools MCP / Codex app server の一時停止

3. **上記 1・2 を実施後も `oom_kill` が発生するなら増設を検討する**

### 7.3 増設の調整箇所（「どこを見るか」のみ）

増設の変更手順はシステム環境に依存するため本ガイドでは扱わない。調整が必要な箇所のみを示す。

**Dev Container 側（`devcontainer.json`）**

`runArgs` に `--memory` / `--memory-swap` が設定されている場合、その値を引き上げることでコンテナのメモリ上限が増える。

```
// 例（現状確認のみ。変更は慎重に）
"runArgs": ["--memory=4g", "--memory-swap=4g"]
```

**Docker Desktop / ホスト VM 側**

- Docker Desktop（Mac / Windows）: Settings → Resources → Memory スライダーで VM 全体のメモリを確認・変更できる
- Linux ホスト（VM なし）: `/etc/docker/daemon.json` の `default-runtime` 設定や、コンテナ起動オプション `--memory` を確認する

**確認の優先順位**

1. まず `docker stats --no-stream` でコンテナのメモリ上限（`LIMIT`）を確認する
2. `LIMIT` が小さい場合（例: 4 GiB 以下で常時 85% 超）、Docker Desktop の VM メモリを確認する
3. VM のメモリ自体が小さい場合はホスト側の物理メモリ量と相談して引き上げる

---

## 受け入れ基準対応表

spec.md の受け入れ基準 9 項目とガイドの各章・節の対応を示す。

| #   | 受け入れ基準                                                                                                                                     | 対応するガイド章・節                                                                  |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------- |
| 1   | `memory.events` の `oom_kill` 増加、`free -h`、主要プロセスの RSS、Docker / Dev Container 側のメモリ割当を確認する手順がドキュメント化されている | 章 2「OOM Kill 診断手順」（2.1〜2.3）                                                 |
| 2   | Claude Code が `Killed` で終了した場合に、OOM Kill とそれ以外の終了要因を切り分ける手順がドキュメント化されている                                | 章 3「`Killed` 終了時の切り分け手順」（ステップ 1〜4）                                |
| 3   | `/iterate-team` の並列度を下げるための運用手順または設定項目が明記されている                                                                     | 章 4「低並列運用手順」                                                                |
| 4   | Claude Code 実行中にプロジェクトのビルド / テスト / Chrome DevTools MCP / Codex MCP を重ねる場合の注意点が明記されている                         | 章 5「重畳時の注意点」（5.1〜5.3）                                                    |
| 5   | IDE 拡張、言語サーバー（LSP）、chrome-devtools MCP、Codex app server など、常駐メモリを消費する代表プロセスの確認方法が明記されている            | 章 6「常駐プロセス確認/停止手順」（6.1〜6.4）                                         |
| 6   | 必要に応じて Docker Desktop / Dev Container / ホスト VM のメモリ割当を増やす判断基準が明記されている                                             | 章 7「Dev Container メモリ増設判断基準」（7.1〜7.3）                                  |
| 7   | 既存の `.mcp.devcontainer.json` / `.mcp.host.json` の lazy 起動方針と矛盾しない                                                                  | 章 6 冒頭の方針（設定変更禁止・運用上の一時停止のみ）、章 6.3・6.4                    |
| 8   | 変更後に Claude Code セッションを起動し、通常の対話開始時点で不要な MCP サーバが自動全起動していないことを確認できる                             | 章 6.3・6.4（設定変更なし・次回セッションでは必要時のみ起動される旨の説明）           |
| 9   | `/iterate-team` または同等の重いワークロードを低並列で実行し、実行前後で `oom_kill` が増加しないことを確認できる                                 | 章 2（`oom_kill` カウンタ確認）・章 4（低並列運用手順）・章 7.1（増設判断の観測指標） |
