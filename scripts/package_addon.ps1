# =============================================================================
# LibGodot Official Crystal Integration Addon Packager
# =============================================================================
# Packages the official Godot editor addon (addons/crystal_integration) into
# a universal redistributable archive: godot-crystal-addon.zip
# =============================================================================

param(
    [string]$TargetDir = "bin",
    [string]$ZipName = "godot-crystal-addon.zip",
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

$addonDir = Join-Path $rootDir "addons/crystal_integration"
if (-not (Test-Path $addonDir)) {
    Write-Error "Addon directory '$addonDir' not found."
    exit 1
}

# 2. Determine target path
$targetFullDir = if ([System.IO.Path]::IsPathRooted($TargetDir)) { $TargetDir } else { Join-Path $rootDir $TargetDir }
if (-not (Test-Path $targetFullDir)) {
    New-Item -ItemType Directory -Force -Path $targetFullDir | Out-Null
}
$zipPath = Join-Path $targetFullDir $ZipName

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "       Packaging Official Addon: $ZipName                        " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "Source: $addonDir"
Write-Host "Target: $zipPath"

# 3. Create clean staging directory
$stagingDir = Join-Path $targetFullDir ".staging_addon_dist_$([System.Guid]::NewGuid().ToString('N').Substring(0, 8))"
if (Test-Path $stagingDir) { Remove-Item $stagingDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stagingDir | Out-Null

try {
    # 4. Copy addon files into addons/crystal_integration
    $destAddon = Join-Path $stagingDir "addons/crystal_integration"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destAddon) | Out-Null
    Copy-Item -Path $addonDir -Destination $destAddon -Recurse -Force

    $destBin = Join-Path $destAddon "bin"
    if (-not (Test-Path $destBin)) { New-Item -ItemType Directory -Force -Path $destBin | Out-Null }

    # 5. Collect and bundle binaries from bin/ and staging/
    $binDir = Join-Path $rootDir "bin"

    # Windows DLLs
    foreach ($dll in @("crystal_bridge.dll", "plugin.dll", "libgodot.dll", "gc.dll", "iconv-2.dll", "pcre2-8.dll")) {
        $src = Join-Path $binDir $dll
        if (Test-Path $src) {
            Copy-Item $src (Join-Path $destBin $dll) -Force -ErrorAction SilentlyContinue
        }
    }

    # Linux shared objects
    foreach ($so in @("crystal_bridge.so", "plugin.so", "libgodot.so")) {
        $src = Join-Path $binDir $so
        if (Test-Path $src) {
            Copy-Item $src (Join-Path $destBin $so) -Force -ErrorAction SilentlyContinue
        }
    }

    # macOS dylibs
    foreach ($dylib in @("crystal_bridge.dylib", "plugin.dylib", "libgodot.dylib")) {
        $src = Join-Path $binDir $dylib
        if (Test-Path $src) {
            Copy-Item $src (Join-Path $destBin $dylib) -Force -ErrorAction SilentlyContinue
        }
    }

    # Clean stray shadow copies and logs
    Get-ChildItem -Path $stagingDir -Filter "*_loaded_*" -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path $stagingDir -Filter "*.log" -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

    # 6. Create Zip Archive
    Write-Host "Creating $ZipName..." -ForegroundColor Cyan
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

    if (Get-Command tar.exe -ErrorAction SilentlyContinue) {
        & tar.exe -a -c -f $zipPath -C $stagingDir addons
    } else {
        Compress-Archive -Path "$stagingDir/addons" -DestinationPath $zipPath -Force
    }

    $sizeKb = [math]::Round(((Get-Item $zipPath).Length / 1KB), 2)
    Write-Host "=================================================================" -ForegroundColor Green
    Write-Host "SUCCESS: Addon packaged at '$zipPath' ($sizeKb KB)" -ForegroundColor Green
    Write-Host "=================================================================" -ForegroundColor Green
} finally {
    if (Test-Path $stagingDir) {
        Remove-Item $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
