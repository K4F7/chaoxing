param(
  [string]$Executable = "build/windows/x64/runner/Release/chaoxing_app.exe"
)

$ErrorActionPreference = "Stop"
$resolvedExecutable = (Resolve-Path -LiteralPath $Executable).Path

Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class NativeWindow {
  [DllImport("user32.dll", SetLastError = true)]
  [return: MarshalAs(UnmanagedType.Bool)]
  public static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

  [DllImport("user32.dll")]
  [return: MarshalAs(UnmanagedType.Bool)]
  public static extern bool IsWindowVisible(IntPtr hWnd);
}
"@

function Wait-Until([scriptblock]$Condition, [string]$FailureMessage) {
  $deadline = [DateTime]::UtcNow.AddSeconds(15)
  while ([DateTime]::UtcNow -lt $deadline) {
    if (& $Condition) {
      return
    }
    Start-Sleep -Milliseconds 100
  }
  throw $FailureMessage
}

$primary = $null
$secondary = $null
try {
  $primary = Start-Process -FilePath $resolvedExecutable -PassThru
  Wait-Until {
    $primary.Refresh()
    -not $primary.HasExited -and $primary.MainWindowHandle -ne [IntPtr]::Zero
  } "Primary instance did not create a window."

  $window = $primary.MainWindowHandle
  Wait-Until {
    if (-not [NativeWindow]::IsWindowVisible($window)) {
      return $true
    }
    if (-not [NativeWindow]::PostMessage($window, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)) {
      throw "Could not send WM_CLOSE to the primary window."
    }
    return $false
  } "Primary window did not become hidden."

  $secondary = Start-Process -FilePath $resolvedExecutable -PassThru
  Wait-Until {
    $secondary.Refresh()
    $secondary.HasExited
  } "Secondary instance did not exit."

  Wait-Until {
    $primary.Refresh()
    -not $primary.HasExited -and [NativeWindow]::IsWindowVisible($window)
  } "Primary window was not restored by the secondary instance."

  $matchingProcesses = @(Get-Process -Name "chaoxing_app" -ErrorAction SilentlyContinue | Where-Object {
    try {
      $_.Path -eq $resolvedExecutable
    } catch {
      $false
    }
  })
  if ($matchingProcesses.Count -ne 1 -or $matchingProcesses[0].Id -ne $primary.Id) {
    throw "Expected exactly one primary process after activation."
  }

  Write-Host "Windows single-instance activation verified."
} finally {
  if ($secondary -and -not $secondary.HasExited) {
    Stop-Process -Id $secondary.Id -Force -ErrorAction SilentlyContinue
  }
  if ($primary -and -not $primary.HasExited) {
    Stop-Process -Id $primary.Id -Force -ErrorAction SilentlyContinue
  }
}
