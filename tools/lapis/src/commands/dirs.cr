require "../core/env"
require "../core/logger"
require "file_utils"

module Lapis
  module Commands
    module Dirs
      def self.run(args : Array(String)) : Int32
        root = Core::Env::ROOT_DIR
        target_dirs = Core::Env.collect_target_bin_dirs(root)

        # Standard root dirs
        target_dirs << root.join("bin")
        target_dirs << root.join("addons/crystal_integration/bin")
        target_dirs << root.join("test/bin")
        target_dirs << root.join("template/bin")
        target_dirs << root.join("template-addon/addons/crystal_addon/bin")
        target_dirs << root.join("performance/bin")
        target_dirs << root.join("performance/addons/crystal_integration/bin")

        created = 0
        target_dirs.uniq.each do |dir|
          unless Dir.exists?(dir)
            FileUtils.mkdir_p(dir)
            Core::Logger.debug("Created directory: #{dir}")
            created += 1
          end
        end

        Core::Logger.step("Dirs", "Ensured all output directories exist (#{created} created)")
        0
      end
    end
  end
end
