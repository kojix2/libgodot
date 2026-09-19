require "../core/env"
require "../core/logger"
require "compress/zip"
require "digest/sha256"
require "file_utils"
require "option_parser"

module Lapis
  module Commands
    module Package
      # Recursively zip a directory into a .zip file
      def self.zip_directory(
        source_dir : Path,
        zip_path : Path,
        strip_prefix : Path? = nil,
        exclude_patterns : Array(String) = [] of String
      )
        FileUtils.mkdir_p(zip_path.parent) unless Dir.exists?(zip_path.parent)
        File.delete(zip_path) if File.exists?(zip_path)

        prefix = strip_prefix || source_dir
        pattern = source_dir.to_s.gsub('\\', '/') + "/**/*"

        File.open(zip_path.to_s, "w") do |file|
          Compress::Zip::Writer.open(file) do |zip|
            Dir.glob(pattern).each do |item|
              next if Dir.exists?(item)

              rel_path = Path.new(item).relative_to(prefix).to_s.gsub('\\', '/')
              # Check exclusion patterns
              if exclude_patterns.any? { |p| rel_path.includes?(p) || rel_path.starts_with?(p) }
                next
              end

              File.open(item) do |io|
                zip.add(rel_path, io)
              end
            end
          end
        end

        Core::Logger.success("Packaged archive: #{zip_path.basename} (#{File.size(zip_path)} bytes)")
      end

      # Calculate SHA256 checksum of a file
      def self.sha256_file(path : Path) : String
        Digest::SHA256.file(path.to_s).hexdigest
      end

      def self.package_template(root : Path, out_path : Path?, bundle_binaries : Bool = false) : Int32
        template_dir = root.join("template")
        zip_file = out_path || root.join("bin/template-project.zip")

        Core::Logger.step("Package", "Packaging starter template project...")
        excludes = [".godot", ".git", ".uid", "~", "crash_dump", "test_ext.log", "template_ext.log"]
        unless bundle_binaries
          excludes << "bin/"
          excludes << "bin\\"
          excludes << "lib/"
        end

        zip_directory(
          template_dir,
          zip_file,
          exclude_patterns: excludes
        )
        0
      end

      def self.package_addon(root : Path, out_path : Path?) : Int32
        addon_dir = root.join("addons/crystal_integration")
        zip_file = out_path || root.join("bin/godot-crystal-addon.zip")

        Core::Logger.step("Package", "Packaging crystal_integration addon...")
        zip_directory(
          addon_dir,
          zip_file,
          strip_prefix: root,
          exclude_patterns: [".godot", "~", "_loaded_", ".log"]
        )
        0
      end

      def self.print_help
        puts <<-HELP
\e[35m=== Lapis: Release & Archive Packaging Tool ===\e[0m

Usage: lapis package <template|addon> [options]

Targets:
  template              Package the starter game template into template-project.zip
  addon                 Package the official crystal_integration addon into godot-crystal-addon.zip

Options:
  -o, --output=PATH     Explicit output archive path (.zip)
  --bundle-binaries     Include compiled binaries in archive (template only)
  -h, --help            Show this help screen

Examples:
  lapis package template
  lapis package template -o dist/my_template.zip --bundle-binaries
  lapis package addon -o dist/crystal_addon.zip
HELP
      end

      def self.run(args : Array(String)) : Int32
        if args.empty? || args.includes?("-h") || args.includes?("--help")
          print_help
          return 0
        end

        target = args[0]
        output_file : String? = nil
        bundle_binaries = false

        parser = OptionParser.new do |opts|
          opts.banner = "Usage: lapis package #{target} [options]"
          opts.on("-o PATH", "--output=PATH", "Explicit output .zip path") { |o| output_file = o }
          opts.on("--bundle-binaries", "Include compiled binaries in archive") { bundle_binaries = true }
          opts.on("-h", "--help", "Show help") { print_help; exit 0 }
        end

        parser.parse(args[1..])

        root = Core::Env::ROOT_DIR
        out_path = (of = output_file) ? Path.new(of).expand : nil

        case target
        when "template"
          package_template(root, out_path, bundle_binaries)
        when "addon"
          package_addon(root, out_path)
        else
          Core::Logger.error("Unknown packaging target: '#{target}'. Expected 'template' or 'addon'.")
          puts
          print_help
          1
        end
      end
    end
  end
end
