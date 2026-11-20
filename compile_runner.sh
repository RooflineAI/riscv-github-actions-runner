#!/bin/bash
#
# Cross-compiles and packages the runner for linux-riscv64 on any host with
# Docker. The build runs in the official .NET SDK image (build_in_container.sh)
# against the riscv64 runtime packs from filipnavara/dotnet-riscv; every
# version is pinned in versions.env.
#
# End result resides in <runner source dir>/_package/. UPSTREAM_COMMIT and
# PATCH_FINGERPRINT (written by patch_runner.sh) are copied into the package
# root, so an installed runner records what it was built from. The ~1 GB .NET
# artifact download is cached in _downloads/ next to this script.
#
# The runner source directory is the second argument. Without it, the only
# runner_src_* directory next to this script is used (it is an error if there
# are several), falling back to runner_src when there is none.
#
# Usage: ./compile_runner.sh [Debug|Release] [runner_src_dir]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${1:-Release}"
RUNNER_SRC="${2:-}"
if [[ -z "$RUNNER_SRC" ]]; then
    shopt -s nullglob
    candidates=("$SCRIPT_DIR"/runner_src_*/)
    shopt -u nullglob
    case ${#candidates[@]} in
        0) RUNNER_SRC="$SCRIPT_DIR/runner_src" ;;
        1) RUNNER_SRC="${candidates[0]%/}" ;;
        *)
            echo "Failed: several runner_src_* directories found, pass the one to build as the second argument:" >&2
            printf '  %s\n' "${candidates[@]%/}" >&2
            exit 1
            ;;
    esac
fi
RUNNER_SRC="$(cd "$RUNNER_SRC" && pwd)"

command -v docker > /dev/null || { echo "Failed: docker is required" >&2; exit 1; }

set -a
# shellcheck source=versions.env
source "$SCRIPT_DIR/versions.env"
set +a

mkdir -p "$SCRIPT_DIR/_downloads"
docker run --rm --user "$(id -u):$(id -g)" \
    -v "$RUNNER_SRC:/runner" \
    -v "$SCRIPT_DIR/_downloads:/downloads" \
    -v "$SCRIPT_DIR/build_in_container.sh:/build_in_container.sh:ro" \
    -e CONFIG="$CONFIG" \
    -e DOTNET_RISCV_RELEASE -e DOTNET_RISCV_ARTIFACTS -e DOTNET_RISCV_ARTIFACTS_SHA256 \
    "mcr.microsoft.com/dotnet/sdk:${DOTNET_SDK_VERSION}" \
    bash /build_in_container.sh

echo "Package(s) available in: $RUNNER_SRC/_package"
ls -1 "$RUNNER_SRC/_package"
