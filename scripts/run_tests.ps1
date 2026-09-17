# =============================================================================
# LibGodot Automated Test Suite Runner (CI & Local)
# =============================================================================
# Runs:
#   1. Crystal Verification Specs (spec/libgodot_spec.cr, spec/boot_spec.cr)
#   2. Headless In-Editor @tool Script Tests (ToolTester2D, ToolTester3D)
#   3. Full Runtime 2D & 3D Test Project Suites (Nodes, GDScript, Mesh, Physics, Stress)
#   4. Template and Example Project Smoke Tests
#
# Returns exit code 0 on complete success, or 1 on any failure (ready for GitHub Actions).
# =============================================================================

param(
    [string]$GodotPath,
    [switch]$SkipSpecs,
    [switch]$SkipToolTests,
    [switch]$SkipEditorTests,
    [switch]$SkipRuntimeTests,
    [switch]$SkipStandaloneTests,
    [switch]$SkipSmokeTests,
    [int]$TimeoutSeconds = 180
)

if ($env:TEST_STEP_TIMEOUT) {
    $TimeoutSeconds = [int]$env:TEST_STEP_TIMEOUT
}

$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $PSScriptRoot
$TestDir = Join-Path $RootDir "test"
$TestBinDir = Join-Path $TestDir "bin"
$TemplateDir = Join-Path $RootDir "template"
$ExamplesDir = Join-Path $RootDir "examples"

if (-not (Test-Path $TestBinDir)) {
    New-Item -ItemType Directory -Force -Path $TestBinDir | Out-Null
}

# Ensure single-worker Crystal runtime when testing inside host engines to prevent thread pool conflicts
if (-not ($env:OS -like "*Windows*" -or $IsWindows)) {
    $env:CRYSTAL_WORKERS = "1"
}

# Clean up any legacy root executables, reports, or markers from previous runs
@(
    (Join-Path $TestDir "tests.exe"),
    (Join-Path $TestDir "tests"),
    (Join-Path $TestDir "game.exe"),
    (Join-Path $TestDir "game"),
    (Join-Path $TestDir "test_report.md"),
    (Join-Path $TestDir "test_report.json"),
    (Join-Path $TestDir ".tool_tests_passed"),
    (Join-Path $TestDir ".tool_tests_failed"),
    (Join-Path $TestDir ".runtime_tests_passed"),
    (Join-Path $TestDir ".runtime_tests_failed"),
    (Join-Path $TestDir ".runtime_test_results.txt")
) | Where-Object { Test-Path $_ } | ForEach-Object {
    Remove-Item $_ -Force -ErrorAction SilentlyContinue
}

# Resolve Godot executable path
$GodotExe = $null
$normGodot4 = if ($env:GODOT4) { if ($IsWindows) { $env:GODOT4 -replace '^/([a-zA-Z])/', '$1:/' } else { $env:GODOT4 } } else { $null }
$normGodot = if ($env:GODOT) { if ($IsWindows) { $env:GODOT -replace '^/([a-zA-Z])/', '$1:/' } else { $env:GODOT } } else { $null }

if (-not [string]::IsNullOrWhiteSpace($GodotPath) -and (Test-Path $GodotPath)) {
    $GodotExe = (Resolve-Path $GodotPath).Path
} elseif (-not [string]::IsNullOrWhiteSpace($normGodot4) -and (Test-Path $normGodot4)) {
    $GodotExe = (Resolve-Path $normGodot4).Path
} elseif (-not [string]::IsNullOrWhiteSpace($normGodot) -and (Test-Path $normGodot)) {
    $GodotExe = (Resolve-Path $normGodot).Path
} elseif ($IsWindows -and (Test-Path (Join-Path $RootDir "godot.exe"))) {
    $GodotExe = Join-Path $RootDir "godot.exe"
} elseif (Test-Path (Join-Path $RootDir "godot")) {
    $GodotExe = Join-Path $RootDir "godot"
} elseif (Test-Path (Join-Path $RootDir "Godot.app/Contents/MacOS/Godot")) {
    $GodotExe = Join-Path $RootDir "Godot.app/Contents/MacOS/Godot"
} elseif (Test-Path "/Applications/Godot.app/Contents/MacOS/Godot") {
    $GodotExe = "/Applications/Godot.app/Contents/MacOS/Godot"
} elseif (Get-Command godot -ErrorAction SilentlyContinue) {
    $GodotExe = (Get-Command godot).Source
} elseif (Test-Path (Join-Path $RootDir "godot.exe")) {
    $GodotExe = Join-Path $RootDir "godot.exe"
}

if (-not $GodotExe -or -not (Test-Path $GodotExe)) {
    Write-Host "::error::Godot executable was not found. Please provide -GodotPath, set `$env:GODOT4 or place godot.exe in $RootDir" -ForegroundColor Red
    exit 1
}

$FailedSteps = [System.Collections.Generic.List[string]]::new()
$RecordedResults = [System.Collections.Generic.List[hashtable]]::new()
$StartTime = Get-Date

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "             LibGodot Automated Test Suite Runner                " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "Root Directory: $RootDir"
Write-Host "Godot Engine:   $GodotExe"
Write-Host ""

