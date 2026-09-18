# =============================================================================
# LibGodot for Crystal - Root Makefile
# =============================================================================
#
# Builds the complete LibGodot Crystal toolchain, editor test suite, and examples:
#   - crystal_bridge.dll (GDExtension C++ loader bridge)
#   - game.dll (Crystal game library for Godot GDExtension host/editor)
#   - game.exe (Crystal standalone executable for LibGodot host paradigm)
#   - Syncs binaries & runtime DLLs to bin/, test/bin/, template/bin/, and examples/*/bin/
#
# Usage:
#   make               - Build everything (bridge, test, examples, template, sync & verify)
#   make bridge        - Build bin/crystal_bridge.dll from C++ source
#   make test_project  - Build test/bin/game.dll test suite project
#   make examples      - Build all example projects in examples/
#   make template      - Build template project
#   make game_dll      - Build and sync game.dll across all targets
#   make deps          - Copy Crystal runtime DLLs (gc, iconv, pcre2)
#   make sync          - Sync compiled binaries from bin/ to all consumer projects
#   make engine        - Recompile Godot engine shared library (libgodot.dll) via SCons
#   make test          - Run Crystal specs and Godot headless smoke tests
#   make docs          - Generate HTML API documentation
#   make run           - Run editor test project with godot.exe
#   make editor        - Open editor test project in Godot editor
#   make clean         - Clean built artifacts (retains libgodot.dll)
#   make help          - Display this help message
# =============================================================================

# Tool configuration
CRYSTAL      ?= crystal
CXX          ?= g++
SCONS        ?= scons
GODOT        ?= ./godot.exe
ENTRY        ?= test/src/main.cr
SCONS_JOBS   ?= 7

# Platform and OS detection
ifeq ($(OS),Windows_NT)
	PLATFORM        = windows
	SO_EXT          = dll
	EXE_EXT         = .exe
	GODOT           ?= ./godot.exe
	PWSH_CMD        ?= powershell -NoProfile -ExecutionPolicy Bypass -Command
	PWSH_FILE       ?= powershell -NoProfile -File
	CXXFLAGS        ?= -std=c++17 -O2 -g -I rsrc -static -static-libgcc -static-libstdc++
	LINK_FLAGS      ?= /DLL /ENTRY:_DllMainCRTStartup /EXPORT:crystal_godot_init
else
	UNAME_S := $(shell uname -s 2>/dev/null)
	ifeq ($(UNAME_S),Darwin)
		PLATFORM        = macos
		SO_EXT          = dylib
		EXE_EXT         =
		GODOT           ?= ./godot
		PWSH_CMD        ?= pwsh -NoProfile -Command
		PWSH_FILE       ?= pwsh -NoProfile -File
		CXX             ?= clang++
		CXXFLAGS        ?= -std=c++17 -O2 -fPIC -I rsrc
		LINK_FLAGS      ?= -dynamiclib -Wl,-exported_symbol,_crystal_godot_init
	else
		PLATFORM        = linux
		SO_EXT          = so
		EXE_EXT         =
		GODOT           ?= ./godot
		PWSH_CMD        ?= pwsh -NoProfile -Command
		PWSH_FILE       ?= pwsh -NoProfile -File
		CXX             ?= g++
		CXXFLAGS        ?= -std=c++17 -O2 -fPIC -I rsrc
		LINK_FLAGS      ?= -shared
	endif
endif

CP           = $(PWSH_CMD) "Copy-Item -Force"
RM           = $(PWSH_CMD) "Remove-Item -Force -ErrorAction SilentlyContinue"

# Optional release mode: make RELEASE=1
CRYSTAL_FLAGS =
ifeq ($(RELEASE), 1)
	CRYSTAL_FLAGS += --release
	CXXFLAGS      += -DLIBGODOT_RELEASE=1 -DNDEBUG
	export RELEASE
endif

