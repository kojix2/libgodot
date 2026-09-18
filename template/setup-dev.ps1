param(
    [string]$Version = "",
    [string]$DownloadUrl = "",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$projRoot = $PSScriptRoot
$onWindows = ($env:OS -eq "Windows_NT" -or [System.IO.Path]::PathSeparator -eq ';')
$isMac = $false
try {
    if ($IsMacOS -or [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)) {
        $isMac = $true
    }
} catch {}
if (-not $isMac -and -not $onWindows) {
    if ((Get-Command uname -ErrorAction SilentlyContinue) -and ((& uname) -eq "Darwin")) { $isMac = $true }
}

$exeName = if ($onWindows) { "godot.exe" } else { "godot" }
$targetExe = Join-Path $projRoot $exeName

# 1. Check if already installed
if (-not $Force -and (Test-Path $targetExe)) {
    Write-Host "[SetupDev] Godot is already installed at '$targetExe'." -ForegroundColor Green
    try {
        & $targetExe --headless --version
    } catch {}
    Write-Host "[SetupDev] To re-download, pass -Force." -ForegroundColor Cyan
    exit 0
}

# 2. Check if an existing Godot can be copied from parent folders or environment
if (-not $Force) {
    $existingCandidates = @(
        (Join-Path $projRoot "../$exeName"),
        (Join-Path $projRoot "../../$exeName"),
        $env:GODOT4,
        $env:GODOT4_BIN
    )
    $existingFound = $null
    foreach ($cand in $existingCandidates) {
        if ($cand -and (Test-Path $cand)) {
            $existingFound = (Resolve-Path $cand).Path
            break
        }
    }
    if (-not $existingFound -and (Get-Command godot -ErrorAction SilentlyContinue)) {
        $existingFound = (Get-Command godot).Source
    }
    if ($existingFound -and (Test-Path $existingFound)) {
        Write-Host "[SetupDev] Found existing Godot at '$existingFound'. Copying to '$targetExe'..." -ForegroundColor Green
        Copy-Item $existingFound $targetExe -Force
        if (-not $onWindows -and (Get-Command chmod -ErrorAction SilentlyContinue)) {
            & chmod +x $targetExe
        }
        try {
            & $targetExe --headless --version
        } catch {}
        exit 0
    }
}

# 3. Resolve target version
if (-not $Version) {
    foreach ($vFile in @((Join-Path $projRoot "godot-version.yml"), (Join-Path $projRoot "../godot-version.yml"))) {
        if (Test-Path $vFile) {
            $content = Get-Content -Path $vFile -Raw
            if ($content -match 'version:\s*"?([^"\r\n]+)"?') {
                $Version = $matches[1].Trim()
                break
            }
        }
    }
}
if (-not $Version) {
    $Version = "4.8-dev6"
}

# Normalize version tag (e.g. '4.8.dev5' -> '4.8-dev5')
$tag = $Version
if ($tag -match '^(\d+\.\d+)\.(dev\d+|rc\d+|beta\d+|alpha\d+|stable)$') {
    $tag = "$($matches[1])-$($matches[2])"
} elseif ($tag -match '^\d+\.\d+$') {
    $tag = "$tag-stable"
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  LibGodot Project Setup: Installing Godot Engine         " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Target Version : $tag" -ForegroundColor Gray

# 4. Resolve download URL (query GitHub API with direct fallback)
if (-not $DownloadUrl) {
    $apiUrl = "https://api.github.com/repos/godotengine/godot-builds/releases/tags/$tag"
    try {
        $headers = @{ "User-Agent" = "LibGodot-SetupDev" }
        $release = Invoke-RestMethod -Uri $apiUrl -Headers $headers -TimeoutSec 10 -ErrorAction Stop
        if ($onWindows) {
            $asset = $release.assets | Where-Object { $_.name -match 'win64.*\.zip$' -and $_.name -notmatch 'mono' } | Select-Object -First 1
        } elseif ($isMac) {
            $asset = $release.assets | Where-Object { $_.name -match 'macos.*\.zip$' -and $_.name -notmatch 'mono' } | Select-Object -First 1
        } else {
            $asset = $release.assets | Where-Object { $_.name -match 'linux.*x86_64.*\.zip$' -and $_.name -notmatch 'mono' } | Select-Object -First 1
        }
        if ($asset -and $asset.browser_download_url) {
            $DownloadUrl = $asset.browser_download_url
        }
    } catch {
        # Fallback to direct release download URL
    }

    if (-not $DownloadUrl) {
        $baseUrl = "https://github.com/godotengine/godot-builds/releases/download/$tag"
        if ($onWindows) {
            $DownloadUrl = "$baseUrl/Godot_v${tag}_win64.exe.zip"
        } elseif ($isMac) {
            $DownloadUrl = "$baseUrl/Godot_v${tag}_macos.universal.zip"
        } else {
            $DownloadUrl = "$baseUrl/Godot_v${tag}_linux.x86_64.zip"
        }
    }
}

Write-Host "[SetupDev] Downloading Godot from:" -ForegroundColor Cyan
Write-Host "  $DownloadUrl" -ForegroundColor Gray

$tempZip = Join-Path ([System.IO.Path]::GetTempPath()) "godot_setup_$([System.Guid]::NewGuid().ToString('N')).zip"
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "godot_setup_extract_$([System.Guid]::NewGuid().ToString('N'))"

try {
    if (Test-Path $tempZip) { Remove-Item $tempZip -Force }
    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }

    Write-Host "[SetupDev] Downloading archive..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $tempZip -UseBasicParsing

    Write-Host "[SetupDev] Extracting Godot archive..." -ForegroundColor Cyan
    Expand-Archive -Path $tempZip -DestinationPath $tempDir -Force

    $binaryFound = $null
    if ($onWindows) {
        $exes = Get-ChildItem -Path $tempDir -Filter "*.exe" -Recurse | Where-Object { $_.Name -notmatch '_console\.exe$' }
        if (-not $exes) {
            $exes = Get-ChildItem -Path $tempDir -Filter "*.exe" -Recurse
        }
        if ($exes) {
            $binaryFound = $exes[0].FullName
        }
    } elseif ($isMac) {
        $apps = Get-ChildItem -Path $tempDir -Filter "Godot.app" -Recurse
        if ($apps) {
            $macBin = Join-Path $apps[0].FullName "Contents/MacOS/Godot"
            if (Test-Path $macBin) { $binaryFound = $macBin }
        }
        if (-not $binaryFound) {
            $bins = Get-ChildItem -Path $tempDir -Recurse | Where-Object { -not $_.PSIsContainer -and $_.Name -match 'Godot' }
            if ($bins) { $binaryFound = $bins[0].FullName }
        }
    } else {
        $bins = Get-ChildItem -Path $tempDir -Recurse | Where-Object { -not $_.PSIsContainer -and ($_.Name -match 'linux' -or $_.Name -match 'Godot') }
        if ($bins) { $binaryFound = $bins[0].FullName }
    }

    if (-not $binaryFound -or -not (Test-Path $binaryFound)) {
        throw "Could not locate Godot executable inside extracted archive."
    }

    Write-Host "[SetupDev] Installing to $targetExe..." -ForegroundColor Cyan
    Copy-Item $binaryFound $targetExe -Force

    if (-not $onWindows -and (Get-Command chmod -ErrorAction SilentlyContinue)) {
        & chmod +x $targetExe
    }

    Write-Host "[SetupDev] Godot installed successfully at '$targetExe'!" -ForegroundColor Green
    try {
        & $targetExe --headless --version
    } catch {}
} finally {
    if (Test-Path $tempZip) { Remove-Item $tempZip -Force -ErrorAction SilentlyContinue }
    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
}
