# CEF Build Scripts

Scripts for building CEF binary distributions. CEF and Chromium source are
downloaded by the build scripts; they are not stored in this repository.

## Targets

| Target | Host |
| --- | --- |
| `linux-x64` | Linux x64 |
| `linux-arm64` | Linux x64 |
| `windows-x64` | Windows x64 |
| `windows-arm64` | Windows x64 |
| `macos-arm64` | Apple Silicon macOS |

## Configure

Edit `config/build.env` on Linux/macOS or `config\build.ps1` on Windows.

S3 config and AWS credentials are only needed when upload is enabled. To build
without S3, pass `--no-upload` on Linux/macOS or `-NoUpload` on Windows.

## Arguments

Linux/macOS:

```bash
bash scripts/build-and-upload.sh <target> [--download-dir DIR] [--build-dir DIR] [--skip-prereqs] [--resume] [--no-upload] [--foreground]
```

| Argument | Meaning |
| --- | --- |
| `<target>` | Build target: `linux-x64`, `linux-arm64`, or `macos-arm64`. |
| `--download-dir DIR` | Download and compile under `DIR`. Defaults to `/tmp/cef`. |
| `--build-dir DIR` | Copy final CEF binary distributions to `DIR`. |
| `--skip-prereqs` | Do not run `scripts/install-linux-build-deps.sh`. |
| `--resume` | Reuse the existing checkout/build tree instead of passing `--force-clean`. |
| `--no-upload` | Build only; do not require AWS config and do not upload to S3. |
| `--foreground` | Run in the current shell instead of starting a detached `nohup` build. |

Windows:

```powershell
.\scripts\build-and-upload.ps1 -Target <target> [-DownloadDir DIR] [-BuildDir DIR] [-InstallPrereqs] [-Resume] [-NoUpload]
```

| Argument | Meaning |
| --- | --- |
| `-Target` | Build target: `windows-x64` or `windows-arm64`. |
| `-DownloadDir DIR` | Download and compile under `DIR`. Defaults to `C:\cef`. |
| `-BuildDir DIR` | Copy final CEF binary distributions to `DIR`. |
| `-InstallPrereqs` | Run `scripts\install-windows-build-deps.ps1` first. |
| `-Resume` | Reuse the existing checkout/build tree instead of passing `--force-clean`. |
| `-NoUpload` | Build only; do not require AWS config and do not upload to S3. |

## Linux

Run from a fresh machine:

```bash
sudo apt-get update
sudo apt-get install -y awscli git python3 curl xz-utils

git clone https://github.com/SparseSet/CEF.git CEF
cd CEF

bash scripts/build-and-upload.sh linux-x64
```

For Linux ARM64:

```bash
bash scripts/build-and-upload.sh linux-arm64
```

## Windows

Run PowerShell as Administrator:

```powershell
git clone https://github.com/SparseSet/CEF.git CEF
cd CEF

.\scripts\build-and-upload.ps1 -Target windows-x64 -InstallPrereqs
```

For Windows ARM64:

```powershell
.\scripts\build-and-upload.ps1 -Target windows-arm64 -InstallPrereqs
```

## macOS ARM64

Install Xcode and AWS CLI, then run:

```bash
sudo xcodebuild -license accept
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

git clone https://github.com/SparseSet/CEF.git CEF
cd CEF

bash scripts/build-and-upload.sh macos-arm64
```

To build on an external drive, pass `--download-dir /Volumes/<drive>/cef`.

## Logs

Linux/macOS builds start detached by default and keep running if SSH
disconnects. Display the latest log line every two seconds with:

```bash
watch -n 2 'tail -n 1 logs/linux-x64-latest.log'
```

Windows builds run in the current PowerShell session. To keep a log:

```powershell
Start-Transcript -Path build-windows-x64.log
.\scripts\build-and-upload.ps1 -Target windows-x64
Stop-Transcript
```

## Output

With upload enabled:

```text
s3://<CEF_ARTIFACT_BUCKET>/<CEF_S3_PREFIX>/<cef_branch>/<target>/
```

With upload disabled, or before upload:

```text
<CEF_DOWNLOAD_DIR>/chromium/src/cef/binary_distrib/
```

When `--build-dir` or `-BuildDir` is provided, final artifacts are copied there.

Default `CEF_DOWNLOAD_DIR`:

| Platform | Path |
| --- | --- |
| Linux/macOS | `/tmp/cef` |
| Windows | `C:\cef` |
