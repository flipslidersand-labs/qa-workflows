# Changelog

All notable changes to this project are documented in this file.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
Versioning: [Semantic Versioning](https://semver.org/)

> No version has been tagged yet. The entries below summarize the git history up to the first release.

---

## [Unreleased]

### Added
- Reusable test workflows: `python-test`, `go-test`, `rust-test`, `node-test`, with PR coverage-diff comments for Python/Go/Rust.
- Reusable delivery and E2E workflows: `smoke-test`, `pre-deploy`, `api-e2e`, `e2e-playwright`, `eval-regression`, `ai-review`.
- Reusable security and hygiene workflows: `gitleaks`, `trivy-scan`, `no-ai-artifacts`, `dep-policy` (dependency drift detection), `pr-title`.
- Reusable review and repo-maintenance workflows: `reviewdog-python`, `reviewdog-go`, `reviewdog-rust`, `size-label`, `stale-pr`, `dependabot-auto-merge`, `dependabot-auto-merge-minor`.
- Audit scripts for callers: pinned SHA reachability, Dependabot auto-merge setup, and deployment status (#75, #120, #128).
- Lint: limited zizmor audit and detection of `|| true` (#135).

### Security
- Inputs are passed to `run:` and `github-script` through `env` and array expansion instead of direct interpolation (#127, #133).
- Removed a job-level permissions escalation that caused `startup_failure` in callers (#11).

### Fixed
- Self-hosted runners: setup-go and setup-python caches are disabled; `COREPACK_HOME` points at `RUNNER_TEMP` (#53, #61, #134).
- gitleaks: retry and checksum verification, download into `RUNNER_TEMP` instead of a fixed `/tmp` path (#93, #117).
- go-test: reads `go-version` from `go.mod` when not given; C toolchain and `CGO_ENABLED=1` with `-race` (#45, #113).
- python-test: ruff version is read from `.pre-commit-config.yaml` (#121).
- smoke-test: rollback on extra-check failure; status code no longer doubled on connect failure (#60, #131).
- Dependabot auto-merge decision is made in one place and gated on all checks passing (#108).
