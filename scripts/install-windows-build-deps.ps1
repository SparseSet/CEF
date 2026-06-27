param()

$ErrorActionPreference = "Stop"

function Invoke-Checked {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
  )

  & $FilePath @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "$FilePath failed with exit code $LASTEXITCODE"
  }
}

function Get-VsWherePath {
  $candidates = @(
    (Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"),
    (Join-Path $env:ProgramFiles "Microsoft Visual Studio\Installer\vswhere.exe")
  )

  foreach ($candidate in $candidates) {
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  throw "vswhere.exe was not found."
}

function Get-VsBuildToolsPath {
  $vsWhere = Get-VsWherePath
  $installPath = & $vsWhere `
    -products * `
    -version "[17.0,18.0)" `
    -requires Microsoft.VisualStudio.Workload.VCTools `
    -property installationPath `
    -latest

  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($installPath)) {
    throw "Visual Studio 2022 Build Tools with VCTools workload was not found."
  }

  return $installPath.Trim()
}

if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
  Set-ExecutionPolicy Bypass -Scope Process -Force
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  Invoke-Expression ((New-Object Net.WebClient).DownloadString("https://community.chocolatey.org/install.ps1"))
}

Invoke-Checked choco install -y awscli git python3 7zip
Invoke-Checked choco install -y visualstudio2022buildtools visualstudio2022-workload-vctools

$vsSetup = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\setup.exe"

if (-not (Test-Path $vsSetup)) {
  throw "Visual Studio installer was not found at $vsSetup"
}

$vsInstallPath = Get-VsBuildToolsPath
$sdkInstallArgs = @(
  "modify",
  "--installPath", "`"$vsInstallPath`"",
  "--add", "Microsoft.VisualStudio.Component.Windows11SDK.26100",
  "--add", "Microsoft.VisualStudio.Component.VC.ATLMFC",
  "--add", "Microsoft.VisualStudio.Component.VC.Tools.ARM64",
  "--add", "Microsoft.VisualStudio.Component.VC.MFC.ARM64",
  "--includeRecommended",
  "--quiet",
  "--norestart"
) -join " "
$sdkInstall = Start-Process `
  -FilePath $vsSetup `
  -ArgumentList $sdkInstallArgs `
  -Wait `
  -PassThru

if ($sdkInstall.ExitCode -ne 0 -and $sdkInstall.ExitCode -ne 3010) {
  throw "Windows SDK installation failed with exit code $($sdkInstall.ExitCode)"
}

if ($sdkInstall.ExitCode -eq 3010) {
  Write-Host "Visual Studio installer requested a reboot. Continuing, but reboot before building if toolchain detection fails."
}

$env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")

Write-Host "Windows build prerequisites installed."
