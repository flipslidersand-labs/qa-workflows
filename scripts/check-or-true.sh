#!/usr/bin/env bash
# workflow 内の `|| true`(失敗の握りつぶし = 偽の緑の温床)を検出する (#116)。
# 許容する箇所は、同じ行の末尾に `# allow-true: 理由` を書く(理由必須)。
# 使い方: check-or-true.sh [file...]   省略時は .github/workflows/*.yml
# 終了コード: 0=違反なし / 1=許容印の無い `|| true` あり
set -u
if [ "$#" -eq 0 ]; then set -- .github/workflows/*.yml; fi
# `|| true` の後ろが語境界(`|| trueish` は対象外)。コメント行そのものは除外。
hits=$(grep -nHE '\|\|[[:space:]]*'"'?"'true([^[:alnum:]_-]|$)' -- "$@" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)
bad=$(printf '%s\n' "$hits" | grep -vE '# allow-true: *[^[:space:]]' | grep -v '^$' || true)
if [ -n "$bad" ]; then
  echo "::error::'|| true' に allow-true の理由が無い(失敗の握りつぶしを避けるか、行末に '# allow-true: 理由' を書く):"
  printf '%s\n' "$bad"
  exit 1
fi
echo "ok: '|| true' の無許可箇所なし ($(printf '%s\n' "$hits" | grep -c . ) 件は allow-true 付き)"
