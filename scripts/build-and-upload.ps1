param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("windows-x64", "windows-arm64")]
  [string]$Target,

  [switch]$InstallPrereqs
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$configFile = Join-Path $repoRoot "config\build.ps1"

if (-not (Test-Path $configFile)) {
  throw "Missing $configFile. Fill in config/build.ps1 before running."
}

. $configFile

foreach ($name in @("AWS_DEFAULT_REGION", "CEF_ARTIFACT_BUCKET")) {
  if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) {
    throw "$name is required."
  }
}

if ($InstallPrereqs) {
  & (Join-Path $repoRoot "scripts\install-windows-build-deps.ps1")
}

if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
  throw "aws CLI is required for artifact upload."
}

$cefBranch = if ($env:CEF_BRANCH) { $env:CEF_BRANCH } else { "7204" }
$downloadDir = if ($env:CEF_DOWNLOAD_DIR) { $env:CEF_DOWNLOAD_DIR } else { "C:\cef" }
$s3PrefixRoot = if ($env:CEF_S3_PREFIX) { $env:CEF_S3_PREFIX } else { "cef-builds" }
$withPgoProfiles = if ($env:CEF_WITH_PGO_PROFILES) { [System.Convert]::ToBoolean($env:CEF_WITH_PGO_PROFILES) } else { $false }

switch ($Target) {
  "windows-x64" {
    $arch = "x64"
    if (-not $env:CEF_WITH_PGO_PROFILES) { $withPgoProfiles = $true }
    $gnDefines = "is_official_build=true v8_enable_sandbox=false proprietary_codecs=true ffmpeg_branding=Chrome"
  }
  "windows-arm64" {
    $arch = "arm64"
    if (-not $env:CEF_WITH_PGO_PROFILES) { $withPgoProfiles = $false }
    $gnDefines = "is_official_build=true use_thin_lto=false chrome_pgo_phase=0 v8_enable_sandbox=false proprietary_codecs=true ffmpeg_branding=Chrome"
  }
}

& (Join-Path $repoRoot "scripts\build-cef.ps1") `
  -CefBranch $cefBranch `
  -DownloadDir $downloadDir `
  -Arch $arch `
  -GnDefines $gnDefines `
  -BuildTarget "cefsimple" `
  -WithPgoProfiles:$withPgoProfiles

if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

$artifactDir = Join-Path $downloadDir "chromium\src\cef\binary_distrib"
if (-not (Test-Path $artifactDir)) {
  throw "Expected artifact directory does not exist: $artifactDir"
}

$s3Uri = "s3://$($env:CEF_ARTIFACT_BUCKET)/$s3PrefixRoot/$cefBranch/$Target"
Write-Host "Uploading artifacts to $s3Uri/"
aws s3 cp --recursive $artifactDir "$s3Uri/"

if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

Write-Host "Done: $s3Uri/"
