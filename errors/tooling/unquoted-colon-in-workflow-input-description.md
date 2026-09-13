---
title: "workflow_call の input description にコロン付き文字列を書くとYAML構文エラーでpush毎に即失敗する"
tags: [github-actions, yaml, workflow-call]
severity: high
date: "2026-09-13"
---

## 症状

`.github/workflows/smoke-test.yml` を含むpushが、内容に関係なく毎回 "likely failed because of a workflow file issue" として即失敗する。`gh run view --json jobs` は `{"jobs":[]}`(ジョブが1つも起動していない)。CI Health Reportでこのリポジトリの成功率が0%になっていた。

## 原因

`inputs.<name>.description` にコロンを含む文字列を未クォートで書いていた:

```yaml
extra-checks:
  description: 追加チェック URL（改行区切り PATH:EXPECTED_STATUS）
```

YAMLパーサは `key: value` のコロン+空白をマッピング区切りとして解釈するため、`description`の値の途中に`: `相当のパターンがあるとワークフロー全体がパース不能になり、ジョブが1つも起動しないままrunだけ失敗扱いになる。

## 解決策

コロンを含む文字列値は必ずダブルクォートで囲む:

```yaml
extra-checks:
  description: "追加チェック URL（改行区切り PATH:EXPECTED_STATUS）"
```

## 予防

- `description:` に限らず、YAMLの値にコロン・ハッシュ・特殊文字を含める場合は常にクォートする
- コミット前に `python3 -c "import yaml; yaml.safe_load(open('file.yml'))"` または `actionlint` でローカル検証してからpushする
- このパターンは `jobs:[]`(ジョブが1件も起動しない)+ "workflow file issue" というエラーメッセージが特徴的なシグナルなので、他のCI失敗(依存関係・テスト失敗等)と区別しやすい
