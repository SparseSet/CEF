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

if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
  Set-ExecutionPolicy Bypass -Scope Process -Force
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  Invoke-Expression ((New-Object Net.WebClient).DownloadString("https://community.chocolatey.org/install.ps1"))
}

Invoke-Checked choco install -y awscli git python3 7zip
Invoke-Checked choco install -y visualstudio2022buildtools visualstudio2022-workload-vctools

$vsSetup = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\setup.exe"
$vsInstallPath = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\2022\BuildTools"

if (-not (Test-Path $vsSetup)) {
  throw "Visual Studio installer was not found at $vsSetup"
}

$sdkInstallArgs = "modify --installPath `"$vsInstallPath`" --add Microsoft.VisualStudio.Component.Windows11SDK.26100 --quiet --norestart"
$sdkInstall = Start-Process `
  -FilePath $vsSetup `
  -ArgumentList $sdkInstallArgs `
  -Wait `
  -PassThru

if ($sdkInstall.ExitCode -ne 0 -and $sdkInstall.ExitCode -ne 3010) {
  throw "Windows SDK installation failed with exit code $($sdkInstall.ExitCode)"
}

$env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")

Write-Host "Windows build prerequisites installed."
