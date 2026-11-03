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

- **runner**: `runner` input は既定で空。空なら `vars.GATE_RUNNER` を reusable 側で参照する（既定値なし。未設定ならエラー。public はリポ変数が必須）。
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
**pytest-cov を dev extras に宣言必須**。ruff の版は `ruff-version` 入力 > caller の `.pre-commit-config.yaml` の ruff-pre-commit `rev`（先頭の `v` を除く）> 最新、の優先順で決まる。pre-commit と CI の版の正本は `rev` の1箇所。

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
| `ruff-version` | `""` | 明示指定が最優先。空なら `.pre-commit-config.yaml`（リポ直下）の ruff-pre-commit rev、無ければ最新 |
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
リポ変数: `WIF_PROVIDER` / `WIF_SA` / `VERTEX_PROJECT` / `VERTEX_REGION`。caller は job-level（または最上位）permissions で `pull-requests: write` / `id-token: write` / `contents: read` を必ず宣言する（reusable 側は permissions を持たない。未宣言だと WIF 認証とコメント投稿が失敗する）。

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
| `reviewdog-go` | `working-directory`(`.`) / `go-version`(`1.23`) / `fail-on-error`(`false`) / `runner`(`""`) |
| `reviewdog-python` | `working-directory`(`.`) / `fail-on-error`(`false`) / `runner`(`""`) |
| `reviewdog-rust` | `working-directory`(`.`) / `rust-version`(`stable`) / `clippy-args`(`--workspace --all-targets`) / `fail-on-error`(`false`) / `runner`(`""`) |

### gitleaks

| input | 既定 | 説明 |
|---|---|---|
| `gitleaks-version` | `8.30.1` | gitleaks CLI のバージョン |
| `fail-on-detect` | `true` | 検出時に失敗にするか |

### no-ai-artifacts

| input | 既定 | 説明 |
|---|---|---|
| `forbidden-pattern` | `^\.claude/\|(^\|/)\.mcp\.json$` | 追跡されていたら失敗にするパスの拡張正規表現 |

`CLAUDE.md` / `AGENTS.md` は既定で検査しない(公開するかはリポごとの判断)。呼び出し側で `permissions: contents: read` を宣言する。
検出時は `git rm -r --cached` と `.gitignore` 追加で直す。履歴に残った内容(ローカル絶対パス等)は別途確認が要る。

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

### pr-title

PR タイトルを Conventional Commits 形式 (`<type>(<scope>)?(!)?: <subject>`) で検査する。違反時は正しい例と修正コマンド `gh pr edit <番号> --title "..."` を表示。

| input | 既定 | 説明 |
|---|---|---|
| `types` | `feat fix docs style refactor perf test chore ci build revert` | 許可 type（スペース区切り。dev-platform の `.commitlintrc.js` と同じ + `revert`） |

caller は `contents: read` を宣言し、`pull_request` の types に `edited` を含める。job 名は `pr-title-check`（check 名: `<caller job 名> / pr-title-check`）。

## caller 早見表

各 `.github/workflows/*.yml` の実装（冒頭コメント・job の `permissions`・`github-script` / コメント投稿・`id-token` 利用）から作成。YAML と食い違えば YAML が正。
「要確認」は実装から断定できなかった箇所。caller の最小 permissions は `contents: read`（private リポの checkout 用）を前提に、追加分のみ列挙する。

