# =============================================================================
# Helper: Package Examples into bin/examples-<platform>.zip
# =============================================================================
param(
    [string]$TargetDir = "bin",
    [string]$Platform = "",
    [string]$ZipName = "",
    [string]$Release = "1"
)

$ErrorActionPreference = "Stop"
$script = Join-Path $PSScriptRoot "scripts/package_examples.ps1"
$params = @{
    TargetDir = $TargetDir
}
if ($Platform) { $params["Platform"] = $Platform }
if ($ZipName) { $params["ZipName"] = $ZipName }
if ($Release) { $params["Release"] = $Release }

& $script @params
exit $LASTEXITCODE
