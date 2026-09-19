require "../core/env"
require "../core/logger"
require "../core/process_runner"
require "file_utils"
require "option_parser"

module Lapis
  module Commands
    module Deps
      def self.safe_copy(src : Path | String, dst : Path | String) : Bool
        return false unless File.exists?(src)
        return true if File.expand_path(src.to_s) == File.expand_path(dst.to_s)

        begin
          dst_path = dst.to_s
          # Only copy if dst doesn't exist or size/mtime differs
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
          Core::Logger.debug("Copied #{src} -> #{dst}")
          true
        rescue ex
          Core::Logger.debug("Skipped copy to #{dst} (possibly file-locked): #{ex.message}")
          false
        end
      end

      def self.print_help
        puts <<-HELP
\e[35m=== Lapis: Runtime Dependencies Manager ===\e[0m

Usage: lapis deps [options]

Options:
  -t, --target-bin=DIR  Explicit target bin directory to synchronize dependencies to
  -h, --help            Show this help screen

Examples:
  lapis deps
  lapis deps -t custom/game/bin
HELP
      end

      def self.run(args : Array(String)) : Int32
        if args.includes?("-h") || args.includes?("--help")
          print_help
          return 0
        end

        target_bin : String? = nil
        OptionParser.parse(args) do |parser|
          parser.banner = "Usage: lapis deps [options]"
          parser.on("-t DIR", "--target-bin=DIR", "Explicit target bin directory") { |dir| target_bin = dir }
          parser.on("-h", "--help", "Show help") { print_help; exit 0 }
        end

        root = Core::Env::ROOT_DIR
        bin_dirs = Core::Env.collect_target_bin_dirs(root, target_bin)
        root_bin = root.join("bin")
        FileUtils.mkdir_p(root_bin) unless Dir.exists?(root_bin)

        if Core::Env.windows?
          # 1. Locate Crystal runtime DLLs (gc.dll, iconv-2.dll, pcre2-8.dll)
          crystal_exe = Core::ProcessRunner.find_executable("crystal")
          crystal_bin = crystal_exe ? Path.new(crystal_exe).parent : nil

          runtime_dlls = ["gc.dll", "iconv-2.dll", "pcre2-8.dll"]
          runtime_dlls.each do |dll|
            # Try to find DLL in crystal dir or in root bin
            src = nil
            if crystal_bin && File.exists?(crystal_bin.join(dll))
              src = crystal_bin.join(dll)
            elsif File.exists?(root_bin.join(dll))
              src = root_bin.join(dll)
            end

            if src
              # Ensure in root_bin
              safe_copy(src, root_bin.join(dll))

              # Sync to all other bin dirs
              bin_dirs.each do |d|
                FileUtils.mkdir_p(d) unless Dir.exists?(d)
                safe_copy(src, d.join(dll))
              end
            end
          end

          # 2. Locate libgodot.dll
          bin_libgodot = root_bin.join("libgodot.dll")
          godot_src_dll = root.join("godot-src/bin/godot.windows.template_debug.x86_64.dll")
          if File.exists?(godot_src_dll) && !File.exists?(bin_libgodot)
            safe_copy(godot_src_dll, bin_libgodot)
          end

          unless File.exists?(bin_libgodot)
            candidates = [
              root.join("addons/crystal_integration/bin/libgodot.dll"),
              root.join("lib/libgodot/bin/libgodot.dll"),
              root.join("../bin/libgodot.dll"),
            ]
            candidates.each do |cand|
              if File.exists?(cand)
                safe_copy(cand, bin_libgodot)
                break
              end
            end
          end

          if File.exists?(bin_libgodot)
            bin_dirs.each do |d|
              FileUtils.mkdir_p(d) unless Dir.exists?(d)
              safe_copy(bin_libgodot, d.join("libgodot.dll"))
            end
          end

          # Also libgodot.lib if present
          bin_libgodot_lib = root_bin.join("libgodot.lib")
          if File.exists?(bin_libgodot_lib)
            bin_dirs.each do |d|
              FileUtils.mkdir_p(d) unless Dir.exists?(d)
              safe_copy(bin_libgodot_lib, d.join("libgodot.lib"))
            end
          end
        else
          # Linux / macOS
          lib_file = "libgodot.#{Core::Env.dll_ext}"
          bin_libgodot = root_bin.join(lib_file)
          if File.exists?(bin_libgodot)
            bin_dirs.each do |d|
              FileUtils.mkdir_p(d) unless Dir.exists?(d)
              safe_copy(bin_libgodot, d.join(lib_file))
            end
          end
        end

        Core::Logger.step("Deps", "Runtime libraries verified and synced across #{bin_dirs.size} destinations")
        0
      end
    end
  end
end
