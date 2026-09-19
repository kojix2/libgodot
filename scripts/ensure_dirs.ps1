$RootDir = Split-Path -Parent $PSScriptRoot
$lapisExe = Join-Path $RootDir "bin/lapis.exe"
if (Test-Path $lapisExe) {
    & $lapisExe dirs
    exit $LASTEXITCODE
}
$dirs = @(
    (Join-Path $RootDir "bin"),
    (Join-Path $RootDir "addons/crystal_integration/bin"),
    (Join-Path $RootDir "test/bin"),
    (Join-Path $RootDir "template/bin"),
    (Join-Path $RootDir "performance/bin"),
    (Join-Path $RootDir "performance/addons/crystal_integration/bin")
)
foreach ($d in $dirs) {
    if (-not (Test-Path $d)) {
        New-Item -ItemType Directory -Force -Path $d | Out-Null
    }
}
