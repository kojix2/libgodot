# =============================================================================
# Helper: Package Addon Starter Template into bin/template-addon-project.zip
# =============================================================================
param(
    [string]$TargetDir = "bin",
    [string]$ZipName = "template-addon-project.zip",
    [string]$Release = "",
    [switch]$BundleBinaries
)

$ErrorActionPreference = "Stop"
$script = Join-Path $PSScriptRoot "scripts/package_template_addon.ps1"
$params = @{
    TargetDir = $TargetDir
    ZipName   = $ZipName
}
if ($Release) { $params["Release"] = $Release }
if ($BundleBinaries) { $params["BundleBinaries"] = $true }

& $script @params
exit $LASTEXITCODE
