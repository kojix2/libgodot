param(
    [Parameter(Mandatory = $true)]
    [string]$Entry,
    [Parameter(Mandatory = $true)]
    [string]$Output,
    [string]$LinkFlags = "",
    [switch]$Release,
    [string]$SourcePath = "",
    [string]$Flags = ""
)

$RootDir = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($SourcePath)) {
    $SourcePath = Join-Path $RootDir "src"
}

# Set CRYSTAL_PATH
$baseCrystalPath = crystal env CRYSTAL_PATH
$sep = if ($env:OS -eq "Windows_NT" -or [System.IO.Path]::PathSeparator -eq ';') { ";" } else { ":" }
$env:CRYSTAL_PATH = "$SourcePath$sep$baseCrystalPath"

# Automatically generate project bindings if custom GDScript files are present
$entryDir = Split-Path -Parent $Entry
$projRoot = if ((Split-Path -Leaf $entryDir) -eq "src") { Split-Path -Parent $entryDir } else { $entryDir }
if ([string]::IsNullOrWhiteSpace($projRoot) -or $projRoot -eq ".") { $projRoot = (Get-Location).Path }
if (Test-Path $projRoot) {
    $gdFiles = Get-ChildItem -Path $projRoot -Filter "*.gd" -Recurse -ErrorAction SilentlyContinue | Where-Object {
        $_.FullName -notmatch '[\\/]addons[\\/]' -and
        $_.FullName -notmatch '[\\/]\.godot[\\/]' -and
        $_.FullName -notmatch '[\\/]tools[\\/]' -and
        $_.Name -ne "dump_project_nodes.gd"
    }
    $outDir = Join-Path $projRoot "src/generated/project_nodes"
    $outJson = Join-Path $projRoot "src/generated/project_nodes.json"

    if ($gdFiles) {
        $dumpScript = @(
            (Join-Path $projRoot "scripts/dump_project_nodes.gd"),
            (Join-Path $projRoot "tools/api_generator/dump_project_nodes.gd"),
            (Join-Path $RootDir "tools/api_generator/dump_project_nodes.gd")
        ) | Where-Object { Test-Path $_ } | Select-Object -First 1

        $genScript = @(
            (Join-Path $projRoot "scripts/generate_project_bindings.cr"),
            (Join-Path $projRoot "tools/api_generator/generate_project_bindings.cr"),
            (Join-Path $RootDir "tools/api_generator/generate_project_bindings.cr")
        ) | Where-Object { Test-Path $_ } | Select-Object -First 1

        if ($dumpScript -and $genScript) {
            $exeExt = if ($env:OS -eq "Windows_NT" -or [System.IO.Path]::PathSeparator -eq ';') { ".exe" } else { "" }
            $godotCandidates = @(
                $env:GODOT,
                $env:GODOT4,
                $env:GODOT_BIN,
                $env:GODOT4_BIN,
                (Join-Path $projRoot "godot$exeExt"),
                (Join-Path $projRoot "../godot$exeExt"),
                (Join-Path $RootDir "godot$exeExt"),
                (Join-Path $projRoot "godot.exe"),
                (Join-Path $projRoot "godot"),
                (Join-Path $RootDir "godot.exe"),
                (Join-Path $RootDir "godot")
            )

            $godotExe = ""
            foreach ($cand in $godotCandidates) {
                if (-not [string]::IsNullOrWhiteSpace($cand) -and (Test-Path $cand)) {
                    $godotExe = (Resolve-Path $cand).Path
                    break
                }
            }
            if (-not $godotExe) {
                $cmd = Get-Command godot -ErrorAction SilentlyContinue
                if ($cmd) {
                    $godotExe = if ($cmd.Source) { $cmd.Source } else { $cmd.Name }
                } else {
                    $cmd4 = Get-Command godot4 -ErrorAction SilentlyContinue
                    if ($cmd4) {
                        $godotExe = if ($cmd4.Source) { $cmd4.Source } else { $cmd4.Name }
                    }
                }
            }

            Write-Host "[Build] Updating project GDScript bindings for $($gdFiles.Count) script(s)..." -ForegroundColor Cyan
            $scriptsDir = Join-Path $projRoot "scripts"
            if (-not (Test-Path $scriptsDir)) { New-Item -ItemType Directory -Force -Path $scriptsDir | Out-Null }
            $localDump = Join-Path $scriptsDir "dump_project_nodes.gd"
            if (-not (Test-Path $localDump)) {
                Copy-Item $dumpScript $localDump -Force
            }

            # Clean out existing generated bindings before regen
            if (Test-Path $outDir) {
                Get-ChildItem -Path $outDir -Recurse | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
            } else {
                New-Item -ItemType Directory -Force -Path $outDir | Out-Null
            }

            $manifest = Join-Path $outDir "all_project_nodes.cr"
            try {
                if ($godotExe) {
                    $null = & $godotExe --headless --path $projRoot -s res://scripts/dump_project_nodes.gd -- --output src/generated/project_nodes.json 2>&1
                    if (Test-Path $outJson) {
                        & crystal run $genScript -- $outJson $outDir
                    } else {
                        Write-Host "[Build] Warning: $outJson was not created during project node dump" -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "[Build] Warning: Could not locate Godot executable to generate project bindings" -ForegroundColor Yellow
                }
            } catch {
                Write-Host "[Build] Warning during project bindings generation: $_" -ForegroundColor Yellow
            } finally {
                # Guarantee manifest exists so crystal build never fails on missing require
                if (-not (Test-Path $outDir)) {
                    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
                }
                if (-not (Test-Path $manifest)) {
                    Set-Content -Path $manifest -Value "# Generated All Project Custom Nodes Manifest`n" -NoNewline
                }
            }
        }
    } elseif (Test-Path $outDir) {
        $oldItems = Get-ChildItem -Path $outDir -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne "all_project_nodes.cr" }
        if ($oldItems) {
            Write-Host "[Build] Cleaning stale generated bindings in $outDir (no project GDScripts found)..." -ForegroundColor Cyan
            $oldItems | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        }
        $manifest = Join-Path $outDir "all_project_nodes.cr"
        if (Test-Path $manifest) {
            Set-Content -Path $manifest -Value "# Generated All Project Custom Nodes Manifest`n" -NoNewline
        }
        if (Test-Path $outJson) {
            Remove-Item -Path $outJson -Force -ErrorAction SilentlyContinue
        }
    }
}

