require "file_utils"
require "path"

module Lapis
  module Core
    module Env
      # Find project root by searching upwards for shard.yml or Makefile
      def self.find_root : Path
        current = Path.new(Dir.current).expand
        loop do
          if File.exists?(current.join("shard.yml")) && File.exists?(current.join("Makefile"))
            return current
          end
          parent = current.parent
          break if parent == current
          current = parent
        end
        # Fallback to current working directory
        Path.new(Dir.current).expand
      end

      ROOT_DIR = find_root

      def self.windows? : Bool
        {% if flag?(:windows) %}
          true
        {% else %}
          false
        {% end %}
      end

      def self.macos? : Bool
        {% if flag?(:darwin) %}
          true
        {% else %}
          false
        {% end %}
      end

      def self.linux? : Bool
        {% if flag?(:linux) %}
          true
        {% else %}
          false
        {% end %}
      end

      def self.dll_ext : String
        if windows?
          "dll"
        elsif macos?
          "dylib"
        else
          "so"
        end
      end

      def self.exe_ext : String
        windows? ? ".exe" : ""
      end

      def self.path_sep : String
        windows? ? ";" : ":"
      end

      # Platform-relevant runtime dependencies
      def self.platform_bin_files : Array(String)
        if windows?
          ["crystal_bridge.dll", "gc.dll", "iconv-2.dll", "pcre2-8.dll", "libgodot.dll", "libgodot.lib"]
        elsif macos?
          ["crystal_bridge.dylib", "libgodot.dylib"]
        else
          ["crystal_bridge.so", "libgodot.so"]
        end
      end

      def self.bridge_file : String
        "crystal_bridge.#{dll_ext}"
      end

      def self.plugin_file : String
        "plugin.#{dll_ext}"
      end

      def self.game_file : String
        "game.#{dll_ext}"
      end

      # Collect all destination bin directories across the repository
      def self.collect_target_bin_dirs(root : Path = ROOT_DIR, target_bin : String? = nil) : Array(Path)
        dirs = [
          root.join("bin"),
          root.join("addons/crystal_integration/bin"),
          root.join("test/bin"),
          root.join("test/addons/crystal_integration/bin"),
          root.join("template/bin"),
          root.join("template/addons/crystal_integration/bin"),
          root.join("template-addon/addons/crystal_addon/bin"),
          root.join("template-addon/addons/crystal_integration/bin"),
          root.join("performance/bin"),
          root.join("performance/addons/crystal_integration/bin"),
        ]

        if target_bin && !target_bin.empty?
          dirs << Path.new(target_bin).expand
        end

        # Discover all addons in test/addons
        test_addons = root.join("test/addons")
        if Dir.exists?(test_addons)
          Dir.each_child(test_addons) do |child|
            p = test_addons.join(child)
            if Dir.exists?(p)
              dirs << p.join("bin")
            end
          end
        end

        # Discover all examples/*/bin and examples/*/addons/*/bin
        examples_dir = root.join("examples")
        if Dir.exists?(examples_dir)
          Dir.each_child(examples_dir) do |child|
            ex = examples_dir.join(child)
            if Dir.exists?(ex)
              dirs << ex.join("bin")
              dirs << ex.join("addons/crystal_integration/bin")

              # Other nested addons in example
              ex_addons = ex.join("addons")
              if Dir.exists?(ex_addons)
                Dir.each_child(ex_addons) do |addon_child|
                  addon_p = ex_addons.join(addon_child)
                  dirs << addon_p.join("bin") if Dir.exists?(addon_p)
                end
              end
            end
          end
        end

        dirs.uniq
      end
    end
  end
end