# Output artifacts
BIN_DIR          = bin
TEST_BIN_DIR     = test/bin
TEMPLATE_BIN_DIR = template/bin
EXAMPLES_DIR     = examples
BRIDGE_LIB       = $(BIN_DIR)/crystal_bridge.$(SO_EXT)
PLUGIN_LIB       = $(BIN_DIR)/plugin.$(SO_EXT)
PLUGIN_ENTRY     ?= src/editor/plugin.cr
GAME_LIB         = $(BIN_DIR)/game.$(SO_EXT)
GAME_EXE         = $(BIN_DIR)/game$(EXE_EXT)
LIBGODOT_LIB     = $(BIN_DIR)/libgodot.$(SO_EXT)

# Aliases for backwards compatibility
BRIDGE_DLL       = $(BRIDGE_LIB)
PLUGIN_DLL       = $(PLUGIN_LIB)
GAME_DLL         = $(GAME_LIB)
LIBGODOT_DLL     = $(LIBGODOT_LIB)

.PHONY: all bridge plugin test_project test_standalone package_tests package-tests package_template package-template package_template_addon package-template-addon package_examples package-examples package_addon package-addon package_all package-all package_release package-release package_perf package-perf package_game package-game new_addon new-addon new_example new-example setup_dev setup-dev run_editor run-editor run_test run-test run_ci_local run-ci-local ci-local ci export_templates export-templates recompile_addons recompile-addons verify_editor verify-editor test_wsl test-wsl report_android report-android examples examples_exe template template_addon perf perf_standalone perf_run perf_editor game_dll game_exe android package_android generate dump_api project_bindings deps addons sync engine spec test tests docs run editor clean help

# Default target: compile bridge, plugin, test project, standalone runner, examples, template, template_addon, perf, sync DLLs, and run test suite
all: dirs deps bridge plugin addons dummy_addons test_project test_standalone examples template template_addon perf perf_standalone sync test
	@echo ===================================================================
	@echo   LibGodot Crystal library build completed successfully!
	@echo   Run 'make run' to launch test runner or 'make editor' for editor.
	@echo ===================================================================

# Ensure output directories exist
dirs:
	@$(PWSH_FILE) scripts/ensure_dirs.ps1

# Compile C++ GDExtension bridge and sync to consumer projects
bridge: dirs
	@echo [Bridge] Compiling GDExtension bridge $(BRIDGE_LIB)...
ifeq ($(PLATFORM),macos)
	$(CXX) -dynamiclib $(CXXFLAGS) src/bridge/crystal_bridge.cpp -o $(BRIDGE_LIB)
else
	$(CXX) -shared $(CXXFLAGS) src/bridge/crystal_bridge.cpp -o $(BRIDGE_LIB)
endif
	@$(PWSH_FILE) scripts/sync_bins.ps1

# Compile Crystal editor integration plugin library (plugin.dll)
plugin: dirs deps bridge
	@echo [Plugin] Compiling Crystal editor integration plugin $(PLUGIN_LIB)...
	@$(PWSH_FILE) scripts/build_crystal.ps1 -Entry $(PLUGIN_ENTRY) -Output $(PLUGIN_LIB) -LinkFlags "$(LINK_FLAGS)" $(if $(filter 1,$(RELEASE)),-Release,) -Flags "-Dlibgodot_addon"
	@$(PWSH_FILE) scripts/sync_bins.ps1

# Synchronize addons across root, test, template, and examples
addons: dirs
	@$(PWSH_FILE) scripts/sync_addons.ps1

# Build dummy test addons for multi-addon isolation stress tests
dummy_addons: dirs deps bridge
	@$(PWSH_FILE) scripts/build_dummy_addons.ps1 $(if $(filter 1,$(RELEASE)),-Release,)
	@$(PWSH_FILE) scripts/sync_bins.ps1

# Build test project
test_project: dirs deps bridge addons dummy_addons
	@echo [Test] Building test suite project...
	$(MAKE) -C test RELEASE=$(RELEASE)

