$env:AWS_DEFAULT_REGION = "us-east-1"

$env:CEF_ARTIFACT_BUCKET = "prototwin-build-artifacts"
$env:CEF_S3_PREFIX = "cef-builds"

# Optional. Defaults are usually fine.
# $env:CEF_BRANCH = "7204"
# $env:CEF_DOWNLOAD_DIR = "C:\cef"
# Leave unset for target-specific defaults:
# - true for windows-x64
# - false for windows-arm64
# $env:CEF_WITH_PGO_PROFILES = "false"
