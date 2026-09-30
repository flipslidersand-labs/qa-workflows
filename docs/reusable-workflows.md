# Reusable Workflows — input 仕様

各リポの `.github/workflows/*.yml` から `uses:` で呼び出す共通 workflow の **input / secret 仕様の正本**。
実際の定義は `.github/workflows/<name>.yml` の `on.workflow_call` で、食い違いがあれば YAML が正。
呼び出し方の例・permissions・落とし穴は [README](../README.md) と [errors/](../errors/) を参照。

```yaml
jobs:
  test:
    uses: flipslidersand-labs/qa-workflows/.github/workflows/go-test.yml@main
    with:
      coverage-threshold: 60
```

## 共通事項

- **runner**: `runner` input は既定で空。空なら `vars.GATE_RUNNER` → `ubuntu-latest` の順に reusable 側で解決する。
  caller の `with:` で `vars` を参照すると workflow 解決に失敗するため、caller は `runner` を通常渡さない。
- **permissions**: reusable 側は job-level permissions を持たない workflow が多い（caller の権限を上書きして
  `startup_failure` になる事故の再発防止）。必要な permissions は README の各節を参照し、caller で明示する。
- **`token` secret**（go-test / python-test / rust-test / node-test）: 任意。GitHub token が別途必要な場合のみ渡す。
- 以下の表の「既定」は `default` 値。「必須」は `required: true`。

## テスト系

### go-test

| input | 既定 | 説明 |
|---|---|---|
| `go-version` | `1.23` | Go バージョン |
| `coverage-threshold` | `60` | 最低カバレッジ（%）。vet/build/test 全パッケージ総計で gate |
| `test-flags` | `-race -timeout 60s` | go test フラグ |
| `working-directory` | `.` | 実行ディレクトリ |
| `runner` | `""` | 共通事項を参照 |
| `run-vet` | `true` | `go vet ./...` |
| `run-build` | `true` | `go build ./...` |

生成コードを除外するオプションは無い。除外していたリポは、生成コード込みの実測に閾値を合わせ直すこと。

### python-test

clean な `pip install -e ".[dev]"` の後に ruff（`check` と `format --check`）と pytest を実行する。
**pytest-cov を dev extras に宣言必須**。ruff は既定で最新版が入るため、ローカルより厳しくなる（`ruff-version` で固定可）。

| input | 既定 | 説明 |
|---|---|---|
| `python-version` | `3.12` | Python バージョン |
| `coverage-threshold` | `60` | 最低カバレッジ（%）。`--cov=.` の実測で決める |
| `working-directory` | `.` | 実行ディレクトリ |
| `test-path` | `tests/` | pytest 対象パス |
| `install-extras` | `dev` | pip extras |
| `install-command` | `""` | 依存インストールを置換（例: pyproject 無しで `requirements.txt` を使う場合） |
| `pre-install` | `""` | pip install 前に実行するコマンド（例: torch CPU index の先入れ） |
| `pytest-args` | `""` | pytest への追加引数（例: `-k "not gpu"`） |
| `run-tests` | `true` | false で lint / format のみ実行 |
| `run-lint` | `true` | ruff を実行するか |
| `ruff-version` | `""` | 空なら最新。固定したい場合に指定 |
| `runner` | `""` | 共通事項を参照 |

torch(GPU) / JVM(Spark) など重いランタイム依存を pytest 前に要するリポは、標準の固定ステップに載らないため対象外。

### rust-test

fmt + clippy + test（`run-coverage` で cargo-llvm-cov による coverage gate）。

