# =============================================================================
# LibGodot Standalone Examples Packager
# =============================================================================
# Packages all example projects into a self-contained, per-platform archive:
# examples-<platform>.zip (e.g. examples-windows.zip)
# Contains the full source code, installed scripts, integration addon, AND
# the pre-compiled playable game binaries.
# =============================================================================

param(
    [string]$TargetDir = "bin",
    [string]$Platform = "",
    [string]$ZipName = "",
    [string]$Release = "1",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# 1. Locate root directory
$curr = $PSScriptRoot
$rootDir = ""
while ($curr) {
    if ((Test-Path (Join-Path $curr "shard.yml")) -and (Test-Path (Join-Path $curr "src/libgodot.cr"))) {
        $rootDir = $curr
        break
    }
    $parent = Split-Path -Parent $curr
    if ($parent -eq $curr) { break }
    $curr = $parent
}
if (-not $rootDir) {
    $rootDir = Split-Path -Parent $PSScriptRoot
}

$examplesDir = Join-Path $rootDir "examples"
if (-not (Test-Path $examplesDir)) {
    Write-Error "Examples directory '$examplesDir' not found."
    exit 1
}

# 2. Determine platform and target archive name
$onWindows = ($env:OS -eq "Windows_NT" -or [System.IO.Path]::PathSeparator -eq ';')
$isMac = $false
try {
    if ($IsMacOS -or [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)) {
        $isMac = $true
    }
} catch {}
if (-not $isMac -and -not $onWindows) {
    if ((Get-Command uname -ErrorAction SilentlyContinue) -and ((& uname) -eq "Darwin")) { $isMac = $true }
}

$detectedPlatform = if ($onWindows) { "windows" } elseif ($isMac) { "macos" } else { "linux" }
$platformName = if ($Platform) { $Platform.ToLower() } else { $detectedPlatform }

$defaultZipName = if ($platformName -eq "windows") { "examples-windows.zip" } else { "examples-$platformName.zip" }
$finalZipName = if ($ZipName) { $ZipName } else { $defaultZipName }

$targetFullDir = if ([System.IO.Path]::IsPathRooted($TargetDir)) { $TargetDir } else { Join-Path $rootDir $TargetDir }
if (-not (Test-Path $targetFullDir)) {
    New-Item -ItemType Directory -Force -Path $targetFullDir | Out-Null
}
$zipPath = Join-Path $targetFullDir $finalZipName

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "       Packaging Standalone Examples: $finalZipName              " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "Platform: $platformName"
Write-Host "Target:   $zipPath"

# 3. Create clean staging directory
$stagingDir = Join-Path $targetFullDir ".staging_examples_$([System.Guid]::NewGuid().ToString('N').Substring(0, 8))"
if (Test-Path $stagingDir) { Remove-Item $stagingDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stagingDir | Out-Null

$commonScripts = @(
    (Join-Path $rootDir "scripts/build_crystal.ps1"),
    (Join-Path $rootDir "scripts/ensure_deps.ps1"),
    (Join-Path $rootDir "scripts/ensure_extension_list.ps1"),
    (Join-Path $rootDir "scripts/generate_project_bindings.ps1"),
    (Join-Path $rootDir "scripts/package_game.ps1"),
    (Join-Path $rootDir "scripts/sync_addons.ps1"),
    (Join-Path $rootDir "tools/api_generator/dump_project_nodes.gd"),
    (Join-Path $rootDir "tools/api_generator/generate_project_bindings.cr")
)
$rootAddon = Join-Path $rootDir "addons/crystal_integration"
$binDir = Join-Path $rootDir "bin"

try {
    # 4. Iterate and package each example project
    $exampleFolders = Get-ChildItem -Path $examplesDir -Directory
    foreach ($ex in $exampleFolders) {
        $exName = $ex.Name
        Write-Host "Processing example: $exName..." -ForegroundColor Cyan
        $destExDir = Join-Path $stagingDir $exName
        New-Item -ItemType Directory -Force -Path $destExDir | Out-Null

        # A. Copy full source files (excluding .godot, lib, bin, dist, .git, .crystal)
        Get-ChildItem -Path $ex.FullName | Where-Object {
            $_.Name -notin @(".godot", "lib", "bin", "dist", ".git", ".crystal")
        } | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination $destExDir -Recurse -Force
        }

        # B. Install support scripts inside the example
        $destScripts = Join-Path $destExDir "scripts"
        if (-not (Test-Path $destScripts)) { New-Item -ItemType Directory -Force -Path $destScripts | Out-Null }
        foreach ($cs in $commonScripts) {
            if (Test-Path $cs) {
                Copy-Item $cs $destScripts -Force
            }
        }

        # C. Install official crystal_integration addon inside the example
        $destAddon = Join-Path $destExDir "addons/crystal_integration"
        if (Test-Path $rootAddon) {
            if (Test-Path $destAddon) { Remove-Item $destAddon -Recurse -Force }
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destAddon) | Out-Null
            Copy-Item -Path $rootAddon -Destination $destAddon -Recurse -Force
        }

        # D. Bundle compiled game binaries & runtime libraries
        $destBin = Join-Path $destExDir "bin"
        if (-not (Test-Path $destBin)) { New-Item -ItemType Directory -Force -Path $destBin | Out-Null }
        $destAddonBin = Join-Path $destAddon "bin"
        if (-not (Test-Path $destAddonBin)) { New-Item -ItemType Directory -Force -Path $destAddonBin | Out-Null }

        # Copy example's compiled game library
        foreach ($libFile in @("game.dll", "game.so", "game.dylib", "$exName.dll")) {
            $exLib = Join-Path $ex.FullName "bin/$libFile"
            if (Test-Path $exLib) {
                Copy-Item $exLib (Join-Path $destBin $libFile) -Force -ErrorAction SilentlyContinue
                Copy-Item $exLib (Join-Path $destAddonBin $libFile) -Force -ErrorAction SilentlyContinue
            }
        }

        # Copy crystal_bridge
        foreach ($bridgeLib in @("crystal_bridge.dll", "crystal_bridge.so", "crystal_bridge.dylib")) {
            $src = Join-Path $binDir $bridgeLib
            if (Test-Path $src) {
                Copy-Item $src (Join-Path $destBin $bridgeLib) -Force -ErrorAction SilentlyContinue
                Copy-Item $src (Join-Path $destAddonBin $bridgeLib) -Force -ErrorAction SilentlyContinue
            }
        }

        # Copy runtime dependencies
        if ($platformName -eq "windows") {
            foreach ($dll in @('gc.dll', 'iconv-2.dll', 'pcre2-8.dll', 'libgodot.dll')) {
                $src = Join-Path $binDir $dll
                if (Test-Path $src) {
                    Copy-Item $src (Join-Path $destBin $dll) -Force -ErrorAction SilentlyContinue
                    Copy-Item $src (Join-Path $destAddonBin $dll) -Force -ErrorAction SilentlyContinue
                }
            }
        } elseif ($platformName -eq "linux") {
            $src = Join-Path $binDir "libgodot.so"
            if (Test-Path $src) {
                Copy-Item $src (Join-Path $destBin "libgodot.so") -Force -ErrorAction SilentlyContinue
                Copy-Item $src (Join-Path $destAddonBin "libgodot.so") -Force -ErrorAction SilentlyContinue
            }
        } elseif ($platformName -eq "macos") {
            $src = Join-Path $binDir "libgodot.dylib"
            if (Test-Path $src) {
                Copy-Item $src (Join-Path $destBin "libgodot.dylib") -Force -ErrorAction SilentlyContinue
                Copy-Item $src (Join-Path $destAddonBin "libgodot.dylib") -Force -ErrorAction SilentlyContinue
            }
        }

        # Copy playable executable if pre-packaged in example folder
        foreach ($exeCandidate in @("$exName.exe", "game.exe", "$exName.pck", "game.pck", "$exName")) {
            $exeSrc = Join-Path $ex.FullName $exeCandidate
            if (Test-Path $exeSrc) {
                Copy-Item $exeSrc (Join-Path $destExDir $exeCandidate) -Force -ErrorAction SilentlyContinue
            }
            $exeBinSrc = Join-Path $ex.FullName "bin/$exeCandidate"
            if (Test-Path $exeBinSrc) {
                Copy-Item $exeBinSrc (Join-Path $destBin $exeCandidate) -Force -ErrorAction SilentlyContinue
            }
        }

        # Clean stray shadow copies and logs from the example
        Get-ChildItem -Path $destExDir -Filter "*_loaded_*" -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        Get-ChildItem -Path $destExDir -Filter "*.log" -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    }

    # 5. Create Zip Archive
    Write-Host "Creating archive $finalZipName..." -ForegroundColor Cyan
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

    if (Get-Command tar.exe -ErrorAction SilentlyContinue) {
        & tar.exe -a -c -f $zipPath -C $stagingDir .
    } else {
        Compress-Archive -Path "$stagingDir/*" -DestinationPath $zipPath -Force
    }

    $sizeKb = [math]::Round(((Get-Item $zipPath).Length / 1KB), 2)
    Write-Host "=================================================================" -ForegroundColor Green
    Write-Host "SUCCESS: Examples packaged at '$zipPath' ($sizeKb KB)" -ForegroundColor Green
    Write-Host "=================================================================" -ForegroundColor Green
} finally {
    if (Test-Path $stagingDir) {
        Remove-Item $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
