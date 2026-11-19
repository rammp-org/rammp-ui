<#
.SYNOPSIS
    Packages RammpUI for Linux ARM64 (Nvidia Jetson).

.DESCRIPTION
    UE 5.8's bundled RemoteControl and WebSocketNetworking plugins restrict
    their modules to Win64/Mac/Linux via PlatformAllowList, which excludes
    LinuxArm64.  This script:

      1. Copies both plugins from the engine into the project's Plugins folder.
      2. Strips PlatformAllowList from every module entry in their .uplugin files.
      3. Runs UnrealAutomationTool (UAT) to package for LinuxArm64.
      4. Cleans up the copied plugins regardless of build outcome.
      5. Has the package's launch script start the app the way the Jetson
         needs it (see Set-JetsonLaunchDefaults): a newer Vulkan loader, no
         X input method, Web Remote Control on.

    The Remote Control presets aren't referenced by the map they bind to, so
    the cooker only includes them through DirectoriesToAlwaysCook in
    Config/DefaultGame.ini (/RammsUI/UI holds RCP_RammsBridge).

.PARAMETER EnginePath
    Root of the UE installation (default: C:\Program Files\Epic Games\UE_5.8).

.PARAMETER Config
    Build configuration: Development (default) or Shipping.

.PARAMETER ArchiveDir
    Where to place the packaged output (default: <ProjectRoot>\Packaged\LinuxArm64).

.PARAMETER NoClean
    If set, keeps the copied plugins after the build (useful for debugging).

.EXAMPLE
    .\Scripts\BuildLinuxArm64.ps1
    .\Scripts\BuildLinuxArm64.ps1 -Config Shipping
    .\Scripts\BuildLinuxArm64.ps1 -EnginePath "D:\UE_5.8" -NoClean
