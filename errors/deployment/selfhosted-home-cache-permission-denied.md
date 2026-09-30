---
title: "self-hosted(linux-general) で ~/.cache 配下が permission denied（go-build / corepack）"
tags: [github-actions, self-hosted, arc, go, node]
severity: medium
date: "2026-10-01"
---

## 症状

- `setup-go` の後: `failed to initialize build cache at /home/runner/.cache/go-build: mkdir /home/runner/.cache/go-build: permission denied`（#50、週次 coverage-report が連続失敗）
- `corepack enable` / pnpm install: `EACCES: permission denied, mkdir '/home/runner/.cache/node/corepack/v1'`（#44）

## 原因

runner の `/home/runner/.cache` が、runner の実行ユーザー以外（root で動いた別ジョブなど）の所有になっていて書き込めない。ツールごとに症状は違うが、原因は同じ。

## 解決策

ワークフロー側で `~/.cache` に依存しない場所へ逃がす。

```yaml
- run: |
    echo "COREPACK_HOME=$RUNNER_TEMP/corepack" >> "$GITHUB_ENV"
    export COREPACK_HOME="$RUNNER_TEMP/corepack"
    corepack enable
```

Go なら `GOCACHE=$RUNNER_TEMP/go-build`、汎用には `XDG_CACHE_HOME=$RUNNER_TEMP/.cache` も使える。job-level の `env:` では `runner` context が使えないため、`$GITHUB_ENV` 経由で設定する。

## 予防

- reusable workflow が `~/.cache` にキャッシュを書くツールを使う場合は、最初から `$RUNNER_TEMP` 配下に向けておく
- runner イメージ側の恒久対応（所有権の修正）は dev-infrastructure の管轄