| workflow | caller 必須 permissions（追加分） | 必須・主要 input | 推奨 job id | 補足 |
|---|---|---|---|---|
| `go-test` | `pull-requests: write`（coverage コメント用。無くても soft-fail） | 必須 input なし。`coverage-threshold` | `test-go` | コメント step は `continue-on-error: true` |
| `python-test` | `pull-requests: write`（同上） | 必須 input なし。`coverage-threshold` / `working-directory` | `test-python` | 同上 |
| `rust-test` | `pull-requests: write`（同上） | 必須 input なし。`coverage-threshold` / `test-args` | `test-rust` | 同上 |
| `node-test` | なし | 必須 input なし。`package-manager` / `test-script` | `test-node` | PR コメント投稿なし（実装に `github-script` 無し） |
| `ai-review` | `pull-requests: write` と `id-token: write` | 必須 input なし。リポ変数 `WIF_PROVIDER` 等 | `ai-review` | reusable 側の job に同じ permissions を宣言済み。`WIF_PROVIDER` 未設定なら認証 skip |
| `reviewdog-go` / `-python` / `-rust` | 要確認（`github-pr-review` reporter でインラインコメントを付けるため `pull-requests: write` が必要と推測。実装に permissions 記載なし） | 必須 input なし。`fail-on-error` | `reviewdog-go` / `reviewdog-python` / `reviewdog-rust` | 言語がジョブ名に入っているため規約どおり |
| `gitleaks` | `contents: read`（冒頭コメントで明記） | 必須 input なし | `gitleaks` | 必須 check に使われる（ADR-006） |
| `no-ai-artifacts` | `contents: read`（冒頭コメントで明記） | 必須 input なし。`forbidden-pattern` | `no-ai-artifacts` | |
| `trivy-scan` | 追加なし。SARIF を Code Scanning に上げる場合のみ `security-events: write` | 必須 input なし。`scan-image` + `image-ref` | `trivy` | SARIF 手順は未宣言でも soft-fail（冒頭コメント） |
| `dep-policy` | 要確認（実装に permissions 記載なし。checkout のみのため `contents: read` で足りると推測） | 必須 input なし。`fail-on-drift` / `policy-ref` | `dep-policy` | caller 直下に `dep-policy.yaml` が無ければ skip |
| `pre-deploy` | 要確認（permissions 記載なし。checkout のみ） | 必須 input なし。`audit-type` / `migration-command` | `pre-deploy` | 内部 job は `build` / `dependency-audit` / `migration-dry-run` |
| `smoke-test` | 要確認（permissions 記載なし） | `service-url`（**必須**） | `smoke-test` | output `rollback` / `status-code` |
| `e2e-playwright` | 要確認（permissions 記載なし） | 必須 input なし。`app-dir` / `base-url` | `e2e-playwright` | secret `APP_ENV`（任意） |
| `api-e2e` | 要確認（permissions 記載なし） | 必須 input なし。`compose-file` / `base-url` / `k6-script` | `api-e2e` | secret `QA_PLATFORM_TOKEN`（**必須**） |
| `dependabot-auto-merge` | `contents: write` と `pull-requests: write`（workflow 全体で宣言。冒頭コメント） | 必須 input なし。secret `alert-token`（任意） | `triage` | `if: github.actor == 'dependabot[bot]'` を caller 側に付ける |
| `dependabot-auto-merge-minor` | `contents: write` と `pull-requests: write`（workflow 全体で宣言。冒頭コメント） | 必須 input なし | `promote` | cron + `workflow_dispatch` の caller 例が冒頭コメントにある |
| `size-label` | `pull-requests: write`（冒頭コメント） | 必須 input なし。`sizes` | `size-label` | |
| `stale-pr` | `pull-requests: write` と `issues: write`（冒頭コメント） | 必須 input なし。`days-before-stale` / `days-before-close` | `stale-pr` | |
| `pr-title` | `contents: read`（冒頭コメント） | 必須 input なし。`types` | `pr-title` | トリガーに `edited` を含める。内部 job 名は `pr-title-check` |

permissions を caller で宣言しないと、reusable 側の要求との不整合で `startup_failure` や権限不足になる（#772/#774 の教訓）。
`runner` input は共通事項のとおり caller からは通常渡さない。

### job id 命名規約

required check 名は `<caller job id> / <reusable 内部 job id>` になる（例: `test / test`）。汎用名（`test` / `quality`）のまま
複数言語を 1 リポで呼ぶと同名 check が衝突しうる（仕様からの推論。実例は未確認）。そこで次の規約を使う。