# Build standalone test project executable
test_standalone: dirs deps bridge addons dummy_addons
	@echo [Test] Building standalone test suite executable...
	$(MAKE) -C test standalone RELEASE=$(RELEASE)

# Build all showcase examples in examples/
examples: dirs deps bridge addons
	@echo [Examples] Building all projects in $(EXAMPLES_DIR)...
	@$(PWSH_FILE) scripts/build_examples.ps1 $(if $(filter 1,$(RELEASE)),-Release 1,)

# Build standalone executables for all projects in examples/
examples_exe: dirs deps bridge addons
	@echo [Examples] Building standalone executables for all projects in $(EXAMPLES_DIR)...
	@$(PWSH_FILE) scripts/build_examples.ps1 -Exe $(if $(filter 1,$(RELEASE)),-Release 1,)

# Build starter game template project
template: dirs deps bridge addons
	@echo [Template] Building template project...
	$(MAKE) -C template RELEASE=$(RELEASE)

# Build addon starter template project
template_addon: dirs deps bridge addons
	@echo [TemplateAddon] Building template-addon project...
	$(MAKE) -C template-addon RELEASE=$(RELEASE)

# Dedicated performance stress testing project
perf: dirs deps bridge addons
	@echo [Performance] Building performance stress benchmark...
	$(MAKE) -C performance RELEASE=$(RELEASE)

# Build standalone performance suite executable
perf_standalone: dirs deps bridge addons
	@echo [Performance] Building standalone performance benchmark executable...
	$(MAKE) -C performance standalone RELEASE=$(RELEASE)

# Package standalone test suite into tests-<platform>.zip
package_tests package-tests: test_standalone
	@echo [Package] Packaging standalone test suite...
	@$(PWSH_FILE) scripts/package_test_suite.ps1 $(if $(TARGET_DIR),-TargetDir "$(TARGET_DIR)",) $(if $(PLATFORM),-Platform "$(PLATFORM)",) $(if $(filter 1,$(RELEASE)),-Release 1,) $(if $(ZIP_NAME),-ZipName "$(ZIP_NAME)",) $(if $(filter 1,$(SKIP_VERIFY)),-SkipVerify,) $(if $(filter 1,$(FORCE)),-Force,)

# Package standalone performance benchmark into perf-<platform>.zip
package_perf package-perf: perf_standalone
	@echo [Package] Packaging standalone performance benchmark...
	@$(PWSH_FILE) scripts/package_perf.ps1 $(if $(TARGET_DIR),-TargetDir "$(TARGET_DIR)",) $(if $(PLATFORM),-Platform "$(PLATFORM)",) $(if $(or $(ARCHIVE_NAME),$(ZIP_NAME)),-ArchiveName "$(or $(ARCHIVE_NAME),$(ZIP_NAME))",) $(if $(filter 1,$(RELEASE)),-Release 1,) $(if $(filter 1,$(SKIP_VERIFY)),-SkipVerify,) $(if $(filter 1,$(FORCE)),-Force,)

# Package starter template project into template-project.zip
package_template package-template: template
	@echo [Package] Packaging starter template project...
	@$(PWSH_FILE) scripts/package_template.ps1 $(if $(TARGET_DIR),-TargetDir "$(TARGET_DIR)",) $(if $(ZIP_NAME),-ZipName "$(ZIP_NAME)",) $(if $(filter 1,$(RELEASE)),-Release 1,) $(if $(or $(filter 1,$(BUNDLE)),$(filter 1,$(BUNDLE_BINARIES))),-BundleBinaries,) $(if $(filter 1,$(FORCE)),-Force,)

# Package addon starter template into template-addon-project.zip
package_template_addon package-template-addon: template_addon
	@echo [Package] Packaging addon starter template...
	@$(PWSH_FILE) scripts/package_template_addon.ps1 $(if $(TARGET_DIR),-TargetDir "$(TARGET_DIR)",) $(if $(ZIP_NAME),-ZipName "$(ZIP_NAME)",) $(if $(filter 1,$(RELEASE)),-Release 1,) $(if $(or $(filter 1,$(BUNDLE)),$(filter 1,$(BUNDLE_BINARIES))),-BundleBinaries,) $(if $(filter 1,$(FORCE)),-Force,)

