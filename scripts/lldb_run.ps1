<#
.SYNOPSIS
    Runs Godot or a compiled LibGodot game executable under LLDB for debugging.

.DESCRIPTION
    Launches the Godot engine (or a standalone executable) under LLDB with full DWARF
    symbols from crystal_bridge.dll and game.dll. Supports batch mode with automatic
    crash backtraces, breakpoint scripts, and interactive debugging.

.EXAMPLE
    # Interactive debug session on test project
    .\scripts\lldb_run.ps1 -Path test

    # Debug editor on template project in batch mode (prints backtrace on crash)
    .\scripts\lldb_run.ps1 -Path template -Editor -Batch -QuitAfter 60

    # Breakpoint on specific function in crystal_bridge.dll
    .\scripts\lldb_run.ps1 -Path template -Headless -Quit -Commands @("b extension_instance.hpp:815", "run", "bt")
#>

param(
    [Parameter(Position = 0)]
    [string]$Path = "test",

    [switch]$Editor,
    [switch]$Headless,
    [switch]$Quit,
    [int]$QuitAfter = 0,
    [switch]$Batch,
    [string[]]$Commands = @(),
    [string]$TargetExe,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$AdditionalArgs
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $PSScriptRoot

# 1. Locate LLDB executable
$lldbCandidates = @(
    $env:LLDB,
    "C:\ProgramData\llvm\bin\lldb.exe",
    "C:\Program Files\LLVM\bin\lldb.exe",
    "C:\msys64\ucrt64\bin\lldb.exe",
    "C:\msys64\mingw64\bin\lldb.exe"
)
$lldbExe = $null
foreach ($cand in $lldbCandidates) {
    if ($cand -and (Test-Path $cand)) {
        $lldbExe = (Resolve-Path $cand).Path
        break
    }
}
if (-not $lldbExe -and (Get-Command lldb -ErrorAction SilentlyContinue)) {
    $lldbExe = (Get-Command lldb).Source
}

if (-not $lldbExe -or -not (Test-Path $lldbExe)) {
    Write-Host "[LLDB] Error: lldb.exe not found! Please install LLVM or set `$env:LLDB." -ForegroundColor Red
    exit 1
}

# 2. Locate Target Executable (default: godot.exe)
if ($TargetExe) {
    if ([System.IO.Path]::IsPathRooted($TargetExe)) {
        $resolvedTarget = $TargetExe
    } else {
        $resolvedTarget = Join-Path $RootDir $TargetExe
    }
} else {
    $godotCandidates = @(
        (Join-Path $RootDir "godot.exe"),
        (Join-Path $RootDir "godot"),
        $env:GODOT4,
        $env:GODOT
    )
    $resolvedTarget = $null
    foreach ($cand in $godotCandidates) {
        if ($cand -and (Test-Path $cand)) {
            $resolvedTarget = (Resolve-Path $cand).Path
            break
        }
    }
    if (-not $resolvedTarget -and (Get-Command godot -ErrorAction SilentlyContinue)) {
        $resolvedTarget = (Get-Command godot).Source
    }
}

if (-not $resolvedTarget -or -not (Test-Path $resolvedTarget)) {
    Write-Host "[LLDB] Error: Target executable '$resolvedTarget' not found!" -ForegroundColor Red
    exit 1
}

# 3. Resolve Target Project Path
if ([System.IO.Path]::IsPathRooted($Path)) {
    $targetDir = (Resolve-Path $Path -ErrorAction SilentlyContinue)
    if (-not $targetDir) { $targetDir = $Path }
} else {
    $candidate = Join-Path $RootDir $Path
    if (Test-Path $candidate) {
        $targetDir = (Resolve-Path $candidate).Path
    } else {
        $targetDir = $candidate
    }
}

# 4. Set up PATH for DLL resolution
$oldPath = $env:PATH
$binDirs = @(
    (Join-Path $targetDir "addons/crystal_integration/bin"),
    (Join-Path $targetDir "addons/crystal_addon/bin"),
    (Join-Path $targetDir "bin"),
    (Join-Path $RootDir "bin"),
    (Join-Path $RootDir "test/bin")
) | Where-Object { Test-Path $_ }

if ($binDirs) {
    $env:PATH = ($binDirs -join [System.IO.Path]::PathSeparator) + [System.IO.Path]::PathSeparator + $env:PATH
}

# 5. Build Program Arguments
$progArgs = @()
if ($Editor) {
    $progArgs += "--editor"
}
if ($Headless) {
    $progArgs += "--headless"
}
if (Test-Path $targetDir) {
    $progArgs += @("--path", $targetDir)
}
if ($Quit) {
    $progArgs += "--quit"
}
if ($QuitAfter -gt 0) {
    $progArgs += @("--quit-after", "$QuitAfter")
}
if ($AdditionalArgs) {
    $progArgs += $AdditionalArgs
}

# 6. Build LLDB Command Line
$lldbArgs = @()
if ($Batch) {
    $lldbArgs += "--batch"
}

if ($Commands -and $Commands.Count -gt 0) {
    foreach ($cmd in $Commands) {
        $lldbArgs += @("-o", $cmd)
    }
} elseif ($Batch) {
    # Default batch behavior: run target and exit cleanly
    $lldbArgs += @(
        "-o", "run",
        "-o", "quit"
    )
}

$lldbArgs += @("--", $resolvedTarget)
$lldbArgs += $progArgs

Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "           LibGodot LLDB Debugger                " -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "Debugger:  $lldbExe"
Write-Host "Target:    $resolvedTarget"
Write-Host "Project:   $targetDir"
Write-Host "Args:      $($progArgs -join ' ')"
if ($Batch) {
    Write-Host "Mode:      Batch (Automated Backtrace on Stop)"
} else {
    Write-Host "Mode:      Interactive"
}
Write-Host "=================================================" -ForegroundColor Cyan

try {
    & $lldbExe @lldbArgs
    $exitCode = $LASTEXITCODE
} finally {
    $env:PATH = $oldPath
}

exit $exitCode