- 形式: `<役割>-<言語>`（例: `test-go` / `test-python` / `lint-python`）。言語を持たない workflow は役割のみ（`gitleaks` / `trivy` / `pr-title`）。
- **既存 caller の job id は変更しない**（required check 名が変わり、旧名が永遠に満たされなくなる）。**新規 caller と複言語リポにのみ適用**する。
- job id を変えた場合は、branch protection の required checks 名も合わせて更新する。

## バージョン固定と参照方法

caller が reusable をどの ref で参照するかの方針（#85。repo-compass ADR-011 で「ref 運用は未決」とされた論点の qa-workflows 側の案）。
**この節は方針の記述のみ**で、タグ・リリースの作成と caller の移行は含まない。

### 現状

- タグ・リリースは **0 件**（`gh api repos/flipslidersand-labs/qa-workflows/tags` と `/releases`、2026-11-03 確認）。
- そのため現時点で実用的な参照は `@main` か SHA のみ。`@main` は非推奨だが、タグができるまでは唯一の移動しない代替が SHA で、
  更新が自動で届くのは `@main` だけ。caller は当面 `@main` のままでよく、タグ作成後に下記の推奨へ移行する。
- 既存 caller には SHA 固定のものがあり、main から遅れたまま修正が届かない例がある（#85）。

### 推奨参照（タグ作成後）

| 用途 | 参照 | 備考 |
|------|------|------|
| 通常 | `@v1`（移動 major タグ） | `v1` 内は後方互換の変更のみ。修正が自動で届く |
| 再現性重視 | `@<40 桁 SHA> # v1.2.3` | SHA の後ろに厳密タグをコメントで付ける。Dependabot がコメントのタグを手掛かりに更新できる |
| 非推奨 | `@main` | 入力名・job id・既定値の変更を即時に受ける。段階展開できない |

### 破壊的変更の定義

次のいずれかは破壊的変更で、**新 major（`v2`）** で出す。`v1` には入れない。

- input / secret の名前の変更・削除（必須 input の追加を含む）
- job id の変更（required check 名 `呼び出しジョブ名 / 内側ジョブ名` が変わる）
- required check 名の変更
- 既定値の意味の変更（値の変更で caller の挙動が変わるもの）

input の追加（任意・既定値は従来動作）、バグ修正、内部実装の変更は互換変更として `v1.x.y` で出す。

### リリース手順（草案・未実施）

1. main が緑で、上記の破壊的変更を含まないことを確認する。
2. 厳密タグ `v1.x.y` を main の対象コミットに打つ（例: `git tag -a v1.0.0 <sha> -m "v1.0.0"` → `git push origin v1.0.0`）。厳密タグは動かさない。
3. 移動タグ `v1` を同じコミットへ付け替える（`git tag -fa v1 <sha> -m "v1"` → `git push --force origin v1`）。**force 更新になる**。
4. caller の 1 件で `@v1` が解決し実行されることを確認する。

**先に確認すること**: org / リポのタグ保護（tag ruleset）が移動タグの更新を拒否しないか、逆に `v1.x.y` が書き換えられないよう保護するか。
実施の可否・タイミングは別判断とし、この草案の記載をもって実施を意味しない。

### SHA 固定時の注意

- squash 前の feature ブランチの SHA を pin しない。squash merge 後にブランチを消すと、その SHA は到達不能になりうる（#77 の audit が検出）。
  pin するのは main に入ったコミット、または厳密タグが指すコミットにする。
- SHA 固定は更新が自動で届かない。`# v1.2.3` コメントを付け、Dependabot の更新対象にする。

## 呼び出せない workflow

`eval-regression.yml` は `workflow_call` を持たず、`pull_request`（`eval/**` の変更）で直接動く。
eval 資産は qa-platform（private・archived）側にあるため、このリポでは事実上発火しない。

## 導入手順

1. 呼び出し側の `.github/workflows/ci.yml` に `uses:` を追加する。
2. `coverage-threshold` は各リポの**実測値**に合わせて設定する（0% の生成コード・cmd が総計を押し下げる）。
3. 導入後、branch protection の required checks 名を確認する。caller の job 名が reusable 内部の job 名と異なると
   `caller / inner` 形式になり、旧名の required check が永遠に満たされない。
