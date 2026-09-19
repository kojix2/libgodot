require "../core/env"
require "../core/logger"
require "file_utils"
require "option_parser"

module Lapis
  module Commands
    module Sync
      def self.safe_copy(src : Path | String, dst : Path | String) : Bool
        return false unless File.exists?(src)
        return true if File.expand_path(src.to_s) == File.expand_path(dst.to_s)

        begin
          dst_path = dst.to_s
          if File.exists?(dst_path)
            src_info = File.info(src)
            dst_info = File.info(dst_path)
            if src_info.size == dst_info.size && src_info.modification_time <= dst_info.modification_time
              return true
            end
          end

          dst_dir = File.dirname(dst_path)
          FileUtils.mkdir_p(dst_dir) unless Dir.exists?(dst_dir)
          FileUtils.cp(src.to_s, dst_path)
          Core::Logger.debug("Synced #{src} -> #{dst}")
          true
        rescue ex
          Core::Logger.debug("Skipped sync to #{dst} (file locked): #{ex.message}")
          false
        end
      end

      # Sync addons directory tree recursively, preserving structure
      def self.sync_addon_directory(src_addon : Path, dst_addon : Path)
        return unless Dir.exists?(src_addon)
        FileUtils.mkdir_p(dst_addon) unless Dir.exists?(dst_addon)

        Dir.glob(src_addon.join("**/*").to_s).each do |file|
          next if Dir.exists?(file)
          # Skip bin directory inside addon (handled separately by bin sync)
          rel = Path.new(file).relative_to(src_addon)
          next if rel.to_s.starts_with?("bin") || rel.to_s.starts_with?("bin/") || rel.to_s.starts_with?("bin\\")

          dst_file = dst_addon.join(rel)
          safe_copy(file, dst_file)
        end
      end

      # Ensure .godot/extension_list.cfg contains the crystal_integration extension
      def self.ensure_extension_list(project_dir : Path)
        godot_dir = project_dir.join(".godot")
        return unless Dir.exists?(godot_dir)

        ext_list = godot_dir.join("extension_list.cfg")
        entry = "res://addons/crystal_integration/crystal_integration.gdextension"

        existing = File.exists?(ext_list) ? File.read(ext_list) : ""
        unless existing.lines.map(&.strip).includes?(entry)
          content = existing.empty? ? "#{entry}\n" : "#{existing.rstrip}\n#{entry}\n"
          File.write(ext_list, content)
          Core::Logger.debug("Updated extension_list.cfg in #{project_dir}")
        end
      end

      def self.print_help
        puts <<-HELP
\e[35m=== Lapis: Binary & Addon Synchronizer ===\e[0m

Usage: lapis sync [options]

Options:
  --addons-only         Sync only GDExtension addons and manifests
  --bins-only           Sync only compiled binaries and runtime libraries
  -h, --help            Show this help screen

Examples:
  lapis sync
  lapis sync --addons-only
  lapis sync --bins-only
HELP
      end

      def self.run(args : Array(String)) : Int32
        if args.includes?("-h") || args.includes?("--help")
          print_help
          return 0
        end

        addons_only = false
        bins_only = false

        OptionParser.parse(args) do |parser|
          parser.banner = "Usage: lapis sync [options]"
          parser.on("--addons-only", "Sync only addons and manifests") { addons_only = true }
          parser.on("--bins-only", "Sync only compiled binaries and runtime DLLs") { bins_only = true }
          parser.on("-h", "--help", "Show help") { print_help; exit 0 }
        end

        root = Core::Env::ROOT_DIR
        bin_dir = root.join("bin")
        target_dirs = Core::Env.collect_target_bin_dirs(root)

        # 1. Sync addons
        unless bins_only
          src_addon = root.join("addons/crystal_integration")
          if Dir.exists?(src_addon)
            addon_targets = [
              root.join("test/addons/crystal_integration"),
              root.join("template/addons/crystal_integration"),
              root.join("performance/addons/crystal_integration"),
            ]

            examples_dir = root.join("examples")
            if Dir.exists?(examples_dir)
              Dir.each_child(examples_dir) do |child|
                ex = examples_dir.join(child)
                if Dir.exists?(ex)
                  addon_targets << ex.join("addons/crystal_integration")
                  ensure_extension_list(ex)
                end
              end
            end

            ensure_extension_list(root.join("test"))
            ensure_extension_list(root.join("template"))
            ensure_extension_list(root.join("performance"))

            addon_targets.each do |dst|
              sync_addon_directory(src_addon, dst)
            end
            Core::Logger.step("Sync", "Addons and manifests synchronized across #{addon_targets.size} targets")
          end
        end

        # 2. Sync binaries
        unless addons_only
          platform_files = Core::Env.platform_bin_files.dup

          synced_count = 0
          target_dirs.each do |dir|
            FileUtils.mkdir_p(dir) unless Dir.exists?(dir)

            platform_files.each do |bin_name|
              src = bin_dir.join(bin_name)
              dst = dir.join(bin_name)
              if safe_copy(src, dst)
                synced_count += 1
              end
            end

            # plugin file is strictly synced to crystal_integration/bin and root bin
            dir_str = dir.to_s.gsub('\\', '/')
            is_crystal_integration = dir_str.ends_with?("addons/crystal_integration/bin") || dir_str == root.join("bin").to_s.gsub('\\', '/')
            plugin_target = dir.join(Core::Env.plugin_file)

            if is_crystal_integration
              src_plugin = bin_dir.join(Core::Env.plugin_file)
              safe_copy(src_plugin, plugin_target)
            else
              # Purge any stray plugin binaries from non-crystal_integration addon directories
              ["plugin.dll", "plugin.so", "plugin.dylib"].each do |p_lib|
                stray = dir.join(p_lib)
                File.delete(stray) if File.exists?(stray)
              end
            end

            # Purge foreign stray files (.cr, .cr.uid, ~* temporary shadow copies)
            if Dir.exists?(dir)
              Dir.each_child(dir) do |item|
                full_path = dir.join(item)
                next if Dir.exists?(full_path)

                if item.ends_with?(".cr") || item.ends_with?(".cr.uid") || item.starts_with?("~")
                  begin
                    File.delete(full_path)
                    Core::Logger.debug("Purged temporary file: #{full_path}")
                  rescue
                  end
                end
              end
            end
          end
          Core::Logger.step("Sync", "Binaries synchronized across #{target_dirs.size} destinations")
        end

        # 3. Ensure .gdignore in bin/ and lib/ across all targets
        ["test", "template", "template-addon", "performance", "examples/basic_demo"].each do |proj|
          proj_dir = root.join(proj)
          next unless Dir.exists?(proj_dir)
          bin_gd = proj_dir.join("bin/.gdignore")
          File.write(bin_gd, "") if Dir.exists?(proj_dir.join("bin")) && !File.exists?(bin_gd)
          lib_gd = proj_dir.join("lib/.gdignore")
          if Dir.exists?(proj_dir.join("lib")) && !File.exists?(lib_gd)
            File.write(lib_gd, "")
          end
        end

        0
      end
    end
  end
end
