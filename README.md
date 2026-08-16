# qa-workflows

flipslidersand-labs 共通の **reusable GitHub Actions workflows**（public source）。

private の [qa-platform](https://github.com/flipslidersand-labs/qa-platform) は eval データセット等を含むため private のまま。
**public リポからは private リポの reusable workflow を呼び出せない**（GitHub 制約）ため、
workflow YAML のみを本 public リポに分離し、public / private 双方から呼び出せるようにする。

## 使い方

```yaml
jobs:
  test:
    uses: flipslidersand-labs/qa-workflows/.github/workflows/go-test.yml@main
    with:
      go-version: "1.25"
      coverage-threshold: 60
```

各 workflow の input 仕様は qa-platform の `docs/reusable-workflows.md` を参照。

## 提供 workflow

| ファイル | 内容 |
|----------|------|
| `go-test.yml` | Go test + vet + build + coverage |
| `python-test.yml` | pytest + coverage |
| `e2e-playwright.yml` | Playwright E2E |
| `api-e2e.yml` | API E2E |
| `ai-review.yml` | Claude AI レビュー |
| `pre-deploy.yml` | Docker build + 脆弱性スキャン + migration dry-run |
| `smoke-test.yml` | デプロイ後ヘルスチェック |
| `coverage-report.yml` | カバレッジ集計 |
| `eval-regression.yml` | RAG/LLM 評価回帰 |

## runner 選択

`go-test` / `python-test` は runner input 未指定なら `vars.GATE_RUNNER` → `ubuntu-latest` の順に自動採用。
public リポは GitHub-hosted が無料のため通常 `ubuntu-latest`（`runner: ubuntu-latest` 明示 or GATE_RUNNER 未設定）。
