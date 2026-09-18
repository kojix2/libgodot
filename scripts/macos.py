#!/usr/bin/env python3
"""Native macOS workspace build and test runner (no PowerShell required)."""

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import platform
import re
import shlex
import shutil
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent.parent
CRYSTAL = shlex.split(os.environ.get("CRYSTAL", "crystal"))
HEADLESS = ["--headless", "--rendering-driver", "opengl3", "--audio-driver", "Dummy"]
ERRORS = re.compile(
    r"Invalid memory access|signal (?:11|6)|Segmentation fault|SIGSEGV|SIGABRT|"
    r"CRASH INTERCEPTED|Stack overflow|AddressSanitizer|SCRIPT ERROR:|"
    r"No loader found for resource.*\.cr|BUG: Unreferenced static string to 0|"
    r"Required virtual method .* must be overridden|Can't open GDExtension dynamic library|"
    r"Error loading extension|Failed to find 'crystal_godot_init'",
    re.MULTILINE | re.IGNORECASE,
)


def godot_path():
    candidates = [os.environ.get(key) for key in ("GODOT", "GODOT4", "GODOT4_BIN")]
    candidates += [str(ROOT / "godot"), str(ROOT / "Godot.app/Contents/MacOS/Godot"),
                   "/Applications/Godot.app/Contents/MacOS/Godot", "godot", "godot4"]
    for candidate in filter(None, candidates):
        resolved = shutil.which(candidate)
        if resolved:
            return str(Path(resolved).absolute())
    raise RuntimeError("Godot was not found. Set GODOT to its executable path.")


def projects():
    return [ROOT / name for name in ("test", "template", "template-addon", "performance")] + [
        path.parent for path in sorted((ROOT / "examples").glob("*/project.godot"))
    ]


def environment():
    env = os.environ.copy()
    base = subprocess.check_output(CRYSTAL + ["env", "CRYSTAL_PATH"], text=True).strip()
    env["CRYSTAL_PATH"] = str(ROOT / "src") + os.pathsep + base
    env["CRYSTAL_WORKERS"] = "1"
    # Keep compiler caches inside the workspace, including in sandboxed runs.
    env.setdefault("CRYSTAL_CACHE_DIR", str(ROOT / "scratch/crystal-cache"))
    return env


def run(command, env, cwd=ROOT):
    print("+ " + shlex.join(map(str, command)), flush=True)
    subprocess.run(list(map(str, command)), cwd=cwd, env=env, check=True)


def copy(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)


def extension_list(project):
    extensions = sorted((project / "addons").rglob("*.gdextension"),
                        key=lambda p: ("crystal_integration" not in p.parts, str(p)))
    config = project / ".godot/extension_list.cfg"
    config.parent.mkdir(parents=True, exist_ok=True)
    config.write_text("".join("res://" + p.relative_to(project).as_posix() + "\n"
                              for p in extensions))
    for name in ("bin", "lib"):
        directory = project / name
        if directory.exists():
            (directory / ".gdignore").touch()


