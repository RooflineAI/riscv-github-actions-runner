#!/bin/bash
#
# Runs inside the .NET SDK image; see compile_runner.sh. Expects the patched
# runner source at /runner, a download cache at /downloads, and CONFIG plus the
# DOTNET_RISCV_* variables from versions.env in the environment.
#
# Replaces dev.sh's layout and package steps rather than calling them: dev.sh
# would install its own (non-riscv64-aware) SDK version instead of the image's.

set -euo pipefail

RUNNER=/runner
LAYOUT="$RUNNER/_layout"
ARTIFACTS="/downloads/${DOTNET_RISCV_ARTIFACTS}"
export HOME=/tmp/home DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
mkdir -p "$HOME"
# Read before entering src/, whose upstream global.json pins an SDK the image lacks.
sdk_version="$(dotnet --version)"

function heading() {
    echo
    echo "-----------------------------------------"
    echo "  $1"
    echo "-----------------------------------------"
}

heading "Download .NET ${DOTNET_RISCV_RELEASE} riscv64 artifacts"
if [[ ! -f "$ARTIFACTS" ]]; then
    curl -fSL --retry 3 -o "$ARTIFACTS.partial" \
        "https://github.com/filipnavara/dotnet-riscv/releases/download/${DOTNET_RISCV_RELEASE}/${DOTNET_RISCV_ARTIFACTS}"
    mv "$ARTIFACTS.partial" "$ARTIFACTS"
else
    echo "Already downloaded: ${DOTNET_RISCV_ARTIFACTS}"
fi
echo "${DOTNET_RISCV_ARTIFACTS_SHA256}  ${ARTIFACTS}" | sha256sum -c -

heading "Extract the linux-riscv64 runtime packs"
# src/NuGet.Config (see apply_changes_for_riscv.py) reads them from here.
rm -rf "$RUNNER/packages"
mkdir -p "$RUNNER/packages"
tar -xzf "$ARTIFACTS" -C "$RUNNER/packages" --wildcards --no-anchored --transform='s|.*/||' \
    --exclude='*.symbols.nupkg' \
    'Microsoft.NETCore.App.Runtime.linux-riscv64.*.nupkg' \
    'Microsoft.NETCore.App.Host.linux-riscv64.*.nupkg' \
    'Microsoft.AspNetCore.App.Runtime.linux-riscv64.*.nupkg'
ls -1 "$RUNNER/packages"

# A self-contained publish asks for the runtime pack version the SDK ships;
# say so plainly instead of failing restore against nuget.org.
pack_version="$(find "$RUNNER/packages" -name 'Microsoft.NETCore.App.Runtime.linux-riscv64.*.nupkg' -printf '%f\n' \
    | sed -E 's/^Microsoft\.NETCore\.App\.Runtime\.linux-riscv64\.(.*)\.nupkg$/\1/')"
sdk_runtime="$(dotnet --list-runtimes | sed -nE 's/^Microsoft\.NETCore\.App ([^ ]+) .*/\1/p' | tail -1)"
if [[ "$pack_version" != "$sdk_runtime" ]]; then
    echo "Failed: the riscv64 runtime pack is ${pack_version} but SDK ${sdk_version} ships runtime ${sdk_runtime}." >&2
    echo "Set DOTNET_SDK_VERSION in versions.env to an SDK that ships ${pack_version}." >&2
    exit 1
fi

heading "Pin global.json to SDK ${sdk_version} for this build"
cd "$RUNNER/src"
cp global.json global.json.orig
trap 'mv global.json.orig global.json' EXIT
printf '{\n  "sdk": {\n    "version": "%s",\n    "rollForward": "latestFeature"\n  }\n}\n' "$sdk_version" > global.json

heading "Build layout"
version="$(cat runnerversion)"
# dir.proj stamps the upstream commit via git; the mounted tree is owned by another uid.
git config --global --add safe.directory '*'
dotnet msbuild -t:layout -p:PackageRuntime=linux-riscv64 -p:BUILDCONFIG="$CONFIG" -p:RunnerVersion="$version" ./dir.proj
chmod +x "$LAYOUT/bin/Runner.Listener" "$LAYOUT/bin/Runner.Worker" "$LAYOUT/bin/Runner.PluginHost" \
    "$LAYOUT/bin/installdependencies.sh" "$LAYOUT/safe_sleep.sh"

heading "Fetch Node into the layout"
# externals.sh downloads only when given a second (precache) argument; a plain run extracts.
bash ./Misc/externals.sh linux-riscv64 precache
bash ./Misc/externals.sh linux-riscv64

heading "Check the layout targets riscv64"
for binary in bin/Runner.Listener bin/Runner.Worker bin/libcoreclr.so externals/node20/bin/node externals/node24/bin/node; do
    # e_machine at ELF offset 18 is 0x00f3 (EM_RISCV), stored little-endian.
    if [[ "$(od -An -tx1 -j18 -N2 "$LAYOUT/$binary" | tr -d ' \n')" != "f300" ]]; then
        echo "Failed: $binary is not a riscv64 ELF binary" >&2
        exit 1
    fi
    echo "riscv64: $binary"
done

heading "Record build provenance in the layout"
for provenance_file in UPSTREAM_COMMIT PATCH_FINGERPRINT; do
    if [[ -f "$RUNNER/$provenance_file" ]]; then
        cp "$RUNNER/$provenance_file" "$LAYOUT/$provenance_file"
    fi
done

heading "Package actions-runner-linux-riscv64-${version}"
rm -rf "$LAYOUT/_diag"
find "$LAYOUT/bin" -type f -name '*.pdb' -delete
rm -rf "$RUNNER/_package"
mkdir -p "$RUNNER/_package"
tar -czf "$RUNNER/_package/actions-runner-linux-riscv64-${version}.tar.gz" -C "$LAYOUT" .
