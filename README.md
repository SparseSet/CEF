# CEF GitHub Larger Runner Builds

This repository contains only build orchestration for Chromium Embedded Framework
(CEF). The GitHub Actions workflow downloads CEF's current `automate-git.py`
script at build time, then lets that script download Chromium, CEF and
`depot_tools`.

The builds intentionally set:

```text
v8_enable_sandbox=false
```

in every `GN_DEFINES` value.

## Requirements

- The `SparseSet` GitHub organization on GitHub Team or Enterprise Cloud.
- GitHub larger runners configured for this repository.
- A repository workflow permission setup that allows reading repository contents
  and uploading build artifacts.

The workflow expects these larger-runner labels:

| Target | Larger runner label | Notes |
| --- | --- | --- |
| Windows x64 | `cef-windows-x64` | Native x64 build |
| Windows ARM64 | `cef-windows-x64` | Cross-build with `CEF_ENABLE_ARM64=1` |
| Linux x64 | `cef-linux-x64` | Native x64 build |
| Linux ARM64 | `cef-linux-x64` | Cross-build with `CEF_INSTALL_SYSROOT=arm64` |
| macOS ARM64 | `cef-macos-arm64` | Apple Silicon build |

Recommended larger-runner shapes:

| Label | Platform | Recommended size |
| --- | --- | --- |
| `cef-windows-x64` | Windows x64, Windows Server 2022 image | 32-core or 64-core, at least 200 GB disk |
| `cef-linux-x64` | Ubuntu x64 | 32-core or 64-core, at least 200 GB disk |
| `cef-macos-arm64` | macOS ARM64 | 12-core Apple Silicon or larger, at least 200 GB disk |

Create those runners in the `SparseSet` organization settings and allow this
repository to use them. If you choose different labels, update
`.github/workflows/build-cef.yml` to match.

## Platform Prerequisites

For the default CEF branch `7204`, the CEF branch table lists these build
requirements:

| Platform | Requirements |
| --- | --- |
| Windows | Windows 10+ build system with VS2022 17.13.4, Windows 10.0.26100.3323 SDK, Ninja |
| macOS | macOS 15.2+ build system with Xcode 16.3 / 15.4 base SDK |
| Linux | Ubuntu 20.04+ or Debian 10+, Ninja |

CEF's Windows quick-start also calls out two practical requirements:

- Install the required Visual Studio sub-components from Chromium's Windows
  build instructions, not just a minimal Visual Studio shell.
- Use a short ASCII-only checkout path. The workflow uses `C:\cef` for
  Windows builds for that reason.

If you change `cef_branch`, check CEF's **Branches And Building** page and
update the runner images/tooling if the required Visual Studio, Windows SDK,
Xcode or Linux distribution changes.

## Running

Run one of the manual workflows from the GitHub Actions tab:

| Workflow | Target |
| --- | --- |
| **Build CEF Windows x64** | Windows x64 |
| **Build CEF Windows ARM64** | Windows ARM64 |
| **Build CEF Linux x64** | Linux x64 |
| **Build CEF Linux ARM64** | Linux ARM64 |
| **Build CEF macOS ARM64** | macOS ARM64 |

There is intentionally no workflow that builds every target at once.

Inputs:

- `cef_branch`: CEF branch number. Defaults to `7204`.
- `build_target`: Target passed to `automate-git.py --build-target`.
  Defaults to `cefsimple`.
- `with_pgo_profiles`: Adds `--with-pgo-profiles` when enabled. Defaults to
  enabled for Windows x64, Linux x64 and macOS ARM64, matching CEF's automated
  build examples. Defaults to disabled for Windows ARM64 and Linux ARM64
  cross-builds.

Each workflow uploads the generated archives from:

```text
<download-dir>/chromium/src/cef/binary_distrib/
```

as a GitHub Actions artifact.

## Notes

The workflow keeps CEF and Chromium source code out of this repository. On each
run, sources are downloaded under the runner's temporary directory.

CEF and Chromium builds are large. CEF's own automated build documentation calls
for at least 16 GB RAM and 200 GB free disk space per platform, which is why this
workflow uses GitHub larger runners instead of standard GitHub-hosted runners.
