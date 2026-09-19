require "./logger"

module Lapis
  module Core
    module ProcessRunner
      # Run a command with streaming output to STDOUT/STDERR
      def self.run(
        command : String,
        args : Array(String) = [] of String,
        env : Process::Env = nil,
        chdir : String? = nil
      ) : Process::Status
        Logger.debug("Executing: #{command} #{args.join(" ")} (chdir: #{chdir || Dir.current})")
        status = Process.run(
          command: command,
          args: args,
          env: env,
          chdir: chdir,
          input: Process::Redirect::Inherit,
          output: Process::Redirect::Inherit,
          error: Process::Redirect::Inherit
        )
        status
      end

      # Run a command and capture STDOUT and STDERR as strings
      def self.capture(
        command : String,
        args : Array(String) = [] of String,
        env : Process::Env = nil,
        chdir : String? = nil
      ) : {status: Process::Status, output: String, error: String}
        Logger.debug("Capturing: #{command} #{args.join(" ")}")
        stdout = IO::Memory.new
        stderr = IO::Memory.new
        status = Process.run(
          command: command,
          args: args,
          env: env,
          chdir: chdir,
          output: stdout,
          error: stderr
        )
        {status: status, output: stdout.to_s, error: stderr.to_s}
      end

      # Find an executable in PATH or check if an absolute/relative path exists and is executable
      def self.find_executable(name : String) : String?
        # If it contains directory separators and exists
        if (name.includes?('/') || name.includes?('\\')) && File.exists?(name)
          return File.expand_path(name)
        end

        exts = Env.windows? ? [".exe", ".cmd", ".bat", ""] : [""]
        paths = (ENV["PATH"]? || "").split(Env.path_sep)

        paths.each do |p|
          next if p.empty?
          exts.each do |ext|
            candidate = Path.new(p).join("#{name}#{ext}")
            if File.exists?(candidate) && !Dir.exists?(candidate)
              return candidate.expand.to_s
            end
          end
        end

        nil
      end
    end
  end
end
