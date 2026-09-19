require "../core/env"
require "../core/logger"
require "../core/process_runner"
require "../core/godot_finder"
require "option_parser"

module Lapis
  module Commands
    module Test
      def self.print_help
        puts <<-HELP
\e[35m=== Lapis: Automated Test Suite Runner ===\e[0m

Usage: lapis test [options]

Options:
  --skip-specs          Skip Crystal spec unit tests (test/spec)
  --skip-tool-tests     Skip headless in-editor @tool tests
  --skip-runtime-tests  Skip Godot runtime test project
  --skip-standalone     Skip standalone test executable
  -g, --godot=PATH      Explicit Godot engine executable path
  -h, --help            Show this help screen

Examples:
  lapis test
  lapis test --skip-specs
  lapis test --skip-runtime-tests
HELP
      end

      def self.run(args : Array(String)) : Int32
        if args.includes?("-h") || args.includes?("--help")
          print_help
          return 0
        end

        skip_specs = false
        skip_tool_tests = false
        skip_runtime_tests = false
        skip_standalone = false
        godot_path : String? = nil

        parser = OptionParser.new do |opts|
          opts.banner = "Usage: lapis test [options]"
          opts.on("--skip-specs", "Skip Crystal spec unit tests") { skip_specs = true }
          opts.on("--skip-tool-tests", "Skip in-editor @tool tests") { skip_tool_tests = true }
          opts.on("--skip-runtime-tests", "Skip Godot runtime test project") { skip_runtime_tests = true }
          opts.on("--skip-standalone", "Skip standalone test executable") { skip_standalone = true }
          opts.on("-g PATH", "--godot=PATH", "Explicit Godot executable path") { |p| godot_path = p }
          opts.on("-h", "--help", "Show help") { print_help; exit 0 }
        end

        parser.parse(args)

        root = Core::Env::ROOT_DIR
        godot_exe = Core::GodotFinder.resolve(godot_path)

        failed_steps = [] of String

        # 1. Crystal Specs
        unless skip_specs
          spec_dir = root.join("test/spec")
          if Dir.exists?(spec_dir)
            Core::Logger.step("Test:Specs", "Running Crystal specifications in #{spec_dir}...")
            status = Core::ProcessRunner.run(
              "crystal",
              ["spec", "test/spec"],
              chdir: root.to_s
            )
            failed_steps << "Crystal Specifications" unless status.success?
          end
        end

        # 2. Standalone Test Project Runner (if built)
        unless skip_standalone
          standalone_exe = root.join("test/bin/tests#{Core::Env.exe_ext}")
          if File.exists?(standalone_exe)
            Core::Logger.step("Test:Standalone", "Running standalone test runner #{standalone_exe.basename}...")
            status = Core::ProcessRunner.run(
              standalone_exe.to_s,
              ["--headless"],
              chdir: root.join("test").to_s
            )
            failed_steps << "Standalone Test Runner" unless status.success?
          end
        end

        # 3. Godot Runtime Test Project
        unless skip_runtime_tests
          if godot_exe
            Core::Logger.step("Test:Runtime", "Running Godot test project with #{File.basename(godot_exe)}...")
            status = Core::ProcessRunner.run(
              godot_exe,
              ["--headless", "--path", root.join("test").to_s],
              chdir: root.join("test").to_s
            )
            failed_steps << "Godot Runtime Tests" unless status.success?
          else
            Core::Logger.warn("Godot executable not found, skipping runtime tests.")
          end
        end

        puts
        if failed_steps.empty?
          Core::Logger.success("All test suites passed successfully!")
          0
        else
          Core::Logger.error("The following test suites failed: #{failed_steps.join(", ")}")
          1
        end
      end
    end
  end
end