def build():
    env = environment()
    godot = godot_path()
    release = os.environ.get("RELEASE") == "1"
    bin_dir = ROOT / "bin"
    bin_dir.mkdir(exist_ok=True)
    bridge = bin_dir / "crystal_bridge.dylib"
    flags = shlex.split(os.environ.get("CXXFLAGS", "-std=c++17 -O2 -g -fPIC -I rsrc"))
    if release:
        flags += ["-DLIBGODOT_RELEASE=1", "-DNDEBUG"]
    run(shlex.split(os.environ.get("CXX", "clang++")) + ["-dynamiclib"] + flags +
        [ROOT / "src/bridge/crystal_bridge.cpp", "-o", bridge], env)

    def library(entry, output, addon=False):
        output.parent.mkdir(parents=True, exist_ok=True)
        command = CRYSTAL + ["build", "--release" if release else "--debug", "-Dwithout_mt"]
        if addon:
            command += ["-Dlibgodot_addon"]
        command += [str(entry), "-o", str(output), "--link-flags",
                    "-dynamiclib -Wl,-exported_symbol,_crystal_godot_init"]
        run(command, env)

    library(ROOT / "src/editor/plugin.cr", bin_dir / "plugin.dylib", addon=True)
    for name in ("crystal_bridge.dylib", "plugin.dylib", "libgodot.dylib"):
        if (bin_dir / name).exists():
            copy(bin_dir / name, ROOT / "addons/crystal_integration/bin" / name)
    for project in projects():
        integration = project / "addons/crystal_integration"
        shutil.copytree(ROOT / "addons/crystal_integration", integration, dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns("bin"))
        if project.name == "template-addon":
            # This project owns its game library in crystal_addon, while the
            # integration addon loads only plugin.dylib. Retire old copied games.
            stale_game = integration / "bin/game.dylib"
            if stale_game.exists():
                retired = ROOT / "scratch/template-addon-obsolete-game.dylib"
                retired.parent.mkdir(parents=True, exist_ok=True)
                stale_game.replace(retired)
        destinations = [project / "bin", integration / "bin"]
        if project.name == "template-addon":
            destinations.append(project / "addons/crystal_addon/bin")
        destinations += [p / "bin" for p in sorted((project / "addons").glob("dummy_*"))]
        for destination in destinations:
            copy(bridge, destination / bridge.name)
            if (bin_dir / "libgodot.dylib").exists():
                copy(bin_dir / "libgodot.dylib", destination / "libgodot.dylib")
        copy(bin_dir / "plugin.dylib", integration / "bin/plugin.dylib")
        extension_list(project)

        for addon in sorted((project / "addons").glob("dummy_*")):
            library(addon / "src/main.cr", addon / "bin" / (addon.name + ".dylib"), addon=True)

        game = (project / "addons/crystal_addon/bin" if project.name == "template-addon"
                else project / "bin") / "game.dylib"
        # The dump loads GDExtensions too: replace old consumers before using the
        # newly built bridge, whose ABI may differ from a previous checkout.
        library(project / "src/main.cr", game, addon=project.name == "template-addon")
        if project.name != "template-addon":
            copy(game, integration / "bin/game.dylib")

        # Regenerate wrappers for custom GDScript classes before compiling consumers.
        scripts = [p for p in project.rglob("*.gd")
                   if not {"addons", ".godot", "lib", "tools", "bin", "dist", "export"}.intersection(
                       p.relative_to(project).parts)
                   and p.name != "dump_project_nodes.gd"]
        if scripts:
            dump = project / "scripts/dump_project_nodes.gd"
            copy(ROOT / "tools/api_generator/dump_project_nodes.gd", dump)
            output = project / "src/generated/project_nodes.json"
            output.parent.mkdir(parents=True, exist_ok=True)
            run([godot] + HEADLESS + ["--path", project, "-s", "res://scripts/dump_project_nodes.gd",
                                      "--", "--output", "src/generated/project_nodes.json"], env)
            run(CRYSTAL + ["run", str(ROOT / "tools/api_generator/generate_project_bindings.cr"),
                           "--", str(output), str(output.parent / "project_nodes")], env)

            library(project / "src/main.cr", game, addon=project.name == "template-addon")
            if project.name != "template-addon":
                copy(game, integration / "bin/game.dylib")
        if project.name == "test":
            copy(game, bin_dir / "game.dylib")
        if project.name == "template-addon":
            shutil.copytree(project / "addons/crystal_addon", project / "dist", dirs_exist_ok=True)
    print("macOS workspace build and synchronization complete.", flush=True)


