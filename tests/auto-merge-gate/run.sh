#!/usr/bin/env bash
# dependabot-auto-merge-minor.yml の GATE_JQ（マージ判定）を固定データでテストする。
# 判定本体はワークフローから直接取り出す（テストした物 = 動く物）。
# 実行: bash tests/auto-merge-gate/run.sh   （要 jq）
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
wf="$here/../../.github/workflows/dependabot-auto-merge-minor.yml"

# <<'JQ' の次の行から、単独行の JQ まで
GATE_JQ="$(awk '/<<.JQ. \|\| true/{f=1; next} f && /^[[:space:]]*JQ[[:space:]]*$/{exit} f' "$wf")"
[ -n "$GATE_JQ" ] || { echo "GATE_JQ をワークフローから取り出せない" >&2; exit 2; }

NOW="$(date -u -d '2030-01-01T00:00:00Z' +%s)"
fail=0

# check <名前> <期待 decision> <wait時間> <JSON>
check() {
  local name="$1" expect="$2" wait="$3" json="$4" got
  # 本番は gh の内蔵 jq(--jq) で動かす。ここでは同じプログラムを jq で評価する（出力は TSV 1 行）
  got="$(GATE_NOW="$NOW" GATE_WAIT="$wait" jq -r "$GATE_JQ" <<<"$json" | cut -f1)"
  if [ "$got" = "$expect" ]; then
    printf 'ok   %-44s %s\n' "$name" "$got"
  else
    printf 'FAIL %-44s expected=%s got=%s\n' "$name" "$expect" "$got"
    fail=1
  fi
}

# --- 実 PR（dataguard-rail。fixtures/ は gh pr view の出力そのもの）---
# 赤: テスト fail のまま自動マージされた PR。必ず red でなければならない
for n in 191 193 208 150; do
  check "real dataguard-rail #$n (テスト fail)" red 0 "$(cat "$here/fixtures/real-dgr-$n.json")"
done
# 緑: マージ済み PR には mergeable が無い(UNKNOWN)ので MERGEABLE を与えて判定する
check "real dataguard-rail #200 (全成功)" merge 0 \
  "$(jq '.mergeable = "MERGEABLE"' "$here/fixtures/real-dgr-200-green.json")"

# --- 合成データ（境界）---
base='"createdAt":"2029-12-01T00:00:00Z","labels":[],"mergeable":"MERGEABLE"'
ok='{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS"}'
skipped='{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SKIPPED"}'
neutral='{"__typename":"CheckRun","status":"COMPLETED","conclusion":"NEUTRAL"}'
ng='{"__typename":"CheckRun","status":"COMPLETED","conclusion":"FAILURE"}'
cancelled='{"__typename":"CheckRun","status":"COMPLETED","conclusion":"CANCELLED"}'
running='{"__typename":"CheckRun","status":"IN_PROGRESS","conclusion":null}'
ctx_ok='{"__typename":"StatusContext","state":"SUCCESS"}'
ctx_ng='{"__typename":"StatusContext","state":"FAILURE"}'
ctx_wait='{"__typename":"StatusContext","state":"PENDING"}'

check "全成功 + SKIPPED + NEUTRAL"                 merge 0  "{$base,\"statusCheckRollup\":[$ok,$skipped,$neutral]}"
check "1件 FAILURE (他は成功)"                       red   0  "{$base,\"statusCheckRollup\":[$ok,$ng]}"
check "CANCELLED は成功扱いにしない"                 red   0  "{$base,\"statusCheckRollup\":[$ok,$cancelled]}"
check "実行中が残っている"                           wait  0  "{$base,\"statusCheckRollup\":[$ok,$running]}"
check "赤と実行中が混在 → 赤を優先"                  red   0  "{$base,\"statusCheckRollup\":[$ng,$running]}"
check "チェックが 0 件 (偽の緑にしない)"             wait  0  "{$base,\"statusCheckRollup\":[]}"
check "statusCheckRollup が null"                    wait  0  "{$base,\"statusCheckRollup\":null}"
check "StatusContext 成功"                           merge 0  "{$base,\"statusCheckRollup\":[$ctx_ok]}"
check "StatusContext 失敗"                           red   0  "{$base,\"statusCheckRollup\":[$ctx_ng]}"
check "StatusContext 保留"                           wait  0  "{$base,\"statusCheckRollup\":[$ctx_wait]}"
check "緑でも待機時間 24h 未満 (minor)"              wait  24 "{\"createdAt\":\"2029-12-31T12:00:00Z\",\"labels\":[],\"mergeable\":\"MERGEABLE\",\"statusCheckRollup\":[$ok]}"
check "緑 + 24h 経過 (minor)"                        merge 24 "{$base,\"statusCheckRollup\":[$ok]}"
check "緑でも conflict"                              skip  0  "{\"createdAt\":\"2029-12-01T00:00:00Z\",\"labels\":[],\"mergeable\":\"CONFLICTING\",\"statusCheckRollup\":[$ok]}"
check "緑でも mergeable=UNKNOWN"                     wait  0  "{\"createdAt\":\"2029-12-01T00:00:00Z\",\"labels\":[],\"mergeable\":\"UNKNOWN\",\"statusCheckRollup\":[$ok]}"

# strict 保護: 緑・MERGEABLE でも base より遅れている PR は直接マージできない
mk() { echo "{\"createdAt\":\"2029-12-01T00:00:00Z\",\"labels\":[],\"mergeable\":\"MERGEABLE\",\"mergeStateStatus\":\"$1\",\"statusCheckRollup\":$2}"; }
check "緑 + BEHIND → behind(マージしない)"          behind 0 "$(mk BEHIND "[$ok]")"
check "緑 + CLEAN → merge"                           merge  0 "$(mk CLEAN "[$ok]")"
check "赤 + BEHIND → 赤を優先"                       red    0 "$(mk BEHIND "[$ng]")"
check "実行中 + BEHIND → wait"                       wait   0 "$(mk BEHIND "[$running]")"
check "緑 + BEHIND でも待機時間未満 → wait"          wait   24 "{\"createdAt\":\"2029-12-31T12:00:00Z\",\"labels\":[],\"mergeable\":\"MERGEABLE\",\"mergeStateStatus\":\"BEHIND\",\"statusCheckRollup\":[$ok]}"
check "conflict + BEHIND → skip"                     skip   0 "{\"createdAt\":\"2029-12-01T00:00:00Z\",\"labels\":[],\"mergeable\":\"CONFLICTING\",\"mergeStateStatus\":\"DIRTY\",\"statusCheckRollup\":[$ok]}"

if [ "$fail" -ne 0 ]; then
  echo "失敗あり" >&2
  exit 1
fi
echo "全て通過"
