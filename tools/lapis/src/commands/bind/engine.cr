require "../../core/env"
require "../../core/logger"
require "../../core/godot_finder"
require "../../core/process_runner"
require "json"
require "yaml"
require "file_utils"

module Lapis
  module Commands
    module Bind
      module Engine
        private def self.format_doc_comment(raw_text : String?, indent : String = "  ") : String
          return "" if raw_text.nil? || raw_text.to_s.strip.empty?

          text = raw_text.to_s
            .gsub(/\[codeblock\]/m, "```gdscript\n")
            .gsub(/\[\/codeblock\]/m, "\n```")
            .gsub(/\[codeblocks\]/m, "")
            .gsub(/\[\/codeblocks\]/m, "")
            .gsub(/\[gdscript\]/m, "```gdscript\n")
            .gsub(/\[\/gdscript\]/m, "\n```")
            .gsub(/\[csharp\]/m, "```csharp\n")
            .gsub(/\[\/csharp\]/m, "\n```")
            .gsub(/\[code\](.*?)\[\/code\]/m) { "`#{$1}`" }
            .gsub(/\[b\](.*?)\[\/b\]/m) { "**#{$1}**" }
            .gsub(/\[i\](.*?)\[\/i\]/m) { "*#{$1}*" }
            .gsub(/\[kbd\](.*?)\[\/kbd\]/m) { "`#{$1}`" }
            .gsub(/\[url=(.*?)\](.*?)\[\/url\]/m) { "[$2]($1)" }
            .gsub(/\[url\](.*?)\[\/url\]/m) { "[$1]($1)" }
            .gsub(/\[annotation\s+([^\]]+)\]/) { "`#{$1}`" }
            .gsub(/\[param\s+(\w+)\]/) { "`#{$1}`" }
            .gsub(/\[member\s+([\w\.]+)\]/) { "`#{$1}`" }
            .gsub(/\[method\s+([\w\.]+)\]/) { "`##{$1}`" }
            .gsub(/\[constant\s+([\w\.]+)\]/) { "`#{$1}`" }
            .gsub(/\[enum\s+([\w\.]+)\]/) { "`#{$1}`" }
            .gsub(/\[signal\s+([\w\.]+)\]/) { "`#{$1}`" }
            .gsub(/\[(\w+)\]/) { "`#{$1}`" }

          lines = text.strip.lines
          doc_lines = lines.map do |line|
            cleaned = line.rstrip
            cleaned.empty? ? "#{indent}#" : "#{indent}# #{cleaned}"
          end

          doc_lines.join("\n") + "\n"
        end

        private def self.sanitize_name(name : String, keywords : Hash(String, String)) : String
          clean = name.gsub(/[^a-zA-Z0-9_]/, "_").underscore
          if clean.starts_with?(/[0-9]/)
            clean = "arg_#{clean}"
          elsif clean.empty?
            clean = "arg"
          end
          keywords[clean]? || clean
        end

        private def self.crystal_type_name(godot_type : String, type_map : Hash(String, String)) : String
          if godot_type.starts_with?("enum::") || godot_type.starts_with?("bitfield::")
            "Int64"
          elsif mapped = type_map[godot_type]?
            mapped
          elsif godot_type.starts_with?("typedarray::")
            "Godot::Array"
          elsif godot_type.ends_with?("*") || godot_type.starts_with?("const ") || godot_type.includes?("*")
            "Void*"
          else
            godot_type.gsub(/[^a-zA-Z0-9_]/, "")
          end
        end

        private def self.visit(
          name : String,
          class_map : Hash(String, JSON::Any),
          inherits_map : Hash(String, String?),
          visited : Set(String),
          sorted_classes : Array(JSON::Any)
        ) : Void
          return if visited.includes?(name)
          visited.add(name)
          if parent = inherits_map[name]?
            if class_map.has_key?(parent)
              visit(parent, class_map, inherits_map, visited, sorted_classes)
            end
          end
          if c = class_map[name]?
            sorted_classes << c
          end
        end

        private def self.generate_class_code(
          io : IO,
          c : JSON::Any,
          keywords : Hash(String, String),
          type_map : Hash(String, String),
          class_names : Set(String),
          all_method_names : Set(String),
          manual_methods : Hash(String, Set(String))
        ) : Void
          name = c["name"].as_s
          parent = c["inherits"]?.try(&.as_s) || "Godot::Object"
          parent_type = parent == "Godot::Object" ? parent : (parent.starts_with?("Godot::") ? parent : "Godot::#{parent}")

          class_doc_parts = [] of String
          if brief = c["brief_description"]?.try(&.as_s.strip)
            class_doc_parts << brief unless brief.empty?
          end
          if desc = c["description"]?.try(&.as_s.strip)
            if !desc.empty? && !class_doc_parts.includes?(desc)
              class_doc_parts << desc
            end
          end
          full_class_doc = class_doc_parts.join("\n\n")
          if !full_class_doc.empty?
            io.print format_doc_comment(full_class_doc, indent: "  ")
          end

          if name == "Object"
            io.puts "  class Object"
            io.puts "    def initialize(@pointer : Void* = Pointer(Void).null)"
            io.puts "      if !@pointer.null?"
            io.puts "        @instance_id = Bridge.object_get_instance_id(@pointer)"
            io.puts "      end"
            io.puts "    end\n"
          else
            io.puts "  class #{name} < #{parent_type}"
            io.puts "    def initialize(pointer : Void* = Pointer(Void).null)"
            io.puts "      super(pointer)"
            io.puts "    end\n"
          end

          if enums = c["enums"]?
            enums.as_a.each do |e|
              e_name = e["name"].as_s
              next if e_name.empty?
              if e_doc = e["description"]?.try(&.as_s.strip)
                io.print format_doc_comment(e_doc, indent: "    ")
              end
              io.puts "    enum #{e_name} : Int64"
              if values = e["values"]?
                values.as_a.each do |v|
                  val_name = v["name"].as_s
                  parts = val_name.split('_')
                  camel_val = parts.map(&.capitalize).join
                  camel_val = "Val#{camel_val}" if camel_val.starts_with?(/[0-9]/)
                  val_num = v["value"].as_i64
                  io.puts "      #{camel_val} = #{val_num}_i64"
                end
              end
              io.puts "    end\n"
            end
          end

          if methods = c["methods"]?
            methods.as_a.each do |m|
              m_name = m["name"].as_s
              next if m["is_virtual"]?.try(&.as_bool)
              next if m["is_vararg"]?.try(&.as_bool)
              hash_val = m["hash"]?.try(&.as_i64) || 0_i64
              sanitized_m_name = sanitize_name(m_name, keywords)

              args = m["arguments"]?.try(&.as_a) || [] of JSON::Any
              arg_defs = [] of String

              args.each_with_index do |a, idx|
                raw_a_name = a["name"].as_s
                a_name = sanitize_name(raw_a_name, keywords)
                a_type = crystal_type_name(a["type"].as_s, type_map)
                arg_defs << "#{a_name} : #{a_type}"
              end

              ret_data = m["return_value"]?
              ret_type_godot = ret_data ? ret_data["type"].as_s : "void"
              ret_type_crystal = crystal_type_name(ret_type_godot, type_map)

              clean_var_name = m_name.gsub(/[^a-zA-Z0-9_]/, "_")
              io.puts "    @@mb_#{clean_var_name} : Void* = Pointer(Void).null"
              if m_doc = m["description"]?.try(&.as_s.strip)
                io.print format_doc_comment(m_doc, indent: "    ")
              end
              io.puts "    def #{sanitized_m_name}(#{arg_defs.join(", ")}) : #{ret_type_crystal}"
              io.puts "      if @@mb_#{clean_var_name}.null?"
              io.puts "        @@mb_#{clean_var_name} = Bridge.get_method_bind(\"#{name}\", \"#{m_name}\", #{hash_val}_i64)"
              io.puts "      end"

              cleanups = [] of String
              args_expr = if args.empty?
                "Pointer(Pointer(Void)).null"
              else
                args.each_with_index do |a, idx|
                  raw_a_name = a["name"].as_s
                  a_name = sanitize_name(raw_a_name, keywords)
                  a_type = crystal_type_name(a["type"].as_s, type_map)
                  godot_type = a["type"].as_s
                  if class_names.includes?(godot_type) || a_type.starts_with?("Godot::") || ["Node", "Resource", "SceneTree", "Object", "Mesh"].includes?(a_type)
                    io.puts "      arg_ptr_#{idx} = #{a_name} ? #{a_name}.pointer : Pointer(Void).null"
                    io.puts "      arg_#{idx} = pointerof(arg_ptr_#{idx}).as(Void*)"
                  elsif godot_type == "String"
                    io.puts "      str_#{idx} = Bridge.make_string(#{a_name})"
                    io.puts "      arg_#{idx} = str_#{idx}"
                    cleanups << "Bridge.free_string(str_#{idx})"
                  elsif godot_type == "StringName"
                    io.puts "      sn_#{idx} = Bridge.make_string_name(#{a_name})"
                    io.puts "      arg_#{idx} = sn_#{idx}"
                    cleanups << "Bridge.free_string_name(sn_#{idx})"
                  else
                    io.puts "      val_#{idx} = #{a_name}"
                    io.puts "      arg_#{idx} = pointerof(val_#{idx}).as(Void*)"
                  end
                end
                arg_names = (0...args.size).map { |i| "arg_#{i}" }
                io.puts "      args = [#{arg_names.join(", ")}]"
                "args.to_unsafe.as(Void**)"
              end

              if ret_type_crystal == "Void"
                io.puts "      Bridge.ptrcall(@@mb_#{clean_var_name}, @pointer, #{args_expr}, Pointer(Void).null)"
              elsif ret_type_crystal == "Bool"
                io.puts "      ret = 0_u8"
                io.puts "      Bridge.ptrcall(@@mb_#{clean_var_name}, @pointer, #{args_expr}, pointerof(ret).as(Void*))"
                io.puts "      ret != 0_u8"
              elsif ret_type_crystal == "Int64" || ret_type_crystal == "Int32"
                io.puts "      ret = 0_i64"
                io.puts "      Bridge.ptrcall(@@mb_#{clean_var_name}, @pointer, #{args_expr}, pointerof(ret).as(Void*))"
                io.puts "      ret"
              elsif ret_type_crystal == "Float64" || ret_type_crystal == "Float32"
                io.puts "      ret = 0.0_f64"
                io.puts "      Bridge.ptrcall(@@mb_#{clean_var_name}, @pointer, #{args_expr}, pointerof(ret).as(Void*))"
                io.puts "      ret"
              elsif ret_type_crystal == "Vector2"
                io.puts "      ret = Vector2.new"
                io.puts "      Bridge.ptrcall(@@mb_#{clean_var_name}, @pointer, #{args_expr}, pointerof(ret).as(Void*))"
                io.puts "      ret"
              elsif ret_type_crystal == "Vector3"
                io.puts "      ret = Vector3.new"
                io.puts "      Bridge.ptrcall(@@mb_#{clean_var_name}, @pointer, #{args_expr}, pointerof(ret).as(Void*))"
                io.puts "      ret"
              elsif ret_type_crystal == "Color"
                io.puts "      ret = Color.new"
                io.puts "      Bridge.ptrcall(@@mb_#{clean_var_name}, @pointer, #{args_expr}, pointerof(ret).as(Void*))"
                io.puts "      ret"
              elsif ret_type_crystal == "Transform3D"
                io.puts "      ret = Transform3D.new"
                io.puts "      Bridge.ptrcall(@@mb_#{clean_var_name}, @pointer, #{args_expr}, pointerof(ret).as(Void*))"
                io.puts "      ret"
              elsif ret_type_crystal == "Void*" || ret_type_crystal == "Pointer(Void)"
                if ret_type_godot == "Variant"
                  io.puts "      ret_var = StaticArray(UInt8, 24).new(0_u8)"
                  io.puts "      Bridge.ptrcall(@@mb_#{clean_var_name}, @pointer, #{args_expr}, ret_var.to_unsafe.as(Void*))"
                  io.puts "      ret_ptr = Pointer(Void).null"
                  io.puts "      Bridge.type_from_variant(24, pointerof(ret_ptr).as(Void*), ret_var.to_unsafe.as(Void*))"
                  io.puts "      ret_ptr"
                else
                  io.puts "      ret_ptr = Pointer(Void).null"
                  io.puts "      Bridge.ptrcall(@@mb_#{clean_var_name}, @pointer, #{args_expr}, pointerof(ret_ptr).as(Void*))"
                  io.puts "      ret_ptr"
                end
              elsif ret_type_crystal == "String"
                io.puts "      \"\""
              else
                io.puts "      ret_ptr = Pointer(Void).null"
                io.puts "      Bridge.ptrcall(@@mb_#{clean_var_name}, @pointer, #{args_expr}, pointerof(ret_ptr).as(Void*))"
                io.puts "      #{ret_type_crystal}.new(ret_ptr)"
              end

              if !cleanups.empty?
                io.puts "    ensure"
                cleanups.each do |c|
                  io.puts "      #{c}"
                end
              end

              io.puts "    end\n"
            end
          end

          if props = c["properties"]?.try(&.as_a)
            existing_methods = Set(String).new
            c["methods"]?.try(&.as_a.each { |m| existing_methods.add(sanitize_name(m["name"].as_s, keywords)) })

            props.each do |p|
              raw_p_name = p["name"].as_s
              next if raw_p_name.empty? || raw_p_name.includes?("/")
              clean_p_name = sanitize_name(raw_p_name, keywords)
              next if existing_methods.includes?(clean_p_name)

              raw_setter = p["setter"]?.try(&.as_s) || ""
              raw_getter = p["getter"]?.try(&.as_s) || ""
              index = p["index"]?
              has_index = index && !index.raw.nil? && !index.to_s.empty?
              index_val = has_index ? "#{index}_i64" : ""

              resolved_getter = if all_method_names.includes?(raw_getter)
                raw_getter
              elsif raw_getter.starts_with?("_") && all_method_names.includes?(raw_getter.lstrip('_'))
                raw_getter.lstrip('_')
              else
                nil
              end

              resolved_setter = if all_method_names.includes?(raw_setter)
                raw_setter
              elsif raw_setter.starts_with?("_") && all_method_names.includes?(raw_setter.lstrip('_'))
                raw_setter.lstrip('_')
              else
                nil
              end

              clean_getter = resolved_getter ? sanitize_name(resolved_getter, keywords) : nil
              clean_setter = resolved_setter ? sanitize_name(resolved_setter, keywords) : nil
              p_type = p["type"].as_s
              class_manuals = manual_methods[name]?

              if clean_getter
                has_manual_getter = class_manuals && (class_manuals.includes?(clean_p_name) || class_manuals.includes?("#{clean_p_name}?"))
                if !has_manual_getter
                  io.puts "    # Property `#{raw_p_name}` getter"
                  if has_index
                    io.puts "    def #{clean_p_name}"
                    io.puts "      #{clean_getter}(#{index_val})"
                    io.puts "    end\n"
                  else
                    io.puts "    def #{clean_p_name}"
                    io.puts "      #{clean_getter}"
                    io.puts "    end\n"
                  end

                  if p_type == "bool" || raw_getter.starts_with?("is_") || raw_getter.starts_with?("has_")
                    io.puts "    def #{clean_p_name}?"
                    io.puts "      #{clean_p_name}"
                    io.puts "    end\n"
                  end
                end
              end

              if clean_setter
                has_manual_setter = class_manuals && class_manuals.includes?("#{clean_p_name}=")
                if !has_manual_setter
                  io.puts "    # Property `#{raw_p_name}` setter"
                  if p_type == "float"
                    if has_index
                      io.puts "    def #{clean_p_name}=(val : Number)"
                      io.puts "      #{clean_setter}(#{index_val}, val.to_f64)"
                      io.puts "    end\n"
                    else
                      io.puts "    def #{clean_p_name}=(val : Number)"
                      io.puts "      #{clean_setter}(val.to_f64)"
                      io.puts "    end\n"
                    end
                  elsif p_type == "int"
                    if has_index
                      io.puts "    def #{clean_p_name}=(val : Int)"
                      io.puts "      #{clean_setter}(#{index_val}, val.to_i64)"
                      io.puts "    end\n"
                    else
                      io.puts "    def #{clean_p_name}=(val : Int)"
                      io.puts "      #{clean_setter}(val.to_i64)"
                      io.puts "    end\n"
                    end
                  else
                    if has_index
                      io.puts "    def #{clean_p_name}=(val)"
                      io.puts "      #{clean_setter}(#{index_val}, val)"
                      io.puts "    end\n"
                    else
                      io.puts "    def #{clean_p_name}=(val)"
                      io.puts "      #{clean_setter}(val)"
                      io.puts "    end\n"
                    end
                  end
                end
              end
            end
          end

          io.puts "  end\n"
        end

        def self.generate(
          api_path : Path? = nil,
          output_dir : Path? = nil,
          overrides_path : Path? = nil,
          dump_api : Bool = false
        ) : Int32
          root = Core::Env::ROOT_DIR

          out_dir = output_dir || root.join("src/libgodot/generated")
          classes_out_dir = out_dir.join("classes")

          # Locate or dump extension_api.json
          api_file = api_path || [
            root.join("extension_api.json"),
            root.join("rsrc/extension_api.json"),
          ].find { |p| File.exists?(p) }

          if dump_api || api_file.nil? || !File.exists?(api_file)
            godot_exe = Core::GodotFinder.resolve
            if godot_exe.nil?
              Core::Logger.error("Godot executable not found to dump extension_api.json!")
              return 1
            end

            Core::Logger.step("Bind:Engine", "Dumping GDExtension API from #{godot_exe}...")
            dump_res = Core::ProcessRunner.run(
              godot_exe,
              ["--headless", "--dump-extension-api"],
              chdir: root.to_s
            )
            if dump_res != 0
              Core::Logger.error("Failed to dump extension_api.json from Godot engine.")
              return 1
            end
            api_file = root.join("extension_api.json")
          end

          unless File.exists?(api_file)
            Core::Logger.error("API definition file not found: #{api_file}")
            return 1
          end

          Core::Logger.step("Bind:Engine", "Loading #{api_file}...")
          api_json = File.read(api_file)
          api_data = JSON.parse(api_json)

          # Load overrides
          ov_file = overrides_path || [
            root.join("tools/api_generator/overrides.yml"),
            root.join("scripts/overrides.yml"),
          ].find { |p| File.exists?(p) }

          overrides = if ov_file && File.exists?(ov_file)
            YAML.parse(File.read(ov_file))
          else
            YAML.parse("{}")
          end

          keywords = Hash(String, String).new
          if kw = overrides["keywords"]?
            kw.as_h.each { |k, v| keywords[k.to_s] = v.to_s }
          end

          type_map = Hash(String, String).new
          if tm = overrides["type_map"]?
            tm.as_h.each { |k, v| type_map[k.to_s] = v.to_s }
          end

          FileUtils.mkdir_p(out_dir)
          FileUtils.mkdir_p(classes_out_dir)

          # 1. Global Enums
          Core::Logger.step("Bind:Engine", "Generating global enums -> #{out_dir.join("global_enums.cr")}...")
          File.open(out_dir.join("global_enums.cr"), "w") do |f|
            f.puts "# Generated Global Enums for Godot 4.8+"
            f.puts "module Godot"
            if global_enums = api_data["global_enums"]?
              global_enums.as_a.each do |e|
                raw_enum_name = e["name"].as_s
                enum_name = raw_enum_name.starts_with?("Variant.") ? raw_enum_name.gsub("Variant.", "") : raw_enum_name
                next if enum_name.empty?

                f.puts "  # Godot `#{enum_name}` global enum."
                f.puts "  enum #{enum_name} : Int64"
                enum_prefix = "#{enum_name.underscore.upcase}_"
                alt_prefix = "#{enum_name.upcase}_"
                if values = e["values"]?
                  values.as_a.each do |v|
                    val_name = v["name"].as_s
                    clean_val = if val_name.starts_with?(enum_prefix)
                      val_name[enum_prefix.size..]
                    elsif val_name.starts_with?(alt_prefix)
                      val_name[alt_prefix.size..]
                    else
                      val_name
                    end
                    parts = clean_val.split('_')
                    camel_val = parts.map(&.capitalize).join
                    camel_val = "Val#{camel_val}" if camel_val.starts_with?(/[0-9]/)
                    camel_val = "None" if camel_val.empty?
                    val_num = v["value"].as_i64
                    f.puts "    #{camel_val} = #{val_num}_i64"
                  end
                end
                f.puts "  end\n"
              end
            end
            f.puts "end"
          end

          # 2. Singletons
          Core::Logger.step("Bind:Engine", "Generating singletons -> #{out_dir.join("singletons.cr")}...")
          File.open(out_dir.join("singletons.cr"), "w") do |f|
            f.puts "# Generated Singletons for Godot 4.8+"
            f.puts "module Godot"
            if singletons = api_data["singletons"]?
              singletons.as_a.each do |s|
                s_name = s["name"].as_s
                s_type = s["type"]?.try(&.as_s) || s_name
                parent_type = s_name == "GDScriptLanguageProtocol" ? "Godot::JSONRPC" : "Godot::Object"
                f.puts "  # Godot `#{s_name}` singleton (#{s_type})."
                f.puts "  class #{s_name} < #{parent_type}"
                f.puts "    @@instance : Void* = Pointer(Void).null"
                f.puts "    def self.singleton_ptr : Void*"
                f.puts "      if @@instance.null?"
                f.puts "        @@instance = Bridge.get_singleton(\"#{s_name}\")"
                f.puts "      end"
                f.puts "      @@instance"
                f.puts "    end"
                f.puts "  end\n"
              end
            end
            f.puts "end"
          end

          # 3. Classes (Topological Sort)
          classes = api_data["classes"].as_a.reject do |c|
            api_type = c["api_type"]?.try(&.as_s)
            api_type == "extension" || api_type == "editor_extension"
          end

          class_map = Hash(String, JSON::Any).new
          inherits_map = Hash(String, String?).new
          classes.each do |c|
            name = c["name"].as_s
            class_map[name] = c
            inherits_map[name] = c["inherits"]?.try(&.as_s)
          end

          visited = Set(String).new
          sorted_classes = Array(JSON::Any).new

          class_map.keys.each do |name|
            visit(name, class_map, inherits_map, visited, sorted_classes)
          end

          Core::Logger.step("Bind:Engine", "Generating #{sorted_classes.size} classes topologically...")

          class_names = Set(String).new
          class_map.keys.each { |k| class_names.add(k) }

          all_method_names = Set(String).new
          classes.each do |c|
            c["methods"]?.try(&.as_a.each { |m| all_method_names.add(m["name"].as_s) })
          end

          manual_methods = Hash(String, Set(String)).new
          [root.join("src/libgodot/object.cr"), root.join("src/lapis.cr")].each do |manual_file|
            next unless File.exists?(manual_file)
            curr_class : String? = nil
            File.each_line(manual_file) do |line|
              if line =~ /^\s*class\s+([A-Za-z0-9_]+)/
                curr_class = $1
                manual_methods[curr_class] ||= Set(String).new
              elsif curr_class
                if line =~ /^\s*(?:def|property|getter|setter)\??\s+([A-Za-z0-9_]+[=?]?)/
                  m_ident = $1
                  manual_methods[curr_class].add(m_ident)
                  manual_methods[curr_class].add("#{m_ident}=") unless m_ident.ends_with?("=")
                end
              end
            end
          end

          num_parts = 6
          chunk_size = (sorted_classes.size.to_f / num_parts).ceil.to_i
          total_chunked = 0

          num_parts.times do |part_idx|
            start_idx = part_idx * chunk_size
            end_idx = Math.min((part_idx + 1) * chunk_size, sorted_classes.size)
            part_classes = sorted_classes[start_idx...end_idx]
            total_chunked += part_classes.size
            part_num = part_idx + 1

            out_part_file = classes_out_dir.join("classes_part#{part_num}.cr")
            File.open(out_part_file, "w") do |f|
              f.puts "# Generated classes part #{part_num} (in topological order)"
              f.puts "module Godot"
              part_classes.each do |c|
                generate_class_code(f, c, keywords, type_map, class_names, all_method_names, manual_methods)
              end
              f.puts "end"
            end
          end

          # 4. Master index
          master_file = classes_out_dir.join("all_classes.cr")
          File.open(master_file, "w") do |f|
            f.puts "# Master index requiring all classes in topological dependency order"
            num_parts.times do |part_idx|
              f.puts "require \"./classes_part#{part_idx + 1}\""
            end
          end

          Core::Logger.success("Engine bindings generated successfully (#{total_chunked} classes) in #{out_dir}!")
          0
        end
      end
    end
  end
end
