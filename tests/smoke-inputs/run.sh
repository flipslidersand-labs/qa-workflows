#!/usr/bin/env bash
# smoke-test.yml の workflow_call と workflow_dispatch の inputs が同一であることを検査する (#89)
# GitHub Actions は inputs の共有(YAML anchor / 参照)ができず二重定義が構造上残るため、ドリフトをここで検出する。
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
YML="$ROOT/.github/workflows/smoke-test.yml"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
# 各トリガ直下の inputs: ブロック(インデント4の "inputs:" から、インデント4以下の次の行まで)を抜き出す
extract() { # trigger
  awk -v t="  $1:" '
    $0 == t {in_t=1; next}
    in_t && /^  [^ ]/ {in_t=0; f=0}
    in_t && /^[^ ]/ {in_t=0; f=0}
    in_t && $0 == "    inputs:" {f=1; next}
    in_t && f && /^    [^ ]/ {f=0}
    in_t && f {print}
  ' "$YML"
}
extract workflow_call > "$TMP/call"
extract workflow_dispatch > "$TMP/dispatch"
[ -s "$TMP/call" ] && [ -s "$TMP/dispatch" ] || { echo "FAIL: inputs ブロックが見つからない"; exit 1; }
if diff -u "$TMP/call" "$TMP/dispatch"; then
  echo "ok   workflow_call / workflow_dispatch の inputs は一致"
else
  echo "FAIL: inputs が workflow_call と workflow_dispatch でずれている(両方を同じに保つこと)"; exit 1
fi