| input | 既定 | 説明 |
|---|---|---|
| `rust-version` | `stable` | toolchain（stable / 1.xx / nightly） |
| `coverage-threshold` | `60` | 最低カバレッジ（%）。`run-coverage=true` 時に gate |
| `test-args` | `--workspace` | cargo test / llvm-cov のスコープ（例 `-p foo -p bar`） |
| `clippy-args` | `--workspace --all-targets` | cargo clippy のスコープ |
| `clippy-deny` | `warnings` | clippy で `-D` する lint |
| `working-directory` | `.` | 実行ディレクトリ |
| `runner` | `""` | 共通事項を参照 |
| `system-deps` | `""` | 事前に `apt-get install` するパッケージ（空でスキップ） |
| `rust-targets` | `""` | 追加で入れる rustup target |
| `pre-install` | `""` | ビルド前に実行するコマンド |
| `run-fmt` | `true` | `cargo fmt --check` |
| `run-clippy` | `true` | `cargo clippy` |
| `run-tests` | `true` | テスト実行 |
| `run-coverage` | `true` | `cargo-llvm-cov` で計測・gate（false なら `cargo test` のみ） |

eBPF / Wasm component 等の特殊ビルドは `test-args` で対象から外し、専用 job で別途担保する。
self-hosted（linux-general）では `~/.cargo/bin` の権限エラーを避けるため `runner: ubuntu-latest` を指定する場合がある。

### node-test

install → lint → build → test。lint / build / test は package.json の script 有無を判定してから実行し、
**該当 script が無ければ自動 skip** する。coverage 閾値は test runner 側の設定で担保する（input は無い）。

| input | 既定 | 説明 |
|---|---|---|
| `node-version` | `20` | Node バージョン |
| `package-manager` | `npm` | `npm` / `pnpm` / `yarn`（pnpm・yarn は corepack で有効化） |
| `working-directory` | `.` | 実行ディレクトリ |
| `install-command` | `""` | 依存インストール。空なら package manager から自動導出 |
| `lint-script` | `lint` | lint の script 名 |
| `build-script` | `build` | build の script 名 |
| `test-script` | `test` | test の script 名（coverage は `test:coverage` 等を渡す） |
| `run-lint` | `true` | lint を実行するか |
| `run-build` | `true` | build を実行するか |
| `run-test` | `true` | test を実行するか |
| `runner` | `""` | 共通事項を参照 |

## レビュー・静的解析

### ai-review

PR の diff を Vertex AI（Workload Identity Federation 認証）でレビューし、PR コメントを投稿する。
`vars.WIF_PROVIDER` が未設定なら認証を skip する（ゲートはブロックしない）。secret の受け渡しは不要。
リポ変数: `WIF_PROVIDER` / `WIF_SA` / `VERTEX_PROJECT` / `VERTEX_REGION`。caller は `id-token: write` と `pull-requests: write` を宣言する。

| input | 既定 | 説明 |
|---|---|---|
| `model` | `claude-haiku-4-5@20251001` | 使用モデル（Vertex 形式） |
| `max-diff-lines` | `500` | 最大 diff 行数 |
| `fail-on-high` | `false` | HIGH 指摘で失敗にするか |
| `ignore-paths` | `*.lock,*.sum,*.pb.go,*_generated.go` | 除外パターン |

スキップ: コミットメッセージに `# ai-review: ignore` を含める。

### reviewdog-go / reviewdog-python / reviewdog-rust

| workflow | input（既定） |
|---|---|
| `reviewdog-go` | `working-directory`(`.`) / `go-version`(`1.23`) / `fail-on-error`(`false`) |
| `reviewdog-python` | `working-directory`(`.`) / `fail-on-error`(`false`) |
| `reviewdog-rust` | `working-directory`(`.`) / `rust-version`(`stable`) / `clippy-args`(`--workspace --all-targets`) / `fail-on-error`(`false`) |

### gitleaks

| input | 既定 | 説明 |
|---|---|---|
| `gitleaks-version` | `8.30.1` | gitleaks CLI のバージョン |
| `fail-on-detect` | `true` | 検出時に失敗にするか |

### trivy-scan

| input | 既定 | 説明 |
|---|---|---|
| `severity` | `CRITICAL,HIGH` | 対象の重大度 |
| `scan-image` | `false` | イメージもスキャンするか |
| `image-ref` | `""` | `scan-image=true` 時のイメージ参照 |
| `working-directory` | `.` | スキャン対象ディレクトリ |

SARIF を Security タブに上げるには caller で `security-events: write` を宣言する。

## デプロイ系

### pre-deploy

