#!/usr/bin/env python3
"""
Patch an actions/runner (main branch) checkout with RISC-V (linux-riscv64)
support, porting the patches from the mliezun/runner RISC-V fork.

Usage:
    python3 patch_riscv.py /path/to/runner/checkout
"""

import argparse
import pathlib
import sys


def patch(repo: pathlib.Path, path: str, old: str, new: str, count: int = 1) -> None:
    p = repo / path
    text = p.read_text()
    occurrences = text.count(old)
    if occurrences != count:
        sys.exit(
            f"ERROR: expected {count} occurrence(s) of anchor text in {path}, "
            f"found {occurrences} (upstream may have drifted since this script "
            f"was written):\n{old!r}"
        )
    p.write_text(text.replace(old, new, count))
    print(f"  patched {path}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Patch an actions/runner checkout with RISC-V (linux-riscv64) support."
    )
    parser.add_argument(
        "repo",
        type=pathlib.Path,
        help="Path to the actions/runner repo checkout to patch",
    )
    args = parser.parse_args()
    repo = args.repo.resolve()

    if not repo.is_dir():
        sys.exit(f"ERROR: {repo} is not a directory")

    # 1. Directory.Build.props: define a RISCV64 build constant, same pattern
    #    used for the existing ARM64 constant.
    patch(
        repo,
        "src/Directory.Build.props",
        """  <PropertyGroup Condition="'$(BUILD_OS)' == 'Linux' AND '$(PackageRuntime)' == 'linux-arm64'">
    <DefineConstants>$(DefineConstants);ARM64</DefineConstants>
  </PropertyGroup>
""",
        """  <PropertyGroup Condition="'$(BUILD_OS)' == 'Linux' AND '$(PackageRuntime)' == 'linux-arm64'">
    <DefineConstants>$(DefineConstants);ARM64</DefineConstants>
  </PropertyGroup>
  <PropertyGroup Condition="'$(BUILD_OS)' == 'Linux' AND '$(PackageRuntime)' == 'linux-riscv64'">
    <DefineConstants>$(DefineConstants);RISCV64</DefineConstants>
  </PropertyGroup>
""",
    )

    # 2. Constants.cs: add RiscV64 to the Architecture enum and wire up
    #    PlatformArchitecture for the RISCV64 build constant.
    patch(
        repo,
        "src/Runner.Common/Constants.cs",
        """            X86,
            X64,
            Arm,
            Arm64
        }""",
        """            X86,
            X64,
            Arm,
            Arm64,
            RiscV64
        }""",
    )
    patch(
        repo,
        "src/Runner.Common/Constants.cs",
        """#elif ARM64
            public static readonly Architecture PlatformArchitecture = Architecture.Arm64;
#else""",
        """#elif ARM64
            public static readonly Architecture PlatformArchitecture = Architecture.Arm64;
#elif RISCV64
            public static readonly Architecture PlatformArchitecture = Architecture.RiscV64;
#else""",
    )

    # 3. VarUtil.cs: report "RISCV64" for the OSArchitecture variable.
    patch(
        repo,
        "src/Runner.Common/Util/VarUtil.cs",
        """                    case Constants.Architecture.Arm64:
                        return "ARM64";
                    default:""",
        """                    case Constants.Architecture.Arm64:
                        return "ARM64";
                    case Constants.Architecture.RiscV64:
                        return "RISCV64";
                    default:""",
    )

    # 4. csproj files: restrict RuntimeIdentifiers to just linux-riscv64.
    #    These builds are self-contained and single-target (dev.sh builds
    #    one PackageRuntime at a time), and a project with SelfContained
    #    plus a *multi*-RID list forces restore to resolve a runtime pack
    #    for every RID in the list - which fails on any RID whose pack
    #    isn't reachable from the build machine.
    csproj_files = [
        "src/Runner.Common/Runner.Common.csproj",
        "src/Runner.Listener/Runner.Listener.csproj",
        "src/Runner.PluginHost/Runner.PluginHost.csproj",
        "src/Runner.Plugins/Runner.Plugins.csproj",
        "src/Runner.Sdk/Runner.Sdk.csproj",
        "src/Runner.Worker/Runner.Worker.csproj",
        "src/Sdk/Sdk.csproj",
    ]
    old_rids = "win-x64;win-x86;linux-x64;linux-arm64;linux-arm;osx-x64;osx-arm64;win-arm64"
    for f in csproj_files:
        patch(
            repo,
            f,
            f"<RuntimeIdentifiers>{old_rids}</RuntimeIdentifiers>",
            "<RuntimeIdentifiers>linux-riscv64</RuntimeIdentifiers>",
        )

    # 5. NuGet.Config: local feed for the manually-built riscv64 runtime
    #    packs (official NuGet doesn't host .NET runtime packs for
    #    linux-riscv64).
    patch(
        repo,
        "src/NuGet.Config",
        """    <clear />
    <add key="api.nuget.org" value="https://api.nuget.org/v3/index.json" />""",
        """    <clear />
    <add key="local" value="/home/ubuntu/packages" />
    <add key="api.nuget.org" value="https://api.nuget.org/v3/index.json" />""",
    )

    # 6. externals.sh: fetch Node for riscv64 from the unofficial Node.js
    #    builds (there's no official nodejs.org riscv64 build for these
    #    versions).
    patch(
        repo,
        "src/Misc/externals.sh",
        "NODE_URL=https://nodejs.org/dist\n",
        "NODE_URL=https://nodejs.org/dist\nUNOFFICIAL_NODE_URL=https://unofficial-builds.nodejs.org/download/release\n",
    )
    patch(
        repo,
        "src/Misc/externals.sh",
        """if [[ "$PACKAGERUNTIME" == "linux-arm" ]]; then
    acquireExternalTool "$NODE_URL/v${NODE20_VERSION}/node-v${NODE20_VERSION}-linux-armv7l.tar.gz" node20 fix_nested_dir
fi
""",
        """if [[ "$PACKAGERUNTIME" == "linux-arm" ]]; then
    acquireExternalTool "$NODE_URL/v${NODE20_VERSION}/node-v${NODE20_VERSION}-linux-armv7l.tar.gz" node20 fix_nested_dir
fi

if [[ "$PACKAGERUNTIME" == "linux-riscv64" ]]; then
    acquireExternalTool "$UNOFFICIAL_NODE_URL/v${NODE20_VERSION}/node-v${NODE20_VERSION}-linux-riscv64.tar.gz" node20 fix_nested_dir
    acquireExternalTool "$UNOFFICIAL_NODE_URL/v${NODE24_VERSION}/node-v${NODE24_VERSION}-linux-riscv64.tar.gz" node24 fix_nested_dir
fi
""",
    )

    # 7. dev.sh: detect a riscv64 host, and accept linux-riscv64 as a
    #    valid Linux build target.
    patch(
        repo,
        "src/dev.sh",
        """            armv7l) RUNTIME_ID="linux-arm";;
            aarch64) RUNTIME_ID="linux-arm64";;
        esac""",
        """            armv7l) RUNTIME_ID="linux-arm";;
            aarch64) RUNTIME_ID="linux-arm64";;
            riscv64) RUNTIME_ID="linux-riscv64";;
        esac""",
    )
    patch(
        repo,
        "src/dev.sh",
        """    if [[ ("$RUNTIME_ID" != 'linux-x64') && ("$RUNTIME_ID" != 'linux-x86') && ("$RUNTIME_ID" != 'linux-arm64') && ("$RUNTIME_ID" != 'linux-arm') ]]; then""",
        """    if [[ ("$RUNTIME_ID" != 'linux-x64') && ("$RUNTIME_ID" != 'linux-x86') && ("$RUNTIME_ID" != 'linux-arm64') && ("$RUNTIME_ID" != 'linux-arm') && ("$RUNTIME_ID" != 'linux-riscv64') ]]; then""",
    )

    print("All patches applied successfully.")


if __name__ == "__main__":
    main()