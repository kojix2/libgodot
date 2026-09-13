param(
    [string]$Project = ""
)

$ErrorActionPreference = "Continue"
$ScriptDir = $PSScriptRoot
$ParentDir = Split-Path -Parent $ScriptDir

# Determine project directory
if ([string]::IsNullOrWhiteSpace($Project)) {
    if (Test-Path "project.godot") {
        $projDir = (Get-Item ".").FullName
    } elseif (Test-Path (Join-Path $ParentDir "project.godot")) {
        $projDir = (Get-Item $ParentDir).FullName
    } elseif (Test-Path "template/project.godot") {
        $projDir = (Get-Item "template").FullName
    } else {
        $projDir = (Get-Item ".").FullName
    }
} elseif ([System.IO.Path]::IsPathRooted($Project)) {
    $projDir = (Resolve-Path $Project).Path
} else {
    if (Test-Path $Project) {
        $projDir = (Resolve-Path $Project).Path
    } elseif (Test-Path (Join-Path $ParentDir $Project)) {
        $projDir = (Resolve-Path (Join-Path $ParentDir $Project)).Path
    } else {
        $projDir = (Resolve-Path $Project).Path
    }
}

$godotCandidates = [System.Collections.Generic.List[string]]::new()
if ($env:GODOT -and (Test-Path $env:GODOT)) { $godotCandidates.Add($env:GODOT) }
if ($env:GODOT4 -and (Test-Path $env:GODOT4)) { $godotCandidates.Add($env:GODOT4) }

$curr = $projDir
while ($curr) {
    $godotCandidates.Add((Join-Path $curr "godot.exe"))
    $godotCandidates.Add((Join-Path $curr "godot"))
    $parent = Split-Path -Parent $curr
    if ($parent -eq $curr) { break }
    $curr = $parent
}
$godotCandidates.Add("godot")

$godotExe = $godotCandidates | Where-Object { (Test-Path $_) -or (Get-Command $_ -ErrorAction SilentlyContinue) } | Select-Object -First 1

if (-not $godotExe) {
    Write-Error "Could not locate Godot executable."
    exit 1
}

$scriptsDir = Join-Path $projDir "scripts"
if (-not (Test-Path $scriptsDir)) { New-Item -ItemType Directory -Force -Path $scriptsDir | Out-Null }
$dumpScript = Join-Path $scriptsDir "dump_project_nodes.gd"
if (-not (Test-Path $dumpScript)) {
    $repoDump = Join-Path $ParentDir "tools/api_generator/dump_project_nodes.gd"
    if (Test-Path $repoDump) {
        Copy-Item $repoDump $dumpScript -Force
    }
}

$genScript = Join-Path $scriptsDir "generate_project_bindings.cr"
if (-not (Test-Path $genScript)) {
    $repoGen = Join-Path $ParentDir "tools/api_generator/generate_project_bindings.cr"
    if (Test-Path $repoGen) {
        Copy-Item $repoGen $genScript -Force
    }
}

$outJson = Join-Path $projDir "src/generated/project_nodes.json"
$outDir = Join-Path $projDir "src/generated/project_nodes"
$genDir = Join-Path $projDir "src/generated"
if (-not (Test-Path $genDir)) { New-Item -ItemType Directory -Force -Path $genDir | Out-Null }

# Clean out old generated files before regen
if (Test-Path $outDir) {
    Write-Host "[ProjectBindings] Cleaning existing generated bindings in $outDir..." -ForegroundColor Cyan
    Get-ChildItem -Path $outDir -Recurse | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
} else {
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
}

Write-Host "[ProjectBindings] Dumping custom nodes for $(Split-Path -Leaf $projDir)..." -ForegroundColor Cyan
& $godotExe --headless --path $projDir -s res://scripts/dump_project_nodes.gd -- --output src/generated/project_nodes.json 2>&1 | Out-Null

if (Test-Path $outJson) {
    Write-Host "[ProjectBindings] Generating typed Crystal wrappers..." -ForegroundColor Cyan
    & crystal run $genScript -- $outJson $outDir
    Write-Host "[ProjectBindings] Successfully updated project bindings in $outDir!" -ForegroundColor Green
} else {
    Write-Host "[ProjectBindings] Warning: $outJson was not created." -ForegroundColor Yellow
}

$manifest = Join-Path $outDir "all_project_nodes.cr"
if (-not (Test-Path $manifest)) {
    Set-Content -Path $manifest -Value "# Generated All Project Custom Nodes Manifest`n" -NoNewline
}