$onWindows = ($env:OS -eq "Windows_NT" -or [System.IO.Path]::PathSeparator -eq ';')

$buildArgs = [System.Collections.Generic.List[string]]::new()
$buildArgs.Add("build")

if ($Release) {
    $buildArgs.Add("--release")
} else {
    $buildArgs.Add("--debug")
    if ($onWindows -and $LinkFlags -notmatch '/DEBUG') {
        $LinkFlags = if ([string]::IsNullOrWhiteSpace($LinkFlags)) { "/DEBUG:FULL" } else { "$LinkFlags /DEBUG:FULL" }
    }
}

if ($onWindows -and ($Output -match '\.dll$' -or $LinkFlags -match '/DLL')) {
    if ([string]::IsNullOrWhiteSpace($LinkFlags)) {
        $LinkFlags = "/DLL /ENTRY:_DllMainCRTStartup /EXPORT:crystal_godot_init"
    } elseif ($LinkFlags -notmatch '/EXPORT:crystal_godot_init') {
        $LinkFlags = "$LinkFlags /EXPORT:crystal_godot_init"
    }
}

if (-not [string]::IsNullOrWhiteSpace($Flags)) {
    foreach ($f in ($Flags -split '\s+')) {
        if (-not [string]::IsNullOrWhiteSpace($f)) {
            $buildArgs.Add($f)
        }
    }
}

# On Linux/Unix, GDExtension shared libraries run inside the Godot engine host process.
# Crystal 1.20+ enables a multi-threaded ExecutionContext thread pool by default on POSIX.
# Passing -Dwithout_mt ensures cooperative single-threaded fiber execution on the host engine thread,
# preventing worker thread spawning, thread pool hijacking, and Godot main thread ID assertions.
if (-not ($env:OS -eq "Windows_NT" -or [System.IO.Path]::PathSeparator -eq ';')) {
    if ($Output -match '\.so$' -or $Output -match '\.dylib$' -or $LinkFlags -match '-shared' -or $LinkFlags -match '-dynamiclib') {
        if (-not ($buildArgs -contains "-Dwithout_mt")) {
            $buildArgs.Add("-Dwithout_mt")
        }
    }
}

# On Linux/macOS, shared library linking requires hiding static runtime symbols
# to avoid symbol collisions between multiple loaded Crystal shared libraries.
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

