#!/bin/bash
#
# Compiles and packages the runner for linux-riscv64.
#
# Must be run on a linux-riscv64 host: the downloaded .NET SDK is a
# native riscv64 build, so it cannot execute on other architectures.
# End result resides in runner_src/_package/.
#
# Usage: ./compile_runner.sh [Debug|Release]

set -euo pipefail

RUNNER_SRC="$(dirname "${BASH_SOURCE[0]}")/runner_src"
RUNNER_SRC="$(cd $RUNNER_SRC && pwd)"
CONFIG="${1:-Release}"

RISCV_DOTNET_VERSION="8.0.101"
RISCV_DOTNET_RELEASE_URL="https://github.com/dkurt/dotnet_riscv/releases/download/v${RISCV_DOTNET_VERSION}"

# Must match DOTNETSDK_VERSION in src/dev.sh: dev.sh only auto-downloads
# a (non-riscv64) SDK if it doesn't already find one installed at
# _dotnetsdk/<DOTNETSDK_VERSION>, so pre-populating that exact path
# with the riscv64 SDK lets it skip its own install step entirely.
DEV_SH_DOTNETSDK_VERSION="$(grep -m1 '^DOTNETSDK_VERSION=' "$RUNNER_SRC/src/dev.sh" | sed -E 's/.*"(.*)".*/\1/')"

DOTNETSDK_DIR="$RUNNER_SRC/_dotnetsdk/${DEV_SH_DOTNETSDK_VERSION}"
SDK_CACHE_DIR="$RUNNER_SRC/_dotnetsdk/downloads"
PACKAGES_DIR="$RUNNER_SRC/packages"
NUGET_CONFIG="$RUNNER_SRC/src/NuGet.Config"
GLOBAL_JSON="$RUNNER_SRC/src/global.json"

RISCV_NUPKGS=(
    "Microsoft.AspNetCore.App.Runtime.linux-riscv64.8.0.1-servicing.23580.8.nupkg"
    "Microsoft.AspNetCore.App.Runtime.linux-riscv64.8.0.1-servicing.23580.8.symbols.nupkg"
    "Microsoft.AspNetCore.App.Runtime.linux-riscv64.8.0.1.nupkg"
    "Microsoft.AspNetCore.App.Runtime.linux-riscv64.8.0.1.symbols.nupkg"
    "Microsoft.NETCore.App.Host.linux-riscv64.8.0.1.nupkg"
    "Microsoft.NETCore.App.Host.linux-riscv64.8.0.1.symbols.nupkg"
    "Microsoft.NETCore.App.Runtime.linux-riscv64.8.0.1-servicing.23580.1.nupkg"
    "Microsoft.NETCore.App.Runtime.linux-riscv64.8.0.1-servicing.23580.1.symbols.nupkg"
    "Microsoft.NETCore.App.Runtime.linux-riscv64.8.0.1.nupkg"
    "Microsoft.NETCore.App.Runtime.linux-riscv64.8.0.1.symbols.nupkg"
)

function heading() {
    echo
    echo "-----------------------------------------"
    echo "  $1"
    echo "-----------------------------------------"
}

function download() {
    local url="$1"
    local dest="$2"
    if [ -f "$dest" ]; then
        echo "Already downloaded: $(basename "$dest")"
        return
    fi
    echo "Downloading $(basename "$dest") ..."
    if command -v curl > /dev/null; then
        curl -fSL --create-dirs -o "$dest" "$url"
    elif command -v wget > /dev/null; then
        mkdir -p "$(dirname "$dest")"
        wget -q -O "$dest" "$url"
    else
        echo "Failed: need curl or wget to download $url" >&2
        exit 1
    fi
}

if [[ "$(uname -s | tr '[:upper:]' '[:lower:]')" != "linux" || "$(uname -m)" != "riscv64" ]]; then
    echo "WARNING: this must run on a linux-riscv64 host to produce a working build (detected $(uname -s)/$(uname -m))." >&2
fi

heading "Download RISC-V .NET SDK and runtime packages (v${RISCV_DOTNET_VERSION})"
download "${RISCV_DOTNET_RELEASE_URL}/dotnet-sdk-${RISCV_DOTNET_VERSION}-linux-riscv64.tar.gz" \
    "$SDK_CACHE_DIR/dotnet-sdk-${RISCV_DOTNET_VERSION}-linux-riscv64.tar.gz"

mkdir -p "$PACKAGES_DIR"
for pkg in "${RISCV_NUPKGS[@]}"; do
    download "${RISCV_DOTNET_RELEASE_URL}/${pkg}" "$PACKAGES_DIR/${pkg}"
done

heading "Install RISC-V .NET SDK into ${DOTNETSDK_DIR}"
if [[ ! -e "$DOTNETSDK_DIR/dotnet" || ! -e "$DOTNETSDK_DIR/.${DEV_SH_DOTNETSDK_VERSION}" ]]; then
    rm -rf "$DOTNETSDK_DIR"
    mkdir -p "$DOTNETSDK_DIR"
    tar -xf "$SDK_CACHE_DIR/dotnet-sdk-${RISCV_DOTNET_VERSION}-linux-riscv64.tar.gz" -C "$DOTNETSDK_DIR"
    # Marks the SDK as present so dev.sh skips its own (non-riscv64) install step.
    echo "$DEV_SH_DOTNETSDK_VERSION" > "$DOTNETSDK_DIR/.${DEV_SH_DOTNETSDK_VERSION}"
else
    echo "Already installed."
fi

heading "Point NuGet.Config and global.json at the RISC-V SDK/packages"
cp "$NUGET_CONFIG" "$NUGET_CONFIG.bak"
cp "$GLOBAL_JSON" "$GLOBAL_JSON.bak"
restore_configs() {
    mv "$NUGET_CONFIG.bak" "$NUGET_CONFIG"
    mv "$GLOBAL_JSON.bak" "$GLOBAL_JSON"
}
trap restore_configs EXIT

sed -i.tmp "s|/home/ubuntu/packages|${PACKAGES_DIR}|" "$NUGET_CONFIG" && rm -f "$NUGET_CONFIG.tmp"
# The downloaded SDK is 8.0.101; pin global.json to it for this build so
# dotnet's SDK resolver accepts it (it otherwise requires an exact
# feature-band match with the version dev.sh normally targets).
sed -i.tmp "s|\"version\": \".*\"|\"version\": \"${RISCV_DOTNET_VERSION}\"|" "$GLOBAL_JSON" && rm -f "$GLOBAL_JSON.tmp"

heading "Build layout"
(cd "$RUNNER_SRC/src" && ./dev.sh layout "$CONFIG" linux-riscv64)

heading "Package"
(cd "$RUNNER_SRC/src" && ./dev.sh package "$CONFIG" linux-riscv64)

heading "Done"
echo "Package(s) available in: $RUNNER_SRC/_package"
ls -1 "$RUNNER_SRC/_package"