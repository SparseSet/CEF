param(
  [Parameter(Mandatory = $true)]
  [string]$CefBranch,

  [Parameter(Mandatory = $true)]
  [string]$DownloadDir,

  [Parameter(Mandatory = $true)]
  [ValidateSet("x64", "arm64")]
  [string]$Arch,

  [Parameter(Mandatory = $true)]
  [string]$GnDefines,

  [string]$BuildTarget = "cefsimple",

  [bool]$WithPgoProfiles = $false
)

$ErrorActionPreference = "Stop"

function Get-PythonCommand {
  foreach ($candidate in @("python3", "python", "py")) {
    $command = Get-Command $candidate -ErrorAction SilentlyContinue
    if ($null -ne $command) {
      return $command.Source
    }
  }

  throw "Python was not found on PATH."
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$automateDir = Join-Path $repoRoot "tools\automate"
$automate = Join-Path $automateDir "automate-git.py"

New-Item -ItemType Directory -Force -Path $automateDir | Out-Null
New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null

Invoke-WebRequest `
  -Uri "https://raw.githubusercontent.com/chromiumembedded/cef/master/tools/automate/automate-git.py" `
  -OutFile $automate `
  -UseBasicParsing

$env:GN_DEFINES = $GnDefines
$env:GYP_MSVS_VERSION = "2022"
$env:CEF_ARCHIVE_FORMAT = "tar.bz2"

$archFlag = "--x64-build"
if ($Arch -eq "arm64") {
  $env:CEF_ENABLE_ARM64 = "1"
  $env:GYP_DEFINES = "target_arch=arm64"
  $archFlag = "--arm64-build"
}

$automateArgs = @(
  $automate,
  "--download-dir=$DownloadDir",
  "--branch=$CefBranch",
  "--minimal-distrib",
  "--client-distrib",
  "--force-clean",
  "--no-chromium-history",
  "--build-target=$BuildTarget",
  $archFlag
)

if ($WithPgoProfiles) {
  $automateArgs += "--with-pgo-profiles"
}

$python = Get-PythonCommand
Write-Host "Building CEF branch $CefBranch for Windows $Arch"
Write-Host "GN_DEFINES=$env:GN_DEFINES"
& $python @automateArgs
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