# Package standalone examples (with source + installed scripts + binaries) into examples-<platform>.zip
package_examples package-examples: examples
	@echo [Package] Packaging standalone examples...
	@$(PWSH_FILE) scripts/package_examples.ps1 $(if $(TARGET_DIR),-TargetDir "$(TARGET_DIR)",) $(if $(PLATFORM),-Platform "$(PLATFORM)",) $(if $(ZIP_NAME),-ZipName "$(ZIP_NAME)",) $(if $(RELEASE),-Release "$(RELEASE)",$(if $(filter 1,$(RELEASE)),-Release 1,)) $(if $(filter 1,$(FORCE)),-Force,)

# Package official crystal_integration addon into godot-crystal-addon.zip
package_addon package-addon: plugin bridge
	@echo [Package] Packaging official Crystal integration addon...
	@$(PWSH_FILE) scripts/package_addon.ps1 $(if $(TARGET_DIR),-TargetDir "$(TARGET_DIR)",) $(if $(ZIP_NAME),-ZipName "$(ZIP_NAME)",) $(if $(filter 1,$(FORCE)),-Force,)

# Package all release archives and checksums into bin/release_dist/
package_all package-all package_release package-release:
	@echo [Package] Packaging all release archives into $(or $(OUTPUT_DIR),$(TARGET_DIR),bin/release_dist)...
	@$(PWSH_FILE) scripts/package_release.ps1 -OutputDir "$(or $(OUTPUT_DIR),$(TARGET_DIR),bin/release_dist)" $(if $(PLATFORM),-Platform "$(PLATFORM)",) -Release "$(or $(RELEASE),1)" $(if $(filter 1,$(SKIP_TESTS)),-SkipTests,) $(if $(filter 1,$(SKIP_PERF)),-SkipPerf,)

# Package playable standalone Godot game (binary + PCK + runtime DLLs)
package_game package-game:
	@echo [Package] Packaging playable standalone Godot game...
	@$(PWSH_FILE) scripts/package_game.ps1 -ProjectPath "$(or $(PROJECT),$(PATH),.)" $(if $(NAME),-Name "$(NAME)",) $(if $(filter 1,$(RELEASE)),-Release 1,) $(if $(or $(TARGET_DIR),$(EXPORT_DIR)),-TargetDir "$(or $(TARGET_DIR),$(EXPORT_DIR))",) $(if $(filter 1,$(FORCE)),-ForceCompile,)

# Scaffold a new compiled Crystal GDExtension addon project
new_addon new-addon:
ifeq ($(strip $(NAME)),)
	@echo Error: 'NAME' parameter is required.
	@echo Usage: make new-addon NAME=my_addon [DIR=path/to/addon] [AUTHOR="Author"] [DESC="Description"]
	@exit 1
else
	@echo [Scaffold] Scaffolding new Crystal GDExtension Addon '$(NAME)'...
	@$(PWSH_FILE) scripts/create_new_addon.ps1 -Name $(NAME) $(if $(or $(DIR),$(TARGET),$(TARGET_PATH)),-TargetPath "$(or $(DIR),$(TARGET),$(TARGET_PATH))",) $(if $(AUTHOR),-Author "$(AUTHOR)",) $(if $(or $(DESC),$(DESCRIPTION)),-Description "$(or $(DESC),$(DESCRIPTION))",)
endif

# Scaffold a new LibGodot showcase example project
new_example new-example:
ifeq ($(strip $(NAME)),)
	@echo Error: 'NAME' parameter is required.
	@echo Usage: make new-example NAME=my_example [DIR=path/to/example]
	@exit 1
