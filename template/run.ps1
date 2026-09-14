# Run script for Crystal Godot Template
param(
    [switch]$NoBuild
)

$ErrorActionPreference = "Stop"

$projRoot = $PSScriptRoot
$onWindows = ($env:OS -eq "Windows_NT" -or [System.IO.Path]::PathSeparator -eq ';')
$exeName = if ($onWindows) { "godot.exe" } else { "godot" }

# 1. Resolve Godot executable
$godotCandidates = @(
    (Join-Path $projRoot $exeName),
    (Join-Path $projRoot "../$exeName"),
    (Join-Path $projRoot "../../$exeName"),
    $env:GODOT4,
    $env:GODOT4_BIN
)

$godotExe = $null
foreach ($cand in $godotCandidates) {
    if ($cand -and (Test-Path $cand)) {
        $godotExe = (Resolve-Path $cand).Path
        break
    }
}

if (-not $godotExe -and (Get-Command godot -ErrorAction SilentlyContinue)) {
    $godotExe = (Get-Command godot).Source
}

if (-not $godotExe) {
    Write-Host "[Run] Error: Godot engine executable was not found!" -ForegroundColor Red
    Write-Host "[Run] Run .\setup-dev.ps1 in this directory to automatically download and install Godot." -ForegroundColor Yellow
    exit 1
}

# 2. Build if requested
if (-not $NoBuild) {
    if (Get-Command make -ErrorAction SilentlyContinue) {
        & make -C $projRoot all
    } elseif (Test-Path (Join-Path $projRoot "build.ps1")) {
        & (Join-Path $projRoot "build.ps1")
    }
}

Write-Host "[Template] Launching Godot using $godotExe..." -ForegroundColor Cyan
& $godotExe --path $projRoot @args
