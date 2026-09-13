<#
.SYNOPSIS
    Runs the LibGodot test suite inside WSL (Ubuntu) with LLDB crash backtrace capture.

.DESCRIPTION
    Verifies that the Linux build, GDExtension bridge, and test suites execute cleanly
    in a native Linux environment (WSL) matching GitHub Actions ubuntu-latest.

.EXAMPLE
    .\scripts\run_wsl_tests.ps1
    .\scripts\run_wsl_tests.ps1 -Distro "Ubuntu" -SkipSpecs
#>

param(
    [string]$Distro = "Ubuntu",
    [switch]$SkipSpecs,
    [switch]$SkipRuntimeTests,
    [switch]$SkipToolTests,
    [switch]$DebugWithLLDB
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $PSScriptRoot

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "             LibGodot Linux (WSL) Test Suite Runner              " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

# 1. Check WSL availability
if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
    Write-Error "WSL (Windows Subsystem for Linux) is not installed or not on PATH."
}

# 2. Check distro
$distroList = wsl --list --quiet 2>$null
if ($LASTEXITCODE -ne 0 -or -not ($distroList -match $Distro)) {
    Write-Host "[WSL] Distribution '$Distro' not found. Available distros:" -ForegroundColor Yellow
    wsl --list
    exit 1
}

# 3. Convert workspace root to WSL path
$wslRoot = (wsl -d $Distro -- wslpath -a ($RootDir -replace '\\', '/')).Trim()
Write-Host "[WSL] Root: $wslRoot (Distro: $Distro)" -ForegroundColor Cyan

# 4. Check dependencies in WSL
$checkDepsCmd = "which crystal make g++ >/dev/null 2>&1 && echo OK || echo MISSING"
$depStatus = (wsl -d $Distro -- bash -c "$checkDepsCmd").Trim()

if ($depStatus -ne "OK") {
    Write-Host "[WSL] Warning: Build dependencies (crystal, make, g++) missing in $Distro." -ForegroundColor Yellow
    Write-Host "To install in WSL Ubuntu, run:" -ForegroundColor Cyan
    Write-Host "  wsl -d $Distro -- sudo apt-get update" -ForegroundColor Gray
    Write-Host "  wsl -d $Distro -- sudo apt-get install -y build-essential lld libgc-dev lldb" -ForegroundColor Gray
    Write-Host "  curl -fsSL https://crystal-lang.org/install.sh | sudo bash" -ForegroundColor Gray
}

# 5. Build run command
$flags = @()
if ($SkipSpecs) { $flags += "-SkipSpecs" }
if ($SkipRuntimeTests) { $flags += "-SkipRuntimeTests" }
if ($SkipToolTests) { $flags += "-SkipToolTests" }

$testCmd = if ($DebugWithLLDB) {
    "cd '$wslRoot' && lldb --batch -o 'run' -o 'bt' -- ./scripts/run_tests.ps1 $($flags -join ' ')"
} else {
    "cd '$wslRoot' && pwsh -NoProfile -File scripts/run_tests.ps1 $($flags -join ' ')"
}

Write-Host "[WSL] Running test suite in $Distro..." -ForegroundColor Cyan
wsl -d $Distro -- bash -c "$testCmd"
$exitCode = $LASTEXITCODE

if ($exitCode -eq 0) {
    Write-Host "[WSL] Test suite passed cleanly!" -ForegroundColor Green
} else {
    Write-Host "[WSL] Test suite failed with exit code $exitCode!" -ForegroundColor Red
}

exit $exitCode
