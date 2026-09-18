# riscv-github-actions-runner

# Overview

Currently, the official Github actions runner repository does not support compilation for RISC-V architectures.
This repository contains the current (at the time of writing) version of the runner with the necessary changes to make it compile on RISC-V.
The source of the changes is [this (outdated) repository](https://github.com/mliezun/runner).

Furthermore, the repository contains scripts necessary for applying these patches on new Github actions runner versions, and for actually compiling.
Note that cross-compilation on a different architecture is currently not supported.
Scripts provided:
- `patch_riscv_runner.sh [runner-branch-or-tag]`: clones the latest (or provided) version of the github actions runner in a temporary directory and applies the necessary changes for RISC-V.
It then copies the resulting codebase into a `runner_src/` next to the script, replacing existing files.
**Requires git & python 3**.
- `compile_runner.sh`: compiles the runner and stores the result in a `_package/` directory inside `runner_src`. 