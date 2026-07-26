param(
  [string]$Installer = "build/chaoxing-app-windows-x64-setup.exe"
)

$ErrorActionPreference = "Stop"
$resolvedInstaller = (Resolve-Path -LiteralPath $Installer).Path
$installDirectory = Join-Path $env:LOCALAPPDATA "Programs\ChaoxingTodo"
$installedExecutable = Join-Path $installDirectory "chaoxing_app.exe"
$runKey = "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"
$runValue = "ChaoxingTodo"
$hiddenProcess = $null

function Wait-Until([scriptblock]$Condition, [string]$FailureMessage) {
  $deadline = [DateTime]::UtcNow.AddSeconds(20)
  while ([DateTime]::UtcNow -lt $deadline) {
    if (& $Condition) { return }
    Start-Sleep -Milliseconds 200
  }
  throw $FailureMessage
}

try {
  $install = Start-Process -FilePath $resolvedInstaller -ArgumentList @(
    "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART"
  ) -Wait -PassThru
  if ($install.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $installedExecutable)) {
    throw "Silent installation failed with exit code $($install.ExitCode)."
  }

  $expectedCommand = '"' + $installedExecutable + '" --hidden'
  & reg.exe add $runKey /v $runValue /t REG_SZ /d $expectedCommand /f | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Could not create the autostart value." }
  $actualCommand = (Get-ItemPropertyValue `
    -LiteralPath "Registry::$runKey" -Name $runValue).Trim()
  if ($actualCommand -ne $expectedCommand) {
    throw "Autostart value mismatch. Expected '$expectedCommand', got '$actualCommand'."
  }

  $hiddenProcess = Start-Process -FilePath $installedExecutable `
    -ArgumentList "--hidden" -PassThru -WindowStyle Hidden
  Wait-Until {
    $hiddenProcess.Refresh()
    -not $hiddenProcess.HasExited
  } "Hidden instance exited unexpectedly."
  Start-Sleep -Seconds 2
  $hiddenProcess.Refresh()
  if ($hiddenProcess.MainWindowHandle -ne [IntPtr]::Zero) {
    throw "Hidden instance unexpectedly created a visible main window."
  }
  Stop-Process -Id $hiddenProcess.Id -Force
  $hiddenProcess.WaitForExit()
  $hiddenProcess = $null

  & "$PSScriptRoot/verify_windows_single_instance.ps1" `
    -Executable $installedExecutable

  $uninstaller = Join-Path $installDirectory "unins000.exe"
  $uninstall = Start-Process -FilePath $uninstaller -ArgumentList @(
    "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART"
  ) -Wait -PassThru
  if ($uninstall.ExitCode -ne 0) {
    throw "Silent uninstall failed with exit code $($uninstall.ExitCode)."
  }
  Wait-Until { -not (Test-Path -LiteralPath $installDirectory) } `
    "Installation directory remains after uninstall."
  $remaining = & reg.exe query $runKey /v $runValue 2>$null
  if ($LASTEXITCODE -eq 0 -or $remaining) {
    throw "Autostart value remains after uninstall."
  }

  Write-Host "Windows installer lifecycle verified."
} finally {
  if ($hiddenProcess -and -not $hiddenProcess.HasExited) {
    Stop-Process -Id $hiddenProcess.Id -Force -ErrorAction SilentlyContinue
  }
}
