# riscv-github-actions-runner

# Overview

The official GitHub Actions runner does not ship a build for RISC-V. This repository patches an upstream release of [actions/runner](https://github.com/actions/runner) for `linux-riscv64` and cross-compiles it on any machine with Docker.
The original patches came from [this (outdated) repository](https://github.com/mliezun/runner).

The runner targets .NET 10. The `linux-riscv64` runtime packs come from [filipnavara/dotnet-riscv](https://github.com/filipnavara/dotnet-riscv), a source build of .NET, because nuget.org has none for that architecture.
The resulting binaries need glibc 2.38 or newer on the board (Ubuntu 24.04 or later).

## Versions

`versions.env` pins every build input: the upstream runner tag, the .NET SDK image, and the `dotnet-riscv` release with the sha256 of its artifacts.
Bumping any pin changes `PATCH_FINGERPRINT`, so a build always records exactly what went into it.
The SDK must ship the same runtime version as the riscv64 packs; the build stops with a message naming both if they differ.

## Scripts

- `patch_runner.sh [runner-branch-or-tag]`: clones the latest (or provided) version of the GitHub Actions runner in a temporary directory and applies the changes for RISC-V (`apply_changes_for_riscv.py`).
It then copies the resulting codebase into `runner_src_<tag>/` next to the script, where `<tag>` is the first 12 characters of the upstream commit followed by a fingerprint of the build scripts and `versions.env`, so the same upstream commit built with the same inputs always lands in the same directory.
The directory also contains `UPSTREAM_COMMIT` (the full upstream commit hash) and `PATCH_FINGERPRINT`. The last line printed is `RUNNER_SRC_DIR=<path>`.
**Requires git & python 3** (rsync is used when available).
- `compile_runner.sh [Debug|Release] [runner_src_dir]`: cross-compiles the runner in the official .NET SDK image (`build_in_container.sh`) and stores `actions-runner-linux-riscv64-<version>.tar.gz` in a `_package/` directory inside the runner source directory.
Without the second argument it builds the only `runner_src_*` directory next to the script (and falls back to `runner_src/`).
`UPSTREAM_COMMIT` and `PATCH_FINGERPRINT` end up in the root of the resulting package. The ~1 GB `dotnet-riscv` download is cached in `_downloads/`.
**Requires Docker.**

A local build:

```sh
source versions.env
./patch_runner.sh "v${RUNNER_VERSION}"
./compile_runner.sh Release
```

## Releases

`.github/workflows/build.yml` builds on every pull request and push to `main`.
Pushing a tag `v<RUNNER_VERSION>-<n>` (for example `v2.338.2-1`) also publishes the package as a GitHub release; `<n>` counts rebuilds of the same upstream version, such as a .NET servicing bump.
The workflow refuses a tag that does not match `RUNNER_VERSION` in `versions.env`.

GitHub stops sending jobs to a runner that has auto-update disabled once it falls behind the latest release for too long, so bump `RUNNER_VERSION` and tag a release when upstream ships one.

The committed `runner_src/` is a snapshot patched at v2.337.0, before this naming scheme existed; `patch_runner.sh` no longer touches it.
