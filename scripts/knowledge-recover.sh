#!/usr/bin/env bash
# 「ステップ 6.7 fail-open」（軽量レトロスペクティブ失敗時の復旧）専用スクリプト。
# team-retrospector の起動失敗 / 戻り値 parse 失敗 / knowledge コミット失敗のいずれかが
# 発生した場合に Orchestrator が本スクリプトを 1 行で呼び出すことで、散文の複数
# Bash コマンド列（operations/iterate-team-runbook.md 旧 §6.7.5）を単一スクリプトへ集約する。
#
# Usage:
#   <plugin_root>/scripts/knowledge-recover.sh <session-id>
#
# Example:
#   <plugin_root>/scripts/knowledge-recover.sh 20260704_my-topic
#
# 動作（旧 §6.7.5 の手順 1-3 に対応）:
#   手順1（tracked 復元。2段階に分離。設計判断1参照）:
#     1a. `git ls-files -- .iterate-team/knowledge/`（index 基準。staged 新規ファイルも
#         列挙される）が非空の場合のみ `git restore --staged -- .iterate-team/knowledge/`
#         を実行する。これにより index が HEAD へ復元される。HEAD に存在しない新規
#         ファイル（staged 新規）は unstage されて untracked に戻るが、worktree の
#         実体はこの時点ではまだ削除されない。
#     1b. `git ls-files -- .iterate-team/knowledge/` を再計算する（1a 実行後は
#         index=HEAD になっている）。これが非空の場合のみ
#         `git restore --worktree -- .iterate-team/knowledge/` を実行し、HEAD 追跡
#         ファイルの worktree 変更のみを復元する。
#     `knowledge_dir` が worktree 上に存在せず、かつ 1b 再計算後の ls-files も空の場合
#     （tracked 資産が一切無く、そのため untracked 資産も物理的に存在し得ない正常
#     no-op）は、手順2・手順3を丸ごとスキップし、副作用なしで exit 0 する
#     （knowledge_dir が存在しないディレクトリへ `git status -- <pathspec>` を投げると
#     `warning: could not open directory` が stderr に出るため、この no-op 経路では
#     そもそも該当コマンドを呼ばないことで stderr を完全に無音にする）。
#   手順2（untracked / ignored 退避）:
#     `.iterate-team/state/` の git 除外を session-start.sh の ensure_state_ignored と
#     同じ方式で冪等に保証したうえで、
#     `git status --porcelain -z -uall --ignored=matching` の `??`（untracked）に加えて
#     `!!`（ignored）エントリも同様に、1 件ずつ
#     `.iterate-team/state/<session-id>/failed-retrospective/` へ mv する
#     （knowledge/ からの相対パス構造を保持。同名衝突は .1, .2... で回避）。
#     退避後に空になった knowledge/ 配下のディレクトリ（knowledge/ 自体を含む）は削除する。
#
#     設計判断（第8ラウンド指摘・実機再現済み）: なぜ ignored (`!!`) も退避対象に含めるか
#       lessons.md は knowledge-append.sh / knowledge-digest.sh が書き出す
#       knowledge/.gitignore により git 無視対象にされた生成物である（第7ラウンド対応）。
#       append + digest 直後（commit 未実施）の fresh な knowledge/ は、.gitignore・
#       .gitattributes・lessons.jsonl が untracked（`??`）、lessons.md が ignored（`!!`）
#       という状態になる。ignored を列挙対象に含めず `??` のみを退避すると、ループが
#       `.gitignore` を（他の untracked エントリと同順で）先に mv した瞬間、以後
#       lessons.md は「.gitignore による無視」を判定する対象ファイルが既に退避先へ
#       移動済みのため git から見えなくなり、突如 untracked として「出現」する。
#       このタイミング（列挙リストを読み終えた後）で出現した lessons.md は今回のループが
#       既に捕捉したエントリ一覧に含まれないため退避されずに残り、手順3の事後検証が
#       `?? .iterate-team/knowledge/` を検出して exit 1 する（fail-open が破れ、作業ツリーが
#       dirty のまま残る）。ignored を untracked と同様に退避対象へ含めることで、
#       `.gitignore` と lessons.md の退避順序に依存せず knowledge/ 配下の生成物を丸ごと
#       退避できる。加えて、.gitignore が既に tracked 済みの通常運用（2回目以降の
#       セッション）でも、再生成された ignored な lessons.md を確実に退避できるため、
#       「古い digest（前回失敗時点の内容）が次回のレトロスペクティブ注入に混入して
#       残る」というハザードも同時に消える（これは手順2が本来 fail-open の事後調査用に
#       生成物を温存するという意図とも整合する）。
#       `--ignored=matching` は pathspec に一致する個々の ignored ファイルを列挙する
#       （ignored なディレクトリ全体を 1 エントリに畳み込む既定動作 `--ignored`/
#       `--ignored=traditional` と異なり、knowledge/ 配下の個別ファイルパスを相対パス
#       構造ごと取得する本スクリプトの mv ループに必要）。git 2.16 (2018) で導入済みの
#       オプションであり、本プラグインの前提実行環境（dev container・git 2.43 系）では
#       常に利用可能。
#   手順3（事後検証）:
#     `git status --porcelain -- .iterate-team/knowledge/` が空であることを確認し、
#     空でなければ診断を stderr に出して exit 1 する。この git status 自体が非ゼロ
#     終了した場合（リポジトリ外実行・index 破損等）も、診断を stderr に出して
#     exit 1 する（stderr は抑制しない。詳細は「修正2」参照）。
#     ただし本 git status 呼び出し自体は、呼び出し直前に再評価した
#     「knowledge_dir が worktree 上に存在する、または tracked（1b 再計算後）が
#     非空」の場合のみ実行する（修正3）。手順2の退避処理により knowledge_dir 配下の
#     空ディレクトリ（knowledge_dir 自体を含む）が削除されて跡形もなくなるケース
#     （tracked 資産が元から無く、untracked を全件退避した結果ディレクトリ自体が
#     消えるケース。テスト R11 で再現）では、この再評価時点で knowledge_dir が
#     既に存在せず tracked も空になるため、事後検証をスキップする（tracked も
#     untracked も存在し得ない以上、構造上 clean であることが自明であり、
#     存在しないディレクトリへの `git status -- <pathspec>` 呼び出しに起因する
#     `warning: could not open directory` を stderr に出さないため）。
#
# 設計判断 1: なぜ「手順1」を2段階（restore --staged → restore --worktree）に
#             分離するか（実機検証で発見した実バグの修正。旧実装は1コマンドだった）
#   `git restore --staged --worktree -- <pathspec>` を単一コマンドで呼ぶと、
#   「index にあるが HEAD に無いファイル」（= staged 新規ファイル。ステップ 6.7.2 の
#   正規フロー「個別 git add 成功 → git commit 失敗」で必ず発生する）は、
#   unstage されて untracked に戻る（--staged 単独の挙動）だけでなく、--worktree を
#   併用しているために worktree からも同時に削除され、ファイルそのものが完全に
#   消失する（実機確認済み。旧コメントの「staged 解除され untracked に戻る」という
#   記述は --staged 単独の場合のみ正しく、--worktree 併用時には誤りだった）。
#   レトロスペクティブ生成物（staged 新規の knowledge ファイル）を手順2の untracked
#   退避で温存するという本スクリプトの目的そのものに違反するため、`restore --staged`
#   （index のみ HEAD へ戻す）と `restore --worktree`（HEAD 追跡ファイルの worktree
#   のみ戻す）を明確に2段階へ分離し、それぞれ独立して ls-files ガードを効かせる。
#   1b の ls-files 再計算を 1a 実行後に行うのは、1a によって index=HEAD になった
#   後の「HEAD に実在する tracked ファイル」だけを --worktree の対象にするためである
#   （1a 前の ls-files には HEAD に存在しない staged 新規ファイルも含まれてしまい、
#   それを --worktree の対象にすると pathspec が HEAD に存在せずエラーになる、
#   または後述のガードの意味そのものが成立しなくなる）。
#
#   なお、fresh リポジトリ（.iterate-team/knowledge/ が HEAD にも index にも存在
#   しない）で ls-files ガード無しに `git restore` を呼ぶと pathspec が一致せず
#   エラー終了し、fail-open の本来の目的（作業ツリーを clean に戻してステップ 7 へ
#   続行する）に到達できない（旧 §6.7.5 は tracked ファイルが 1 つも無い運用開始
#   直後のリポジトリでこの罠に落ちる）。`git ls-files` の出力有無で分岐することで、
#   tracked 資産が存在しないケースを構造的に無害化する（PR レビュー指摘 P1）。
#
# 設計判断 2: なぜロック取得タイムアウトでも exit せず続行するか
#   本ロックは knowledge-append.sh / knowledge-prune.sh と共有する
#   `.iterate-team/state/knowledge-lessons.lock`（tracked な lessons.jsonl の書き換えが
#   append/prune と競合しうるため）。しかし本スクリプトの目的は fail-open、つまり
#   「失敗時にツリーを clean に戻して処理を止めないこと」そのものである。ロック待ちで
#   exit してしまうと、まさに fail-open が救うべき「dirty ツリーのまま abort」を
#   ロック競合という別要因で再発させてしまう。そのため、ロック取得に失敗した場合は
#   stderr に警告を出すのみで、ロック無しのまま復旧処理を続行する
#   （並走する append/prune との競合窓は残るが、fail-open の主目的を阻害しないことを優先する）。
#
# 実行環境前提: Linux / GNU coreutils + git（dev container・メイン checkout）。
# bash 3.2 / macOS 互換は目標外だが、ロック節のみ flock 非搭載環境向けの
# mkdir フォールバックを残す（knowledge-append.sh / runlog-append.sh と同一方式）。
#
# stdout 契約: 1 件以上退避した場合のみ、退避先ディレクトリの repo-root 相対パス
# `.iterate-team/state/<session-id>/failed-retrospective/` を 1 行だけ出力する
# （呼び出し側 Orchestrator がそのまま runlog の evacuated_to に使う）。それ以外は
# stdout に何も出力しない。
#
# Exit code:
#   0 = 正常終了（.iterate-team/knowledge/ が clean な状態に復旧できた）
#   1 = 引数不正 / session-id 不正 / 復旧後も差分が残存（異常系）
#
# 仕様の正本: <plugin_root>/operations/iterate-team-runbook.md §6.7.5

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
# knowledge-append.sh / runlog-append.sh と同一規約で state 先の分裂を防ぐ。
repo_root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
knowledge_dir="${repo_root}/.iterate-team/knowledge"
knowledge_pathspec=".iterate-team/knowledge/"
state_root="${repo_root}/.iterate-team/state"
evac_dir="${state_root}/${session_id}/failed-retrospective"
evac_dir_relpath=".iterate-team/state/${session_id}/failed-retrospective/"

