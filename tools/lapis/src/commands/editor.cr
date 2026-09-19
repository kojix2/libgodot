require "../core/env"
require "../core/logger"
require "../core/process_runner"
require "../core/godot_finder"
require "option_parser"
require "file_utils"

module Lapis
  module Commands
    module Editor
      def self.print_help
        puts <<-HELP
\e[35m=== Lapis: Godot Editor Launcher ===\e[0m

Usage: lapis editor [options]

Options:
  -p, --path=PATH       Godot project path (default: test)
  -q, --quit-after=SEC  Auto-quit after N seconds
  -l, --log-file=FILE   Save editor log output to file
  --lldb                Launch editor under LLDB debugger
  --batch               Non-interactive batch mode
  -g, --godot=PATH      Explicit Godot binary path
  -h, --help            Show this help screen

Examples:
  lapis editor
  lapis editor -p template
  lapis editor -p test --quit-after 10
  lapis editor -p test --lldb
HELP
      end

      def self.run(args : Array(String)) : Int32
        if args.includes?("-h") || args.includes?("--help")
          print_help
          return 0
        end

        proj_path = "test"
        quit_after : Int32? = nil
        log_file : String? = nil
        lldb = false
        batch = false
        godot_path : String? = nil

        parser = OptionParser.new do |opts|
          opts.banner = "Usage: lapis editor [options]"
          opts.on("-p PATH", "--path=PATH", "Godot project path (default: test)") { |p| proj_path = p }
          opts.on("-q SEC", "--quit-after=SEC", "Auto-quit after N seconds") { |s| quit_after = s.to_i? }
          opts.on("-l FILE", "--log-file=FILE", "Save editor log output to file") { |f| log_file = f }
          opts.on("--lldb", "Launch editor under LLDB debugger") { lldb = true }
          opts.on("--batch", "Non-interactive batch mode") { batch = true }
          opts.on("-g PATH", "--godot=PATH", "Explicit Godot binary path") { |g| godot_path = g }
          opts.on("-h", "--help", "Show help") { print_help; exit 0 }
        end

        parser.parse(args)

        root = Core::Env::ROOT_DIR
        godot_exe = Core::GodotFinder.resolve(godot_path)

        unless godot_exe
          Core::Logger.error("Godot executable not found.")
          return 1
        end

        target_dir = root.join(proj_path)
        unless Dir.exists?(target_dir)
          Core::Logger.error("Target project directory does not exist: #{target_dir}")
          return 1
        end

        godot_args = ["--editor", "--path", target_dir.to_s]
        if qa = quit_after
          godot_args << "--quit-after"
          godot_args << qa.to_s
        end

        Core::Logger.step("Editor", "Launching Godot Editor for #{proj_path} (#{File.basename(godot_exe)})...")

        status = if lldb
          lldb_cmd = Core::ProcessRunner.find_executable("lldb") || "lldb"
          lldb_args = ["--", godot_exe] + godot_args
          Core::ProcessRunner.run(lldb_cmd, lldb_args, chdir: target_dir.to_s)
        else
          Core::ProcessRunner.run(godot_exe, godot_args, chdir: target_dir.to_s)
        end

        status.exit_code
      end
    end
  end
end
