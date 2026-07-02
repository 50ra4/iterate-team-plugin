#!/usr/bin/env bash
# scripts/__tests__/*.test.sh を全件実行するランナー。
#
# 直に `bash scripts/__tests__/*.test.sh` と書くと、グロブ展開後の先頭 1 本しか
# 実行されない（残りは第 1 引数以降としてその 1 本へ渡るだけ）。他スイートを黙って
# 飛ばしたまま success 扱いになりうるため、検収ゲートとしては使えない。
# 本スクリプトは各テストを個別に起動し、1 本でも失敗すれば非ゼロで終了する。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

shopt -s nullglob
tests=(scripts/__tests__/*.test.sh)

if (( ${#tests[@]} == 0 )); then
  echo "no test files found under scripts/__tests__/" >&2
  exit 2
fi

fail=0
for t in "${tests[@]}"; do
  echo "== ${t} =="
  if ! bash "${t}"; then
    echo "  -> FAIL: ${t}" >&2
    fail=1
  fi
done

if (( fail )); then
  echo "" >&2
  echo "some shell unit tests failed." >&2
  exit 1
fi

echo ""
echo "all ${#tests[@]} shell unit test file(s) passed."
