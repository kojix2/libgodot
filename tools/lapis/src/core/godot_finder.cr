require "./env"
require "./process_runner"

module Lapis
  module Core
    module GodotFinder
      def self.resolve(custom_path : String? = nil) : String?
        if custom_path && !custom_path.empty? && File.exists?(custom_path)
          return File.expand_path(custom_path)
        end

        exe_ext = Env.exe_ext

        candidates = [
          ENV["GODOT"]?,
          ENV["GODOT4"]?,
          ENV["GODOT_BIN"]?,
          ENV["GODOT4_BIN"]?,
          Env::ROOT_DIR.join("godot#{exe_ext}").to_s,
          Env::ROOT_DIR.join("godot.exe").to_s,
          Env::ROOT_DIR.join("godot").to_s,
          Env::ROOT_DIR.join("..", "godot#{exe_ext}").to_s,
          Env::ROOT_DIR.join("..", "godot.exe").to_s,
          Env::ROOT_DIR.join("..", "godot").to_s,
        ].compact

        candidates.each do |c|
          if !c.empty? && File.exists?(c) && !Dir.exists?(c)
            return File.expand_path(c)
          end
        end

        # Search PATH
        ProcessRunner.find_executable("godot") ||
          ProcessRunner.find_executable("godot4") ||
          ProcessRunner.find_executable("godot.exe")
      end
    end
  end
end
