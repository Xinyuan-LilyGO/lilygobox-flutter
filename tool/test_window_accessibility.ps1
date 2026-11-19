param(
  [string]$Flutter = "flutter",
  [string]$LogPath = "tmp/window-accessibility.log",
  [int]$Cycles = 24,
  [string]$Target = "integration_test/window_accessibility_test.dart"
)

# Native AXTree errors do not reach tester.takeException(), so validate the
# engine output as well as the integration test result.
$taskRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $taskRoot
try {
  $logParent = Split-Path -Parent $LogPath
  if ($logParent) { New-Item -ItemType Directory -Path $logParent -Force | Out-Null }
  & $Flutter drive --no-pub --driver=test_driver/tray_theme.dart "--target=$Target" "--dart-define=WINDOW_CYCLES=$Cycles" -d windows 2>&1 |
    Tee-Object -FilePath $LogPath
  $testExitCode = $LASTEXITCODE
  if ($testExitCode -ne 0) { throw "Windows integration test failed ($testExitCode). See $LogPath" }
  if (Select-String -LiteralPath $LogPath -Pattern 'Failed to update ui::AXTree|Lost connection to device|EXCEPTION CAUGHT|Unhandled Exception' -Quiet) {
    throw "Windows integration emitted native or framework errors. See $LogPath"
  }
} finally {
  Pop-Location
}
