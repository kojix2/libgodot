---
name: libgodot-scaffold
description: >-
  Scaffold new showcase examples and redistributable Godot addons using LibGodot.
  Use when creating a new demo project, example game, or packaging an addon.
---

# LibGodot Project Scaffolding Runbook

This skill outlines how to create new showcase examples and redistributable GDExtension addons without violating project separation rules.

---

## 1. Scaffolding a New Showcase Example

To create a new showcase project under `examples/<name>`:
```bash
make new-example NAME=<example_name>
# Or specify a custom target directory:
make new-example NAME=<example_name> DIR=path/to/example
```
*(Equivalent PowerShell command: `.\scripts\create_new_example.ps1 -Name <example_name> [-TargetPath <path>]`)*

### What this command creates:
1. `examples/<example_name>/` (or custom `DIR`):
   - `project.godot`: Godot project configured with Crystal extension addon.
   - `shard.yml`: Crystal shard dependency pointing to root `../../src`.
   - `src/main.cr`: Entry point defining example nodes.
   - `Makefile`: Configured with `all`, `game`, `clean`, `run`, `editor`.
   - `scenes/main.tscn`: Minimal starting scene.
2. Registers new example in root `Makefile` under `EXAMPLES` list (if scaffolded under `examples/`).
3. Runs an initial `make all` in the newly created example project.

---

## 2. Scaffolding a New Redistributable Addon

To create a standalone, redistributable Godot addon package:
```bash
make new-addon NAME=<addon_name>
# Or with custom options:
make new-addon NAME=<addon_name> DIR=addons_dev/<addon_name> AUTHOR="Your Name" DESC="Addon description"
```
*(Equivalent PowerShell command: `.\scripts\create_new_addon.ps1 -Name <addon_name> [-TargetPath <path>] [-Author <author>] [-Description <desc>]`)*

### What this creates:
1. An isolated Godot project designed to distribute a Crystal-backed GDExtension library.
2. Generates:
   - Extension manifest (`<addon_name>.gdextension`) configured for Windows, Linux, and Android.
   - `addons/<addon_name>/` structure ready for export into other Godot projects.
   - Packaging script (`package.ps1`) to create a distributable `.zip` archive.

---

## 3. Post-Scaffolding Verification

After scaffolding an example:
```powershell
# Compile all projects including the new example
make all

# Open the new example in the Godot Editor
godot.exe --editor --path examples/<example_name>
```
