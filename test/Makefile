# =============================================================================
# Crystal LibGodot Test Suite Makefile
# =============================================================================

# Platform and OS detection
ifeq ($(OS),Windows_NT)
	PLATFORM        = windows
	SO_EXT          = dll
	EXE_EXT         = .exe
	GODOT           ?= ../godot.exe
	PWSH_CMD        ?= powershell -NoProfile -ExecutionPolicy Bypass -Command
	PWSH_FILE       ?= powershell -NoProfile -ExecutionPolicy Bypass -File
	LINK_FLAGS      ?= /DLL /ENTRY:_DllMainCRTStartup /EXPORT:crystal_godot_init
else
	UNAME_S := $(shell uname -s 2>/dev/null)
	ifeq ($(UNAME_S),Darwin)
		PLATFORM        = macos
		SO_EXT          = dylib
		EXE_EXT         =
		GODOT           ?= ../godot
		PWSH_CMD        ?= pwsh -NoProfile -Command
		PWSH_FILE       ?= pwsh -NoProfile -File
		LINK_FLAGS      ?= -dynamiclib
	else
		PLATFORM        = linux
		SO_EXT          = so
		EXE_EXT         =
		GODOT           ?= ../godot
		PWSH_CMD        ?= pwsh -NoProfile -Command
		PWSH_FILE       ?= pwsh -NoProfile -File
		LINK_FLAGS      ?= -shared
	endif
endif

ENTRY        ?= src/main.cr

BIN_DIR       = bin
GAME_LIB      = $(BIN_DIR)/game.$(SO_EXT)
TESTS_EXE     = $(BIN_DIR)/tests$(EXE_EXT)
BRIDGE_SRC    = ../bin/crystal_bridge.$(SO_EXT)

# Backward-compatibility alias
GAME_DLL      = $(GAME_LIB)
GAME_EXE      = $(TESTS_EXE)

CP           = $(PWSH_CMD) "Copy-Item -Force"
RM           = $(PWSH_CMD) "Remove-Item -Force -ErrorAction SilentlyContinue"

CRYSTAL_FLAGS =
ifeq ($(RELEASE), 1)
	CRYSTAL_FLAGS += --release
endif

.PHONY: all game_dll game-dll game_exe game-exe package_game package-game package_tests package-tests standalone spec deps bridge extension_list addons bindings project_bindings project-bindings rebuild export export_release export-release run editor run_editor run-editor run_test run-test clean help

all: dirs deps bridge extension_list addons game_dll
	@echo ===================================================================
	@echo   Test Suite game library built successfully!
	@echo ===================================================================

bindings project_bindings project-bindings:
	@echo [API] Updating test project node bindings...
	@$(PWSH_CMD) "if (Test-Path 'src/generated/project_nodes') { Get-ChildItem 'src/generated/project_nodes' -Recurse | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue }"
	$(GODOT) --headless -s ../tools/api_generator/dump_project_nodes.gd -- --output src/generated/project_nodes.json
	crystal run ../tools/api_generator/generate_project_bindings.cr -- src/generated/project_nodes.json src/generated/project_nodes

dirs:
	@$(PWSH_CMD) "if (-not (Test-Path '$(BIN_DIR)')) { New-Item -ItemType Directory -Force -Path '$(BIN_DIR)' | Out-Null }"

deps: dirs
	@$(PWSH_FILE) ../scripts/ensure_deps.ps1

bridge: dirs
	@$(PWSH_CMD) "if (Test-Path '$(BRIDGE_SRC)') { Copy-Item '$(BRIDGE_SRC)' '$(BIN_DIR)/crystal_bridge.$(SO_EXT)' -Force -ErrorAction SilentlyContinue }"

extension_list: dirs
	@$(PWSH_FILE) ../scripts/ensure_extension_list.ps1 -ProjectPath .

addons:
	@$(PWSH_FILE) ../scripts/sync_addons.ps1 -Source ../addons -Destinations addons

game_dll game-dll: dirs deps bridge extension_list addons
	@echo [Test] Compiling game.$(SO_EXT) from $(ENTRY)...
	@$(PWSH_FILE) ../scripts/build_crystal.ps1 -Entry $(ENTRY) -Output $(GAME_LIB) -LinkFlags '$(LINK_FLAGS)' $(if $(filter 1,$(RELEASE)),-Release,) -SourcePath ../src
	@$(PWSH_CMD) "Copy-Item '$(GAME_LIB)' '../bin/game.$(SO_EXT)' -Force -ErrorAction SilentlyContinue"

spec:
	@echo [Spec] Running Crystal specifications in spec/...
	crystal spec

