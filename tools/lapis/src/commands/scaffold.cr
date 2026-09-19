require "../core/env"
require "../core/logger"
require "file_utils"
require "option_parser"

module Lapis
  module Commands
    module Scaffold
      def self.print_help
        puts <<-HELP
\e[35m=== Lapis: Project Scaffolding Tool ===\e[0m

Usage:
  lapis scaffold <addon|example> <name> [options]
  lapis new <addon|example> <name> [options]

Subcommands:
  example <name>         Scaffold a self-contained showcase example project in examples/<name>
  addon <name>           Scaffold a redistributable GDExtension addon in addons/<name>

Options:
  -t, --target=DIR       Explicit target output directory
  -a, --author=NAME      Author name for shard.yml (addons only)
  -d, --desc=TEXT        Description for shard.yml (addons only)
  -h, --help             Show this help screen

Examples:
  lapis scaffold example platformer_demo
  lapis scaffold addon my_inventory -a "Sol-Vin" -d "Inventory system for Godot"
  lapis new example 3d_fps --target custom/path/fps
HELP
      end

      def self.scaffold_example(name : String, target_dir : Path?) : Int32
        root = Core::Env::ROOT_DIR
        ex_dir = target_dir || root.join("examples", name)

        if Dir.exists?(ex_dir)
          Core::Logger.error("Target directory already exists: #{ex_dir}")
          return 1
        end

        Core::Logger.step("Scaffold", "Creating new Lapis example '#{name}' at #{ex_dir}...")
        FileUtils.mkdir_p(ex_dir.join("src"))
        FileUtils.mkdir_p(ex_dir.join("scenes"))
        FileUtils.mkdir_p(ex_dir.join("bin"))

        # project.godot
        File.write(ex_dir.join("project.godot"), <<-GODOT
config_version=5

[application]

config/name="#{name}"
run/main_scene="res://scenes/main.tscn"
config/features=PackedStringArray("4.3", "Forward Plus")
GODOT
        )

        # shard.yml
        File.write(ex_dir.join("shard.yml"), <<-YAML
name: #{name}
version: 0.1.0

dependencies:
  lapis:
    path: ../..
YAML
        )

        # src/main.cr
        File.write(ex_dir.join("src/main.cr"), <<-CR
require "lapis"

node #{name.camelcase} < Node2D do
  def _ready : Void
    Godot.print("#{name.camelcase} initialized successfully!")
  end
end
CR
        )

        # scenes/main.tscn
        File.write(ex_dir.join("scenes/main.tscn"), <<-TSCN
[gd_scene format=3]

[node name="Main" type="#{name.camelcase}"]
TSCN
        )

        Core::Logger.success("Example '#{name}' scaffolded successfully at #{ex_dir}!")
        0
      end

      def self.scaffold_addon(name : String, target_dir : Path?, author : String?, desc : String?) : Int32
        root = Core::Env::ROOT_DIR
        addon_dir = target_dir || root.join("addons", name)

        if Dir.exists?(addon_dir)
          Core::Logger.error("Target addon directory already exists: #{addon_dir}")
          return 1
        end

        Core::Logger.step("Scaffold", "Creating new GDExtension addon '#{name}' at #{addon_dir}...")
        FileUtils.mkdir_p(addon_dir.join("src"))
        FileUtils.mkdir_p(addon_dir.join("bin"))

        # .gdextension manifest
        File.write(addon_dir.join("#{name}.gdextension"), <<-GDM
[configuration]
entry_symbol = "crystal_godot_init"
compatibility_minimum = "4.1"
reloadable = true

[libraries]
windows.debug.x86_64 = "res://addons/#{name}/bin/#{name}.dll"
windows.release.x86_64 = "res://addons/#{name}/bin/#{name}.dll"
linux.debug.x86_64 = "res://addons/#{name}/bin/#{name}.so"
linux.release.x86_64 = "res://addons/#{name}/bin/#{name}.so"
macos.debug = "res://addons/#{name}/bin/#{name}.dylib"
macos.release = "res://addons/#{name}/bin/#{name}.dylib"
GDM
        )

        # shard.yml
        File.write(addon_dir.join("shard.yml"), <<-YAML
name: #{name}
version: 0.1.0
authors:
  - #{author || "Author"}
description: #{desc || "#{name} GDExtension Addon"}

dependencies:
  lapis:
    path: ../..
YAML
        )

        # src/main.cr
        File.write(addon_dir.join("src/main.cr"), <<-CR
require "lapis"

@[Tool]
node #{name.camelcase}Node < Node do
  def _ready : Void
    Godot.print("#{name.camelcase}Node ready!")
  end
end
CR
        )

        Core::Logger.success("Addon '#{name}' scaffolded successfully at #{addon_dir}!")
        0
      end

      def self.run(args : Array(String)) : Int32
        if args.empty? || args.includes?("-h") || args.includes?("--help")
          print_help
          return 0
        end

        kind = args[0]
        if args.size < 2
          Core::Logger.error("Name is required: lapis scaffold #{kind} <name>")
          puts
          print_help
          return 1
        end

        name = args[1]
        target_path : String? = nil
        author : String? = nil
        desc : String? = nil

        parser = OptionParser.new do |opts|
          opts.banner = "Usage: lapis scaffold #{kind} <name> [options]"
          opts.on("-t DIR", "--target=DIR", "Explicit target directory") { |d| target_path = d }
          opts.on("-a NAME", "--author=NAME", "Addon author name") { |a| author = a }
          opts.on("-d TEXT", "--desc=TEXT", "Addon description") { |text| desc = text }
          opts.on("-h", "--help", "Show help") { print_help; exit 0 }
        end

        parser.parse(args[2..])

        target_dir = (tp = target_path) ? Path.new(tp).expand : nil

        case kind
        when "example"
          scaffold_example(name, target_dir)
        when "addon"
          scaffold_addon(name, target_dir, author, desc)
        else
          Core::Logger.error("Unknown scaffold type: '#{kind}'. Expected 'addon' or 'example'.")
          puts
          print_help
          1
        end
      end
    end
  end
end