# Helper to run a command and stream output directly
function Invoke-TestCommand {
    param(
        [string]$Name,
        [string]$Category,
        [string]$Executable,
        [string[]]$Arguments,
        [string]$WorkingDirectory = $RootDir,
        [hashtable]$EnvironmentVars = @{},
        [switch]$CustomVerification,
        [int]$Timeout = $TimeoutSeconds,
        [string]$OutputFile = ""
    )

    Write-Host "::group::$Name" -ForegroundColor Yellow
    Write-Host "[RUNNING] $Name (Timeout: ${Timeout}s)" -ForegroundColor Cyan
    Write-Host "Command: $Executable $($Arguments -join ' ')" -ForegroundColor DarkGray

    # Set environment variables
    foreach ($k in $EnvironmentVars.Keys) {
        [System.Environment]::SetEnvironmentVariable($k, $EnvironmentVars[$k])
    }

    $cmdStart = Get-Date
    # Ensure working directory bin and root bin are in PATH for DLL resolution
    $oldPath = $env:PATH
    $oldDyldFallback = $env:DYLD_FALLBACK_LIBRARY_PATH
    $binCandidates = @(
        (Join-Path $WorkingDirectory "addons/crystal_addon/bin"),
        (Join-Path $WorkingDirectory "bin"),
        (Join-Path $RootDir "bin"),
        (Join-Path $RootDir "test/bin")
    ) | Where-Object { Test-Path $_ }
    if ($binCandidates) {
        $binJoined = $binCandidates -join [System.IO.Path]::PathSeparator
        $env:PATH = $binJoined + [System.IO.Path]::PathSeparator + $env:PATH
        if ($env:DYLD_FALLBACK_LIBRARY_PATH) {
            $env:DYLD_FALLBACK_LIBRARY_PATH = $binJoined + ":" + $env:DYLD_FALLBACK_LIBRARY_PATH
        } else {
            $env:DYLD_FALLBACK_LIBRARY_PATH = $binJoined
        }
    }

    $timedOut = $false
    $exitCode = -1

    Push-Location $WorkingDirectory
    try {
        $resolvedExe = $Executable
        if (Test-Path $Executable) {
            $resolvedExe = (Resolve-Path $Executable).Path
        } else {
            $cmd = Get-Command $Executable -ErrorAction SilentlyContinue
            if ($cmd -and $cmd.Source) {
                $resolvedExe = $cmd.Source
            } elseif ($cmd -and $cmd.Path) {
                $resolvedExe = $cmd.Path
            }
        }

        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $resolvedExe
        $psi.WorkingDirectory = $WorkingDirectory
        $psi.UseShellExecute = $false

        foreach ($k in $EnvironmentVars.Keys) {
            $psi.EnvironmentVariables[$k] = [string]$EnvironmentVars[$k]
        }

        if ($psi.PSObject.Properties['ArgumentList']) {
            foreach ($a in $Arguments) { $psi.ArgumentList.Add($a) }
        } else {
            $psi.Arguments = ($Arguments | ForEach-Object {
                if ($_ -match '[\s"]') {
                    '"' + ($_ -replace '(\\*)(")', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
                } else {
                    $_
                }
            }) -join ' '
        }

        $stdoutTask = $null
        $stderrTask = $null

        if ($OutputFile) {
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.CreateNoWindow = $true
        } else {
            $psi.RedirectStandardOutput = $false
            $psi.RedirectStandardError = $false
        }

        $proc = [System.Diagnostics.Process]::Start($psi)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()

        if ($OutputFile) {
            $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
            $stderrTask = $proc.StandardError.ReadToEndAsync()
        }

        while (-not $proc.HasExited) {
            if ($sw.Elapsed.TotalSeconds -ge $Timeout) {
                $timedOut = $true
                Write-Host "`n::error::[TIMEOUT] '$Name' exceeded maximum timeout of ${Timeout}s! Terminating process..." -ForegroundColor Red
                try {
                    $proc.Kill($true)
                } catch {
                    try { $proc.Kill() } catch {}
                }
                break
            }
            Start-Sleep -Milliseconds 100
        }

        $proc.WaitForExit()

        if ($OutputFile) {
            $outStr = if ($stdoutTask) { $stdoutTask.Result } else { "" }
            $errStr = if ($stderrTask) { $stderrTask.Result } else { "" }
            $fullLog = ($outStr + "`n" + $errStr).Trim()
            Set-Content -Path $OutputFile -Value $fullLog -Force
            if ($fullLog) {
                Write-Host $fullLog
            }
        }

        $exitCode = if ($timedOut) { -1 } else { $proc.ExitCode }
    } catch {
        Write-Host "::error::Failed to launch '$Executable': $_" -ForegroundColor Red
        $exitCode = 1
    } finally {
        Pop-Location
        $env:PATH = $oldPath
        $env:DYLD_FALLBACK_LIBRARY_PATH = $oldDyldFallback
        foreach ($k in $EnvironmentVars.Keys) {
            [System.Environment]::SetEnvironmentVariable($k, $null)
        }
    }

    $cmdDuration = [math]::Round(((Get-Date) - $cmdStart).TotalSeconds, 2)
    Write-Host "::endgroup::"

    $crashPatterns = @(
        "Invalid memory access",
        "signal 11",
        "signal 6",
        "Segmentation fault",
        "SIGSEGV",
        "SIGABRT",
        "EXCEPTION_ACCESS_VIOLATION",
        "CRASH INTERCEPTED",
        "0xC0000005",
        "Stack overflow",
        "AddressSanitizer"
    )
    $hasCrash = $false
    if ($OutputFile -and (Test-Path $OutputFile)) {
        $logCheck = Get-Content $OutputFile -Raw
        foreach ($cp in $crashPatterns) {
            if ($logCheck -match [regex]::Escape($cp)) {
                $hasCrash = $true
                break
            }
        }
    }

    $isSuccess = ($exitCode -eq 0 -and -not $timedOut -and -not $hasCrash)
    $item = @{
        Name = $Name
        Category = $Category
        Success = $isSuccess
        ExitCode = $exitCode
        Duration = $cmdDuration
        TimedOut = $timedOut
        HasCrash = $hasCrash
    }
    $RecordedResults.Add($item)

    if ($timedOut) {
        $FailedSteps.Add("$Name (Timed out after ${Timeout}s)")
        Write-Host "[FAILED] $Name (TIMED OUT after ${Timeout}s)`n" -ForegroundColor Red
        return $item
    }

    if ($hasCrash) {
        $FailedSteps.Add("$Name (Fatal crash / memory violation detected, exit code: $exitCode)")
        Write-Host "::error::[CRASH DETECTED] '$Name' crashed with fatal signal or memory access violation! (Exit Code: $exitCode)`n" -ForegroundColor Red
        Write-Host "[FAILED] $Name (CRASHED: signal 11 / memory violation detected, exit code: $exitCode)`n" -ForegroundColor Red
        return $item
    }

    if ($exitCode -ne 0) {
        if (-not $CustomVerification) {
            $FailedSteps.Add("$Name (Exit Code: $exitCode)")
            Write-Host "[FAILED] $Name (Exit Code: $exitCode, ${cmdDuration}s)`n" -ForegroundColor Red
        }
        return $item
    }

    if ($CustomVerification) {
        return $item
    }

    Write-Host "[PASSED] $Name (Exit Code: $exitCode, ${cmdDuration}s)`n" -ForegroundColor Green
    return $item
}

# -----------------------------------------------------------------------------
# Phase 1: Crystal Unit Specs
# -----------------------------------------------------------------------------
if (-not $SkipSpecs) {
    Write-Host "--- Phase 1: Crystal Verification Specs ---" -ForegroundColor Magenta

    $editorSpecResult = Invoke-TestCommand -Name "Crystal Spec: Test Editor Suite (test/spec)" `
        -Executable "crystal" `
        -Arguments @("spec", "--no-color") `
        -WorkingDirectory $TestDir
    if (-not $editorSpecResult["Success"]) {
        $FailedSteps.Add("Crystal Spec: Test Editor Suite (test/spec)")
    }

    $specResult1 = Invoke-TestCommand -Name "Crystal Spec: LibGodot Core" `
        -Executable "crystal" `
        -Arguments @("run", "spec/libgodot_spec.cr")
    if (-not $specResult1["Success"]) {
        $FailedSteps.Add("Crystal Spec (libgodot_spec.cr)")
    }

    $specResult2 = Invoke-TestCommand -Name "Crystal Spec: Boot Loader" `
        -Executable "crystal" `
        -Arguments @("run", "spec/boot_spec.cr")
    if (-not $specResult2["Success"]) {
        $FailedSteps.Add("Crystal Spec (boot_spec.cr)")
    }

    $apiJsonPath = Join-Path $RootDir "extension_api.json"
    if ((-not (Test-Path $apiJsonPath)) -and $GodotExe -and (Test-Path $GodotExe)) {
        Write-Host "Dumping extension_api.json for api_coverage_spec..." -ForegroundColor Cyan
        & $GodotExe --headless --dump-extension-api | Out-Null
    }

    $specResult3 = Invoke-TestCommand -Name "Crystal Spec: API Definition & Class Coverage" `
        -Executable "crystal" `
        -Arguments @("run", "spec/api_coverage_spec.cr")
    if (-not $specResult3["Success"]) {
        $FailedSteps.Add("Crystal Spec (api_coverage_spec.cr)")
    }

    $specResult4 = Invoke-TestCommand -Name "Crystal Spec: Project Scaffolding & Directory Integrity" `
        -Executable "crystal" `
        -Arguments @("run", "spec/project_scaffolding_spec.cr")
    if (-not $specResult4["Success"]) {
        $FailedSteps.Add("Crystal Spec (project_scaffolding_spec.cr)")
    }
}

# -----------------------------------------------------------------------------
# Phase 2: In-Editor Tool Script Tests (Tickled via godot --headless --editor)
# -----------------------------------------------------------------------------
if (-not $SkipToolTests) {
    Write-Host "--- Phase 2: In-Editor @tool Script Tests ---" -ForegroundColor Magenta

    # Clear old marker files
    $passMarkers = @(
        (Join-Path $TestBinDir ".tool_tests_passed"),
        (Join-Path $TestDir ".tool_tests_passed")
    )
    $failMarkers = @(
        (Join-Path $TestBinDir ".tool_tests_failed"),
        (Join-Path $TestDir ".tool_tests_failed")
    )
    foreach ($m in ($passMarkers + $failMarkers)) {
        if (Test-Path $m) { Remove-Item $m -Force }
    }

    # Ensure test project extension_list.cfg is pre-populated before headless tool tests
    $ensureExtScript = Join-Path $RootDir "scripts/ensure_extension_list.ps1"
    if (Test-Path $ensureExtScript) {
        & $ensureExtScript -ProjectPath $TestDir
    }

    $scratchDir = Join-Path $RootDir "scratch"
    if (-not (Test-Path $scratchDir)) { New-Item -ItemType Directory -Force -Path $scratchDir | Out-Null }
    $toolLogFile = Join-Path $scratchDir "headless_editor_tool_tests.log"
    if (Test-Path $toolLogFile) { Remove-Item $toolLogFile -Force }

    $toolResult = Invoke-TestCommand -Name "Headless Editor Tool Tests (ToolTester2D & ToolTester3D)" `
        -Executable $GodotExe `
        -Arguments @("--headless", "--rendering-driver", "opengl3", "--audio-driver", "Dummy", "--editor", "--path", "test", "--quit-after", "300") `
        -EnvironmentVars @{ "GODOT_RUN_TOOL_TESTS" = "1"; "LIBGL_ALWAYS_SOFTWARE" = "1" } `
        -OutputFile $toolLogFile `
        -CustomVerification

    $failedMarkerFound = $failMarkers | Where-Object { Test-Path $_ } | Select-Object -First 1
    $passedMarkerFound = $passMarkers | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $toolResult["Success"] -or $toolResult["HasCrash"] -or $toolResult["ExitCode"] -ne 0 -or $toolResult["TimedOut"]) {
        $toolResult["Success"] = $false
        if (-not ($FailedSteps | Where-Object { $_ -like "*Headless Editor Tool Tests*" })) {
            $FailedSteps.Add("In-Editor Tool Tests (Process crashed or exited with code $($toolResult['ExitCode']))")
        }
        Write-Host "[FAILED] Headless Editor Tool Tests (ToolTester2D & ToolTester3D) (Exit Code: $($toolResult['ExitCode']))`n" -ForegroundColor Red
    } elseif ($failedMarkerFound) {
        $failContent = Get-Content $failedMarkerFound -Raw
        Write-Host "::error::In-Editor tool tests reported failures in marker file:`n$failContent" -ForegroundColor Red
        $FailedSteps.Add("In-Editor Tool Tests (ToolTester2D / ToolTester3D failed: $failContent)")
        $toolResult["Success"] = $false
        Write-Host "[FAILED] Headless Editor Tool Tests (ToolTester2D & ToolTester3D)`n" -ForegroundColor Red
    } elseif ($passedMarkerFound) {
        $toolResult["Success"] = $true
        Write-Host "[PASSED] In-Editor tool tests executed cleanly and verified via marker file.`n" -ForegroundColor Green
    } else {
        $FailedSteps.Add("In-Editor Tool Tests (Missing completion marker file)")
        $toolResult["Success"] = $false
        Write-Host "[FAILED] Headless Editor Tool Tests (Missing completion marker file)`n" -ForegroundColor Red
    }

    # -------------------------------------------------------------------------
    # Editor Addon Verification: Load compiled Crystal EditorPlugin and verify unique string
    # -------------------------------------------------------------------------
    Write-Host "[Editor Addon Test] Verifying compiled Crystal Addon loads in Godot Editor..." -ForegroundColor Cyan
    $scratchDir = Join-Path $RootDir "scratch"
    if (-not (Test-Path $scratchDir)) { New-Item -ItemType Directory -Force -Path $scratchDir | Out-Null }
    $addonLogFile = Join-Path $scratchDir "addon_editor_test.log"
    if (Test-Path $addonLogFile) { Remove-Item $addonLogFile -Force }

    $uniqueString = "[CRYSTAL_ADDON_VERIFIED_SUCCESS_8A3F1E]"

    # Pre-populate extension_list.cfg so Godot loads GDExtension upfront without in-flight scan races
    $addonGodotDir = Join-Path $RootDir "template-addon/.godot"
    if (-not (Test-Path $addonGodotDir)) { New-Item -ItemType Directory -Force -Path $addonGodotDir | Out-Null }
    Set-Content -Path (Join-Path $addonGodotDir "extension_list.cfg") -Value @('res://addons/crystal_addon/crystal_addon.gdextension', 'res://addons/crystal_integration/crystal.gdextension') -Force

    $addonDir = Join-Path $RootDir "template-addon"
    $addonEditorResult = Invoke-TestCommand -Name "Headless Editor Addon Test (template-addon)" `
        -Executable $GodotExe `
        -Arguments @("--headless", "--rendering-driver", "opengl3", "--audio-driver", "Dummy", "--editor", "--path", $addonDir, "--quit") `
        -WorkingDirectory $addonDir `
        -OutputFile $addonLogFile `
        -CustomVerification

    $addonLogContent = if (Test-Path $addonLogFile) { Get-Content $addonLogFile -Raw } else { "" }
    $hasCrash = $addonLogContent -match "CRASH INTERCEPTED" -or $addonLogContent -match "EXCEPTION_ACCESS_VIOLATION" -or $addonLogContent -match "Invalid memory access" -or $addonLogContent -match "signal 11" -or $addonLogContent -match "signal 6" -or $addonLogContent -match "Segmentation fault" -or $addonLogContent -match "SIGSEGV" -or $addonLogContent -match "SIGABRT" -or $addonLogContent -match "0xC0000005" -or $addonLogContent -match "Stack overflow"
    if ($addonLogContent -match [regex]::Escape($uniqueString) -and (-not $hasCrash) -and ($addonEditorResult["ExitCode"] -eq 0 -or $addonEditorResult["ExitCode"] -eq 1)) {
        $addonEditorResult["Success"] = $true
        Write-Host "[PASSED] Compiled Crystal Addon verified in Godot Editor! Found unique string: $uniqueString`n" -ForegroundColor Green
    } elseif ($addonLogContent -match [regex]::Escape($uniqueString)) {
        $addonEditorResult["Success"] = $false
        Write-Host "::error::Compiled Crystal Addon loaded, but process crashed or exited with error!`nLog output:`n$addonLogContent" -ForegroundColor Red
        $FailedSteps.Add("Editor Addon Test (Process crashed or exited with code $($addonEditorResult['ExitCode']))")
        Write-Host "[FAILED] Headless Editor Addon Test (template-addon) (Exit Code: $($addonEditorResult['ExitCode']))`n" -ForegroundColor Red
    } else {
        $addonEditorResult["Success"] = $false
        Write-Host "::error::Compiled Crystal Addon failed to load or did not print unique string '$uniqueString'!`nLog output:`n$addonLogContent" -ForegroundColor Red
        $FailedSteps.Add("Editor Addon Test (Unique string '$uniqueString' not found in editor log)")
        Write-Host "[FAILED] Headless Editor Addon Test (template-addon)`n" -ForegroundColor Red
    }
}

