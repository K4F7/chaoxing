# CI native build for the Windows production host.
# TypeScript is verified by the caller. This script publishes the C# shell
# and, when ISCC is available, the per-user Inno installer.
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $root "build\windows\x64"
$installerOut = Join-Path $root "build"
New-Item -ItemType Directory -Force -Path $out | Out-Null
New-Item -ItemType Directory -Force -Path $installerOut | Out-Null

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
  throw "dotnet SDK is missing on this runner; cannot publish the Windows shell."
}

$csproj = Join-Path $root "native\ChaoxingWindowsShell\ChaoxingWindowsShell.csproj"
dotnet publish $csproj -c Release -r win-x64 --self-contained true -o $out

$exe = Join-Path $out "chaoxing_windows.exe"
if (-not (Test-Path -LiteralPath $exe)) {
  throw "dotnet publish did not produce chaoxing_windows.exe"
}

$isccCandidates = @(
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "${env:ProgramFiles}\Inno Setup 6\ISCC.exe"
)
$iscc = $isccCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

if (-not $iscc) {
  Write-Host "Inno Setup (ISCC.exe) is not installed; attempting Chocolatey."
  if (Get-Command choco -ErrorAction SilentlyContinue) {
    choco install innosetup --no-progress -y
    $iscc = $isccCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
  } else {
    Write-Host "Chocolatey is not available; skipping installer."
  }
}

if (-not $iscc) {
  Write-Host "ISCC.exe still missing after install attempt; C# publish succeeded, installer skipped."
  "mode=csharp-only`nmissing=Inno Setup ISCC.exe" | Set-Content -LiteralPath (Join-Path $installerOut "WINDOWS-BUILD.txt")
  exit 0
}

$version = if ($env:GITHUB_RUN_NUMBER) { "1.0.$($env:GITHUB_RUN_NUMBER)" } else { "0.0.0-ci" }
$iss = Join-Path $root "installer\chaoxing_windows.iss"
& $iscc "/DAppVersion=$version" $iss
if ($LASTEXITCODE -ne 0) {
  throw "ISCC.exe failed with exit code $LASTEXITCODE"
}

$setup = Join-Path $installerOut "chaoxing-windows-x64-setup.exe"
if (-not (Test-Path -LiteralPath $setup)) {
  throw "ISCC.exe did not produce chaoxing-windows-x64-setup.exe"
}

"mode=csharp+inno`ninstaller=chaoxing-windows-x64-setup.exe" | Set-Content -LiteralPath (Join-Path $installerOut "WINDOWS-BUILD.txt")
Write-Host "Published $exe and $setup"
