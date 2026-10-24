---
title: "reusable workflow を feature ブランチの SHA で pin すると squash merge + ブランチ削除後に startup_failure になる"
tags: [github-actions, reusable-workflow, dependabot]
severity: high
date: "2026-10-03"
---

## 症状

dataguard-rail の `dependabot-auto-merge-minor.yml` が 27 回連続で失敗。run は job 実行前の "workflow file issue"（startup_failure）で落ち、ログも残らない。

## 原因

caller が `uses: .../qa-workflows/.github/workflows/<name>.yml@<SHA>` で、qa-workflows の PR#39 の **squash 前** feature ブランチ上のコミット SHA を pin していた。squash merge + ブランチ削除で、その SHA は default ブランチの履歴から到達不能になり、参照解決に失敗した。

## 解決策

- main から到達可能な（squash 後の）コミット SHA に pin し直す（dataguard-rail PR#196）
- 確認: `gh api repos/<owner>/<repo>/compare/main...<sha> --jq .status` が `behind`/`identical` なら到達可能、`diverged` なら到達不能

## 予防

- pin する SHA は PR マージ後に `git log main` から取る。PR ブランチ上の SHA を使わない
- 全 caller の pin を定期的に compare API で検証する（qa-workflows-audit の対象に追加余地あり）
