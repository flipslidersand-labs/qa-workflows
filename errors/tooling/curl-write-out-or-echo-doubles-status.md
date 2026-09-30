---
title: "curl -w '%{http_code}' ... || echo 000 が接続失敗時に 000000 になる"
tags: [bash, curl, github-actions]
severity: low
date: "2026-10-01"
---

## 症状

smoke-test で到達できない URL に接続したとき、ログと `status-code` output が `HTTP 000000` になった（#49）。

## 原因

curl は接続に失敗しても、`-w "%{http_code}"` で `000` を**出力してから**非0で終了する。そのため `$(curl ... || echo "000")` は `000` と `000` を連結した値になる。

```bash
$ echo "[$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:9 || echo 000)]"
[000000]
```

## 解決策

終了コードを無視するだけにする: `$(curl -s -o /dev/null -w '%{http_code}' "$URL" || true)`。`-w` が常に3桁を出すので、フォールバック値は要らない。

## 予防

- `-w` で値を取るときは `|| echo <default>` を付けない
- 失敗パスも一度は実際に通して確認する（今回は `workflow_dispatch` で `service-url=http://127.0.0.1:9` を渡して確認した）
