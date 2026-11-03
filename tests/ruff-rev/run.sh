#!/usr/bin/env bash
# python-test.yml の ruff rev 抜き出し部(BEGIN/END ruff-rev-extract 区間)を取り出して検証する (#96)
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
YML="$ROOT/.github/workflows/python-test.yml"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
# 区間内の python ヒアドキュメント本体(インデント10を除去)
awk '/^ *PY$/{f=0} f{sub(/^          /,""); print} /<<.PY.$/{f=1}' "$YML" > "$TMP/extract.py"
[ -s "$TMP/extract.py" ] || { echo "FAIL: 抜き出しロジックが見つからない"; exit 1; }
fail=0
check() { # name expected config-content
  printf '%s' "$3" > "$TMP/cfg.yaml"
  got="$(python3 "$TMP/extract.py" "$TMP/cfg.yaml")"
  if [ "$got" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1: expected '$2' got '$got'"; fail=1; fi
}
check normal "0.16.10" $'repos:\n  - repo: https://github.com/astral-sh/ruff-pre-commit\n    rev: v0.16.10\n    hooks:\n      - id: ruff\n'
check quoted-comment "0.15.18" $'repos:\n- repo: https://github.com/astral-sh/ruff-pre-commit\n  rev: "v0.15.18"  # pin\n'
check no-v "0.6.9" $'repos:\n  - repo: https://github.com/astral-sh/ruff-pre-commit\n    rev: 0.6.9\n'
check no-ruff "" $'repos:\n  - repo: https://github.com/pre-commit/pre-commit-hooks\n    rev: v4.6.0\n    hooks:\n      - id: end-of-file-fixer\n'
check empty-file "" ""
check mixed-ruff-last "0.16.10" $'repos:\n  - repo: https://github.com/pre-commit/pre-commit-hooks\n    rev: v4.6.0\n  - repo: https://github.com/gitleaks/gitleaks\n    rev: v8.18.0\n  - repo: https://github.com/astral-sh/ruff-pre-commit\n    rev: v0.16.10\n'
check mixed-ruff-first "0.16.10" $'repos:\n  - repo: https://github.com/astral-sh/ruff-pre-commit\n    rev: v0.16.10\n  - repo: https://github.com/pre-commit/pre-commit-hooks\n    rev: v4.6.0\n'
check ruff-no-rev-then-other "" $'repos:\n  - repo: https://github.com/astral-sh/ruff-pre-commit\n    hooks:\n      - id: ruff\n  - repo: https://github.com/pre-commit/pre-commit-hooks\n    rev: v4.6.0\n'
exit $fail