else
	@echo [Scaffold] Scaffolding new LibGodot Example '$(NAME)'...
	@$(PWSH_FILE) scripts/create_new_example.ps1 -Name $(NAME) $(if $(or $(DIR),$(TARGET),$(TARGET_PATH)),-TargetPath "$(or $(DIR),$(TARGET),$(TARGET_PATH))",)
endif

perf_run: perf
	@echo [Performance] Launching performance stress benchmark...
	$(MAKE) -C performance run ARGS="$(ARGS)"

perf_editor: perf
	@echo [Performance] Opening performance project in Godot Editor...
	$(MAKE) -C performance editor

# Compile game_dll for all consumers and synchronize
game_dll: dirs deps bridge addons test_project examples template template_addon perf sync
	@echo [Build] All game library targets compiled and synced!

game_exe: dirs deps bridge
	@echo [Standalone] Compiling standalone game executable from $(ENTRY)...
	@$(PWSH_FILE) scripts/build_crystal.ps1 -Entry $(ENTRY) -Output $(GAME_EXE) $(if $(filter 1,$(RELEASE)),-Release,)

# Cross-compile for Android (libcrystal_bridge.so and libgame.so)
android: dirs
	@echo [Android] Cross-compiling LibGodot for Android arm64-v8a...
	@$(PWSH_FILE) scripts/build_android.ps1 -Release "$(RELEASE)" $(if $(ENTRY),-Entry $(ENTRY),)

# Package Android APK
package_android: dirs bridge android
	@echo [Android] Packaging Android APK...
	@$(PWSH_FILE) scripts/package_android.ps1 $(if $(filter 1,$(RELEASE)),-Release,) $(if $(ENTRY),-Entry $(ENTRY),)

# Create or inspect Android keystores
keystore: dirs
	@$(PWSH_FILE) scripts/manage_keystore.ps1

keystore_decode: dirs
	@$(PWSH_FILE) scripts/manage_keystore.ps1 -Decode $(if $(KEYSTORE),-Path $(KEYSTORE),)


# Generate Crystal bindings from Godot extension_api.json
dump_api:
	@echo [API] Dumping extension_api.json from Godot...
	@$(PWSH_CMD) "New-Item -ItemType Directory -Force scratch/dump_tmp | Out-Null; Set-Content scratch/dump_tmp/project.godot 'config_version=5'; Start-Process -FilePath (Resolve-Path ./godot.exe) -ArgumentList '--headless', '--path', (Resolve-Path scratch/dump_tmp), '--dump-extension-api' -WorkingDirectory (Resolve-Path scratch/dump_tmp) -Wait; Start-Process -FilePath (Resolve-Path ./godot.exe) -ArgumentList '--headless', '--path', (Resolve-Path scratch/dump_tmp), '--dump-gdextension-interface' -WorkingDirectory (Resolve-Path scratch/dump_tmp) -Wait; Copy-Item scratch/dump_tmp/extension_api.json extension_api.json -Force; Copy-Item scratch/dump_tmp/extension_api.json rsrc/extension_api.json -Force; Copy-Item scratch/dump_tmp/gdextension_interface.h rsrc/gdextension_interface.h -Force; Remove-Item scratch/dump_tmp -Recurse -Force"

generate:
	@echo [Generator] Generating complete Godot bindings from extension_api.json...
	$(CRYSTAL) run tools/api_generator/generate_bindings.cr

# Generate typed Crystal bindings for project custom GDScript and plugin nodes
project_bindings:
	@echo [API] Dumping and generating typed bindings for project custom GDScript and plugin nodes...
	@$(PWSH_FILE) scripts/generate_project_bindings.ps1 -Project $(or $(PROJECT),template)

# Copy Crystal runtime dependencies and libgodot to all bin dirs
deps: dirs
	@echo [Dependencies] Ensuring runtime libraries are available in bin/, test/bin/, and template/bin/...
	@$(PWSH_FILE) scripts/ensure_deps.ps1

