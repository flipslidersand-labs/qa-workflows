#!/usr/bin/env bash
# zizmor を限定設定(zizmor.yml)・オフラインで実行する (#116)。
# 使い方: run-zizmor.sh [path...]  省略時は .github/workflows
# zizmor 本体は PATH 上のものを使う(CI は lint.yml で pip の ==1.31.1 固定で入れる)。
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ "$#" -gt 0 ] || set -- "$ROOT/.github/workflows"
exec zizmor --offline --no-progress --config "$ROOT/zizmor.yml" --min-severity medium --format plain -q "$@"
