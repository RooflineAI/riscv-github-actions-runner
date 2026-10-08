# riscv-github-actions-runner

# Overview

Currently, the official Github actions runner repository does not support compilation for RISC-V architectures.
This repository contains the current (at the time of writing) version of the runner with the necessary changes to make it compile on RISC-V.
The source of the changes is [this (outdated) repository](https://github.com/mliezun/runner).

Furthermore, the repository contains scripts necessary for applying these patches on new Github actions runner versions, and for actually compiling.
Note that cross-compilation on a different architecture is currently not supported.
Scripts provided:
- `patch_runner.sh [runner-branch-or-tag]`: clones the latest (or provided) version of the github actions runner in a temporary directory and applies the necessary changes for RISC-V.
It then copies the resulting codebase into `runner_src_<tag>/` next to the script, where `<tag>` is the first 12 characters of the upstream commit followed by a fingerprint of the three scripts in this repository, so the same upstream commit patched by the same scripts always lands in the same directory.
The directory also contains `UPSTREAM_COMMIT` (the full upstream commit hash) and `PATCH_FINGERPRINT`. The last line printed is `RUNNER_SRC_DIR=<path>`.
**Requires git & python 3** (rsync is used when available).
- `compile_runner.sh [Debug|Release] [runner_src_dir]`: compiles the runner and stores the result in a `_package/` directory inside the runner source directory.
Without the second argument it builds the only `runner_src_*` directory next to the script (and falls back to `runner_src/`).
`UPSTREAM_COMMIT` and `PATCH_FINGERPRINT` end up in the root of the resulting package.

The committed `runner_src/` is a snapshot patched  at v2.337.0, before this naming scheme existed; `patch_runner.sh` no longer touches it.