# Synchronize compiled binaries and runtime dependencies to consumer projects
sync: addons
	@echo [Sync] Syncing runtime libraries and bridge to test/bin, template/bin, and examples...
	@$(PWSH_FILE) scripts/sync_bins.ps1

# Build Godot engine shared library from source (requires godot-src and scons)
engine:
	@echo Compiling Godot Engine shared library $(LIBGODOT_LIB) via SCons...
	$(SCONS) -C godot-src target=template_debug dev_build=yes library_type=shared_library -j$(SCONS_JOBS)
	@$(PWSH_FILE) scripts/sync_bins.ps1
	@echo $(LIBGODOT_LIB) updated successfully!

# Run Crystal unit specifications (test/spec)
spec:
	@echo [Spec] Running Crystal specifications in test/spec...
	$(CRYSTAL) spec test/spec

# Run complete test suites and verification (Crystal specs, in-editor @tool tests, standalone runner, runtime project tests, smoke tests)
test tests: test_standalone
	@$(PWSH_FILE) scripts/run_tests.ps1 $(if $(filter 1,$(SKIP_SPECS)),-SkipSpecs,) $(if $(filter 1,$(SKIP_TOOL_TESTS)),-SkipToolTests,) $(if $(filter 1,$(SKIP_RUNTIME_TESTS)),-SkipRuntimeTests,) $(ARGS)

# Unified test runner (supports interactive UI or automated suite)
run_test run-test:
ifeq ($(or $(filter 1,$(INTERACTIVE)),$(filter 1,$(UI))),1)
	@echo Launching Crystal LibGodot Interactive Test Runner...
	$(GODOT) --path test $(ARGS)
else
	@$(PWSH_FILE) scripts/run_tests.ps1 $(if $(filter 1,$(SKIP_SPECS)),-SkipSpecs,) $(if $(filter 1,$(SKIP_TOOL_TESTS)),-SkipToolTests,) $(if $(filter 1,$(SKIP_RUNTIME_TESTS)),-SkipRuntimeTests,) $(ARGS)
endif

# Run complete local CI test matrix harness
run_ci_local run-ci-local ci-local ci:
	@$(PWSH_FILE) scripts/run_ci_local.ps1 $(if $(or $(filter 1,$(RELEASE)),$(filter 1,$(TEST_RELEASE))),-TestRelease,) $(if $(filter 1,$(SKIP_SPECS)),-SkipSpecs,) $(if $(filter 1,$(SKIP_TOOL_TESTS)),-SkipToolTests,) $(if $(filter 1,$(SKIP_RUNTIME_TESTS)),-SkipRuntimeTests,) $(if $(filter 1,$(SKIP_SMOKE_TESTS)),-SkipSmokeTests,)

# Download and configure Godot engine binary for development
setup_dev setup-dev:
	@$(PWSH_FILE) scripts/setup_dev.ps1 $(if $(VERSION),-Version "$(VERSION)",)

# Generate offline HTML documentation
docs:
	@echo Generating Crystal HTML documentation in docs/...
	$(CRYSTAL) docs
	@$(PWSH_FILE) scripts/patch_docs.ps1
	@echo Documentation generated at docs/index.html

# Launch test project using Godot
run:
	@echo Launching Crystal LibGodot Test Runner...
	$(GODOT) --path test

# Launch Godot editor for test project
editor:
	@echo Opening Godot Editor for Test Project...
	$(GODOT) --editor --path test

# Unified Godot editor launcher with shadow logging, auto-quit, and LLDB flags
run_editor run-editor:
	@$(PWSH_FILE) scripts/run_editor.ps1 -Path "$(or $(PROJECT),$(PATH),test)" $(if $(or $(LOG),$(LOG_FILE)),-LogFile "$(or $(LOG),$(LOG_FILE))",) $(if $(or $(QUIT),$(QUIT_AFTER)),-QuitAfter $(or $(QUIT),$(QUIT_AFTER)),) $(if $(filter 1,$(LLDB)),-LLDB,) $(if $(filter 1,$(BATCH)),-Batch,) $(ARGS)