if ($isMac -and ($Output -match '\.dylib$' -or $LinkFlags -match '-dynamiclib')) {
    if ($LinkFlags -notmatch '-dynamiclib') {
        $LinkFlags = if ([string]::IsNullOrWhiteSpace($LinkFlags)) { "-dynamiclib" } else { "$LinkFlags -dynamiclib" }
    }
    if ($LinkFlags -notmatch '-exported_symbol') {
        $LinkFlags = "$LinkFlags -Wl,-exported_symbol,_crystal_godot_init"
    }
} elseif (-not $onWindows -and -not $isMac -and ($Output -match '\.so$' -or $LinkFlags -match '-shared')) {
    # Crystal passes -rdynamic when invoking cc, which translates to -export-dynamic.
    # On Linux, this forces internal Crystal symbols containing '@' into .dynsym,
    # causing linkers (LLD and GNU ld) to fail with "has undefined version" or "version node not found".
    # We use a wrapper for CC that strips -rdynamic so only exported symbols (crystal_godot_init) enter .dynsym.
    $wrapperCandidate = Join-Path $RootDir "scripts/cc_wrapper.sh"
    $wrapperPath = ""
    if (Test-Path $wrapperCandidate) {
        $wrapperPath = (Resolve-Path $wrapperCandidate).Path
    } else {
        $wrapperPath = $wrapperCandidate
        $scriptContent = @'
#!/usr/bin/env bash
is_shared=0
for arg in "$@"; do
    if [ "$arg" = "-shared" ]; then
        is_shared=1
        break
    fi
done

target_cc="${REAL_CC:-cc}"
if [ "$is_shared" -eq 0 ]; then
    exec "$target_cc" "$@"
fi

objs=()
flags=()
for arg in "$@"; do
    if [ "$arg" = "-rdynamic" ]; then
        continue
    elif [ -f "$arg" ] && [[ "$arg" == *.o || "$arg" == *.o.* || "$arg" == *.obj ]]; then
        objs+=("$arg")
    else
        flags+=("$arg")
    fi
done

if [ ${#objs[@]} -eq 0 ]; then
    exec "$target_cc" "$@"
fi

tmp_dir="${TMPDIR:-/tmp}"
combined="$tmp_dir/crystal_comb_$$.o"
localized="$tmp_dir/crystal_loc_$$.o"
cleanup() { rm -f "$combined" "$localized"; }
trap cleanup EXIT INT TERM

ld -r "${objs[@]}" -o "$combined" || exit $?
objcopy -w --keep-global-symbol=crystal_godot_init "$combined" "$localized" || exit $?
"$target_cc" "$localized" -Wl,-Bsymbolic -Wl,-Bsymbolic-functions "${flags[@]}"
exit $?
'@
        Set-Content -Path $wrapperPath -Value $scriptContent -NoNewline -Force
    }
    if (Get-Command chmod -ErrorAction SilentlyContinue) {
        & chmod +x $wrapperPath
    }
    if (-not [string]::IsNullOrWhiteSpace($env:CC) -and $env:CC -ne $wrapperPath) {
        $env:REAL_CC = $env:CC
    }
    $env:CC = $wrapperPath

    if ($LinkFlags -notmatch '--version-script') {
        $candidates = @(
            (Join-Path $RootDir "src/bridge/crystal_game.sym"),
            (Join-Path $RootDir "addons/crystal_integration/crystal_game.sym"),
            (Join-Path (Get-Location) "addons/crystal_integration/crystal_game.sym")
        )
        $symFile = ""
        foreach ($cand in $candidates) {
            if (Test-Path $cand) {
                $symFile = (Resolve-Path $cand).Path
                break
            }
        }
        if ([string]::IsNullOrWhiteSpace($symFile)) {
            $symFile = Join-Path ([System.IO.Path]::GetTempPath()) "crystal_game.sym"
            Set-Content -Path $symFile -Value "{`n  global:`n    crystal_godot_init;`n  local:`n    *;`n};`n" -Force
        }
        $extraFlags = "-Wl,-Bsymbolic -Wl,-Bsymbolic-functions -Wl,--undefined-version -Wl,--no-export-dynamic -Wl,--version-script=$symFile"
        if ((Get-Command ld.lld -ErrorAction SilentlyContinue) -or (Get-Command lld -ErrorAction SilentlyContinue)) {
            $extraFlags = "-fuse-ld=lld $extraFlags"
        }
        $LinkFlags = if ([string]::IsNullOrWhiteSpace($LinkFlags)) { "-shared $extraFlags" } else { "$LinkFlags $extraFlags" }
    }
}

if (-not [string]::IsNullOrWhiteSpace($LinkFlags)) {
    $buildArgs.Add("--link-flags")
    $buildArgs.Add($LinkFlags)
}

$buildArgs.Add($Entry)
$buildArgs.Add("-o")
$buildArgs.Add($Output)

& crystal $buildArgs
exit $LASTEXITCODE
