require "../core/env"
require "../core/logger"
require "../core/process_runner"
require "../core/godot_finder"
require "file_utils"
require "option_parser"

module Lapis
  module Commands
    module Build
      # Automatically dump and generate project GDScript bindings if project contains custom .gd files
      def self.check_and_generate_project_bindings(entry : Path, root : Path)
        proj_dir = entry.parent
        proj_dir = proj_dir.parent if proj_dir.basename == "src"

        # Check for .gd files excluding addons, .godot, tools
        gd_files = Dir.glob(proj_dir.join("**/*.gd").to_s).reject do |f|
          f.includes?("/addons/") || f.includes?("\\addons\\") ||
            f.includes?("/.godot/") || f.includes?("\\.godot\\") ||
            f.includes?("/tools/") || f.includes?("\\tools\\") ||
            File.basename(f) == "dump_project_nodes.gd"
        end

        return if gd_files.empty?

        Core::Logger.info("Detected custom GDScript files in #{proj_dir.basename}, generating project bindings...")

        dump_script = [
          proj_dir.join("scripts/dump_project_nodes.gd"),
          proj_dir.join("tools/api_generator/dump_project_nodes.gd"),
          root.join("tools/api_generator/dump_project_nodes.gd"),
        ].find { |p| File.exists?(p) }

        gen_script = [
          proj_dir.join("scripts/generate_project_bindings.cr"),
          proj_dir.join("tools/api_generator/generate_project_bindings.cr"),
          root.join("tools/api_generator/generate_project_bindings.cr"),
        ].find { |p| File.exists?(p) }

        godot_exe = Core::GodotFinder.resolve

        if dump_script && gen_script && godot_exe
          # 1. Run Godot dump
          Core::ProcessRunner.run(
            godot_exe,
            ["--headless", "--path", proj_dir.to_s, "--script", dump_script.to_s],
            chdir: proj_dir.to_s
          )

          # 2. Run generator
          out_json = proj_dir.join("src/generated/project_nodes.json")
          out_dir = proj_dir.join("src/generated/project_nodes")
          if File.exists?(out_json)
            Core::ProcessRunner.run(
              "crystal",
              ["run", gen_script.to_s, "--", out_json.to_s, out_dir.to_s],
              chdir: root.to_s
            )
          end
        end
      end

      def self.print_help
        puts <<-HELP
\e[35m=== Lapis: Crystal Game & Plugin Compiler ===\e[0m

Usage: lapis build --entry <path.cr> --output <path.dll|path.exe> [options]

Options:
  -e, --entry=PATH      Entry source file (.cr) [Required]
  -o, --output=PATH     Output binary path (.dll, .so, .dylib, or .exe) [Required]
  -r, --release         Compile in release mode with optimizations (-O3)
  -l, --link-flags=FLAGS Linker flags passed to crystal build
  -f, --flags=FLAGS     Extra Crystal compiler flags (e.g. -Dlibgodot_addon)
  -s, --source-path=DIR Source path prepended to CRYSTAL_PATH
  -h, --help            Show this help screen

Examples:
  lapis build -e src/editor/plugin.cr -o bin/plugin.dll --flags "-Dlibgodot_addon"
  lapis build -e template/src/main.cr -o template/bin/game.dll --release
HELP
      end

      def self.run(args : Array(String)) : Int32
        if args.empty? || args.includes?("-h") || args.includes?("--help")
          print_help
          return 0
        end

        entry : String? = nil
        output : String? = nil
        link_flags : String? = nil
        flags : String? = nil
        release = false
        source_path : String? = nil

        parser = OptionParser.new do |opts|
          opts.banner = "Usage: lapis build --entry <path> --output <path> [options]"
          opts.on("-e PATH", "--entry=PATH", "Entry source file (.cr)") { |v| entry = v }
          opts.on("-o PATH", "--output=PATH", "Output binary path") { |v| output = v }
          opts.on("-l FLAGS", "--link-flags=FLAGS", "Linker flags") { |v| link_flags = v }
          opts.on("-f FLAGS", "--flags=FLAGS", "Extra Crystal compiler flags") { |v| flags = v }
          opts.on("-r", "--release", "Compile in release mode with optimizations") { release = true }
          opts.on("-s PATH", "--source-path=PATH", "Source path for CRYSTAL_PATH") { |v| source_path = v }
          opts.on("-h", "--help", "Show help") { print_help; exit 0 }
        end

        parser.parse(args)

        unless entry && output
          Core::Logger.error("Both --entry and --output are required.")
          puts
          print_help
          return 1
        end

        root = Core::Env::ROOT_DIR
        entry_path = Path.new(entry.not_nil!).expand
        output_path = Path.new(output.not_nil!).expand

        # Ensure output directory exists
        FileUtils.mkdir_p(output_path.parent) unless Dir.exists?(output_path.parent)

        # Check and auto-dump project bindings if applicable
        check_and_generate_project_bindings(entry_path, root)

        # Determine CRYSTAL_PATH
        src_dir = if sp = source_path
          Path.new(sp).expand
        else
          root.join("src")
        end
        base_crystal_path = Core::ProcessRunner.capture("crystal", ["env", "CRYSTAL_PATH"])[:output].strip
        full_crystal_path = "#{src_dir}#{Core::Env.path_sep}#{base_crystal_path}"

        # Construct crystal build command
        cmd_args = ["build", entry_path.to_s, "-o", output_path.to_s]
        cmd_args << "--release" if release

        if (lf = link_flags) && !lf.empty?
          cmd_args << "--link-flags"
          cmd_args << lf
        end

        if (fl = flags) && !fl.empty?
          fl.split(' ').each do |f|
            cmd_args << f unless f.empty?
          end
        end

        # Override CRYSTAL_PATH while inheriting other environment variables
        env = {"CRYSTAL_PATH" => full_crystal_path}

        Core::Logger.step("Build", "Compiling #{output_path.basename}...")
        status = Core::ProcessRunner.run(
          "crystal",
          cmd_args,
          env: env,
          chdir: root.to_s
        )

        if status.success?
          Core::Logger.success("#{output_path.basename} built successfully!")
          0
        else
          Core::Logger.error("Build failed with exit code #{status.exit_code}")
          status.exit_code
        end
      end
    end
  end
end
