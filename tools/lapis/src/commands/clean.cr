require "../core/env"
require "../core/logger"
require "file_utils"
require "option_parser"

module Lapis
  module Commands
    module Clean
      PRESERVED_FILES = Set{
        "libgodot.dll", "libgodot.lib", "libgodot.so", "libgodot.dylib",
        "gc.dll", "iconv-2.dll", "pcre2-8.dll"
      }

      def self.print_help
        puts <<-HELP
\e[35m=== Lapis: Workspace Clean Tool ===\e[0m

Usage: lapis clean [options]

Options:
  --all                 Also purge .godot/ and .crystal/ cache directories
  -h, --help            Show this help screen

Examples:
  lapis clean
  lapis clean --all
HELP
      end

      private def self.clean_bin_dir(dir : Path) : Void
        return unless Dir.exists?(dir)
        Dir.each_child(dir) do |child|
          next if PRESERVED_FILES.includes?(child)
          p = dir.join(child)
          begin
            if File.file?(p)
              File.delete(p)
            elsif Dir.exists?(p)
              FileUtils.rm_rf(p)
            end
          rescue ex
            Core::Logger.debug("Could not delete #{p}: #{ex.message}")
          end
        end
      end

      private def self.clean_project_caches(dir : Path) : Void
        godot_dir = dir.join(".godot")
        if Dir.exists?(godot_dir)
          FileUtils.rm_rf(godot_dir) rescue nil
        end
        crystal_dir = dir.join(".crystal")
        if Dir.exists?(crystal_dir)
          FileUtils.rm_rf(crystal_dir) rescue nil
        end
      end

      def self.run(args : Array(String)) : Int32
        if args.includes?("-h") || args.includes?("--help")
          print_help
          return 0
        end

        purge_all = args.includes?("--all")

        root = Core::Env::ROOT_DIR
        Core::Logger.step("Clean", "Cleaning build artifacts across workspace...")

        # 1. Clean bin directories across root and consumers
        target_dirs = [
          root.join("bin"),
          root.join("test/bin"),
          root.join("template/bin"),
          root.join("template-addon/dist"),
          root.join("performance/bin"),
          root.join("docs"),
        ]

        # Examples
        ex_dir = root.join("examples")
        if Dir.exists?(ex_dir)
          Dir.each_child(ex_dir) do |child|
            p = ex_dir.join(child)
            target_dirs << p.join("bin") if Dir.exists?(p)
          end
        end

        # Addon bins
        addons_dir = root.join("test/addons")
        if Dir.exists?(addons_dir)
          Dir.each_child(addons_dir) do |child|
            p = addons_dir.join(child)
            target_dirs << p.join("bin") if Dir.exists?(p)
          end
        end

        target_dirs.each do |d|
          clean_bin_dir(d)
        end

        # 2. Purge caches if requested
        if purge_all
          Core::Logger.step("Clean", "Purging .godot and .crystal caches...")
          [root, root.join("test"), root.join("template"), root.join("performance")].each do |proj|
            clean_project_caches(proj)
          end
        end

        Core::Logger.success("Workspace cleaned successfully (runtime libraries safely preserved)!")
        0
      end
    end
  end
end
