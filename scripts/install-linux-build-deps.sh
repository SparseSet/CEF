#!/usr/bin/env bash
set -euo pipefail

sudo apt-get update
sudo apt-get install -y curl git lsb-release python3 xz-utils

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

deps_script="$tmp_dir/install-build-deps.sh"
deps_python="$tmp_dir/install-build-deps.py"

download_base64() {
  local url="$1"
  local output="$2"

  curl -fsSL \
    --retry 10 \
    --retry-delay 10 \
    --retry-all-errors \
    "$url" \
    | base64 -d > "$output"
}

download_base64 \
  "https://chromium.googlesource.com/chromium/src/+/main/build/install-build-deps.sh?format=TEXT" \
  "$deps_script"
download_base64 \
  "https://chromium.googlesource.com/chromium/src/+/main/build/install-build-deps.py?format=TEXT" \
  "$deps_python"

chmod +x "$deps_script"
chmod +x "$deps_python"

args=(--no-prompt --no-chromeos-fonts)
if [[ "${CEF_ARCH:-}" == "arm64" ]]; then
  args+=(--arm)
fi

sudo "$deps_script" "${args[@]}"
