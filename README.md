# CEF Manual Build Scripts

This repository contains build scripts for producing Chromium Embedded Framework
(CEF) binary distributions without storing CEF or Chromium source code in this
repo.

The intended workflow is:

1. Start a build machine manually, such as an EC2 instance or your Mac mini.
2. Clone this repository.
3. Fill in the S3 upload config.
4. Run the target build script.
5. Download the generated archives from S3.
6. Terminate the build machine when done.

There are no GitHub Actions workflows in this branch.

## Targets

Supported targets:

| Target | Host machine |
| --- | --- |
| `linux-x64` | Linux x64 |
| `linux-arm64` | Linux x64 cross-build |
| `windows-x64` | Windows x64 |
| `windows-arm64` | Windows x64 cross-build |
| `macos-arm64` | Apple Silicon macOS |

Windows ARM64 is built on Windows x64 using the Visual Studio ARM64 toolchain.
Linux ARM64 is built on Linux x64 using CEF's ARM64 sysroot flow.

## Build Flags

All targets build release-only distributions and pass:

```text
--minimal-distrib
--client-distrib
--force-clean
--no-chromium-history
--no-debug-build
--build-target=cefsimple
```

All targets set:

```text
v8_enable_sandbox=false
proprietary_codecs=true
ffmpeg_branding=Chrome
```

The proprietary codec flags are included for MP4/H.264/AAC support. You are
responsible for any codec licensing requirements that apply to your
distribution.

PGO profile downloads are target-specific:

| Target | Default |
| --- | --- |
| `linux-x64` | enabled |
| `windows-x64` | enabled |
| `macos-arm64` | enabled |
| `linux-arm64` | disabled |
| `windows-arm64` | disabled |

The ARM64 cross-build targets also set `chrome_pgo_phase=0`, matching CEF's
automated build examples for those targets.

## S3 Upload Config

Linux/macOS: edit `config/build.env` and set:

```bash
AWS_DEFAULT_REGION="us-east-1"
CEF_ARTIFACT_BUCKET="prototwin-build-artifacts"
CEF_S3_PREFIX="cef-builds"
```

Windows: edit `config\build.ps1` and set:

```powershell
$env:AWS_DEFAULT_REGION = "us-east-1"
$env:CEF_ARTIFACT_BUCKET = "prototwin-build-artifacts"
$env:CEF_S3_PREFIX = "cef-builds"
```

The machine needs AWS credentials with S3 write access to:

```text
s3://<CEF_ARTIFACT_BUCKET>/<CEF_S3_PREFIX>/*
```

For EC2, use an IAM instance profile. Create this once, then attach the same
role whenever you launch a build instance. Stop/start of the same instance keeps
the role attached.

Create an IAM policy like this:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "BucketMetadata",
      "Effect": "Allow",
      "Action": [
        "s3:GetBucketLocation",
        "s3:ListBucket",
        "s3:ListBucketMultipartUploads"
      ],
      "Resource": "arn:aws:s3:::prototwin-build-artifacts"
    },
    {
      "Sid": "UploadCefArtifacts",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:AbortMultipartUpload",
        "s3:ListMultipartUploadParts"
      ],
      "Resource": "arn:aws:s3:::prototwin-build-artifacts/cef-builds/*"
    }
  ]
}
```

Create an IAM role with trusted entity `EC2`, attach that policy, and select the
role under **IAM instance profile** when launching the EC2 instance. For an
existing instance, use **Actions > Security > Modify IAM role**.

Verify access on the instance:

```bash
aws sts get-caller-identity
aws s3 ls s3://prototwin-build-artifacts/cef-builds/
```

## Linux

Use Ubuntu 22.04 or another CEF-supported Linux distro. For a fresh EC2 machine,
use a large instance with at least 32 vCPU, 128 GB RAM and a 1 TB root volume.

Install AWS CLI first if your image does not include it:

```bash
sudo apt-get update
sudo apt-get install -y awscli git python3 curl xz-utils
```

Run:

```bash
git clone <this-repo-url> CEF
cd CEF
# edit config/build.env

