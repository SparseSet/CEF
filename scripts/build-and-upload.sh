#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/build-and-upload.sh <target> [--download-dir DIR] [--build-dir DIR] [--skip-prereqs] [--resume] [--foreground] [--no-upload]

Targets:
  linux-x64
  linux-arm64
  macos-arm64

Before running with uploads enabled, fill in config/build.env with the target
S3 bucket and make sure the machine has AWS credentials, usually from an EC2
instance role. Use --no-upload to build locally without S3.

By default this script starts the build in the background with nohup and writes
to logs/<target>-<timestamp>.log. Use --foreground to run in the current shell.
EOF
}

finish() {
  exit_code=$?
  set +e

  if [[ "${NO_UPLOAD:-false}" == "false" && -n "${CEF_BUILD_LOG_FILE:-}" && -f "${CEF_BUILD_LOG_FILE:-}" ]]; then
    log_name="$(basename "$CEF_BUILD_LOG_FILE")"
    log_s3_uri="s3://${CEF_ARTIFACT_BUCKET}/${CEF_S3_PREFIX:-cef-builds}/${CEF_BRANCH}/${TARGET}/logs/${log_name}"
    echo
    echo "Build finished with exit code $exit_code at $(date)"
    echo "Uploading build log to $log_s3_uri"
    aws s3 cp "$CEF_BUILD_LOG_FILE" "$log_s3_uri"
  fi

  exit "$exit_code"
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

TARGET="$1"
shift

SKIP_PREREQS=false
FOREGROUND=false
NO_UPLOAD=false
RESUME=false
REQUESTED_DOWNLOAD_DIR=""
REQUESTED_BUILD_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --download-dir)
      if [[ $# -lt 2 || "$2" == -* ]]; then
        echo "--download-dir requires a directory argument." >&2
        exit 1
      fi
      REQUESTED_DOWNLOAD_DIR="$2"
      shift
      ;;
    --build-dir)
      if [[ $# -lt 2 || "$2" == -* ]]; then
        echo "--build-dir requires a directory argument." >&2
        exit 1
      fi
      REQUESTED_BUILD_DIR="$2"
      shift
      ;;
    --skip-prereqs)
      SKIP_PREREQS=true
      ;;
    --resume)
      RESUME=true
      ;;
    --foreground)
      FOREGROUND=true
      ;;
    --no-upload)
      NO_UPLOAD=true
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

if [[ "$NO_UPLOAD" == "false" ]]; then
  : "${AWS_DEFAULT_REGION:?AWS_DEFAULT_REGION is required}"
  : "${CEF_ARTIFACT_BUCKET:?CEF_ARTIFACT_BUCKET is required}"
fi

export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-}"
export AWS_REGION="$AWS_DEFAULT_REGION"
export CEF_BRANCH="${CEF_BRANCH:-7204}"
export CEF_WITH_PGO_PROFILES="${CEF_WITH_PGO_PROFILES:-}"

RUN_ARGS=("$TARGET")
if [[ -n "$REQUESTED_DOWNLOAD_DIR" ]]; then
  RUN_ARGS+=("--download-dir" "$REQUESTED_DOWNLOAD_DIR")
fi
if [[ -n "$REQUESTED_BUILD_DIR" ]]; then
  RUN_ARGS+=("--build-dir" "$REQUESTED_BUILD_DIR")
fi
if [[ "$SKIP_PREREQS" == "true" ]]; then
  RUN_ARGS+=("--skip-prereqs")
fi
if [[ "$RESUME" == "true" ]]; then
  RUN_ARGS+=("--resume")
fi
if [[ "$NO_UPLOAD" == "true" ]]; then
  RUN_ARGS+=("--no-upload")
fi