# =====================================================================
# 対象リポジトリの runtime state (.iterate-team/state/) を git の無視対象へ登録する。
# session-start.sh の ensure_state_ignored と同一方式（冪等・ローカル限定の
# .git/info/exclude 追記）。手順2で state/ 配下へ mv する前に必ず呼ぶことで、
# 退避先自体が untracked 差分として全体の dirty check を汚染しないようにする。
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
# 排他ロック取得（knowledge-append.sh / knowledge-prune.sh と同一パスを共有）。
# 手順1（tracked 復元）・手順2（untracked 退避）はいずれも tracked な lessons.jsonl の
# 内容に影響しうるため、append/prune と相互排他する。ただしタイムアウト時は exit せず
# 警告のみで続行する（理由はヘッダコメント「設計判断 2」参照）。
# =====================================================================
lock_base_dir="$state_root"
mkdir -p "$lock_base_dir"

# ロックが実際に取得できたかどうかは以降の処理で参照しない（取得できなくても
# fail-open 処理は続行する。設計判断2参照）。そのため専用の状態変数は持たない。
if command -v flock >/dev/null 2>&1; then
  lock_file="${lock_base_dir}/knowledge-lessons.lock"
  exec 9>>"$lock_file"
  if ! flock -x -w 5 9; then
    echo "knowledge-recover: warning: flock timeout ($lock_file)。ロック未取得のまま fail-open 処理を続行します（ツリーを clean に戻すことを優先するため abort しない）。" >&2
    exec 9>&- 2>/dev/null || true
  fi