# Ensure Godot export templates are downloaded/installed
export_templates export-templates:
	@$(PWSH_FILE) scripts/ensure_export_templates.ps1 $(if $(VERSION),-Version "$(VERSION)",) $(if $(DOWNLOAD_URL),-DownloadUrl "$(DOWNLOAD_URL)",)

# Recompile all Crystal addons found across a project
recompile_addons recompile-addons:
	@$(PWSH_FILE) scripts/recompile_addons.ps1 -ProjectPath "$(or $(PROJECT),$(PATH),.)" $(if $(filter 1,$(RELEASE)),-Release,) $(if $(filter 1,$(FORCE)),-Force,)

# Verify Godot editor launch, script loader, and clean shutdown
verify_editor verify-editor:
	@$(PWSH_FILE) scripts/verify_editor.ps1 -Path "$(or $(PROJECT),$(PATH),template)" $(if $(or $(QUIT),$(QUIT_AFTER)),-QuitAfter $(or $(QUIT),$(QUIT_AFTER)),) $(if $(RELOAD_CYCLES),-ReloadCycles $(RELOAD_CYCLES),) $(if $(filter 1,$(PURGE_CACHE)),-PurgeCache,) $(if $(filter 1,$(HEADLESS)),-Headless,)

# Run Linux test suite inside WSL with crash backtrace capture
test_wsl test-wsl:
	@$(PWSH_FILE) scripts/run_wsl_tests.ps1 $(if $(DISTRO),-Distro "$(DISTRO)",) $(if $(filter 1,$(SKIP_SPECS)),-SkipSpecs,) $(if $(filter 1,$(SKIP_RUNTIME_TESTS)),-SkipRuntimeTests,) $(if $(filter 1,$(SKIP_TOOL_TESTS)),-SkipToolTests,) $(if $(filter 1,$(LLDB)),-DebugWithLLDB,)

# Audit Android libraries and generated APK packages
report_android report-android:
	@$(PWSH_FILE) scripts/report_android.ps1 $(if $(ANDROID_BIN_DIR),-AndroidBinDir "$(ANDROID_BIN_DIR)",)

# Run project under LLDB debugger
debug:
	@echo Launching under LLDB debugger...
	@$(PWSH_FILE) scripts/lldb_run.ps1 -Path $(or $(PROJECT),test) $(if $(BATCH),-Batch,) $(if $(QUIT),-Quit,)

# Launch Godot editor under LLDB debugger
debug-editor:
	@echo Opening Godot Editor under LLDB debugger...
	@$(PWSH_FILE) scripts/lldb_run.ps1 -Path $(or $(PROJECT),test) -Editor $(if $(BATCH),-Batch,)

# Clean build artifacts (preserves libgodot.dll and runtime DLLs)
clean:
	@echo Cleaning build artifacts across bin/, test/bin/, template/bin/, addons/crystal_integration/bin, template-addon, performance, and examples...
	@$(PWSH_CMD) "Get-ChildItem -Path '$(BIN_DIR)', '$(TEST_BIN_DIR)', '$(TEMPLATE_BIN_DIR)', 'addons/crystal_integration/bin', 'template-addon/addons', 'performance/bin' -Include 'crystal_bridge.*', 'game.*', '~crystal_bridge.*' -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue"
	@$(PWSH_CMD) "if (Test-Path '$(EXAMPLES_DIR)') { Get-ChildItem -Path '$(EXAMPLES_DIR)' -Include 'crystal_bridge.*', 'game.*', '~crystal_bridge.*' -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue }"
	@$(PWSH_CMD) "Remove-Item -Path 'test/tests.exe', 'test/tests', 'performance/perf.exe', 'performance/perf' -Force -ErrorAction SilentlyContinue"
	@$(PWSH_CMD) "Get-ChildItem -Path 'scratch' -Include '*.obj', '*.exp' -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue"
	@echo Clean complete.

