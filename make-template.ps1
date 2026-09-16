# =============================================================================
# Helper: Package Starter Template into bin/template-project.zip
# =============================================================================
param(
    [string]$TargetDir = "bin",
    [string]$ZipName = "template-project.zip",
    [string]$Release = "",
    [switch]$BundleBinaries
)

$ErrorActionPreference = "Stop"
$script = Join-Path $PSScriptRoot "scripts/package_template.ps1"
$params = @{
    TargetDir = $TargetDir
    ZipName   = $ZipName
}
if ($Release) { $params["Release"] = $Release }
if ($BundleBinaries) { $params["BundleBinaries"] = $true }

& $script @params
exit $LASTEXITCODE