def test(args):
    started = time.monotonic()
    test_dir = ROOT / "test"
    (test_dir / "bin").mkdir(exist_ok=True)
    for directory in (test_dir, test_dir / "bin"):
        for name in ("test_report.json", "test_report.md"):
            (directory / name).unlink(missing_ok=True)
    env = environment()
    godot = godot_path()
    timeout = int(os.environ.get("TEST_STEP_TIMEOUT", args.timeout_seconds))
    scratch = ROOT / "scratch"
    scratch.mkdir(exist_ok=True)
    results = []
    for project in projects():
        extension_list(project)

    def step(name, command, cwd=ROOT, extra_env=None, verify=None):
        print(f"[RUNNING] {name}", flush=True)
        started = time.monotonic()
        log = scratch / (re.sub(r"[^a-z0-9]+", "_", name.lower()) + ".log")
        timed_out = False
        with log.open("w") as output:
            try:
                process = subprocess.Popen(list(map(str, command)), cwd=cwd,
                                           env=dict(env, **(extra_env or {})), stdout=output,
                                           stderr=subprocess.STDOUT, start_new_session=True)
                try:
                    code = process.wait(timeout=timeout)
                except subprocess.TimeoutExpired:
                    timed_out = True
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    code = process.wait()
            except OSError as error:
                output.write(str(error))
                code = 1
        content = log.read_text(errors="replace")
        success = code == 0 and not timed_out and not ERRORS.search(content)
        if verify:
            success = success and verify(content)
        print(content, end="" if content.endswith("\n") else "\n", flush=True)
        print(f"[{'PASSED' if success else 'FAILED'}] {name} (log: {log.relative_to(ROOT)})", flush=True)
        results.append(dict(Name=name, Success=bool(success), ExitCode=code,
                            TimedOut=timed_out, Duration=round(time.monotonic() - started, 2)))

    def markers(kind):
        locations = [test_dir, test_dir / "bin"]
        for directory in locations:
            for suffix in ("passed", "failed"):
                (directory / f".{kind}_tests_{suffix}").unlink(missing_ok=True)
            if kind == "runtime":
                (directory / ".runtime_test_results.txt").unlink(missing_ok=True)

        def verify(content):
            return (any((p / f".{kind}_tests_passed").exists() for p in locations)
                    and not any((p / f".{kind}_tests_failed").exists() for p in locations))
        return verify

    if not args.skip_specs:
        step("Crystal specs", CRYSTAL + ["spec", "test/spec", "--no-color"])
        for name in ("libgodot", "boot", "api_coverage", "project_scaffolding"):
            if name == "api_coverage" and not (ROOT / "extension_api.json").exists():
                step("Dump extension API", [godot] + HEADLESS + ["--dump-extension-api"])
            step("Crystal " + name, CRYSTAL + ["run", f"spec/{name}_spec.cr", "--no-color"])
    if not args.skip_tool_tests:
        step("Editor tool tests", [godot] + HEADLESS + ["--editor", "--path", test_dir,
                                                      "--quit-after", "300"],
             cwd=test_dir, extra_env={"GODOT_RUN_TOOL_TESTS": "1"}, verify=markers("tool"))
        step("Editor addon", [godot] + HEADLESS + ["--editor", "--path", ROOT / "template-addon",
                                                 "--quit-after", "60"],
             verify=lambda log: "[CRYSTAL_ADDON_VERIFIED_SUCCESS_8A3F1E]" in log)
    if not args.skip_editor_tests:
        for project in (ROOT / "template", test_dir):
            step("Editor shutdown " + project.name, [godot] + HEADLESS +
                 ["--editor", "--path", project, "--quit-after", "60"], cwd=project)
    if not args.skip_runtime_tests:
        step("Runtime tests", [godot] + HEADLESS + ["--path", test_dir, "--quit-after", "600",
                                                  "--", "--autorun"],
             cwd=test_dir, verify=markers("runtime"))
    if not args.skip_standalone_tests:
        # Exported GDExtensions resolve native libraries beside the runner,
        # outside the PCK. Preserve each addon's independent runtime library.
        for library in (test_dir / "addons").rglob("*.dylib"):
            if "_loaded_" not in library.name and not library.name.startswith("~"):
                copy(library, test_dir / "bin/addons" / library.relative_to(test_dir / "addons"))
        (test_dir / "bin/addons/.gdignore").touch()
        pack = test_dir / "bin/tests.pck"
        pack.unlink(missing_ok=True)
        step("Standalone pack export", [godot] + HEADLESS + ["--path", test_dir,
                                                           "--export-pack", "macOS", pack],
             verify=lambda log: pack.exists() and pack.stat().st_size >= 100)
        if results[-1]["Success"]:
            # The macOS exporter removes temporary files named after the pack.
            # Install the runner after export so bin/tests survives cleanup.
            runner = test_dir / "bin/tests"
            copy(Path(godot), runner)
            # The locally generated runner must not inherit the downloaded
            # application's quarantine flag, which makes Gatekeeper kill it.
            attributes = subprocess.check_output(["xattr", str(runner)], text=True).splitlines()
            if "com.apple.quarantine" in attributes:
                run(["xattr", "-d", "com.apple.quarantine", runner], env)
            # Sign the local binary copied out of Godot.app; shell launchers
            # need no signing.
            with runner.open("rb") as binary:
                is_script = binary.read(2) == b"#!"
            if not is_script:
                run(["codesign", "--force", "--sign", "-", runner], env)
            step("Standalone pack tests", [runner] + HEADLESS + ["--main-pack", pack,
                                                              "--quit-after", "600", "--", "--autorun"],
                 cwd=test_dir / "bin", verify=markers("runtime"))
    if not args.skip_smoke_tests:
        for project in [ROOT / "template"] + [p for p in projects() if p.parent.name == "examples"]:
            step("Smoke " + project.name, [godot] + HEADLESS + ["--path", project, "--quit-after", "10"],
                 cwd=project)

    success = all(result["Success"] for result in results)
    summary = {}
    summary_file = test_dir / "bin/.runtime_test_results.txt"
    if summary_file.exists() and not args.skip_runtime_tests:
        summary = {name.lower(): int(value) for name, value in
                   re.findall(r"^(TOTAL|PASSED|FAILED)=(\d+)$", summary_file.read_text(), re.MULTILINE)}
    failed = [result["Name"] for result in results if not result["Success"]]
    report = dict(platform="macOS " + platform.machine(), overall_success=success,
                  duration_seconds=round(time.monotonic() - started, 2),
                  failed_steps_count=len(failed), failed_steps=failed, runtime_summary=summary,
                  steps=results, timestamp=datetime.now(timezone.utc).isoformat())
    rows = "".join(f"<tr><td>{r['Name']}</td><td>{'PASS' if r['Success'] else 'FAIL'}</td>"
                   f"<td>{r['Duration']}s</td></tr>\n" for r in results)
    markdown = (
        f"LibGodot macOS tests: {'PASS' if success else 'FAIL'}\n\n"
        "<table><thead><tr><th>Test</th><th>Status</th><th>Duration</th></tr></thead>\n"
        f"<tbody>\n{rows}</tbody></table>\n")
    for directory in (test_dir, test_dir / "bin"):
        (directory / "test_report.json").write_text(json.dumps(report, indent=2) + "\n")
        (directory / "test_report.md").write_text(markdown)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as output:
            output.write(markdown)
    print(f"macOS tests: {'PASS' if success else 'FAIL'} ({len(results)} steps)", flush=True)
    return 0 if success else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("build", "test"))
    for name in ("specs", "tool-tests", "editor-tests", "runtime-tests", "standalone-tests", "smoke-tests"):
        parser.add_argument("--skip-" + name, action="store_true")
    parser.add_argument("--timeout-seconds", type=int, default=180)
    args = parser.parse_args()
    try:
        if args.action == "build":
            build()
            return 0
        return test(args)
    except (RuntimeError, subprocess.CalledProcessError, OSError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
