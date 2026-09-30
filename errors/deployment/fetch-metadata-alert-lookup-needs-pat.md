---
title: "dependabot/fetch-metadata の alert-state/ghsa-id は github.token では常に空（セキュリティ除外が無言で効かない）"
tags: [github-actions, dependabot, security]
severity: high
date: "2026-10-01"
---

## 症状

`dependabot-auto-merge.yml`（#39 のレビュー時点）は `steps.metadata.outputs.alert-state` を見て、セキュリティ更新を auto-merge から外すつもりだった。しかしこの条件は一度も true にならず、security の patch 更新もそのまま `gh pr merge --auto` されていた。エラーは出ないので気づけない。

## 原因

- `alert-state` / `ghsa-id` / `cvss` は `alert-lookup: true` のときにしか値が入らない
- `alert-lookup` には PAT か App トークン（`Dependabot alerts: Read only`）が必要で、`github.token` では動かない
- 条件にあった `AUTO_DISMISSED` は実在しない値だった（実際の値は `OPEN` / `FIXED` / `DISMISSED`）
- patch step 側にセキュリティ除外の条件が無く、ラベル付与と auto-merge が両方実行されていた

## 解決策

- 任意の secret `alert-token` を追加し、`alert-lookup: ${{ secrets.alert-token != '' }}` と `github-token: ${{ secrets.alert-token || github.token }}` を渡す
- 独立した step で `ghsa-id` の有無（と dependency-group 名）からセキュリティ更新かを判定し、patch/minor の step 全部を `is-security != 'true'` で守る
- Dependabot が起動した run からは **Dependabot secrets** しか見えないので、登録先は Actions secrets ではなく Dependabot secrets にする

## 予防

- 「除外」のための条件は、除外される側の step にも書く（ラベル付与だけの step で満足しない）
- action の output を条件に使う前に、その output がどの input・どの権限で値を持つかを README で確認する