# -----------------------------------------------------------------------------
# Phase 2b: Godot Editor Launch & Clean Shutdown Verification
# -----------------------------------------------------------------------------
if (-not $SkipEditorTests) {
    Write-Host "--- Phase 2b: Godot Editor Launch & Clean Shutdown Verification ---" -ForegroundColor Magenta
    $verifyEditorScript = Join-Path $RootDir "scripts/verify_editor.ps1"
    if (Test-Path $verifyEditorScript) {
        $pwshExe = (Get-Process -Id $PID).Path
        if (-not $pwshExe -or -not (Test-Path $pwshExe)) { $pwshExe = "powershell" }
        $extraVerifyArgs = if (-not ($env:OS -like "*Windows*" -or $IsWindows)) { @("-Headless") } else { @() }

        # 1. Verify template project editor launch
        $editorTemplateResult = Invoke-TestCommand -Name "Editor Launch & Clean Shutdown (template)" `
            -Executable $pwshExe `
            -Arguments (@("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $verifyEditorScript, "-Path", "template", "-QuitAfter", "60", "-PurgeCache", "-GodotExe", $GodotExe) + $extraVerifyArgs) `
            -CustomVerification
        if (-not $editorTemplateResult["Success"]) {
            $FailedSteps.Add("Editor Launch (template project)")
            Write-Host "[FAILED] Godot Editor Launch on template project`n" -ForegroundColor Red
        } else {
            Write-Host "[PASSED] Godot Editor Launch on template project verified.`n" -ForegroundColor Green
        }

        # 2. Verify test project editor launch
        $editorTestResult = Invoke-TestCommand -Name "Editor Launch & Clean Shutdown (test)" `
            -Executable $pwshExe `
            -Arguments (@("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $verifyEditorScript, "-Path", "test", "-QuitAfter", "60", "-GodotExe", $GodotExe) + $extraVerifyArgs) `
            -CustomVerification
        if (-not $editorTestResult["Success"]) {
            $FailedSteps.Add("Editor Launch (test project)")
            Write-Host "[FAILED] Godot Editor Launch on test project`n" -ForegroundColor Red
        } else {
            Write-Host "[PASSED] Godot Editor Launch on test project verified.`n" -ForegroundColor Green
        }

        # 3. Verify editor live Crystal recompilation & GDExtension reload (template project)
        $editorRebuildResult = Invoke-TestCommand -Name "Editor Live Crystal Rebuild & Reload (template, 1 cycle)" `
            -Executable $pwshExe `
            -Arguments (@("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $verifyEditorScript, "-Path", "template", "-TestBuildButton", "-ReloadCycles", "1", "-PurgeCache", "-GodotExe", $GodotExe) + $extraVerifyArgs) `
            -Timeout 360 `
            -CustomVerification
        if (-not $editorRebuildResult["Success"]) {
            $FailedSteps.Add("Editor Live Rebuild & Reload (template)")
            Write-Host "[FAILED] In-Editor Crystal Rebuild & Reload on template project`n" -ForegroundColor Red
        } else {
            Write-Host "[PASSED] In-Editor Crystal Rebuild & Reload on template project verified.`n" -ForegroundColor Green
        }

        # 3b. Verify editor live Crystal compilation error recovery (template project)
        $editorErrRecoveryResult = Invoke-TestCommand -Name "Editor Live Crystal Error Recovery (template)" `
            -Executable $pwshExe `
            -Arguments (@("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $verifyEditorScript, "-Path", "template", "-TestErrorRecovery", "-PurgeCache", "-GodotExe", $GodotExe) + $extraVerifyArgs) `
            -Timeout 300 `
            -CustomVerification
        if (-not $editorErrRecoveryResult["Success"]) {
            $FailedSteps.Add("Editor Live Error Recovery (template)")
            Write-Host "[FAILED] In-Editor Crystal Error Recovery on template project`n" -ForegroundColor Red
        } else {
            Write-Host "[PASSED] In-Editor Crystal Error Recovery on template project verified.`n" -ForegroundColor Green
        }

        # 4. Verify run-editor.ps1 CLI & Output Shadowing
        $testRunEditorScript = Join-Path $RootDir "scripts/test_run_editor.ps1"
        if (Test-Path $testRunEditorScript) {
            $runnerTestResult = Invoke-TestCommand -Name "Unified Editor Launcher & Log Shadowing (run-editor.ps1)" `
                -Executable $pwshExe `
                -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $testRunEditorScript) `
                -CustomVerification
            if (-not $runnerTestResult["Success"]) {
                $FailedSteps.Add("Editor Launcher CLI Test (run-editor.ps1)")
                Write-Host "[FAILED] Unified Editor Launcher & Log Shadowing verification`n" -ForegroundColor Red
            } else {
                Write-Host "[PASSED] Unified Editor Launcher & Log Shadowing verified.`n" -ForegroundColor Green
            }
        }
    }
}

# -----------------------------------------------------------------------------
# Phase 3: Standalone Compiled Test Runner (./tests --autorun)
# -----------------------------------------------------------------------------
# Ensure dummy addons are compiled and synced for multi-addon isolation tests
$dummyScript = Join-Path $RootDir "scripts/build_dummy_addons.ps1"
if (Test-Path $dummyScript) {
    & $dummyScript
}
$syncScript = Join-Path $RootDir "scripts/sync_bins.ps1"
if (Test-Path $syncScript) {
    & $syncScript
}

if (-not $SkipStandaloneTests) {
    Write-Host "--- Phase 3: Standalone Compiled Test Runner (./tests --autorun) ---" -ForegroundColor Magenta

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
    $exeExt = if ($onWindows) { ".exe" } else { "" }
    $pkgScript = Join-Path $RootDir "scripts/package_game.ps1"
    $standaloneExe = Join-Path $TestBinDir "tests$exeExt"

    # Clean any stale shadow files before packaging
    Get-ChildItem -Path $TestDir -Filter "~*" -Force -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

    # 1. Package test suite into standalone executable (Debug)
    Write-Host "[Standalone Test] Packaging test project into standalone executable (Debug)..." -ForegroundColor Cyan
    & $pkgScript -ProjectPath $TestDir -Name "tests" -ForceCompile
    Get-ChildItem -Path $TestDir -Filter "~*" -Force -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

    if (-not (Test-Path $standaloneExe)) {
        $candidateExe = Join-Path $TestBinDir "game$exeExt"
        if (Test-Path $candidateExe) { $standaloneExe = $candidateExe }
    }

    $runExe = $standaloneExe
    if ($onWindows) {
        $consoleExe = Join-Path $TestBinDir "tests.console.exe"
        if (Test-Path $consoleExe) {
            $runExe = $consoleExe
        }
    }

    if (Test-Path $runExe) {
        $runPassMarkers = @(
            (Join-Path $TestBinDir ".runtime_tests_passed"),
            (Join-Path $TestDir ".runtime_tests_passed")
        )
        $runFailMarkers = @(
            (Join-Path $TestBinDir ".runtime_tests_failed"),
            (Join-Path $TestDir ".runtime_tests_failed")
        )
        $summaryFiles = @(
            (Join-Path $TestBinDir ".runtime_test_results.txt"),
            (Join-Path $TestDir ".runtime_test_results.txt")
        )
        foreach ($m in ($runPassMarkers + $runFailMarkers + $summaryFiles)) {
            if (Test-Path $m) { Remove-Item $m -Force }
        }

        # Standalone exported templates forbid '--path' and '--main-pack', so we run directly in TestBinDir.
        # On macOS, Godot runs as a launcher wrapper around Godot.app which requires explicit --main-pack.
        $standalonePackArgs = @()
        if ($isMac) {
            $pckCandidate = Join-Path $TestBinDir "tests.pck"
            if (Test-Path $pckCandidate) {
                $standalonePackArgs = @("--main-pack", $pckCandidate)
            }
        }
        $standaloneLogFile = Join-Path $scratchDir "standalone_tests.log"
        if (Test-Path $standaloneLogFile) { Remove-Item $standaloneLogFile -Force }

        $standaloneResult = Invoke-TestCommand -Name "Standalone Compiled Test Runner (tests$exeExt --autorun)" `
            -Executable $runExe `
            -Arguments (@("--headless", "--rendering-driver", "opengl3", "--audio-driver", "Dummy") + $standalonePackArgs + @("--quit-after", "600", "--", "--autorun")) `
            -WorkingDirectory $TestBinDir `
            -OutputFile $standaloneLogFile `
            -CustomVerification

        foreach ($sf in $summaryFiles) {
            if (Test-Path $sf) {
                $summary = Get-Content $sf -Raw
                Write-Host "Standalone Test Execution Summary:`n$summary" -ForegroundColor Cyan
                break
            }
        }

        $failedMarkerFound = $runFailMarkers | Where-Object { Test-Path $_ } | Select-Object -First 1
        $passedMarkerFound = $runPassMarkers | Where-Object { Test-Path $_ } | Select-Object -First 1

        if (-not $standaloneResult["Success"] -or $standaloneResult["HasCrash"] -or $standaloneResult["ExitCode"] -ne 0 -or $standaloneResult["TimedOut"]) {
            $standaloneResult["Success"] = $false
            if (-not ($FailedSteps | Where-Object { $_ -like "*Standalone Test Suite*" })) {
                $FailedSteps.Add("Standalone Test Suite (Process crashed or exited with code $($standaloneResult['ExitCode']))")
            }
            Write-Host "[FAILED] Standalone Compiled Test Runner (tests$exeExt --autorun) (Exit Code: $($standaloneResult['ExitCode']))`n" -ForegroundColor Red
        } elseif ($failedMarkerFound) {
            $standaloneResult["Success"] = $false
            Write-Host "::error::Standalone runtime test suite reported failures!" -ForegroundColor Red
            $FailedSteps.Add("Standalone Test Suite (Failures recorded in $failedMarkerFound)")
            Write-Host "[FAILED] Standalone Compiled Test Runner (tests$exeExt --autorun)`n" -ForegroundColor Red
        } elseif ($passedMarkerFound) {
            $standaloneResult["Success"] = $true
            Write-Host "[PASSED] Standalone compiled test runner executed and verified with --autorun.`n" -ForegroundColor Green
        } else {
            $standaloneResult["Success"] = $false
            $FailedSteps.Add("Standalone Test Suite (Missing completion marker file)")
            Write-Host "[FAILED] Standalone Compiled Test Runner (Missing completion marker file)`n" -ForegroundColor Red
        }
    } else {
        Write-Host "::error::Standalone tests executable '$runExe' was not created." -ForegroundColor Red
        $FailedSteps.Add("Standalone Test Suite (Executable not found: $runExe)")
    }

    # 2. Package and verify in Standalone Release Mode if requested
    if ($env:RELEASE -eq "1") {
        Get-ChildItem -Path $TestDir -Filter "~*" -Force -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        Write-Host "[Standalone Test] Packaging test project in RELEASE mode..." -ForegroundColor Cyan
        & $pkgScript -ProjectPath $TestDir -Name "tests" -Release 1 -ForceCompile
        Get-ChildItem -Path $TestDir -Filter "~*" -Force -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

        if (Test-Path $runExe) {
            foreach ($m in ($runPassMarkers + $runFailMarkers + $summaryFiles)) {
                if (Test-Path $m) { Remove-Item $m -Force }
            }

            $relPackArgs = @()
            if ($isMac) {
                $pckCandidate = Join-Path $TestBinDir "tests.pck"
                if (Test-Path $pckCandidate) {
                    $relPackArgs = @("--main-pack", $pckCandidate)
                }
            }
            $relLogFile = Join-Path $scratchDir "standalone_rel_tests.log"
            if (Test-Path $relLogFile) { Remove-Item $relLogFile -Force }

            $relResult = Invoke-TestCommand -Name "Standalone Release Test Runner (tests$exeExt --autorun RELEASE=1)" `
                -Executable $runExe `
                -Arguments (@("--headless", "--rendering-driver", "opengl3", "--audio-driver", "Dummy") + $relPackArgs + @("--quit-after", "600", "--", "--autorun")) `
                -WorkingDirectory $TestBinDir `
                -OutputFile $relLogFile `
                -CustomVerification

            $failedRel = $runFailMarkers | Where-Object { Test-Path $_ } | Select-Object -First 1
            $passedRel = $runPassMarkers | Where-Object { Test-Path $_ } | Select-Object -First 1

            if (-not $relResult["Success"] -or $relResult["HasCrash"] -or $relResult["ExitCode"] -ne 0 -or $relResult["TimedOut"] -or $failedRel -or (-not $passedRel)) {
                $relResult["Success"] = $false
                if (-not ($FailedSteps | Where-Object { $_ -like "*Standalone Release Test Suite*" })) {
                    $FailedSteps.Add("Standalone Release Test Suite (Process crashed or exited with code $($relResult['ExitCode']))")
                }
                Write-Host "[FAILED] Standalone Release Test Runner`n" -ForegroundColor Red
            } else {
                $relResult["Success"] = $true
                Write-Host "[PASSED] Standalone release test runner executed and verified with --autorun.`n" -ForegroundColor Green
            }
        }
    }
}

# -----------------------------------------------------------------------------
# Phase 3b: In-Project Runtime Test Runner (Godot Engine Host)
# -----------------------------------------------------------------------------
if (-not $SkipRuntimeTests) {
    Write-Host "--- Phase 3b: In-Project Runtime Test Runner (Godot Engine Host) ---" -ForegroundColor Magenta

    # Clear old marker files
    $runPassMarkers = @(
        (Join-Path $TestBinDir ".runtime_tests_passed"),
        (Join-Path $TestDir ".runtime_tests_passed")
    )
    $runFailMarkers = @(
        (Join-Path $TestBinDir ".runtime_tests_failed"),
        (Join-Path $TestDir ".runtime_tests_failed")
    )
    $summaryFiles = @(
        (Join-Path $TestBinDir ".runtime_test_results.txt"),
        (Join-Path $TestDir ".runtime_test_results.txt")
    )
    foreach ($m in ($runPassMarkers + $runFailMarkers + $summaryFiles)) {
        if (Test-Path $m) { Remove-Item $m -Force }
    }

    $runtimeLogFile = Join-Path $scratchDir "runtime_tests.log"
    if (Test-Path $runtimeLogFile) { Remove-Item $runtimeLogFile -Force }

    $runtimeResult = Invoke-TestCommand -Name "Runtime Test Runner (main_test_runner.tscn --autorun)" `
        -Executable $GodotExe `
        -Arguments @("--headless", "--rendering-driver", "opengl3", "--audio-driver", "Dummy", "--path", ".", "--quit-after", "600", "--", "--autorun") `
        -WorkingDirectory $TestDir `
        -OutputFile $runtimeLogFile `
        -CustomVerification

    foreach ($sf in $summaryFiles) {
        if (Test-Path $sf) {
            $summary = Get-Content $sf -Raw
            Write-Host "Test Execution Summary:`n$summary" -ForegroundColor Cyan
            break
        }
    }

    $failedMarkerFound = $runFailMarkers | Where-Object { Test-Path $_ } | Select-Object -First 1
    $passedMarkerFound = $runPassMarkers | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $runtimeResult["Success"] -or $runtimeResult["HasCrash"] -or $runtimeResult["ExitCode"] -ne 0 -or $runtimeResult["TimedOut"]) {
        $runtimeResult["Success"] = $false
        if (-not ($FailedSteps | Where-Object { $_ -like "*Runtime Test Suite*" })) {
            $FailedSteps.Add("Runtime Test Suite (Process crashed or exited with code $($runtimeResult['ExitCode']))")
        }
        Write-Host "[FAILED] Runtime Test Runner (main_test_runner.tscn) (Exit Code: $($runtimeResult['ExitCode']))`n" -ForegroundColor Red
    } elseif ($failedMarkerFound) {
        $runtimeResult["Success"] = $false
        Write-Host "::error::Runtime test suite reported failures!" -ForegroundColor Red
        $FailedSteps.Add("Runtime Test Suite (Failures recorded in $failedMarkerFound)")
        Write-Host "[FAILED] Runtime Test Runner (main_test_runner.tscn)`n" -ForegroundColor Red
    } elseif ($passedMarkerFound) {
        $runtimeResult["Success"] = $true
        Write-Host "[PASSED] All runtime test suites executed and verified.`n" -ForegroundColor Green
    } else {
        $runtimeResult["Success"] = $false
        $FailedSteps.Add("Runtime Test Suite (Missing completion marker file)")
        Write-Host "[FAILED] Runtime Test Runner (Missing completion marker file)`n" -ForegroundColor Red
    }
}

