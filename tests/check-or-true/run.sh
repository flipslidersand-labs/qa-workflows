#!/usr/bin/env bash
# scripts/check-or-true.sh を固定データで検証する (#116)
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
S="$ROOT/scripts/check-or-true.sh"; F="$ROOT/tests/check-or-true/fixtures"
fail=0
check() { # name expected_rc files...
  n="$1"; want="$2"; shift 2
  bash "$S" "$@" >/dev/null 2>&1; rc=$?
  if [ "$rc" = "$want" ]; then echo "ok   $n"; else echo "FAIL $n: expected rc=$want got $rc"; fail=1; fi
}
check plain-detected      1 "$F/bad-plain.yml"
check allowed-passes      0 "$F/allowed.yml"
check empty-reason-fails  1 "$F/bad-empty-reason.yml"
check expr-string-detected 1 "$F/bad-expr.yml"
check mixed-fails         1 "$F/allowed.yml" "$F/bad-plain.yml"
# bad-plain は 2 行とも報告される
n=$(bash "$S" "$F/bad-plain.yml" | grep -c 'bad-plain.yml:')
if [ "$n" = 2 ]; then echo "ok   reports-both-lines"; else echo "FAIL reports-both-lines: $n"; fail=1; fi
# 実際の workflow は 0 件
check repo-workflows      0 "$ROOT"/.github/workflows/*.yml
exit $fail