# Display help menu
help:
	@echo =========================================================================================
	@echo   LibGodot for Crystal - Root Build and Command Reference
	@echo =========================================================================================
	@echo   CORE BUILD TARGETS:
	@echo     make                        Build bridge, test project, examples, template, sync, verify
	@echo     make bridge                 Compile C++ GDExtension bridge (bin/crystal_bridge.dll)
	@echo     make plugin                 Compile Crystal editor plugin library (bin/plugin.dll)
	@echo     make test_project           Compile test suite library (test/bin/game.dll)
	@echo     make examples               Compile all showcase projects in examples/
	@echo     make template               Compile starter game template (template/bin/game.dll)
	@echo     make template_addon         Compile addon starter template (template-addon/)
	@echo     make perf                   Compile performance stress benchmark (performance/)
	@echo     make game_dll               Compile and synchronize game.dll across all targets
	@echo     make deps                   Verify and copy runtime DLLs (gc, iconv, pcre2, libgodot)
	@echo     make sync                   Synchronize binaries and addons across consumer projects
	@echo     make clean                  Remove compiled game and bridge binaries
	@echo.
	@echo   SCAFFOLDING TARGETS:
	@echo     make new-addon NAME=^<n^>      Scaffold new addon [DIR=...] [AUTHOR=...] [DESC=...]
	@echo     make new-example NAME=^<n^>    Scaffold new example project [DIR=...]
	@echo.
	@echo   PACKAGING TARGETS:
	@echo     make package-game           Package playable game [PROJECT=.] [RELEASE=1] [FORCE=1]
	@echo     make package-release        Package all release archives into bin/release_dist/
	@echo     make package-tests          Package standalone test runner into tests-^<platform^>.zip
	@echo     make package-template       Package starter template into template-project.zip
	@echo     make package-template-addon Package addon template into template-addon-project.zip
	@echo     make package-examples       Package examples into examples-^<platform^>.zip
	@echo     make package-addon          Package crystal_integration addon into zip
	@echo     make package-perf           Package performance benchmark into perf-^<platform^>.zip
	@echo.
	@echo   EXECUTION, TESTING AND DEBUGGING:
	@echo     make run                    Launch test suite in Godot
	@echo     make editor                 Open test suite in Godot Editor
	@echo     make run-editor             Launch editor [PROJECT=...] [LOG=...] [QUIT=...] [LLDB=1]
	@echo     make run-test               Run tests [UI=1] [SKIP_SPECS=1] [SKIP_RUNTIME_TESTS=1]
	@echo     make run-ci-local           Simulate local GitHub Actions CI matrix harness
	@echo     make test                   Run complete test suite and verification specs
	@echo     make spec                   Run headless Crystal unit specifications (test/spec)
	@echo     make debug                  Run test suite under LLDB debugger [PROJECT=...]
	@echo     make debug-editor           Open Godot Editor under LLDB debugger [PROJECT=...]
	@echo.
	@echo   ENGINE AND DEVELOPER TOOLS:
	@echo     make setup-dev              Download/setup Godot engine binary [VERSION=...]
	@echo     make export-templates       Ensure Godot export templates installed [VERSION=...]
	@echo     make recompile-addons       Recompile all Crystal addons in project [PROJECT=...]
	@echo     make verify-editor          Verify editor launch, hot-reload, clean exit [PROJECT=...]
	@echo     make test-wsl               Run Linux test suite inside WSL (Ubuntu)
	@echo     make report-android         Audit Android binaries and APK artifacts
	@echo     make dump_api               Dump extension_api.json from Godot
	@echo     make generate               Generate typed Crystal bindings from extension_api.json
	@echo     make project_bindings       Generate typed bindings for project custom GDScript
	@echo     make docs                   Generate offline HTML API documentation in docs/
	@echo =========================================================================================
