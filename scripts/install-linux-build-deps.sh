#!/usr/bin/env bash
set -euo pipefail

sudo apt-get update
sudo apt-get install -y curl git lsb-release python3 xz-utils

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

deps_script="$tmp_dir/install-build-deps.sh"
curl -fsSL \
  "https://chromium.googlesource.com/chromium/src/+/main/build/install-build-deps.sh?format=TEXT" \
  | base64 -d > "$deps_script"

chmod +x "$deps_script"

args=(--no-prompt --no-chromeos-fonts)
if [[ "${CEF_ARCH:-}" == "arm64" ]]; then
  args+=(--arm)
fi

sudo "$deps_script" "${args[@]}"
