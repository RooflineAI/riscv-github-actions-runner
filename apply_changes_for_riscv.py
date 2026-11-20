#!/usr/bin/env python3
"""
Patch an actions/runner (main branch) checkout with RISC-V (linux-riscv64)
support, porting the patches from the mliezun/runner RISC-V fork.

Usage:
    python3 patch_riscv.py /path/to/runner/checkout
"""

import argparse
import pathlib
import re
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


def remove_package_ref(repo: pathlib.Path, path: str, name: str) -> None:
    """Drop one <PackageReference> line, whatever version upstream pins."""
    p = repo / path
    pattern = re.compile(
        rf'^[ \t]*<PackageReference Include="{re.escape(name)}" Version="[^"]*" />\n', re.M
    )
    text, removed = pattern.subn("", p.read_text())
    if removed != 1:
        sys.exit(
            f"ERROR: expected 1 PackageReference to {name} in {path}, found {removed} "
            f"(upstream may have dropped it; remove it from this script)"
        )
    p.write_text(text)
    print(f"  removed {name} from {path}")


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

    # 5. NuGet.Config: local feed for the riscv64 runtime packs (official
    #    NuGet doesn't host .NET runtime packs for linux-riscv64).
    #    build_in_container.sh extracts them into <runner source>/packages,
    #    which NuGet resolves relative to src/NuGet.Config.
    patch(
        repo,
        "src/NuGet.Config",
        """    <clear />
    <add key="api.nuget.org" value="https://api.nuget.org/v3/index.json" />""",
        """    <clear />
    <add key="local" value="../packages" />
    <add key="api.nuget.org" value="https://api.nuget.org/v3/index.json" />""",
    )

    # 6. externals.sh: fetch Node for riscv64 from the unofficial Node.js
    #    builds (there's no official nodejs.org riscv64 build for these
    #    versions). Node 24 comes from NODE24_RISCV_VERSION in versions.env
    #    rather than upstream's NODE24_VERSION; see the comment there.
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
    acquireExternalTool "$UNOFFICIAL_NODE_URL/v${NODE24_RISCV_VERSION:?set in versions.env}/node-v${NODE24_RISCV_VERSION}-linux-riscv64.tar.gz" node24 fix_nested_dir
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

    # 8. Retarget to .NET 10: the only .NET with maintained linux-riscv64
    #    builds (8.0's riscv64 packs stopped at 8.0.1). Drop this step once
    #    upstream targets net10.0 (actions/runner#4757).
    for f in csproj_files + ["src/Test/Test.csproj"]:
        patch(
            repo,
            f,
            "<TargetFramework>net8.0</TargetFramework>",
            "<TargetFramework>net10.0</TargetFramework>",
        )

    # 9. Remove references to packages the .NET 10 shared framework now
    #    provides. NuGet reports each as NU1510, an error under upstream's
    #    TreatWarningsAsErrors.
    in_shared_framework = {
        "src/Runner.Common/Runner.Common.csproj": [
            "Microsoft.Win32.Registry",
            "System.Text.Encoding.CodePages",
            "System.Threading.Channels",
        ],
        "src/Runner.Listener/Runner.Listener.csproj": ["Microsoft.Win32.Registry"],
        "src/Runner.PluginHost/Runner.PluginHost.csproj": ["System.Runtime.Loader"],
        "src/Runner.Sdk/Runner.Sdk.csproj": [
            "Microsoft.Win32.Registry",
            "System.Text.Encoding.CodePages",
            "System.Threading.Channels",
        ],
        "src/Runner.Worker/Runner.Worker.csproj": ["System.Threading.Channels"],
        "src/Sdk/Sdk.csproj": [
            "Microsoft.Win32.Registry",
            "System.Formats.Asn1",
            "System.Net.Http",
            "System.Private.Uri",
            "System.Security.Cryptography.Cng",
            "System.Text.RegularExpressions",
        ],
    }
    for f, names in in_shared_framework.items():
        for name in names:
            remove_package_ref(repo, f, name)

    # 10. Microsoft.DevTunnels.Connections pulls in WebUtilities 8.0.25, which
    #     NuGet audit fails (NU1903, CVE-2026-114149 / GHSA-x33c-w48q-qrgc).
    #     Pin the patched 10.0 release directly.
    patch(
        repo,
        "src/Runner.Worker/Runner.Worker.csproj",
        "</Project>",
        """  <ItemGroup>
    <PackageReference Include="Microsoft.AspNetCore.WebUtilities" Version="10.0.15" />
  </ItemGroup>
</Project>""",
    )

    print("All patches applied successfully.")


if __name__ == "__main__":
    main()