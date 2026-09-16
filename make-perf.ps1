# =============================================================================
# Helper: Package Standalone Performance Benchmark into bin/perf-<platform>.zip
# =============================================================================
param(
    [string]$TargetDir = "bin",
    [string]$Platform = "",
    [string]$ArchiveName = "",
    [string]$Release = "",
    [switch]$SkipVerify,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$script = Join-Path $PSScriptRoot "scripts/package_perf.ps1"
$params = @{
    TargetDir = $TargetDir
}
if ($Platform) { $params["Platform"] = $Platform }
if ($ArchiveName) { $params["ArchiveName"] = $ArchiveName }
if ($Release) { $params["Release"] = $Release }
if ($SkipVerify) { $params["SkipVerify"] = $true }
if ($Force) { $params["Force"] = $true }

& $script @params
exit $LASTEXITCODE
