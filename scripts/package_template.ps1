# =============================================================================
# LibGodot Standalone Template Project Packager
# =============================================================================
# Packages the starter game template into a self-contained, ready-to-run
# archive: template-project.zip
# =============================================================================

param(
    [string]$TargetDir = "bin",
    [string]$ZipName = "template-project.zip",
    [string]$Release = "",
    [switch]$BundleBinaries,
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

$templateDir = Join-Path $rootDir "template"
if (-not (Test-Path $templateDir)) {
    Write-Error "Template directory '$templateDir' not found."
    exit 1
}

# 2. Determine target paths
$targetFullDir = if ([System.IO.Path]::IsPathRooted($TargetDir)) { $TargetDir } else { Join-Path $rootDir $TargetDir }
if (-not (Test-Path $targetFullDir)) {
    New-Item -ItemType Directory -Force -Path $targetFullDir | Out-Null
}
$zipPath = Join-Path $targetFullDir $ZipName

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "       Packaging Starter Template: $ZipName                      " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "Source: $templateDir"
Write-Host "Target: $zipPath"

# 3. Create clean staging directory
$stagingDir = Join-Path $targetFullDir ".staging_template_$([System.Guid]::NewGuid().ToString('N').Substring(0, 8))"
if (Test-Path $stagingDir) { Remove-Item $stagingDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stagingDir | Out-Null

try {
    # 4. Copy template source files (excluding .godot, lib, bin, dist, .git)
    Write-Host "[1/5] Copying template source files..." -ForegroundColor Gray
    Get-ChildItem -Path $templateDir -Exclude ".godot", "lib", "bin", "dist", ".git" | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $stagingDir -Recurse -Force
    }

    # Ensure clean output bin folder
    $stagingBin = Join-Path $stagingDir "bin"
    if (Test-Path $stagingBin) { Remove-Item $stagingBin -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $stagingBin | Out-Null

    # 5. Bundle canonical support scripts from root
    Write-Host "[2/5] Installing common scripts into template..." -ForegroundColor Gray
    $stagingScripts = Join-Path $stagingDir "scripts"
    if (-not (Test-Path $stagingScripts)) { New-Item -ItemType Directory -Force -Path $stagingScripts | Out-Null }

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

    foreach ($cs in $commonScripts) {
        if (Test-Path $cs) {
            Copy-Item $cs $stagingScripts -Force
        }
    }

    # 6. Bundle canonical addons/crystal_integration from root
    Write-Host "[3/5] Installing crystal_integration addon into template..." -ForegroundColor Gray
    $rootAddon = Join-Path $rootDir "addons/crystal_integration"
    $stagingAddon = Join-Path $stagingDir "addons/crystal_integration"
    if (Test-Path $rootAddon) {
        if (Test-Path $stagingAddon) { Remove-Item $stagingAddon -Recurse -Force }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $stagingAddon) | Out-Null
        Copy-Item -Path $rootAddon -Destination $stagingAddon -Recurse -Force
        # Clean any existing binaries or shadow copies in addon bin
        $addonBin = Join-Path $stagingAddon "bin"
        if (Test-Path $addonBin) {
            Get-ChildItem -Path $addonBin -Filter "*_loaded_*" -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }

    # 7. Bundle precompiled binaries if available
    Write-Host "[4/5] Bundling platform binaries and runtime libraries..." -ForegroundColor Gray
    $binDir = Join-Path $rootDir "bin"
    $stagingAddonBin = Join-Path $stagingDir "addons/crystal_integration/bin"
    if (-not (Test-Path $stagingAddonBin)) { New-Item -ItemType Directory -Force -Path $stagingAddonBin | Out-Null }

    # Copy crystal_bridge
    foreach ($bridgeLib in @("crystal_bridge.dll", "crystal_bridge.so", "crystal_bridge.dylib")) {
        $src = Join-Path $binDir $bridgeLib
        if (Test-Path $src) {
            Copy-Item $src (Join-Path $stagingBin $bridgeLib) -Force -ErrorAction SilentlyContinue
            Copy-Item $src (Join-Path $stagingAddonBin $bridgeLib) -Force -ErrorAction SilentlyContinue
        }
    }

    # Copy template game.dll if present
    foreach ($gameLib in @("game.dll", "game.so", "game.dylib")) {
        $tplLib = Join-Path $templateDir "bin/$gameLib"
        if (Test-Path $tplLib) {
            Copy-Item $tplLib (Join-Path $stagingBin $gameLib) -Force -ErrorAction SilentlyContinue
        }
    }

    # Copy runtime DLLs (Windows)
    foreach ($dll in @('gc.dll', 'iconv-2.dll', 'pcre2-8.dll', 'libgodot.dll')) {
        $src = Join-Path $binDir $dll
        if (Test-Path $src) {
            Copy-Item $src (Join-Path $stagingBin $dll) -Force -ErrorAction SilentlyContinue
            Copy-Item $src (Join-Path $stagingAddonBin $dll) -Force -ErrorAction SilentlyContinue
        }
    }

    # 8. Swap shard.release.yml to shard.yml for standalone release
    $releaseShard = Join-Path $stagingDir "shard.release.yml"
    if (Test-Path $releaseShard) {
        Copy-Item $releaseShard (Join-Path $stagingDir "shard.yml") -Force
        Remove-Item $releaseShard -Force
    }

    # Clean any temporary residue
    Get-ChildItem -Path $stagingDir -Filter "*.log" -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path $stagingDir -Filter "*_loaded_*" -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

    # 9. Create Zip Archive
    Write-Host "[5/5] Creating $ZipName..." -ForegroundColor Cyan
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

    if (Get-Command tar.exe -ErrorAction SilentlyContinue) {
        & tar.exe -a -c -f $zipPath -C $stagingDir .
    } else {
        Compress-Archive -Path "$stagingDir/*" -DestinationPath $zipPath -Force
    }

    $sizeKb = [math]::Round(((Get-Item $zipPath).Length / 1KB), 2)
    Write-Host "=================================================================" -ForegroundColor Green
    Write-Host "SUCCESS: Template packaged at '$zipPath' ($sizeKb KB)" -ForegroundColor Green
    Write-Host "=================================================================" -ForegroundColor Green
} finally {
    if (Test-Path $stagingDir) {
        Remove-Item $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
