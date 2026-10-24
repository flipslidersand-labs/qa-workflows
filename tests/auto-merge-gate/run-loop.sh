#!/usr/bin/env bash
# promoter のステップ全体(ループ・ラベル操作・マージ呼び出し)を、gh を差し替えてテストする。
# 判定そのものは run.sh。ここでは「判定 → 正しい gh コマンドが呼ばれるか」を見る。
# 実行: bash tests/auto-merge-gate/run-loop.sh   （要 jq, awk）
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
wf="$here/../../.github/workflows/dependabot-auto-merge-minor.yml"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# ステップの run: ブロックを取り出す（このファイルの唯一のステップで、末尾にある前提）。
# 取り出せなければ、テストが空振りしないよう失敗させる。
awk '/^        run: \|$/{f=1; next} f{sub(/^          /,""); print}' "$wf" > "$tmp/step.sh"
[ -s "$tmp/step.sh" ] && grep -q 'GATE_JQ' "$tmp/step.sh" || { echo "ステップを取り出せない" >&2; exit 2; }

# 偽 gh: pr list は PR 番号 7 を返し、pr view は \$SCEN_JSON を --jq で処理して返す。
# 書き込み系(label create / pr merge / pr edit)は呼び出しをログに残すだけ。
mkdir "$tmp/bin"
cat > "$tmp/bin/gh" <<'SH'
#!/usr/bin/env bash
echo "gh $*" >> "$GH_LOG"
case "$1 $2" in
  "pr list")  if [[ " $* " == *"dependabot/${LIST_KIND}-pending"* ]]; then echo 7; fi ;;
  "pr view")  prog=""; while [ $# -gt 0 ]; do [ "$1" = "--jq" ] && prog="$2"; shift; done
              jq -r "$prog" <<<"$SCEN_JSON" ;;
  "pr merge") [ "${MERGE_FAIL:-0}" = 1 ] && exit 1 || exit 0 ;;
esac
SH
chmod +x "$tmp/bin/gh"

fail=0
# scenario <名前> <kind> <JSON> <期待するログ(grep -E)> <出てはいけないログ(grep -E, 空可)> [MERGE_FAIL]
scenario() {
  local name="$1" kind="$2" json="$3" must="$4" mustnot="$5" mf="${6:-0}"
  : > "$tmp/log"
  PATH="$tmp/bin:$PATH" GH_LOG="$tmp/log" LIST_KIND="$kind" SCEN_JSON="$json" MERGE_FAIL="$mf" \
    GITHUB_REPOSITORY=o/r GH_TOKEN=x DRY_RUN=false bash "$tmp/step.sh" >/dev/null 2>&1 || true
  local ok=1
  grep -qE "$must" "$tmp/log" || ok=0
  if [ -n "$mustnot" ] && grep -qE "$mustnot" "$tmp/log"; then ok=0; fi
  if [ "$ok" = 1 ]; then printf 'ok   %s\n' "$name"; else printf 'FAIL %s\n--- log\n%s\n---\n' "$name" "$(cat "$tmp/log")"; fail=1; fi
}

old='"createdAt":"2020-01-01T00:00:00Z"'
ok='{"status":"COMPLETED","conclusion":"SUCCESS"}'
ng='{"status":"COMPLETED","conclusion":"FAILURE"}'
run='{"status":"IN_PROGRESS","conclusion":null}'
j() { echo "{$old,\"labels\":$2,\"mergeable\":\"MERGEABLE\",\"statusCheckRollup\":$1}"; }

scenario "緑 patch → squash マージ(--auto なし) + promoted ラベル" patch "$(j "[$ok]" '[]')" \
  'pr merge 7 --repo o/r --squash' 'pr merge .*--auto'
scenario "緑 patch → pending を外し promoted を付ける" patch "$(j "[$ok]" '[]')" \
  'remove-label dependabot/patch-pending.*add-label dependabot/patch-promoted' ''
scenario "赤 → ci-red を付け、マージしない" minor "$(j "[$ok,$ng]" '[]')" \
  'add-label dependabot/ci-red' 'pr merge'
scenario "赤 + すでに ci-red → 二重に付けない" minor "$(j "[$ng]" '[{"name":"dependabot/ci-red"}]')" \
  'pr view 7' 'add-label|pr merge'
scenario "実行中 → 何もしない" patch "$(j "[$ok,$run]" '[]')" \
  'pr view 7' 'pr merge|pr edit'
scenario "緑に戻った → ci-red を外してマージ" patch "$(j "[$ok]" '[{"name":"dependabot/ci-red"}]')" \
  'pr merge 7' ''
scenario "待機中で ci-red が残っている → 外す" patch "$(j "[$ok,$run]" '[{"name":"dependabot/ci-red"}]')" \
  'remove-label dependabot/ci-red' 'pr merge'
scenario "マージ失敗 → ラベルを触らない(次回再判定)" patch "$(j "[$ok]" '[]')" \
  'pr merge 7' 'pr edit' 1
scenario "チェック 0 件 → マージしない(偽の緑にしない)" patch "$(j '[]' '[]')" \
  'pr view 7' 'pr merge'

# dry-run は書き込み系を一切呼ばない
: > "$tmp/log"
PATH="$tmp/bin:$PATH" GH_LOG="$tmp/log" LIST_KIND=patch SCEN_JSON="$(j "[$ok]" '[]')" \
  GITHUB_REPOSITORY=o/r GH_TOKEN=x DRY_RUN=true bash "$tmp/step.sh" >/dev/null 2>&1 || true
if grep -qE 'pr merge|pr edit|label create' "$tmp/log"; then
  printf 'FAIL dry-run が書き込み系を呼んだ\n%s\n' "$(cat "$tmp/log")"; fail=1
else
  echo "ok   dry-run は書き込み系を呼ばない"
fi

[ "$fail" -eq 0 ] && echo "全て通過" || { echo "失敗あり" >&2; exit 1; }
