# =============================================================================
# LibGodot Unified Release Packager
# =============================================================================
# Builds and stages all release zip archives and computes SHA-256 checksums
# into bin/release_dist/ ready for upload to GitHub Releases.
# =============================================================================

param(
    [string]$OutputDir = "bin/release_dist",
    [string]$Platform = "",
    [string]$Release = "1",
    [switch]$SkipTests,
    [switch]$SkipPerf
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
$scriptsDir = $PSScriptRoot

$targetFullDir = if ([System.IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path $root $OutputDir }
if (-not (Test-Path $targetFullDir)) {
    New-Item -ItemType Directory -Force -Path $targetFullDir | Out-Null
}

Write-Host "=================================================================" -ForegroundColor Magenta
Write-Host "         LibGodot Unified Release Packager                       " -ForegroundColor Magenta
Write-Host "=================================================================" -ForegroundColor Magenta
Write-Host "Target Directory: $targetFullDir" -ForegroundColor Cyan

# 1. Package Template Project
Write-Host "`n--- [1/6] Packaging Starter Template ---" -ForegroundColor Cyan
& (Join-Path $scriptsDir "package_template.ps1") -TargetDir $targetFullDir -Release $Release

# 2. Package Addon Template Project
Write-Host "`n--- [2/6] Packaging Addon Template ---" -ForegroundColor Cyan
& (Join-Path $scriptsDir "package_template_addon.ps1") -TargetDir $targetFullDir -Release $Release

# 3. Package Examples (Full Source + Scripts + Playable Binaries)
Write-Host "`n--- [3/6] Packaging Standalone Examples ---" -ForegroundColor Cyan
& (Join-Path $scriptsDir "package_examples.ps1") -TargetDir $targetFullDir -Platform $Platform -Release $Release

# 4. Package Official Integration Addon
Write-Host "`n--- [4/6] Packaging Crystal Integration Addon ---" -ForegroundColor Cyan
& (Join-Path $scriptsDir "package_addon.ps1") -TargetDir $targetFullDir

# 5. Package Standalone Test Suite
if (-not $SkipTests) {
    Write-Host "`n--- [5/6] Packaging Standalone Test Suite ---" -ForegroundColor Cyan
    & (Join-Path $scriptsDir "package_test_suite.ps1") -TargetDir $targetFullDir -Platform $Platform -Release $Release -SkipVerify
} else {
    Write-Host "`n--- [5/6] Skipping Standalone Test Suite ---" -ForegroundColor Yellow
}

# 6. Package Performance Stress Benchmark
if (-not $SkipPerf) {
    Write-Host "`n--- [6/6] Packaging Performance Stress Benchmark ---" -ForegroundColor Cyan
    & (Join-Path $scriptsDir "package_perf.ps1") -TargetDir $targetFullDir -Platform $Platform -Release $Release -SkipVerify
} else {
    Write-Host "`n--- [6/6] Skipping Performance Stress Benchmark ---" -ForegroundColor Yellow
}

# 7. Generate SHA-256 Checksums
Write-Host "`n--- Generating Checksums (checksums.txt) ---" -ForegroundColor Cyan
$checksumFile = Join-Path $targetFullDir "checksums.txt"
if (Test-Path $checksumFile) { Remove-Item $checksumFile -Force }

$lines = [System.Collections.Generic.List[string]]::new()
Get-ChildItem -Path $targetFullDir -Filter "*.zip" | ForEach-Object {
    $hash = (Get-FileHash -Path $_.FullName -Algorithm SHA256).Hash.ToLower()
    $line = "$hash  $($_.Name)"
    $lines.Add($line)
    Write-Host "  $line" -ForegroundColor Gray
}
Set-Content -Path $checksumFile -Value $lines -Force

Write-Host "=================================================================" -ForegroundColor Green
Write-Host "SUCCESS: All release assets packaged into '$targetFullDir'!" -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor Green
exit 0