# -----------------------------------------------------------------------------
# Phase 4: Template and Example Project Smoke Tests
# -----------------------------------------------------------------------------
if (-not $SkipSmokeTests) {
    Write-Host "--- Phase 4: Template & Example Smoke Tests ---" -ForegroundColor Magenta

    if (Test-Path $TemplateDir) {
        $templateResult = Invoke-TestCommand -Name "Smoke Test: Template Project" `
            -Executable $GodotExe `
            -Arguments @("--headless", "--rendering-driver", "opengl3", "--audio-driver", "Dummy", "--path", "template", "--quit")
        if (-not $templateResult["Success"]) {
            $FailedSteps.Add("Smoke Test: Template Project")
        }
    }

    $basicDemoDir = Join-Path $ExamplesDir "basic_demo"
    if (Test-Path $basicDemoDir) {
        $demoResult = Invoke-TestCommand -Name "Smoke Test: Basic Demo Example" `
            -Executable $GodotExe `
            -Arguments @("--headless", "--rendering-driver", "opengl3", "--audio-driver", "Dummy", "--path", "examples/basic_demo", "--quit")
        if (-not $demoResult["Success"]) {
            $FailedSteps.Add("Smoke Test: Basic Demo")
        }
    }
}

# -----------------------------------------------------------------------------
# Generate Custom Status Report (Markdown & JSON)
# -----------------------------------------------------------------------------
$Duration = [math]::Round(((Get-Date) - $StartTime).TotalSeconds, 2)
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
$platformArch = if ([System.Environment]::Is64BitProcess) {
    if ($isMac -and [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture -eq "Arm64") { "arm64" } else { "x86_64" }
} else { "x86" }
$platformName = if ($onWindows) { "Windows ($platformArch)" } elseif ($isMac) { "macOS ($platformArch)" } else { "Linux ($platformArch)" }
$crystalVer = (crystal -v 2>$null | Select-Object -First 1)
$godotVer = (& $GodotExe --version 2>$null | Select-Object -First 1)

$runtimeTotal = 0
$runtimePassed = 0
$runtimeFailed = 0
$summaryFile = Join-Path $TestBinDir ".runtime_test_results.txt"
if (Test-Path $summaryFile) {
    $rawSummary = Get-Content $summaryFile -Raw
    if ($rawSummary -match 'TOTAL=(\d+)') { $runtimeTotal = [int]$matches[1] }
    if ($rawSummary -match 'PASSED=(\d+)') { $runtimePassed = [int]$matches[1] }
    if ($rawSummary -match 'FAILED=(\d+)') { $runtimeFailed = [int]$matches[1] }
}

$statusBadge = if ($FailedSteps.Count -eq 0) { "**SUCCESS (All Passed)**" } else { "**FAILED ($($FailedSteps.Count) failed)**" }

$mdReport = [System.Text.StringBuilder]::new()
[void]$mdReport.AppendLine("## LibGodot Test Suite Status Report ($platformName)")
[void]$mdReport.AppendLine("")
[void]$mdReport.AppendLine("| Metric | Value |")
[void]$mdReport.AppendLine("| :--- | :--- |")
[void]$mdReport.AppendLine("| **Overall Status** | $statusBadge |")
[void]$mdReport.AppendLine("| **Platform** | $platformName |")
[void]$mdReport.AppendLine("| **Crystal Version** | $crystalVer |")
[void]$mdReport.AppendLine("| **Godot Version** | $godotVer |")
[void]$mdReport.AppendLine("| **Total Duration** | ${Duration}s |")
if ($runtimeTotal -gt 0) {
    [void]$mdReport.AppendLine("| **Runtime Assertions** | $runtimePassed / $runtimeTotal passed |")
}
[void]$mdReport.AppendLine("")
[void]$mdReport.AppendLine("### Executed Test Steps")
[void]$mdReport.AppendLine("")
[void]$mdReport.AppendLine("| Status | Phase / Test Step | Duration | Exit Code |")
[void]$mdReport.AppendLine("| :---: | :--- | :---: | :---: |")

foreach ($res in $RecordedResults) {
    $resIcon = if ($res["Success"]) { "PASSED" } else { "FAILED" }
    [void]$mdReport.AppendLine("| $resIcon | $($res['Name']) | $($res['Duration'])s | $($res['ExitCode']) |")
}

if ($FailedSteps.Count -gt 0) {
    [void]$mdReport.AppendLine("")
    [void]$mdReport.AppendLine("### Failures Detected ($($FailedSteps.Count))")
    foreach ($f in $FailedSteps) {
        [void]$mdReport.AppendLine("- FAIL: $f")
    }
}

$reportMdContent = $mdReport.ToString()
$reportMdPath = Join-Path $TestBinDir "test_report.md"
Set-Content -Path $reportMdPath -Value $reportMdContent -Force
$reportMdPathRoot = Join-Path $TestDir "test_report.md"
Set-Content -Path $reportMdPathRoot -Value $reportMdContent -Force

# Generate JSON report
$jsonReport = @{
    platform = $platformName
    crystal_version = $crystalVer
    godot_version = $godotVer
    duration_seconds = $Duration
    overall_success = ($FailedSteps.Count -eq 0)
    failed_steps_count = $FailedSteps.Count
    failed_steps = $FailedSteps
    runtime_summary = @{
        total = $runtimeTotal
        passed = $runtimePassed
        failed = $runtimeFailed
    }
    steps = $RecordedResults
    timestamp = (Get-Date -Format "o")
} | ConvertTo-Json -Depth 5
$reportJsonPath = Join-Path $TestBinDir "test_report.json"
Set-Content -Path $reportJsonPath -Value $jsonReport -Force
$reportJsonPathRoot = Join-Path $TestDir "test_report.json"
Set-Content -Path $reportJsonPathRoot -Value $jsonReport -Force

# Append to GITHUB_STEP_SUMMARY if running in GitHub Actions
if ($env:GITHUB_STEP_SUMMARY) {
    try {
        [System.IO.File]::AppendAllText($env:GITHUB_STEP_SUMMARY, "`n$reportMdContent`n")
        Write-Host "  -> Published test report to GitHub Step Summary." -ForegroundColor Green
    } catch {
        Write-Warning "Could not write to GITHUB_STEP_SUMMARY: $_"
    }
}

# -----------------------------------------------------------------------------
# Final Summary & Exit
# -----------------------------------------------------------------------------
Write-Host "=================================================================" -ForegroundColor Cyan
if ($FailedSteps.Count -eq 0) {
    Write-Host "  SUCCESS: All LibGodot test suites passed! ($Duration seconds)   " -ForegroundColor Green
    Write-Host "=================================================================" -ForegroundColor Cyan
    exit 0
} else {
    Write-Host "  FAILURE: $($FailedSteps.Count) test step(s) failed ($Duration seconds):" -ForegroundColor Red
    foreach ($f in $FailedSteps) {
        Write-Host "    ✘ $f" -ForegroundColor Red
    }
    Write-Host "=================================================================" -ForegroundColor Cyan
    exit 1
}