else
  # flock 非搭載（macOS ホスト）: mkdir の原子性を利用したポータブルな排他制御。
  lock_dir="${lock_base_dir}/knowledge-lessons.lock.d"
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
    echo "knowledge-recover: warning: mkdir lock timeout ($lock_dir)。ロック未取得のまま fail-open 処理を続行します。" >&2
  fi
fi

# =====================================================================
# 手順1: tracked 復元（2段階に分離。ls-files ガード付き。設計判断1参照）
# =====================================================================

# 1a. index を HEAD へ戻す（staged 新規ファイルは worktree を残したまま untracked へ戻る）。
tracked_list_before="$(git -C "$repo_root" ls-files -- "$knowledge_pathspec" 2>/dev/null || true)"
if [[ -n "$tracked_list_before" ]]; then
  git -C "$repo_root" restore --staged -- "$knowledge_pathspec"
fi

# 1b. 1a 実行後（index=HEAD）に ls-files を再計算し、HEAD に実在する tracked
#     ファイルの worktree 変更のみを復元する。
tracked_list_after="$(git -C "$repo_root" ls-files -- "$knowledge_pathspec" 2>/dev/null || true)"
if [[ -n "$tracked_list_after" ]]; then
  git -C "$repo_root" restore --worktree -- "$knowledge_pathspec"
