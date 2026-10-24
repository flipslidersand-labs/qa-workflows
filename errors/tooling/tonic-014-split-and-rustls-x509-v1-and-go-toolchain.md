---
title: "tonic 0.14 分割・rustls の X.509 v1 拒否・go.mod 1.25 と CI go-version 1.24 の不一致で master CI が壊れる"
tags: [rust, tonic, rustls, go, ci, dependabot]
severity: medium
date: "2026-10-03"
---

## 症状

dataguard-rail の master で Rust / Go の CI が同時に失敗し、dependabot PR も全て赤になっていた。

## 原因

1. **tonic 0.14**: codegen が `tonic-build` から `tonic-prost-build` / `tonic-prost` に分離。`tls` feature は `tls-ring` に改名。dependabot が tonic / prost / tonic-build を個別に bump して依存が不整合になった。
2. **rustls（tonic 0.14）**: X.509 v1 証明書を `UnsupportedCertVersion` で拒否。テストが openssl `x509 -req` で拡張なしのクライアント証明書を作っていた。
3. **Go**: go.mod が `go 1.25.0`、CI は `go-version: 1.24` + `GOTOOLCHAIN=local` で `go vet` が失敗。

## 解決策（dataguard-rail PR#197）

- Cargo.toml: `tonic 0.14` (`tls-ring`)、`tonic-prost`、`prost 0.14`、build-dep を `tonic-prost-build` に。build.rs は `tonic_prost_build::compile_protos(...)`
- テスト証明書: CSR に `-addext basicConstraints=CA:FALSE`、署名時 `-copy_extensions copy` で v3 化
- go-test.yml: `go-version: "1.25"`

## 予防

- tonic / tonic-prost / prost は dependabot の group で一括更新する
- 本番の gRPC TLS 証明書が X.509 v1 でないか確認する（rustls 更新後に接続できなくなる恐れ）
- go.mod の go 行と CI の go-version を揃える。`GOTOOLCHAIN=local` では自動取得されない