standalone game_exe game-exe: dirs deps bridge extension_list addons game_dll
	@echo [Test] Packaging standalone test runner executable...
	@$(PWSH_FILE) ../scripts/package_game.ps1 -ProjectPath . $(if $(NAME),-Name "$(NAME)",-Name tests) $(if $(filter 1,$(RELEASE)),-Release 1,) -ForceCompile

package_game package-game: dirs deps bridge extension_list addons game_dll
	@echo [Test] Packaging playable standalone test suite...
	@$(PWSH_FILE) ../scripts/package_game.ps1 -ProjectPath . $(if $(NAME),-Name "$(NAME)",-Name tests) $(if $(filter 1,$(RELEASE)),-Release 1,) $(if $(or $(TARGET_DIR),$(EXPORT_DIR)),-TargetDir "$(or $(TARGET_DIR),$(EXPORT_DIR))",) -ForceCompile

package_tests package-tests: standalone
	@echo [Test] Packaging standalone test runner archive...
	@$(PWSH_FILE) ../scripts/package_test_suite.ps1 $(if $(TARGET_DIR),-TargetDir "$(TARGET_DIR)",) $(if $(PLATFORM),-Platform "$(PLATFORM)",) $(if $(filter 1,$(RELEASE)),-Release 1,) $(if $(ZIP_NAME),-ZipName "$(ZIP_NAME)",) $(if $(filter 1,$(SKIP_VERIFY)),-SkipVerify,) $(if $(filter 1,$(FORCE)),-Force,)

run: all
	@echo [Test] Running test suite with Godot...
	$(GODOT) --path .

editor: all
	@echo [Test] Opening test suite in Godot Editor...
	$(GODOT) --editor --path .

run_editor run-editor: all
	@$(PWSH_FILE) ../scripts/run_editor.ps1 -Path . $(if $(or $(LOG),$(LOG_FILE)),-LogFile "$(or $(LOG),$(LOG_FILE))",) $(if $(or $(QUIT),$(QUIT_AFTER)),-QuitAfter $(or $(QUIT),$(QUIT_AFTER)),) $(if $(filter 1,$(LLDB)),-LLDB,) $(if $(filter 1,$(BATCH)),-Batch,) $(ARGS)

run_test run-test: all
ifeq ($(or $(filter 1,$(INTERACTIVE)),$(filter 1,$(UI))),1)
	@echo Launching Crystal LibGodot Interactive Test Runner...
	$(GODOT) --path . $(ARGS)
else
	@$(PWSH_FILE) ../scripts/run_tests.ps1 $(if $(filter 1,$(SKIP_SPECS)),-SkipSpecs,) $(if $(filter 1,$(SKIP_TOOL_TESTS)),-SkipToolTests,) $(if $(filter 1,$(SKIP_RUNTIME_TESTS)),-SkipRuntimeTests,) $(ARGS)
endif

clean:
	@$(RM) $(BIN_DIR)/*
	@$(PWSH_CMD) "Remove-Item -Path 'tests.exe', 'tests', 'game.exe', 'game', 'export', 'test_report.md', 'test_report.json', '.tool_tests_passed', '.tool_tests_failed', '.runtime_tests_passed', '.runtime_tests_failed', '.runtime_test_results.txt' -Recurse -Force -ErrorAction SilentlyContinue"

rebuild: clean all

export: all
	@echo [Test] Exporting test project to export/ directory...
	@$(PWSH_FILE) ../scripts/package_game.ps1 -ProjectPath . -Name tests -TargetDir $(or $(TARGET_DIR),export) -ForceCompile

export_release export-release: dirs deps bridge extension_list addons
	@echo [Test] Exporting optimized release test project to export/ directory...
	@$(PWSH_FILE) ../scripts/package_game.ps1 -ProjectPath . -Name tests -TargetDir $(or $(TARGET_DIR),export) -Release 1 -ForceCompile

help:
	@echo ===================================================================
	@echo   LibGodot Test Suite - Build and Export Commands
	@echo ===================================================================
	@echo   make                Build test project and dependencies
	@echo   make rebuild        Clean and rebuild all artifacts
	@echo   make game-dll       Compile test game shared library (game.$(SO_EXT))
	@echo   make standalone     Package standalone test executable runner
	@echo   make package-game   Package standalone test game [TARGET_DIR=...]
	@echo   make package-tests  Package standalone test runner archive (.zip)
	@echo   make export         Export standalone playable test suite to export/
	@echo   make export-release Export release optimized test suite to export/
	@echo   make run            Launch test suite with Godot
	@echo   make editor         Open test suite in Godot Editor
	@echo   make run-editor     Launch editor [LOG=...] [QUIT=...] [LLDB=1]
	@echo   make run-test       Run test suite [UI=1] [SKIP_SPECS=1]
	@echo   make clean          Remove all built artifacts and test reports
	@echo ===================================================================
