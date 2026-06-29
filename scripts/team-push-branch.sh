#!/usr/bin/env bash
# 目的: /iterate-team の唯一許可 push 経路。Claude Code permissions.allow に
#       `Bash(<plugin_root>/scripts/team-push-branch.sh *)` を登録し、本ラッパー経由でのみ
#       git push を許す設計。`Bash(git push *)` の wildcard 吸収による
#       force / destructive / refspec のすり抜け（force / refspec / 保護 branch
#       上書き）を構造的に拒否する。
#
# 引数: <branch-name> 1 個のみ
#
# 拒否条件（allowlist 方式: 明示的に許可した branch 名以外は exit 1）:
#   - 引数 0 個 / 2 個以上                    -> Usage: <branch-name>
#   - <branch-name> = main / master           -> PROTECTED_BRANCH
#   - <branch-name> 末尾 main / master を含む refs -> PROTECTED_REFSPEC
#   - refs/ で始まる                          -> REFSPEC_FORBIDDEN
#   - `:` を含む（src:dst refspec）           -> REFSPEC_FORBIDDEN
#   - `-f` / `--force` / `--force-with-lease` -> FORCE_FORBIDDEN
#     / `--force-if-includes` 派生形含む
#   - `--mirror` / `--delete` / `-d`          -> DESTRUCTIVE_FORBIDDEN
#   - `^[A-Za-z0-9_][A-Za-z0-9._/-]*$` 不一致 -> INVALID_BRANCH
#   - `..` を含む                             -> INVALID_BRANCH
#   - `/` で始まる / 終わる                   -> INVALID_BRANCH
#   - HEAD / @ 等の特殊 ref                   -> SPECIAL_REF_FORBIDDEN
#   - `claude/` 接頭辞でない                  -> BRANCH_NOT_ALLOWED
#   - ローカルに refs/heads/<branch> が無い   -> BRANCH_NOT_FOUND
#   - 現在 HEAD が <branch> と不一致          -> HEAD_MISMATCH
#
# push は HEAD 解決・オプション注入を避けるため明示 refspec で行う:
#   git push -u origin -- "refs/heads/<branch>:refs/heads/<branch>"
#
# 成功時: stdout に `PUSHED: <branch-name>` を出力し exit 0
# 失敗時: stderr に `<REASON>: <input>` を出力し exit 1
#
# 呼出元: <plugin_root>/agents/team-publisher.md（push_branch operation）/ 手動
# exit code: 0 成功 / 1 検証拒否 or git push 失敗

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: <branch-name>" >&2
  exit 1
fi

BRANCH="$1"

# 1. force / destructive 系フラグ拒否（引数 1 個のみ受理の allowlist だが、
#    branch 名としてフラグ風文字列が来た場合も明示的に拒否してメッセージを明確化）
case "$BRANCH" in
  -f|--force|--force-with-lease|--force-with-lease=*|--force-if-includes|--force=*|*--force*)
    echo "FORCE_FORBIDDEN: $BRANCH" >&2
    exit 1
    ;;
  --mirror|--delete|-d|--mirror=*|--delete=*)
    echo "DESTRUCTIVE_FORBIDDEN: $BRANCH" >&2
    exit 1
    ;;
esac

# 2. 保護ブランチ拒否（exact match）
case "$BRANCH" in
  main|master)
    echo "PROTECTED_BRANCH: $BRANCH" >&2
    exit 1
    ;;
esac

# 3. refspec 形式（: 含有）拒否（src:dst で他 branch を上書きする経路を遮断）
case "$BRANCH" in
  *:*)
    echo "REFSPEC_FORBIDDEN: $BRANCH" >&2
    exit 1
    ;;
esac

# 4. refs/ 始まり拒否（refs/heads/main / refs/tags/* / refs/* 任意 ref push を遮断）
case "$BRANCH" in
  refs/*)
    case "$BRANCH" in
      refs/heads/main|refs/heads/master)
        echo "PROTECTED_REFSPEC: $BRANCH" >&2
        ;;
      *)
        echo "REFSPEC_FORBIDDEN: $BRANCH" >&2
        ;;
    esac
    exit 1
    ;;
esac

# 5. 形式チェック（branch 名の許容文字 + path traversal 防止）
if [[ ! "$BRANCH" =~ ^[A-Za-z0-9_][A-Za-z0-9._/-]*$ ]]; then
  echo "INVALID_BRANCH: $BRANCH" >&2
  exit 1
fi
if [[ "$BRANCH" == *..* ]]; then
  echo "INVALID_BRANCH: $BRANCH" >&2
  exit 1
fi
if [[ "$BRANCH" == /* ]] || [[ "$BRANCH" == */ ]]; then
  echo "INVALID_BRANCH: $BRANCH" >&2
  exit 1
fi

# 6. 特殊 ref 拒否（HEAD / @ は git push origin HEAD で現在ブランチへ解決され、
#    main 上で呼ぶと PROTECTED_BRANCH 検査を迂回し得るため明示的に弾く）
case "$BRANCH" in
  HEAD|@)
    echo "SPECIAL_REF_FORBIDDEN: $BRANCH" >&2
    exit 1
    ;;
esac

# 7. ハーネス統合ブランチ限定（claude/ prefix）。本ラッパーは無プロンプト allow される
#    唯一の push 経路であり、push 対象はハーネスが作成する統合ブランチ claude/<topic>
#    に限る。develop / release/* 等の任意ブランチを自動 push する経路を構造的に塞ぐ。
case "$BRANCH" in
  claude/?*) : ;;
  *)
    echo "BRANCH_NOT_ALLOWED: $BRANCH" >&2
    exit 1
    ;;
esac

# 8. ローカル実在確認（refs/heads/<branch> が存在する正規ブランチのみ push 対象。
#    tag / 特殊 ref / 未作成ブランチはここで弾く）
if ! git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  echo "BRANCH_NOT_FOUND: $BRANCH" >&2
  exit 1
fi

# 9. 現在 HEAD が push 対象ブランチと一致することを必須化する。本ラッパーは無確認 allow
#    されるため、Publisher の HEAD 整合検証（head_branch_mismatch）をラッパー単体でも担保し、
#    task worktree や誤コンテキストから既存 claude/* を勝手に push する経路を塞ぐ。
current_head="$(git symbolic-ref --short HEAD 2>/dev/null || echo "")"
if [[ "$current_head" != "$BRANCH" ]]; then
  echo "HEAD_MISMATCH: head=${current_head:-<detached>} branch=$BRANCH" >&2
  exit 1
fi

# 10. git push 実行（HEAD 解決とオプション注入を避けるため -- + 明示 refspec を固定。
#     ローカル refs/heads/<branch> を同名リモートブランチへのみ push する）
git push -u origin -- "refs/heads/$BRANCH:refs/heads/$BRANCH"
echo "PUSHED: $BRANCH"
