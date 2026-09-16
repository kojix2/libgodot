# =============================================================================
# Helper: Package Standalone Test Suite into bin/test-suite-<platform>.zip
# =============================================================================
param(
    [string]$TargetDir = "bin",
    [string]$Platform = "",
    [string]$Release = "",
    [string]$ZipName = "",
    [switch]$SkipVerify,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$script = Join-Path $PSScriptRoot "scripts/package_test_suite.ps1"
$params = @{
    TargetDir = $TargetDir
}
if ($Platform) { $params["Platform"] = $Platform }
if ($Release) { $params["Release"] = $Release }
if ($ZipName) { $params["ZipName"] = $ZipName }
if ($SkipVerify) { $params["SkipVerify"] = $true }
if ($Force) { $params["Force"] = $true }

& $script @params
exit $LASTEXITCODE
