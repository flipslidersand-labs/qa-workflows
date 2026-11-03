#!/usr/bin/env bash
# smoke-test.yml の rollback 決定部(BEGIN/END smoke-rollback-decide 区間)を取り出してケース別に検証する (#89)
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
YML="$ROOT/.github/workflows/smoke-test.yml"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
awk '/# END smoke-rollback-decide/{f=0} f{sub(/^          /,""); print} /# BEGIN smoke-rollback-decide/{f=1}' "$YML" > "$TMP/decide.sh"
[ -s "$TMP/decide.sh" ] || { echo "FAIL: 決定ロジックが見つからない"; exit 1; }
fail=0
check() { # name expected CHECK_ROLLBACK CHECK_OUTCOME EXTRA_OUTCOME
  : > "$TMP/out"
  CHECK_ROLLBACK="$3" CHECK_OUTCOME="$4" EXTRA_OUTCOME="$5" GITHUB_OUTPUT="$TMP/out" bash "$TMP/decide.sh" >/dev/null
  got="$(cat "$TMP/out")"
  if [ "$got" = "rollback=$2" ]; then echo "ok   $1"; else echo "FAIL $1: expected rollback=$2 got '$got'"; fail=1; fi
}
check normal-no-extra      false false success skipped
check normal-with-extra    false false success success
check health-fail          true  true  failure skipped
check extra-fail           true  false success failure
check check-crashed        true  ""    failure skipped
exit $fail
