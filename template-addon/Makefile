# =============================================================================
# Crystal Godot Addon Template Makefile
# =============================================================================

ADDON_NAME      ?= crystal_addon
ADDON_DIR       = addons/$(ADDON_NAME)
ADDON_BIN_DIR   = $(ADDON_DIR)/bin

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

ENTRY           ?= src/main.cr
GAME_LIB        = $(ADDON_BIN_DIR)/game.$(SO_EXT)
BRIDGE_SRC      = ../bin/crystal_bridge.$(SO_EXT)
SCRIPTS_DIR     = $(if $(wildcard scripts),scripts,../scripts)
SOURCE_DIR      = $(if $(wildcard ../src),../src,lib)

RM              = $(PWSH_CMD) "Remove-Item -Force -ErrorAction SilentlyContinue"

CRYSTAL_FLAGS   =
ifeq ($(RELEASE), 1)
	CRYSTAL_FLAGS += --release
endif

.PHONY: all build deps bridge extension_list addons project_bindings bindings package export export_release rebuild run editor clean help

all: dirs deps bridge extension_list addons project_bindings build
	@echo ===================================================================
	@echo   Crystal Godot Addon '$(ADDON_NAME)' built successfully!
	@echo   Run 'make editor' to test in editor or 'make package' to create zip.
	@echo ===================================================================

dirs:
	@$(PWSH_CMD) "if (-not (Test-Path '$(ADDON_BIN_DIR)')) { New-Item -ItemType Directory -Force -Path '$(ADDON_BIN_DIR)' | Out-Null }"

deps: dirs
	@$(PWSH_FILE) $(SCRIPTS_DIR)/ensure_deps.ps1 -TargetBin '$(ADDON_BIN_DIR)'

bridge: dirs
	@$(PWSH_CMD) "if (Test-Path '$(BRIDGE_SRC)') { Copy-Item '$(BRIDGE_SRC)' '$(ADDON_BIN_DIR)/crystal_bridge.$(SO_EXT)' -Force -ErrorAction SilentlyContinue }"

extension_list: dirs
	@$(PWSH_CMD) "if (-not (Test-Path '.godot')) { New-Item -ItemType Directory -Force -Path '.godot' | Out-Null }; Set-Content -Path '.godot/extension_list.cfg' -Value @('res://$(ADDON_DIR)/crystal_addon.gdextension', 'res://addons/crystal_integration/crystal.gdextension') -Force"

addons: dirs
	@$(PWSH_FILE) $(SCRIPTS_DIR)/sync_addons.ps1 -Source ../addons -Destinations addons

project_bindings: dirs
	@echo [Addon] Dumping project custom GDScript and plugin nodes...
	@$(PWSH_FILE) $(SCRIPTS_DIR)/generate_project_bindings.ps1

bindings: project_bindings

build: dirs deps bridge extension_list addons project_bindings
	@echo [Addon] Compiling $(GAME_LIB) from $(ENTRY)...
	@$(PWSH_FILE) $(SCRIPTS_DIR)/build_crystal.ps1 -Entry $(ENTRY) -Output $(GAME_LIB) -LinkFlags '$(LINK_FLAGS)' $(if $(filter 1,$(RELEASE)),-Release,) -SourcePath $(SOURCE_DIR) -Flags '-Dlibgodot_addon'

package: all
	@echo [Addon] Packaging distributable zip for '$(ADDON_NAME)'...
	@$(PWSH_FILE) $(SCRIPTS_DIR)/package.ps1 -AddonName $(ADDON_NAME)

export: package

export_release:
	@echo [Addon] Packaging release optimized distributable zip for '$(ADDON_NAME)'...
	@$(MAKE) package RELEASE=1

rebuild: clean all

editor: all
	@echo [Addon] Launching Godot Editor to test addon...
	$(GODOT) --editor --path .

run: all
	@echo [Addon] Running Godot project with addon...
	$(GODOT) --path .

clean:
	@$(RM) $(ADDON_BIN_DIR)/*
	@$(RM) dist/*

help:
	@echo ===================================================================
	@echo   LibGodot Addon Template - Build and Export Commands
	@echo ===================================================================
	@echo   make                Build addon library and sync dependencies
	@echo   make build          Compile addon Crystal library (game.$(SO_EXT))
	@echo   make project_bindings Generate typed Crystal wrappers for GDScript nodes
	@echo   make rebuild        Clean and rebuild all addon artifacts
	@echo   make package        Package redistributable zip archive into dist/
	@echo   make export         Alias for 'make package'
	@echo   make export_release Package release optimized zip into dist/
	@echo   make run            Run test project with addon in Godot
	@echo   make editor         Launch Godot Editor to test addon
	@echo   make clean          Remove compiled addon binaries and dist/
	@echo ===================================================================
