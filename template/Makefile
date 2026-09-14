# =============================================================================
# Crystal Godot Template Makefile
# =============================================================================

# Platform and OS detection
ifeq ($(OS),Windows_NT)
	PLATFORM        = windows
	SO_EXT          = dll
	EXE_EXT         = .exe
	GODOT           ?= $(if $(wildcard ./godot.exe),./godot.exe,$(if $(wildcard ../godot.exe),../godot.exe,godot.exe))
	PWSH_CMD        ?= powershell -NoProfile -ExecutionPolicy Bypass -Command
	PWSH_FILE       ?= powershell -NoProfile -ExecutionPolicy Bypass -File
	LINK_FLAGS      ?= /DLL /ENTRY:_DllMainCRTStartup /EXPORT:crystal_godot_init
else
	UNAME_S := $(shell uname -s 2>/dev/null)
	ifeq ($(UNAME_S),Darwin)
		PLATFORM        = macos
		SO_EXT          = dylib
		EXE_EXT         =
		GODOT           ?= $(if $(wildcard ./godot),./godot,$(if $(wildcard ../godot),../godot,godot))
		PWSH_CMD        ?= pwsh -NoProfile -Command
		PWSH_FILE       ?= pwsh -NoProfile -File
		LINK_FLAGS      ?= -dynamiclib
	else
		PLATFORM        = linux
		SO_EXT          = so
		EXE_EXT         =
		GODOT           ?= $(if $(wildcard ./godot),./godot,$(if $(wildcard ../godot),../godot,godot))
		PWSH_CMD        ?= pwsh -NoProfile -Command
		PWSH_FILE       ?= pwsh -NoProfile -File
		LINK_FLAGS      ?= -shared
	endif
endif

ENTRY        ?= src/main.cr

BIN_DIR       = bin
GAME_LIB      = $(BIN_DIR)/game.$(SO_EXT)
GAME_EXE      = $(BIN_DIR)/game$(EXE_EXT)
BRIDGE_SRC    = ../bin/crystal_bridge.$(SO_EXT)
SCRIPTS_DIR   = $(if $(wildcard scripts),scripts,../scripts)
SOURCE_DIR    = $(if $(wildcard ../src),../src,$(if $(wildcard lib/libgodot/src),lib/libgodot/src,lib))

# Backward-compatibility alias
GAME_DLL      = $(GAME_LIB)

CP           = $(PWSH_CMD) "Copy-Item -Force"
RM           = $(PWSH_CMD) "Remove-Item -Force -ErrorAction SilentlyContinue"

CRYSTAL_FLAGS =
ifeq ($(RELEASE), 1)
	CRYSTAL_FLAGS += --release
endif

.PHONY: all game_dll game_exe deps bridge extension_list addons project_bindings bindings rebuild export export_release run editor clean help

all: dirs deps bridge extension_list addons project_bindings game_dll game_exe
	@echo ===================================================================
	@echo   Template game library and playable executable built successfully!
	@echo ===================================================================

dirs:
	@$(PWSH_CMD) "if (-not (Test-Path '$(BIN_DIR)')) { New-Item -ItemType Directory -Force -Path '$(BIN_DIR)' | Out-Null }"

deps: dirs
	@$(PWSH_FILE) $(SCRIPTS_DIR)/ensure_deps.ps1 -TargetBin '$(BIN_DIR)'

bridge: dirs
	@$(PWSH_CMD) "if (Test-Path '$(BRIDGE_SRC)') { Copy-Item '$(BRIDGE_SRC)' '$(BIN_DIR)/crystal_bridge.$(SO_EXT)' -Force -ErrorAction SilentlyContinue } elseif (Test-Path 'addons/crystal_integration/bin/crystal_bridge.$(SO_EXT)') { Copy-Item 'addons/crystal_integration/bin/crystal_bridge.$(SO_EXT)' '$(BIN_DIR)/crystal_bridge.$(SO_EXT)' -Force -ErrorAction SilentlyContinue } elseif (Test-Path 'lib/libgodot/bin/crystal_bridge.$(SO_EXT)') { Copy-Item 'lib/libgodot/bin/crystal_bridge.$(SO_EXT)' '$(BIN_DIR)/crystal_bridge.$(SO_EXT)' -Force -ErrorAction SilentlyContinue }"

extension_list:
	@$(PWSH_FILE) $(SCRIPTS_DIR)/ensure_extension_list.ps1 -ProjectPath .

addons:
	@$(PWSH_CMD) "if (Test-Path '../addons') { & $(PWSH_FILE) $(SCRIPTS_DIR)/sync_addons.ps1 -Source ../addons -Destinations addons }"

project_bindings: dirs
	@echo [Template] Dumping project custom GDScript and plugin nodes...
	@$(PWSH_FILE) $(SCRIPTS_DIR)/generate_project_bindings.ps1

bindings: project_bindings

game_dll: dirs deps bridge extension_list addons project_bindings
	@echo [Template] Compiling game.$(SO_EXT) from $(ENTRY)...
	@$(PWSH_FILE) $(SCRIPTS_DIR)/build_crystal.ps1 -Entry $(ENTRY) -Output $(GAME_LIB) -LinkFlags '$(LINK_FLAGS)' $(if $(filter 1,$(RELEASE)),-Release,) -SourcePath $(SOURCE_DIR)

game_exe: dirs deps bridge extension_list addons game_dll
	@echo [Template] Packaging complete playable game executable...
	@$(PWSH_FILE) $(SCRIPTS_DIR)/package_game.ps1 -ProjectPath . -Name game $(if $(filter 1,$(RELEASE)),-Release 1,)

run: all
	@echo [Template] Running project with Godot...
	$(GODOT) --path .

editor: all
	@echo [Template] Opening project in Godot Editor...
	$(GODOT) --editor --path .

clean:
	@$(RM) $(BIN_DIR)/*
	@$(PWSH_CMD) "Remove-Item -Path 'game.exe', 'game', 'export' -Recurse -Force -ErrorAction SilentlyContinue"

rebuild: clean all

export: all
	@echo [Template] Exporting project to export/ directory...
	@$(PWSH_FILE) $(SCRIPTS_DIR)/package_game.ps1 -ProjectPath . -Name game -TargetDir export -ForceCompile

export_release: dirs deps bridge extension_list addons project_bindings
	@echo [Template] Exporting optimized release project to export/ directory...
	@$(PWSH_FILE) $(SCRIPTS_DIR)/package_game.ps1 -ProjectPath . -Name game -TargetDir export -Release 1 -ForceCompile

help:
	@echo ===================================================================
	@echo   LibGodot Template - Build and Export Commands
	@echo ===================================================================
	@echo   make                Build game library, runnable executable, and sync
	@echo   make rebuild        Clean and rebuild all artifacts
	@echo   make game_dll       Compile game shared library (game.$(SO_EXT))
	@echo   make game_exe       Package playable game executable into bin/
	@echo   make project_bindings Generate typed Crystal wrappers for project GDScript nodes
	@echo   make export         Export standalone playable game package to export/
	@echo   make export_release Export release optimized game package to export/
	@echo   make run            Launch game in Godot
	@echo   make editor         Open project in Godot Editor
	@echo   make clean          Remove built binaries and export directories
	@echo ===================================================================
