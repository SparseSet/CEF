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

  [bool]$WithPgoProfiles = $false,

  [bool]$ForceClean = $true
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

function Get-VsBuildToolsPath {
  $vsWhereCandidates = @(
    (Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"),
    (Join-Path $env:ProgramFiles "Microsoft Visual Studio\Installer\vswhere.exe")
  )

  foreach ($vsWhere in $vsWhereCandidates) {
    if (-not (Test-Path $vsWhere)) {
      continue
    }

    $installPath = & $vsWhere `
      -products * `
      -version "[17.0,18.0)" `
      -requires Microsoft.VisualStudio.Workload.VCTools `
      -property installationPath `
      -latest

    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($installPath)) {
      return $installPath.Trim()
    }
  }

  throw "Visual Studio 2022 Build Tools with VCTools workload was not found."
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
$env:DEPOT_TOOLS_WIN_TOOLCHAIN = "0"
$env:GYP_MSVS_VERSION = "2022"
$env:GYP_MSVS_OVERRIDE_PATH = Get-VsBuildToolsPath
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
  "--no-chromium-history",
  "--no-debug-build",
  "--build-target=$BuildTarget",
  $archFlag
)

if ($ForceClean) {
  $automateArgs += "--force-clean"
}

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
