#!/usr/bin/env bash
# 「§7 コミット・push フロー / fail-open」（`.agent-os/` コミット失敗時の復旧）専用
# スクリプト。team-profiler / team-adapter の起動失敗・戻り値 parse 失敗・
# `.agent-os/` コミット失敗のいずれかが発生した場合に Orchestrator が本スクリプトを
# 1 行で呼び出すことで、作業ツリーを clean に戻し PR フローを止めない（fail-open）。
#
# `knowledge-recover.sh`（`.iterate-team/knowledge/` 用）の `.agent-os/` 版であり、
# 復旧アルゴリズムの構造・安全規律は同スクリプトをそのままクローンしている。
#
# Usage:
#   <plugin_root>/scripts/adapter-recover.sh <session-id>
#
# Example:
#   <plugin_root>/scripts/adapter-recover.sh 20260704_my-topic
#
# 動作（operations/adapter-policy.md §7 fail-open 手順 1 に対応）:
#   手順1（tracked 復元。2段階に分離。設計判断1参照）:
#     1a. `git ls-files -- .agent-os/`（index 基準。staged 新規ファイルも列挙される）が
#         非空の場合のみ `git restore --staged -- .agent-os/` を実行する。これにより
#         index が HEAD へ復元される。HEAD に存在しない新規ファイル（staged 新規）は
#         unstage されて untracked に戻るが、worktree の実体はこの時点ではまだ削除
#         されない。
#     1b. `git ls-files -- .agent-os/` を再計算する（1a 実行後は index=HEAD になって
#         いる）。これが非空の場合のみ `git restore --worktree -- .agent-os/` を実行し、
#         HEAD 追跡ファイルの worktree 変更のみを復元する。
#     `agent_os_dir` が worktree 上に存在せず、かつ 1b 再計算後の ls-files も空の場合
#     （tracked 資産が一切無く、そのため untracked 資産も物理的に存在し得ない正常
#     no-op。`/iterate-adapt` 初回実行前の対象リポで発生する）は、手順2・手順3を
#     丸ごとスキップし、副作用なしで exit 0 する（agent_os_dir が存在しないディレクト
#     リへ `git status -- <pathspec>` を投げると `warning: could not open directory`
#     が stderr に出るため、この no-op 経路ではそもそも該当コマンドを呼ばないことで
#     stderr を完全に無音にする）。
#   手順2（untracked 退避）:
#     `.iterate-team/state/` の git 除外を session-start.sh の ensure_state_ignored と
#     同じ方式で冪等に保証したうえで、`git status --porcelain -z -uall` の
#     `??`（untracked）エントリを 1 件ずつ `.iterate-team/state/<session-id>/failed-adapter/`
#     へ mv する（.agent-os/ からの相対パス構造を保持。同名衝突は .1, .2... で回避）。
#     退避後に空になった .agent-os/ 配下のディレクトリ（.agent-os/ 自体を含む）は削除する。
#
#     `knowledge-recover.sh` との差分（ignored (`!!`) 退避を行わない理由）:
#       `knowledge-recover.sh` は `--ignored=matching` を併用し `!!`（ignored）エントリも
#       退避対象に含める。これは `.iterate-team/knowledge/lessons.md` が
#       `knowledge-append.sh`/`knowledge-digest.sh` の書き出す `.gitignore` により
#       git 無視対象にされた生成物だからである（knowledge-recover.sh ヘッダコメント
#       「手順2」参照）。一方 `.agent-os/` は operations/adapter-policy.md §2 のとおり
#       8 required files + `GLOBAL_AGENTS.md`（+ 任意の `rules/*.md`）が**すべて
#       git-tracked** であり、`.agent-os/` 配下に git-ignore される生成物は存在しない
#       （`.iterate-team/knowledge/` のような「tracked 資産と ignored 派生物の対」が
#       構造上ない）。そのため本スクリプトは `??`（untracked）のみを退避対象とし、
#       `--ignored=matching` は使わない（`!!` エントリが原理上出現しないため、
#       退避しても事後検証を通らないケースが生じない）。
#   手順3（事後検証）:
#     `git status --porcelain -- .agent-os/` が空であることを確認し、空でなければ
#     診断を stderr に出して exit 1 する。この git status 自体が非ゼロ終了した場合
#     （リポジトリ外実行・index 破損等）も、診断を stderr に出して exit 1 する
#     （stderr は抑制しない）。
#     ただし本 git status 呼び出し自体は、呼び出し直前に再評価した
#     「agent_os_dir が worktree 上に存在する、または tracked（1b 再計算後）が
#     非空」の場合のみ実行する。手順2の退避処理により agent_os_dir 配下の空ディレクトリ
#     （agent_os_dir 自体を含む）が削除されて跡形もなくなるケース（tracked 資産が
#     元から無く、untracked を全件退避した結果ディレクトリ自体が消えるケース）では、
#     この再評価時点で agent_os_dir が既に存在せず tracked も空になるため、事後検証を
#     スキップする（tracked も untracked も存在し得ない以上、構造上 clean であることが
#     自明であり、存在しないディレクトリへの `git status -- <pathspec>` 呼び出しに
#     起因する `warning: could not open directory` を stderr に出さないため）。
#
# 設計判断 1: なぜ「手順1」を2段階（restore --staged → restore --worktree）に
#             分離するか（knowledge-recover.sh と同一の実機検証済みバグ回避）
#   `git restore --staged --worktree -- <pathspec>` を単一コマンドで呼ぶと、
#   「index にあるが HEAD に無いファイル」（= staged 新規ファイル。§7 の正規フロー
#   「個別 git add 成功 → git commit 失敗」で発生しうる）は、unstage されて
#   untracked に戻る（--staged 単独の挙動）だけでなく、--worktree を併用している
#   ために worktree からも同時に削除され、ファイルそのものが完全に消失する。
#   team-adapter/team-profiler が生成した staged 新規の `.agent-os/` ファイルを手順2の
#   untracked 退避で温存するという本スクリプトの目的そのものに違反するため、
#   `restore --staged`（index のみ HEAD へ戻す）と `restore --worktree`（HEAD 追跡
#   ファイルの worktree のみ戻す）を明確に2段階へ分離し、それぞれ独立して ls-files
#   ガードを効かせる。1b の ls-files 再計算を 1a 実行後に行うのは、1a によって
#   index=HEAD になった後の「HEAD に実在する tracked ファイル」だけを --worktree の
#   対象にするためである（1a 前の ls-files には HEAD に存在しない staged 新規
#   ファイルも含まれてしまい、それを --worktree の対象にすると pathspec が HEAD に
#   存在せずエラーになる、または後述のガードの意味そのものが成立しなくなる）。
#
#   なお、fresh リポジトリ（.agent-os/ が HEAD にも index にも存在しない。
#   `/iterate-adapt` 初回実行前）で ls-files ガード無しに `git restore` を呼ぶと
#   pathspec が一致せずエラー終了し、fail-open の本来の目的（作業ツリーを clean に
#   戻して PR フローへ続行する）に到達できない。`git ls-files` の出力有無で分岐する
#   ことで、tracked 資産が存在しないケースを構造的に無害化する。
#
# 設計判断 2: なぜロック取得タイムアウトでも exit せず続行するか
#   本ロックは（将来の）`adapter-record-feedback.sh` / team-adapter による
#   `.agent-os/` 書き込みと共有する `.iterate-team/state/adapter-agent-os.lock`。
#   しかし本スクリプトの目的は fail-open、つまり「失敗時にツリーを clean に戻して
#   処理を止めないこと」そのものである。ロック待ちで exit してしまうと、まさに
#   fail-open が救うべき「dirty ツリーのまま abort」をロック競合という別要因で
#   再発させてしまう。そのため、ロック取得に失敗した場合は stderr に警告を出す
#   のみで、ロック無しのまま復旧処理を続行する（並走する書き込みとの競合窓は
#   残るが、fail-open の主目的を阻害しないことを優先する）。
#
# 実行環境前提: Linux / GNU coreutils + git（dev container・メイン checkout）。
# bash 3.2 / macOS 互換は目標外だが、ロック節のみ flock 非搭載環境向けの
# mkdir フォールバックを残す（knowledge-recover.sh / runlog-append.sh と同一方式）。
#
# stdout 契約: 1 件以上退避した場合のみ、退避先ディレクトリの repo-root 相対パス
# `.iterate-team/state/<session-id>/failed-adapter/` を 1 行だけ出力する
# （呼び出し側 Orchestrator がそのまま runlog の evacuated_to に使う）。それ以外は
# stdout に何も出力しない。
#
# Exit code:
#   0 = 正常終了（.agent-os/ が clean な状態に復旧できた）
#   1 = 引数不正 / session-id 不正 / 復旧後も差分が残存（異常系）
#
# 仕様の正本: <plugin_root>/operations/adapter-policy.md §7

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <session-id>" >&2
  exit 1