bash scripts/build-and-upload.sh linux-x64
```

For Linux ARM64:

```bash
bash scripts/build-and-upload.sh linux-arm64
```

The script runs `scripts/install-linux-build-deps.sh` automatically. If you have
already installed prerequisites and want to skip that step:

```bash
bash scripts/build-and-upload.sh linux-x64 --skip-prereqs
```

## Windows

Use Windows Server 2022 or Windows 10/11 x64. For EC2, use a large x64 instance
with at least 32 vCPU, 128 GB RAM and a 1 TB root volume.

For a fresh machine, run PowerShell as Administrator and use:

```powershell
git clone <this-repo-url> CEF
cd CEF
# edit config\build.ps1

.\scripts\build-and-upload.ps1 -Target windows-x64 -InstallPrereqs
```

For Windows ARM64:

```powershell
.\scripts\build-and-upload.ps1 -Target windows-arm64 -InstallPrereqs
```

`-InstallPrereqs` runs `scripts\install-windows-build-deps.ps1`, which installs
Chocolatey, AWS CLI, Git, Python, Visual Studio 2022 Build Tools, the C++
workload and Windows SDK package. For repeat runs on the same machine, omit
`-InstallPrereqs`.

For CEF branch `7204`, CEF's branch table calls for VS2022 17.13.4 and Windows
SDK 10.0.26100.3323. If Chocolatey's package versions move beyond those, you may
need to install the exact Visual Studio/SDK versions manually.

## macOS ARM64

Use your Apple Silicon Mac mini. Install Xcode and accept the license:

```bash
sudo xcodebuild -license accept
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

Install AWS CLI if needed, for example with Homebrew:

```bash
brew install awscli
```

Run:

```bash
git clone <this-repo-url> CEF
cd CEF
# edit config/build.env

bash scripts/build-and-upload.sh macos-arm64
```

Keep the machine awake for the full build.

## Long-Running Builds

On Linux/macOS, `scripts/build-and-upload.sh` starts the actual build as a
detached `nohup` process by default. That means the build keeps running if your
SSH session disconnects.

Run the script normally:

```bash
bash scripts/build-and-upload.sh linux-x64
```

The script prints the background PID and writes logs under `logs/`, including a
stable latest-log symlink for the target:

```bash
tail -f logs/linux-x64-latest.log
```

After reconnecting, run the same `tail -f` command to resume viewing logs. To
check whether the latest build is still running:

```bash
ps -p "$(cat logs/linux-x64-latest.pid)"
```

For debugging, or if you deliberately want the build tied to the current shell,
run with `--foreground`:

```bash
bash scripts/build-and-upload.sh linux-x64 --foreground
```

On Windows, disconnecting an RDP session normally leaves processes running, but
closing the PowerShell window stops the build. Use `Start-Transcript` to save a
log:

```powershell
Start-Transcript -Path build-windows-x64.log
.\scripts\build-and-upload.ps1 -Target windows-x64 -InstallPrereqs
Stop-Transcript
```

After reconnecting, view the live log with:

```powershell
Get-Content .\build-windows-x64.log -Wait
```

## Output

Artifacts upload to:

```text
s3://<CEF_ARTIFACT_BUCKET>/<CEF_S3_PREFIX>/<cef_branch>/<target>/
```

For the default branch and Linux x64, that is:

```text
s3://<bucket>/cef-builds/7204/linux-x64/
```

The local build output is under:

```text
<CEF_DOWNLOAD_DIR>/chromium/src/cef/binary_distrib/
```

Defaults:

| Platform | Default `CEF_DOWNLOAD_DIR` |
| --- | --- |
| Linux/macOS | `/tmp/cef` |
| Windows | `C:\cef` |

## Notes

These scripts intentionally use short build paths on Windows to avoid path
length and non-ASCII path issues.

CEF and Chromium builds are large. Make sure the machine has enough CPU, RAM,
disk and time before starting a build.