case "$TARGET" in
  linux-x64)
    [[ "$(uname -s)" == "Linux" ]] || { echo "$TARGET must run on Linux." >&2; exit 1; }
    export CEF_ARCH="x64"
    export CEF_BUILD_TARGET="cefsimple"
    export CEF_DOWNLOAD_DIR="${REQUESTED_DOWNLOAD_DIR:-${CEF_DOWNLOAD_DIR:-/tmp/cef}}"
    export CEF_WITH_PGO_PROFILES="${CEF_WITH_PGO_PROFILES:-true}"
    export CEF_GN_DEFINES="is_official_build=true use_sysroot=true symbol_level=0 blink_symbol_level=0 v8_symbol_level=0 is_cfi=false v8_enable_sandbox=false proprietary_codecs=true ffmpeg_branding=Chrome"
    ;;
  linux-arm64)
    [[ "$(uname -s)" == "Linux" ]] || { echo "$TARGET must run on Linux." >&2; exit 1; }
    export CEF_ARCH="arm64"
    export CEF_BUILD_TARGET="cefsimple"
    export CEF_DOWNLOAD_DIR="${REQUESTED_DOWNLOAD_DIR:-${CEF_DOWNLOAD_DIR:-/tmp/cef}}"
    export CEF_WITH_PGO_PROFILES="${CEF_WITH_PGO_PROFILES:-false}"
    export CEF_GN_DEFINES="is_official_build=true use_sysroot=true symbol_level=0 blink_symbol_level=0 v8_symbol_level=0 is_cfi=false use_thin_lto=false chrome_pgo_phase=0 v8_enable_sandbox=false proprietary_codecs=true ffmpeg_branding=Chrome"
    ;;
  macos-arm64)
    [[ "$(uname -s)" == "Darwin" ]] || { echo "$TARGET must run on macOS." >&2; exit 1; }
    export CEF_ARCH="arm64"
    export CEF_BUILD_TARGET="cefclient"
    export CEF_DOWNLOAD_DIR="${REQUESTED_DOWNLOAD_DIR:-${CEF_DOWNLOAD_DIR:-/tmp/cef}}"
    export CEF_WITH_PGO_PROFILES="${CEF_WITH_PGO_PROFILES:-true}"
    export CEF_GN_DEFINES="is_official_build=true v8_enable_sandbox=false proprietary_codecs=true ffmpeg_branding=Chrome"
    ;;
  *)
    echo "Unsupported target: $TARGET" >&2
    usage
    exit 1
    ;;
esac

export CEF_BUILD_DIR="${REQUESTED_BUILD_DIR:-${CEF_BUILD_DIR:-}}"
if [[ "$RESUME" == "true" ]]; then
  export CEF_FORCE_CLEAN="false"
  export CEF_FORCE_BUILD="true"
  export CEF_FORCE_DISTRIB="true"
else
  export CEF_FORCE_CLEAN="${CEF_FORCE_CLEAN:-true}"
  export CEF_FORCE_BUILD="${CEF_FORCE_BUILD:-false}"
  export CEF_FORCE_DISTRIB="${CEF_FORCE_DISTRIB:-false}"
fi

if [[ "$FOREGROUND" == "false" ]]; then
  mkdir -p "$LOG_DIR"
  timestamp="$(date +"%Y%m%d-%H%M%S")"
  LOG_FILE="$LOG_DIR/$TARGET-$timestamp.log"
  LATEST_LOG="$LOG_DIR/$TARGET-latest.log"
  PID_FILE="$LOG_DIR/$TARGET-latest.pid"

  ln -sfn "$LOG_FILE" "$LATEST_LOG"
  CEF_BUILD_LOG_FILE="$LOG_FILE" nohup bash "$SCRIPT_PATH" "${RUN_ARGS[@]}" --foreground >"$LOG_FILE" 2>&1 </dev/null &
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

trap finish EXIT

echo "Started $TARGET build at $(date)"
echo "Repository: $REPO_ROOT"
echo "Download directory: $CEF_DOWNLOAD_DIR"
if [[ -n "$CEF_BUILD_DIR" ]]; then
  echo "Build artifact directory: $CEF_BUILD_DIR"
fi
echo

if [[ "$NO_UPLOAD" == "false" ]] && ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI is required for artifact upload." >&2
  exit 1
fi

if [[ "$(uname -s)" == "Linux" && "$SKIP_PREREQS" == "false" ]]; then
  bash "$REPO_ROOT/scripts/install-linux-build-deps.sh"
fi

bash "$REPO_ROOT/scripts/build-cef.sh"

ARTIFACT_SOURCE_DIR="$CEF_DOWNLOAD_DIR/chromium/src/cef/binary_distrib"

if [[ ! -d "$ARTIFACT_SOURCE_DIR" ]]; then
  echo "Expected artifact directory does not exist: $ARTIFACT_SOURCE_DIR" >&2
  exit 1
fi

ARTIFACT_DIR="$ARTIFACT_SOURCE_DIR"
if [[ -n "$CEF_BUILD_DIR" ]]; then
  mkdir -p "$CEF_BUILD_DIR"
  cp -a "$ARTIFACT_SOURCE_DIR"/. "$CEF_BUILD_DIR"/
  ARTIFACT_DIR="$CEF_BUILD_DIR"
fi

if [[ "$NO_UPLOAD" == "true" ]]; then
  echo "Upload disabled. Artifacts are available at:"
  echo "  $ARTIFACT_DIR"
  exit 0
fi

S3_PREFIX="${CEF_S3_PREFIX:-cef-builds}/$CEF_BRANCH/$TARGET"
S3_URI="s3://$CEF_ARTIFACT_BUCKET/$S3_PREFIX"

echo "Uploading artifacts to $S3_URI/"
aws s3 cp --recursive "$ARTIFACT_DIR" "$S3_URI/"
echo "Done: $S3_URI/"