fi

# =====================================================================
# 手順2 + 手順3: untracked 退避 + 事後検証
# =====================================================================
ensure_state_ignored "$repo_root"

moved_any=false

# knowledge_dir が worktree 上に存在せず、かつ 1b 再計算後の tracked も存在しない場合は
# 正常な no-op（tracked も untracked も一切無い。untracked は knowledge_dir が物理的に
# 存在しない限り発生し得ない）。この場合、手順2・手順3の git status 呼び出し自体を
# スキップすることで、存在しないディレクトリへのパス指定に起因する
# `warning: could not open directory` を stderr に出さないようにする。
if [[ -d "$knowledge_dir" ]] || [[ -n "$tracked_list_after" ]]; then
  while IFS= read -r -d '' entry; do
    status="${entry:0:2}"
    # untracked (`??`) / ignored (`!!`) 以外は対象外。ignored も対象に含める理由は
    # ヘッダコメント「手順2」の設計判断（第8ラウンド指摘）を参照
    # （.gitignore により無視される lessons.md 等の生成物を退避順序に依存せず捕捉するため）。
    [[ "$status" == "??" || "$status" == "!!" ]] || continue

    path="${entry:3}"
    rel="${path#"$knowledge_pathspec"}"
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
  done < <(git -C "$repo_root" status --porcelain -z -uall --ignored=matching -- "$knowledge_pathspec")

  # 退避後に空になった knowledge/ 配下のディレクトリ（knowledge/ 自体を含む）を削除する。
  # untracked の空ディレクトリは git status に現れないため tree の clean 判定には影響しないが、
  # 次回 preflight の見た目を綺麗にするための後始末。
  if [[ -d "$knowledge_dir" ]]; then
    find "$knowledge_dir" -depth -type d -empty -delete 2>/dev/null || true
  fi

  # ---- 手順3: 事後検証 ----
  # 手順2 の退避によって knowledge_dir 自体（空になったディレクトリ）が削除済みで、
  # かつ tracked（1b 再計算後）も空の場合は、tracked も untracked も存在し得ない
  # 以上構造上 clean であることが自明なので、git status 呼び出し自体をスキップする
  # （存在しないディレクトリへの pathspec 指定による `warning: could not open
  # directory` を stderr に出さないため。修正3。上記の外側 if の判定は「手順2実行
  # 直前」時点のものであり、手順2の副作用（空ディレクトリ削除）を反映していないため
  # ここで再評価する）。
  if [[ -d "$knowledge_dir" ]] || [[ -n "$tracked_list_after" ]]; then
    # stderr は抑制しない（git status 自体の失敗を握り潰さないため。修正2）。
    set +e
    remaining="$(git -C "$repo_root" status --porcelain -- "$knowledge_pathspec")"
    status_exit=$?
    set -e

    if [[ "$status_exit" -ne 0 ]]; then
      echo "knowledge-recover: ERROR: 事後検証の git status 自体が失敗しました（exit=${status_exit}）。リポジトリ外実行や index 破損の可能性があります。" >&2
      exit 1
    fi

    if [[ -n "$remaining" ]]; then
      echo "knowledge-recover: ERROR: ${knowledge_pathspec} が clean な状態に復旧できませんでした。残存差分:" >&2
      echo "$remaining" >&2
      exit 1
    fi
  fi
fi

if [[ "$moved_any" == true ]]; then
  echo "$evac_dir_relpath"
fi

exit 0