Docker build + 脆弱性スキャン + migration dry-run。

| input | 既定 | 説明 |
|---|---|---|
| `dockerfile-path` | `Dockerfile` | Dockerfile のパス |
| `build-context` | `.` | build コンテキスト |
| `build-args` | `""` | 追加 build args（改行区切り `KEY=VALUE`） |
| `migration-command` | `""` | dry-run コマンド（空で skip） |
| `audit-type` | `none` | `trivy` / `pip-audit` / `npm-audit` / `none` |
| `audit-path` | `.` | pip-audit / npm-audit の対象 |
| `fail-on-vuln` | `true` | 脆弱性検出で失敗にするか |
| `working-directory` | `.` | 実行ディレクトリ |

### smoke-test

デプロイ後のヘルスチェック。失敗時は output `rollback=true` でロールバックをトリガーできる。
output: `rollback`（true/false）、`status-code`。単体検証用に `workflow_dispatch` でも起動できる。

| input | 既定 | 説明 |
|---|---|---|
| `service-url` | **必須** | ヘルスチェック対象のベース URL |
| `health-path` | `/health` | ヘルスエンドポイント |
| `timeout` | `60` | タイムアウト（秒） |
| `retry-interval` | `5` | リトライ間隔（秒） |
| `expected-status` | `200` | 期待する HTTP ステータス |
| `extra-checks` | `""` | 追加チェック（改行区切り `PATH:STATUS`） |

## E2E

### e2e-playwright

| input | 既定 | 説明 |
|---|---|---|
| `app-dir` | `.` | アプリのディレクトリ |
| `base-url` | `http://app:5173` | テスト対象 URL |
| `node-version` | `20` | Node バージョン |

secret: `APP_ENV`（任意）。

### api-e2e

k6 シナリオは private の qa-platform（archived）から取得するため、read 権限のある PAT が必要。

| input | 既定 | 説明 |
|---|---|---|
| `compose-file` | `docker-compose.yml` | 起動する compose ファイル |
| `base-url` | `http://app:8080` | テスト対象 URL |
| `k6-script` | `scenarios/crud.js` | k6 シナリオ |
| `duration` | `""` | 実行時間（空で既定） |

secret: `QA_PLATFORM_TOKEN`（**必須**）。

## リポジトリ運用系

### dependabot-auto-merge / dependabot-auto-merge-minor

triage（patch は即マージ、minor は待機ラベル、major・security は手動）と、待機ラベル付き minor の 24h 後昇格（cron）。
caller は `contents: write` と `pull-requests: write` を宣言する。詳細は README。

| workflow | input | secret |
|---|---|---|
| `dependabot-auto-merge` | `runner`(`""`) | `alert-token`（任意。**未指定だと security 更新も自動処理される**。Dependabot secrets に登録） |
| `dependabot-auto-merge-minor` | `runner`(`""`) | なし |

### size-label

| input | 既定 | 説明 |
|---|---|---|
| `sizes` | `{"0":"XS","10":"S","30":"M","100":"L","500":"XL","1000":"XXL"}` | 変更行数の閾値と、対応するラベルの JSON |

caller は `pull-requests: write` を宣言する。

### stale-pr

| input | 既定 | 説明 |
|---|---|---|
| `days-before-stale` | `14` | stale 化までの日数 |
| `days-before-close` | `7` | stale 後にクローズするまでの日数 |

caller は `pull-requests: write` と `issues: write` を宣言する。

## 呼び出せない workflow

`eval-regression.yml` は `workflow_call` を持たず、`pull_request`（`eval/**` の変更）で直接動く。
eval 資産は qa-platform（private・archived）側にあるため、このリポでは事実上発火しない。

## 導入手順

1. 呼び出し側の `.github/workflows/ci.yml` に `uses:` を追加する。
2. `coverage-threshold` は各リポの**実測値**に合わせて設定する（0% の生成コード・cmd が総計を押し下げる）。
3. 導入後、branch protection の required checks 名を確認する。caller の job 名が reusable 内部の job 名と異なると
   `caller / inner` 形式になり、旧名の required check が永遠に満たされない。
