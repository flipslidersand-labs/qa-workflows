---
title: "YAML の description に未クォートのコロン+スペースがあるとパース不能になる"
tags: [yaml, github-actions, tooling]
severity: high
date: "2026-09-11"
---

## 症状

`smoke-test.yml` の `service-url` input:

```yaml
description: ヘルスチェック対象のベース URL（例: https://api.example.com）
```

見た目は正常な1行に見えるが、実際は不正な YAML。GitHub Actions 上ではエラーメッセージが
分かりにくい形で workflow_call の解決に失敗する。手動でのコードレビューでは全く気づけなかった
（構文的には自然な日本語の説明文にしか見えない）。

## 原因

YAML の plain scalar（クォート無しの値）内で `: `（コロン+半角スペース）が現れると、
そこがマッピングのキー区切りとして解釈される。`例: https://...` の `例:` の直後の
スペースがこれに該当し、パーサーが「新しいキーが始まった」と誤認してエラーになる。
全角コロン（：）や、コロンの直後にスペースが無い場合（例: `PATH:EXPECTED_STATUS`）は
問題にならないため、同じファイル内の他の description は正常だった。

## 解決策

該当行をダブルクォートで囲む:

```yaml
description: "ヘルスチェック対象のベース URL（例: https://api.example.com）"
```

## 予防

- workflow YAML を編集したら `python3 -c "import yaml; yaml.safe_load(open('<file>'))"` で
  必ず構文検証する。手動レビューだけでは見逃す。
- 複数ファイルを一括変更した後は、全ファイルをループで検証する:
  ```bash
  for f in .github/workflows/*.yml; do
    python3 -c "import yaml; yaml.safe_load(open('$f'))" 2>/dev/null || echo "FAIL: $f"
  done
  ```
- description に「例: 」のような日本語の説明パターンを書くときは、コロンの前後に
  半角スペースが入る箇所がないか意識するか、迷ったら常にダブルクォートで囲む。
