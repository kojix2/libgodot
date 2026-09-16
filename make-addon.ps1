# =============================================================================
# Helper: Package Official Crystal Addon into bin/godot-crystal-addon.zip
# =============================================================================
param(
    [string]$TargetDir = "bin",
    [string]$ZipName = "godot-crystal-addon.zip",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$script = Join-Path $PSScriptRoot "scripts/package_addon.ps1"
$params = @{
    TargetDir = $TargetDir
    ZipName   = $ZipName
}
if ($Force) { $params["Force"] = $true }

& $script @params
exit $LASTEXITCODE