#>
[CmdletBinding()]
param(
    [string]$EnginePath = "C:\Program Files\Epic Games\UE_5.8",
    [ValidateSet("Development", "Shipping")]
    [string]$Config = "Development",
    [string]$ArchiveDir = "",
    [switch]$NoClean
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -- Paths -----------------------------------------------------------------
$ProjectRoot  = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$UProject     = Join-Path $ProjectRoot "RammpUI.uproject"
$PluginsDir   = Join-Path $ProjectRoot "Plugins"
$RunUAT       = Join-Path $EnginePath  "Engine\Build\BatchFiles\RunUAT.bat"

if (-not $ArchiveDir) {
    $ArchiveDir = Join-Path $ProjectRoot "Packaged\LinuxArm64"
}

# Engine plugin sources
$EnginePlugins = @(
    @{
        Name   = "RemoteControl"
        Source = Join-Path $EnginePath "Engine\Plugins\VirtualProduction\RemoteControl"
    },
    @{
        Name   = "WebSocketNetworking"
        Source = Join-Path $EnginePath "Engine\Plugins\Experimental\WebSocketNetworking"
    }
)

# -- Validation ------------------------------------------------------------
if (-not (Test-Path $UProject)) {
    Write-Error "Project file not found: $UProject"
    exit 1
}
if (-not (Test-Path $RunUAT)) {
    Write-Error "RunUAT not found: $RunUAT. Check -EnginePath."
    exit 1
}
foreach ($plugin in $EnginePlugins) {
    if (-not (Test-Path $plugin.Source)) {
        Write-Error "Engine plugin not found: $($plugin.Source)"
        exit 1
    }
}

# -- Helper: strip PlatformAllowList from a .uplugin ----------------------
function Remove-PlatformAllowList([string]$UPluginPath) {
    $json = Get-Content $UPluginPath -Raw | ConvertFrom-Json

    $modified = $false
    if ($json.PSObject.Properties["Modules"]) {
        foreach ($mod in $json.Modules) {
            if ($mod.PSObject.Properties["PlatformAllowList"]) {
                $mod.PSObject.Properties.Remove("PlatformAllowList")
                $modified = $true
                Write-Host "  Removed PlatformAllowList from module '$($mod.Name)'"
            }
        }
    }

    if ($modified) {
        $json | ConvertTo-Json -Depth 10 | Set-Content $UPluginPath -Encoding UTF8
    }
}

# -- Helper: launch defaults for the Jetson -------------------------------
# UAT stages <Project>-Arm64.sh, which only runs the binary with the caller's
# arguments. Its last line becomes:
#   LD_LIBRARY_PATH             UE 5.8 takes the system Vulkan loader only if
#                               it is newer than 1.3.204, and has no loader of
#                               its own for ARM64. Ubuntu 22.04's is 1.3.204,
#                               so the app stops at an "Unable to initialize
#                               Vulkan" box. A newer loader goes first on the
#                               path: the directory in RAMMP_VULKAN_LOADER_DIR,
#                               by default ~/Vulkan-Loader/build/loader (a local
#                               build of KhronosGroup/Vulkan-Loader). Without
#                               one there, it warns and uses the system's.
#   export XMODIFIERS=@im=none  SDL3 on X11 gives the X input method focus
#                               whenever the window gains focus, which opens
#                               GNOME's on-screen keyboard; with no input
#                               method, it stays shut.
#   -RCWebControlEnable         Web Remote Control (HTTP 30010, WebSocket
#                               30020). RammpUIStartup also adds it when the
#                               command line has neither it nor
#                               -RCWebControlDisable, so this is belt and braces.
# Arguments given to the script still follow.
# -archive puts the package in a platform folder under -archivedirectory
# (<ArchiveDir>\LinuxArm64), so the launcher is looked for there as well as
# in <ArchiveDir> itself. Returns $false when no launcher got the defaults.
function Set-JetsonLaunchDefaults([string]$PackageDir) {
    $scripts = @(Get-ChildItem -Path $PackageDir -Filter "*.sh" -File -Recurse -Depth 1)
    $pattern = '(?m)^("[^"\n]*/Binaries/LinuxArm64/[^"/\n]+") (\S+) "\$@"[ \t]*$'
    $inputMethod = "export XMODIFIERS=@im=none"
    # Single-quoted: these are shell lines, and PowerShell would expand their $ in double quotes.
    $vulkan = @(
        '# Added by Scripts/BuildLinuxArm64.ps1: UE 5.8 needs a Vulkan loader newer than 1.3.204 and has none'
        '# of its own for ARM64; Ubuntu 22.04 ships 1.3.204. So a newer one goes first on the library path.'
        '# RAMMP_VULKAN_LOADER_DIR names its directory (default: a build of KhronosGroup/Vulkan-Loader in'
        '# ~/Vulkan-Loader). Made absolute here: the app changes directory before it loads Vulkan.'
        'RAMMP_VULKAN_LOADER_DIR="${RAMMP_VULKAN_LOADER_DIR:-$HOME/Vulkan-Loader/build/loader}"'
        'case "$RAMMP_VULKAN_LOADER_DIR" in /*) ;; *) RAMMP_VULKAN_LOADER_DIR="$PWD/$RAMMP_VULKAN_LOADER_DIR" ;; esac'
        'if [ -e "$RAMMP_VULKAN_LOADER_DIR/libvulkan.so.1" ]; then'
        '    export LD_LIBRARY_PATH="$RAMMP_VULKAN_LOADER_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"'
        'else'
        '    echo "RammpUI: no libvulkan.so.1 in $RAMMP_VULKAN_LOADER_DIR, so the system Vulkan loader is used;" >&2'
        '    echo "RammpUI: if it is 1.3.204 or older the app will not start. Set RAMMP_VULKAN_LOADER_DIR." >&2'
        'fi'
    ) -join "`n"
    $done = 0
    foreach ($script in $scripts) {
        $text = [IO.File]::ReadAllText($script.FullName) -replace "`r`n", "`n"
        if ($text.Contains("RAMMP_VULKAN_LOADER_DIR")) {
            Write-Host "Launch defaults already in $($script.FullName)"
            $done++
            continue
        }
        $at = $text.IndexOf($inputMethod)
        if ($at -ge 0) {
            # Patched by an earlier version of this script, before the Vulkan loader: add it
            # ahead of that block (its comment, when it is there, starts the block).
            $comment = $text.LastIndexOf("# Added by Scripts/BuildLinuxArm64.ps1", $at)
            if ($comment -ge 0) { $at = $comment }
            $text = $text.Substring(0, $at) + $vulkan + "`n" + $text.Substring($at)
        } else {
            $match = [regex]::Match($text, $pattern)
            if (-not $match.Success) {
                continue   # not a UAT launcher (it runs no LinuxArm64 binary)
            }
            $launch = @(
                $vulkan
                "# Added by Scripts/BuildLinuxArm64.ps1: no X input method, so GNOME's on-screen keyboard stays"
                "# shut; Web Remote Control on (HTTP 30010, WebSocket 30020). Arguments given to this script follow."
                $inputMethod
                "$($match.Groups[1].Value) $($match.Groups[2].Value) -RCWebControlEnable " + '"$@"'
            ) -join "`n"
            $text = $text.Substring(0, $match.Index) + $launch + $text.Substring($match.Index + $match.Length)
        }
        [IO.File]::WriteAllText($script.FullName, $text, (New-Object System.Text.UTF8Encoding $false))
        Write-Host "Launch defaults (Vulkan loader, XMODIFIERS=@im=none, -RCWebControlEnable) added to $($script.FullName)"
        $done++
    }
    if ($done -eq 0) {
        $found = if ($scripts.Count) { ($scripts | ForEach-Object { $_.FullName }) -join ", " } else { "none" }
        Write-Warning "No UAT launch script under $PackageDir (or one folder down; .sh files: $found): launch defaults not added."
        return $false
    }
    return $true
}

# -- Step 1: Copy engine plugins into project -----------------------------
$copiedDirs = @()
foreach ($plugin in $EnginePlugins) {
    $dest = Join-Path $PluginsDir $plugin.Name
    if (Test-Path $dest) {
        Write-Warning "$($plugin.Name) already exists in Plugins/ - skipping copy."
    } else {
        Write-Host "Copying $($plugin.Name) from engine..."
        Copy-Item -Path $plugin.Source -Destination $dest -Recurse
        $copiedDirs += $dest
    }
}

# -- Step 2: Strip PlatformAllowList --------------------------------------
foreach ($plugin in $EnginePlugins) {
    $dest = Join-Path $PluginsDir $plugin.Name
    $upluginFiles = Get-ChildItem -Path $dest -Filter "*.uplugin" -Recurse
    foreach ($f in $upluginFiles) {
        Write-Host "Patching $($f.FullName)..."
        Remove-PlatformAllowList $f.FullName
    }
}

# -- Step 3: Package ------------------------------------------------------
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Packaging RammpUI for LinuxArm64 ($Config)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$uatArgs = @(
    "BuildCookRun"
    "-project=`"$UProject`""
    "-targetplatform=LinuxArm64"
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

# -- Step 4: Cleanup copied plugins ---------------------------------------
if ($NoClean) {
    Write-Host "Skipping cleanup (-NoClean specified). Copied plugins remain in Plugins/."
} else {
    foreach ($dir in $copiedDirs) {
        if (Test-Path $dir) {
            Write-Host "Cleaning up $dir..."
            Remove-Item -Path $dir -Recurse -Force
        }
    }
}

# -- Result ----------------------------------------------------------------
Write-Host ""
if ($buildExitCode -eq 0) {
    if (-not (Set-JetsonLaunchDefaults $ArchiveDir)) {
        # The package may not start on the system Vulkan loader, and GNOME's keyboard opens.
        Write-Host "Build SUCCEEDED, but its launch script lacks the Jetson defaults. Output: $ArchiveDir" -ForegroundColor Red
        exit 2
    }
    Write-Host "Build SUCCEEDED. Output: $ArchiveDir" -ForegroundColor Green
} else {
    Write-Host "Build FAILED (exit code $buildExitCode)." -ForegroundColor Red
    exit $buildExitCode
}
