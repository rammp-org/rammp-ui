<#
.SYNOPSIS
    Packages RammpUI for Windows.

.DESCRIPTION
    UE 5.7's bundled RemoteControl and WebSocketNetworking plugins restrict
    their modules to Win64/Mac/Linux via PlatformAllowList, which excludes
    LinuxArm64.  This script:

      1. Copies both plugins from the engine into the project's Plugins folder.
      2. Strips PlatformAllowList from every module entry in their .uplugin files.
      3. Runs UnrealAutomationTool (UAT) to package for Windows.
      4. Cleans up the copied plugins regardless of build outcome.

.PARAMETER EnginePath
    Root of the UE installation (default: C:\Program Files\Epic Games\UE_5.7).

.PARAMETER Config
    Build configuration: Development (default) or Shipping.

.PARAMETER ArchiveDir
    Where to place the packaged output (default: <ProjectRoot>\Packaged\Windows).

.EXAMPLE
    .\Scripts\BuildWindowsX86_64.ps1
    .\Scripts\BuildWindowsX86_64.ps1 -Config Shipping
    .\Scripts\BuildWindowsX86_64.ps1 -EnginePath "D:\UE_5.7"
#>
[CmdletBinding()]
param(
    [string]$EnginePath = "C:\Program Files\Epic Games\UE_5.7",
    [ValidateSet("Development", "Shipping")]
    [string]$Config = "Development",
    [string]$ArchiveDir = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -- Paths -----------------------------------------------------------------
$ProjectRoot  = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$UProject     = Join-Path $ProjectRoot "RammpUI.uproject"
$RunUAT       = Join-Path $EnginePath  "Engine\Build\BatchFiles\RunUAT.bat"

if (-not $ArchiveDir) {
    $ArchiveDir = Join-Path $ProjectRoot "Packaged\Windows"
}


# -- Validation ------------------------------------------------------------
if (-not (Test-Path $UProject)) {
    Write-Error "Project file not found: $UProject"
    exit 1
}
if (-not (Test-Path $RunUAT)) {
    Write-Error "RunUAT not found: $RunUAT. Check -EnginePath."
    exit 1
}


# -- Step 1: Package ------------------------------------------------------
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Packaging RammpUI for Windows ($Config)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$uatArgs = @(
    "BuildCookRun"
    "-project=`"$UProject`""
    "-targetplatform=Win64"
    "-clientconfig=$Config"
    "-build"
    "-cook"
    "-stage"
    "-pak"
    "-archive"
    "-archivedirectory=`"$ArchiveDir`""
    "-utf8output"
)

$buildExitCode = 0
try {
    & $RunUAT @uatArgs
    $buildExitCode = $LASTEXITCODE
} catch {
    Write-Warning "Build process threw an exception: $_"
    $buildExitCode = 1
}


# -- Result ----------------------------------------------------------------
Write-Host ""
if ($buildExitCode -eq 0) {
    Write-Host "Build SUCCEEDED. Output: $ArchiveDir" -ForegroundColor Green
} else {
    Write-Host "Build FAILED (exit code $buildExitCode)." -ForegroundColor Red
    exit $buildExitCode
}
