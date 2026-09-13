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
| `gitleaks.yml` | シークレット静的スキャン(gitleaks OSS CLI) |
| `trivy-scan.yml` | 脆弱性/設定ミススキャン(trivy) + Code Scanning SARIF連携 |
| `dependabot-auto-merge.yml` | Dependabot PRのtriage(patch即マージ/minor待機ラベル/major・security手動レビュー) |
| `dependabot-auto-merge-minor.yml` | minor待機ラベルのPRを24h経過後にauto-merge昇格(cron) |

## api-e2e の使い方

`qa-platform`（k6 シナリオの取得元）は private リポのため、caller のデフォルト
`GITHUB_TOKEN` ではチェックアウトできない。qa-platform への read アクセス権を持つ
PAT を `QA_PLATFORM_TOKEN` として渡す。

```yaml
jobs:
  api-e2e:
    uses: flipslidersand-labs/qa-workflows/.github/workflows/api-e2e.yml@main
    secrets:
      QA_PLATFORM_TOKEN: ${{ secrets.QA_PLATFORM_TOKEN }}
```

## gitleaks の使い方

呼び出し側で `permissions: contents: read` を明記する（reusable workflow 側に
job-level permissions を持たせて呼び出し元の permissions を上書きし、
startup_failure を招いた過去の事故を避けるため）。

```yaml
jobs:
  gitleaks:
    permissions:
      contents: read
    uses: flipslidersand-labs/qa-workflows/.github/workflows/gitleaks.yml@main
```

## trivy-scan の使い方

`pre-deploy.yml` の `audit-type: trivy` は build 済みイメージの軽量な fs スキャン（table出力のみ）。
`trivy-scan.yml` はそれとは別に、misconfig 検出と GitHub Security タブへの SARIF 連携、
および任意のイメージスキャンを行う独立ワークフロー。secret はスキャンしない（`gitleaks.yml` に一任）。

SARIF アップロード（Code Scanning 連携）を機能させたい場合、呼び出し側で
`permissions: security-events: write` を明示する（未宣言でも fs/misconfig ゲート自体は動作し、
SARIF アップロードのみ soft-fail する）。

```yaml
jobs:
  trivy:
    permissions:
      security-events: write
    uses: flipslidersand-labs/qa-workflows/.github/workflows/trivy-scan.yml@main
    with:
      severity: "CRITICAL,HIGH"
      scan-image: true
      image-ref: "myapp:${{ github.sha }}"
```

## dependabot-auto-merge の使い方

PRをマージするため `contents: write` + `pull-requests: write` が必須。gitleaksと同様の理由で
reusable workflow 側に job-level permissions を持たせていないため、**caller が明示的に
両方の permissions を宣言すること**（未宣言のまま呼ぶと権限不足でマージ操作が失敗する）。

```yaml
# .github/workflows/dependabot-auto-merge.yml (caller)
name: Dependabot Auto-merge
on:
  pull_request:
    types: [opened, synchronize, reopened]
permissions:
  contents: write
  pull-requests: write
jobs:
  triage:
    if: github.actor == 'dependabot[bot]'
    uses: flipslidersand-labs/qa-workflows/.github/workflows/dependabot-auto-merge.yml@main
```

```yaml
# .github/workflows/dependabot-auto-merge-minor.yml (caller)
name: Dependabot Auto-merge (minor, 24h wait)
on:
  schedule:
    - cron: "0 * * * *"
  workflow_dispatch: {}
permissions:
  contents: write
  pull-requests: write
jobs:
  promote:
    uses: flipslidersand-labs/qa-workflows/.github/workflows/dependabot-auto-merge-minor.yml@main
```

各リポの `.github/dependabot.yml` 自体(package-ecosystem設定)はこれまで通り個別管理。

## runner 選択

`go-test` / `python-test` は runner input 未指定なら `vars.GATE_RUNNER` → `ubuntu-latest` の順に自動採用。
public リポは GitHub-hosted が無料のため通常 `ubuntu-latest`（`runner: ubuntu-latest` 明示 or GATE_RUNNER 未設定）。
