require "./core/env"
require "./core/logger"
require "./commands/dirs"
require "./commands/deps"
require "./commands/sync"
require "./commands/build"
require "./commands/test"
require "./commands/editor"
require "./commands/scaffold"
require "./commands/package"

module Lapis
  VERSION = "0.1.0"

  def self.print_help
    puts <<-HELP
\e[35m========================================================================\e[0m
\e[35m   Lapis: Unified Crystal Engine Toolchain for Godot (v#{VERSION})\e[0m
\e[35m========================================================================\e[0m

Usage:
  lapis <subcommand> [options]
  lapis help <subcommand>

\e[36mBuild & Synchronization Commands:\e[0m
  dirs                  Ensure all project and binary output directories exist
  deps                  Verify and copy Crystal runtime dependencies & libgodot DLLs
  sync                  Synchronize binaries, addons, and manifests across all targets
  build                 Compile Crystal game libraries, plugins, or standalone executables

\e[36mTesting & Development Commands:\e[0m
  test                  Run unit specs, in-editor tool tests, and runtime test projects
  editor                Launch Godot Editor with log monitoring, auto-quit, and LLDB attachment

\e[36mScaffolding & Distribution Commands:\e[0m
  scaffold, new         Scaffold a new addon or showcase example ('lapis scaffold <addon|example> <name>')
  package               Create native .zip distribution archives ('lapis package <template|addon>')

\e[36mGlobal Options:\e[0m
  -v, --version         Show Lapis toolchain version
  -h, --help            Show this help text
  -q, --quiet           Suppress non-essential log output
  --verbose             Enable verbose debug logging

\e[36mExamples:\e[0m
  lapis dirs
  lapis deps
  lapis sync
  lapis build -e src/editor/plugin.cr -o bin/plugin.dll --flags "-Dlibgodot_addon"
  lapis test --skip-specs
  lapis editor -p test --quit-after 5
  lapis scaffold example my_rpg
  lapis scaffold addon custom_particles -a "Developer"
  lapis package template -o dist/template.zip

For detailed help on any subcommand, run:
  lapis help <subcommand>   or   lapis <subcommand> --help

HELP
  end

  def self.dispatch_help(subcommand : String)
    case subcommand
    when "dirs"
      puts "Usage: lapis dirs\n\nEnsures all output directories exist across root, test, template, and performance."
    when "deps"
      Commands::Deps.run(["--help"])
    when "sync"
      Commands::Sync.run(["--help"])
    when "build"
      Commands::Build.run(["--help"])
    when "test"
      Commands::Test.run(["--help"])
    when "editor"
      Commands::Editor.run(["--help"])
    when "scaffold", "new"
      Commands::Scaffold.print_help
    when "package"
      Commands::Package.run(["--help"])
    else
      Core::Logger.error("Unknown command for help: '#{subcommand}'")
      puts
      print_help
    end
  end

  def self.main(args : Array(String)) : Int32
    if args.empty?
      print_help
      return 0
    end

    if args.size == 1 && (args[0] == "-h" || args[0] == "--help")
      print_help
      return 0
    end

    if args.size == 1 && (args[0] == "-v" || args[0] == "--version")
      puts "Lapis v#{VERSION}"
      return 0
    end

    # Handle global quiet/verbose flags
    filtered_args = [] of String
    args.each do |arg|
      case arg
      when "-q", "--quiet"
        Core::Logger.quiet = true
      when "--verbose"
        Core::Logger.verbose = true
      else
        filtered_args << arg
      end
    end

    if filtered_args.empty?
      print_help
      return 0
    end

    subcommand = filtered_args[0]
    sub_args = filtered_args[1..]

    case subcommand
    when "help"
      if sub_args.empty?
        print_help
      else
        dispatch_help(sub_args[0])
      end
      0
    when "dirs"
      Commands::Dirs.run(sub_args)
    when "deps"
      Commands::Deps.run(sub_args)
    when "sync"
      Commands::Sync.run(sub_args)
    when "build"
      Commands::Build.run(sub_args)
    when "test"
      Commands::Test.run(sub_args)
    when "editor"
      Commands::Editor.run(sub_args)
    when "scaffold", "new"
      Commands::Scaffold.run(sub_args)
    when "package"
      Commands::Package.run(sub_args)
    else
      Core::Logger.error("Unknown command: '#{subcommand}'")
      puts
      print_help
      1
    end
  end
end

exit Lapis.main(ARGV)