fi

session_id="$1"

# ---- session-id パス安全性検証（空・'/' 含み・'..' を拒否） ----
# runlog-append.sh の許容文字集合（英数 . _ -）も踏襲し、想定外文字を含む session-id を
# 多層防御で拒否する（'/' や '..' は個別に先行チェックし、エラーメッセージを明確化する）。
if [[ -z "$session_id" ]]; then
  echo "invalid session-id: (empty)" >&2
  exit 1
fi
case "$session_id" in
  */* | *..*)
    echo "invalid session-id (must not contain '/' or '..'): $session_id" >&2
    exit 1
    ;;
esac
if [[ "$session_id" =~ [^A-Za-z0-9._-] ]]; then
  echo "invalid session-id (allowed chars: A-Za-z0-9._-): $session_id" >&2
  exit 1
fi

# repo_root は対象プロジェクト基準で解決する（プラグイン自身の git root は見ない）。
# CLAUDE_PROJECT_DIR を優先し、未注入時は CWD の git root → pwd の順でフォールバックする。
# knowledge-recover.sh / runlog-append.sh と同一規約で state 先の分裂を防ぐ。
repo_root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
agent_os_dir="${repo_root}/.agent-os"
agent_os_pathspec=".agent-os/"
state_root="${repo_root}/.iterate-team/state"
evac_dir="${state_root}/${session_id}/failed-adapter"
evac_dir_relpath=".iterate-team/state/${session_id}/failed-adapter/"

# =====================================================================
# 対象リポジトリの runtime state (.iterate-team/state/) を git の無視対象へ登録する。
# session-start.sh の ensure_state_ignored / knowledge-recover.sh と同一方式
# （冪等・ローカル限定の .git/info/exclude 追記）。手順2で state/ 配下へ mv する前に
# 必ず呼ぶことで、退避先自体が untracked 差分として全体の dirty check を汚染しない
# ようにする。
# =====================================================================
ensure_state_ignored() {
  local project_dir="$1"
  command -v git >/dev/null 2>&1 || return 0
  git -C "$project_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

  if git -C "$project_dir" check-ignore -q .iterate-team/state/escalation-template.md 2>/dev/null; then
    return 0
  fi

  local git_dir
  git_dir="$(git -C "$project_dir" rev-parse --git-common-dir 2>/dev/null || true)"
  [ -n "$git_dir" ] || return 0
  case "$git_dir" in
    /*) : ;;
    *) git_dir="$project_dir/$git_dir" ;;
  esac
  local exclude_file="$git_dir/info/exclude"

  local prefix
  prefix="$(git -C "$project_dir" rev-parse --show-prefix 2>/dev/null || true)"
  local pattern="/${prefix}.iterate-team/state/"

  if [ -f "$exclude_file" ] && grep -qxF "$pattern" "$exclude_file" 2>/dev/null; then
    return 0
  fi

  mkdir -p "$git_dir/info" 2>/dev/null || return 0
  if [ -s "$exclude_file" ] && [ -n "$(tail -c1 "$exclude_file" 2>/dev/null)" ]; then
    printf '\n' >> "$exclude_file" 2>/dev/null || return 0
  fi
  printf '# iterate-team SessionStart hook が自動追記 (runtime state)\n%s\n' "$pattern" \
    >> "$exclude_file" 2>/dev/null || return 0
}

# =====================================================================
# 排他ロック取得（将来の adapter-record-feedback.sh / team-adapter の .agent-os/
# 書き込みと同一パスを共有する想定）。手順1（tracked 復元）・手順2（untracked 退避）
# はいずれも .agent-os/ の内容に影響しうるため、並走する書き込みと相互排他する。
# ただしタイムアウト時は exit せず警告のみで続行する（理由はヘッダコメント
# 「設計判断 2」参照）。
# =====================================================================
lock_base_dir="$state_root"
mkdir -p "$lock_base_dir"

# ロックが実際に取得できたかどうかは以降の処理で参照しない（取得できなくても
# fail-open 処理は続行する。設計判断2参照）。そのため専用の状態変数は持たない。
if command -v flock >/dev/null 2>&1; then
  lock_file="${lock_base_dir}/adapter-agent-os.lock"
  exec 9>>"$lock_file"
  if ! flock -x -w 5 9; then
    echo "adapter-recover: warning: flock timeout ($lock_file)。ロック未取得のまま fail-open 処理を続行します（ツリーを clean に戻すことを優先するため abort しない）。" >&2
    exec 9>&- 2>/dev/null || true
  fi
else
  # flock 非搭載（macOS ホスト）: mkdir の原子性を利用したポータブルな排他制御。
  lock_dir="${lock_base_dir}/adapter-agent-os.lock.d"
  waited=0
  lock_acquired=false
  while true; do
    if mkdir "$lock_dir" 2>/dev/null; then
      lock_acquired=true
      break
    fi
    if [[ "$waited" -ge 50 ]]; then
      break
    fi
    sleep 0.1
    waited=$((waited + 1))
  done
  if [[ "$lock_acquired" == true ]]; then
    trap 'rmdir "'"$lock_dir"'" 2>/dev/null || true' EXIT
  else
    echo "adapter-recover: warning: mkdir lock timeout ($lock_dir)。ロック未取得のまま fail-open 処理を続行します。" >&2
  fi
fi

# =====================================================================
# 手順1: tracked 復元(2段階に分離。ls-files ガード付き。設計判断1参照)
# =====================================================================

# 1a. index を HEAD へ戻す（staged 新規ファイルは worktree を残したまま untracked へ戻る）。
tracked_list_before="$(git -C "$repo_root" ls-files -- "$agent_os_pathspec" 2>/dev/null || true)"
if [[ -n "$tracked_list_before" ]]; then
  git -C "$repo_root" restore --staged -- "$agent_os_pathspec"
fi

# 1b. 1a 実行後（index=HEAD）に ls-files を再計算し、HEAD に実在する tracked
#     ファイルの worktree 変更のみを復元する。
tracked_list_after="$(git -C "$repo_root" ls-files -- "$agent_os_pathspec" 2>/dev/null || true)"
if [[ -n "$tracked_list_after" ]]; then
  git -C "$repo_root" restore --worktree -- "$agent_os_pathspec"
fi

# =====================================================================
# 手順2 + 手順3: untracked 退避 + 事後検証
# =====================================================================
ensure_state_ignored "$repo_root"

moved_any=false

# agent_os_dir が worktree 上に存在せず、かつ 1b 再計算後の tracked も存在しない場合は
# 正常な no-op（tracked も untracked も一切無い。untracked は agent_os_dir が物理的に
# 存在しない限り発生し得ない）。この場合、手順2・手順3の git status 呼び出し自体を
# スキップすることで、存在しないディレクトリへのパス指定に起因する
# `warning: could not open directory` を stderr に出さないようにする。
if [[ -d "$agent_os_dir" ]] || [[ -n "$tracked_list_after" ]]; then
  while IFS= read -r -d '' entry; do
    status="${entry:0:2}"
    # untracked (`??`) 以外は対象外。.agent-os/ には git-ignore される生成物が
    # 存在しないため、knowledge-recover.sh と異なり ignored (`!!`) は退避対象に
    # 含めない（ヘッダコメント「手順2」の差分説明を参照）。
    [[ "$status" == "??" ]] || continue

    path="${entry:3}"
    rel="${path#"$agent_os_pathspec"}"
    # pathspec に一致しない・空になったエントリは想定外なのでスキップ（fail-closed）
    [[ -n "$rel" && "$rel" != "$path" ]] || continue

    src="${repo_root}/${path}"
    dest="${evac_dir}/${rel}"

    mkdir -p "$(dirname "$dest")"

    final_dest="$dest"
    suffix=1
    while [[ -e "$final_dest" ]]; do
      final_dest="${dest}.${suffix}"
      suffix=$((suffix + 1))
    done

    mv -- "$src" "$final_dest"
    moved_any=true
  done < <(git -C "$repo_root" status --porcelain -z -uall -- "$agent_os_pathspec")

  # 退避後に空になった .agent-os/ 配下のディレクトリ（.agent-os/ 自体を含む）を削除する。
  # untracked の空ディレクトリは git status に現れないため tree の clean 判定には影響しないが、
  # 次回 preflight の見た目を綺麗にするための後始末。
  if [[ -d "$agent_os_dir" ]]; then
    find "$agent_os_dir" -depth -type d -empty -delete 2>/dev/null || true
  fi

  # ---- 手順3: 事後検証 ----
  # 手順2 の退避によって agent_os_dir 自体（空になったディレクトリ）が削除済みで、
  # かつ tracked（1b 再計算後）も空の場合は、tracked も untracked も存在し得ない
  # 以上構造上 clean であることが自明なので、git status 呼び出し自体をスキップする
  # （存在しないディレクトリへの pathspec 指定による `warning: could not open
  # directory` を stderr に出さないため。上記の外側 if の判定は「手順2実行直前」
  # 時点のものであり、手順2の副作用（空ディレクトリ削除）を反映していないため
  # ここで再評価する）。
  if [[ -d "$agent_os_dir" ]] || [[ -n "$tracked_list_after" ]]; then
    # stderr は抑制しない（git status 自体の失敗を握り潰さないため）。
    set +e
    remaining="$(git -C "$repo_root" status --porcelain -- "$agent_os_pathspec")"
    status_exit=$?
    set -e

    if [[ "$status_exit" -ne 0 ]]; then
      echo "adapter-recover: ERROR: 事後検証の git status 自体が失敗しました（exit=${status_exit}）。リポジトリ外実行や index 破損の可能性があります。" >&2
      exit 1
    fi

    if [[ -n "$remaining" ]]; then
      echo "adapter-recover: ERROR: ${agent_os_pathspec} が clean な状態に復旧できませんでした。残存差分:" >&2
      echo "$remaining" >&2
      exit 1
    fi
  fi
fi

if [[ "$moved_any" == true ]]; then
  echo "$evac_dir_relpath"
fi

exit 0
