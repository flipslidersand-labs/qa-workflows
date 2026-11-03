#!/usr/bin/env bash
# word-splitting 前提 input の「直展開(旧)」と「read -r -a 配列展開(新)」で
# 実行コマンド(argv)が同一になることを比較する (#83 第2段)。
# 差が出る想定のケースは DIFF として明示し、期待どおり差が出ていることを確認する。
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WF="$ROOT/.github/workflows"
fail=0
# 旧: 値が run: にソースとして直展開される (引用符・glob を shell が解釈)
old() { (cd "$TMPD" && bash -c 'show() { printf "<%s>" "$@"; echo; }; show pre '"$1"' post'); }
# 新: env 経由 + read -r -a + "${ARR[@]}"
new() { (cd "$TMPD" && V="$1" bash -c 'read -r -a ARR <<< "$V"; show() { printf "<%s>" "$@"; echo; }; show pre "${ARR[@]}" post'); }
TMPD="$(mktemp -d)"; trap 'rm -rf "$TMPD"' EXIT
touch "$TMPD/a.txt" "$TMPD/b.txt"
same() { # name value
  o="$(old "$2")"; n="$(new "$2")"
  if [ "$o" = "$n" ]; then echo "ok   same  $1: $n"; else echo "FAIL $1: old=$o new=$n"; fail=1; fi
}
differs() { # name value  (差が出ることが期待値)
  o="$(old "$2")"; n="$(new "$2")"
  if [ "$o" != "$n" ]; then echo "ok   DIFF  $1: old=$o new=$n"; else echo "FAIL $1: 差が出る想定なのに同一: $o"; fail=1; fi
}
same empty ""
same single "-v"
same go-flags "-race -timeout 60s"
same multi-cov "--cov=scripts --cov=experiments --cov=e5svc"
same cargo-scope "-p trace-nest -p trace-nest-common --all-targets"
same deny "clippy::correctness"
same deps "libssl-dev pkg-config"
same extra-spaces "  -v    -x  "
differs quoted-k '-k "a and b"'
differs quoted-m "-m 'not integration'"
differs glob "*.txt"
differs dollar '$HOME'
# 各 workflow が実際にこの配列化を使っていることの確認
chk() { grep -qF -- "$2" "$WF/$1" && echo "ok   uses  $1: $2" || { echo "FAIL $1 に '$2' が無い"; fail=1; }; }
chk python-test.yml 'read -r -a TEST_PATH_ARR <<< "$TEST_PATH"'
chk go-test.yml 'read -r -a FLAGS <<< "$TEST_FLAGS"'
chk rust-test.yml 'read -r -a DEPS <<< "$SYSTEM_DEPS"'
chk rust-test.yml 'read -r -a CLIPPY_ARR <<< "$CLIPPY_ARGS"'
chk rust-test.yml 'read -r -a DENY_ARR <<< "$CLIPPY_DENY"'
chk rust-test.yml 'read -r -a TEST_ARR <<< "$TEST_ARGS"'
# 据え置き(引用符入り caller あり): pytest-args は直展開のまま
chk python-test.yml '${{ inputs.pytest-args }}'
exit $fail
