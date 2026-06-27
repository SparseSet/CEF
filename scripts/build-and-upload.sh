#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/build-and-upload.sh <target> [--skip-prereqs] [--foreground]

Targets:
  linux-x64
  linux-arm64
  macos-arm64

Before running, fill in config/build.env with the target S3 bucket and make
sure the machine has AWS credentials, usually from an EC2 instance role.

By default this script starts the build in the background with nohup and writes
to logs/<target>-<timestamp>.log. Use --foreground to run in the current shell.
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

TARGET="$1"
shift

SKIP_PREREQS=false
FOREGROUND=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-prereqs)
      SKIP_PREREQS=true
      ;;
    --foreground)
      FOREGROUND=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_PATH="$REPO_ROOT/scripts/build-and-upload.sh"
CONFIG_FILE="$REPO_ROOT/config/build.env"
LOG_DIR="$REPO_ROOT/logs"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Missing $CONFIG_FILE. Fill in config/build.env before running." >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

: "${AWS_DEFAULT_REGION:?AWS_DEFAULT_REGION is required}"
: "${CEF_ARTIFACT_BUCKET:?CEF_ARTIFACT_BUCKET is required}"

export AWS_DEFAULT_REGION
export AWS_REGION="$AWS_DEFAULT_REGION"
export CEF_BRANCH="${CEF_BRANCH:-7204}"
export CEF_BUILD_TARGET="cefsimple"
export CEF_WITH_PGO_PROFILES="${CEF_WITH_PGO_PROFILES:-}"

RUN_ARGS=("$TARGET")
if [[ "$SKIP_PREREQS" == "true" ]]; then
  RUN_ARGS+=("--skip-prereqs")
fi

case "$TARGET" in
  linux-x64)
    [[ "$(uname -s)" == "Linux" ]] || { echo "$TARGET must run on Linux." >&2; exit 1; }
    export CEF_ARCH="x64"
    export CEF_DOWNLOAD_DIR="${CEF_DOWNLOAD_DIR:-/tmp/cef}"
    export CEF_WITH_PGO_PROFILES="${CEF_WITH_PGO_PROFILES:-true}"
    export CEF_GN_DEFINES="is_official_build=true use_sysroot=true symbol_level=1 is_cfi=false v8_enable_sandbox=false proprietary_codecs=true ffmpeg_branding=Chrome"
    ;;
  linux-arm64)
    [[ "$(uname -s)" == "Linux" ]] || { echo "$TARGET must run on Linux." >&2; exit 1; }
    export CEF_ARCH="arm64"
    export CEF_DOWNLOAD_DIR="${CEF_DOWNLOAD_DIR:-/tmp/cef}"
    export CEF_WITH_PGO_PROFILES="${CEF_WITH_PGO_PROFILES:-false}"
    export CEF_GN_DEFINES="is_official_build=true use_sysroot=true symbol_level=1 is_cfi=false use_thin_lto=false chrome_pgo_phase=0 v8_enable_sandbox=false proprietary_codecs=true ffmpeg_branding=Chrome"
    ;;
  macos-arm64)
    [[ "$(uname -s)" == "Darwin" ]] || { echo "$TARGET must run on macOS." >&2; exit 1; }
    export CEF_ARCH="arm64"
    export CEF_DOWNLOAD_DIR="${CEF_DOWNLOAD_DIR:-/tmp/cef}"
    export CEF_WITH_PGO_PROFILES="${CEF_WITH_PGO_PROFILES:-true}"
    export CEF_GN_DEFINES="is_official_build=true v8_enable_sandbox=false proprietary_codecs=true ffmpeg_branding=Chrome"
    ;;
  *)
    echo "Unsupported target: $TARGET" >&2
    usage
    exit 1
    ;;
esac

if [[ "$FOREGROUND" == "false" ]]; then
  mkdir -p "$LOG_DIR"
  timestamp="$(date +"%Y%m%d-%H%M%S")"
  LOG_FILE="$LOG_DIR/$TARGET-$timestamp.log"
  LATEST_LOG="$LOG_DIR/$TARGET-latest.log"
  PID_FILE="$LOG_DIR/$TARGET-latest.pid"

  ln -sfn "$LOG_FILE" "$LATEST_LOG"
  nohup bash "$SCRIPT_PATH" "${RUN_ARGS[@]}" --foreground >"$LOG_FILE" 2>&1 </dev/null &
  build_pid="$!"
  printf "%s\n" "$build_pid" >"$PID_FILE"

  echo "Started $TARGET build in the background."
  echo "PID: $build_pid"
  echo "Log: $LOG_FILE"
  echo "Latest log: $LATEST_LOG"
  echo
  echo "Watch progress:"
  echo "  tail -f \"$LATEST_LOG\""
  exit 0
fi

echo "Started $TARGET build at $(date)"
echo "Repository: $REPO_ROOT"
echo "Download directory: $CEF_DOWNLOAD_DIR"
echo

if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI is required for artifact upload." >&2
  exit 1
fi

if [[ "$(uname -s)" == "Linux" && "$SKIP_PREREQS" == "false" ]]; then
  bash "$REPO_ROOT/scripts/install-linux-build-deps.sh"
fi

bash "$REPO_ROOT/scripts/build-cef.sh"

ARTIFACT_DIR="$CEF_DOWNLOAD_DIR/chromium/src/cef/binary_distrib"
S3_PREFIX="${CEF_S3_PREFIX:-cef-builds}/$CEF_BRANCH/$TARGET"
S3_URI="s3://$CEF_ARTIFACT_BUCKET/$S3_PREFIX"

if [[ ! -d "$ARTIFACT_DIR" ]]; then
  echo "Expected artifact directory does not exist: $ARTIFACT_DIR" >&2
  exit 1
fi

echo "Uploading artifacts to $S3_URI/"
aws s3 cp --recursive "$ARTIFACT_DIR" "$S3_URI/"
echo "Done: $S3_URI/"
