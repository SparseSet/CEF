#!/usr/bin/env bash
set -euo pipefail

: "${CEF_BRANCH:?CEF_BRANCH is required}"
: "${CEF_DOWNLOAD_DIR:?CEF_DOWNLOAD_DIR is required}"
: "${CEF_ARCH:?CEF_ARCH is required}"
: "${CEF_GN_DEFINES:?CEF_GN_DEFINES is required}"

BUILD_TARGET="${CEF_BUILD_TARGET:-cefsimple}"
WITH_PGO_PROFILES="${CEF_WITH_PGO_PROFILES:-false}"

case "$CEF_ARCH" in
  x64)
    ARCH_FLAG="--x64-build"
    ;;
  arm64)
    ARCH_FLAG="--arm64-build"
    if [[ "$(uname -s)" == "Linux" ]]; then
      export CEF_INSTALL_SYSROOT=arm64
    else
      export CEF_ENABLE_ARM64=1
    fi
    ;;
  *)
    echo "Unsupported CEF_ARCH: $CEF_ARCH" >&2
    exit 1
    ;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUTOMATE_DIR="$REPO_ROOT/tools/automate"
AUTOMATE="$AUTOMATE_DIR/automate-git.py"

mkdir -p "$AUTOMATE_DIR" "$CEF_DOWNLOAD_DIR"
curl -fsSL \
  "https://raw.githubusercontent.com/chromiumembedded/cef/master/tools/automate/automate-git.py" \
  -o "$AUTOMATE"

export GN_DEFINES="$CEF_GN_DEFINES"
export CEF_ARCHIVE_FORMAT=tar.bz2

ARGS=(
  "$AUTOMATE"
  "--download-dir=$CEF_DOWNLOAD_DIR"
  "--branch=$CEF_BRANCH"
  "--minimal-distrib"
  "--client-distrib"
  "--force-clean"
  "--no-chromium-history"
  "--build-target=$BUILD_TARGET"
  "$ARCH_FLAG"
)

if [[ "$WITH_PGO_PROFILES" == "true" ]]; then
  ARGS+=("--with-pgo-profiles")
fi

echo "Building CEF branch $CEF_BRANCH for $(uname -s) $CEF_ARCH"
echo "GN_DEFINES=$GN_DEFINES"
python3 "${ARGS[@]}"
