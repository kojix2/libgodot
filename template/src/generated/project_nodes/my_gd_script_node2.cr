# Generated strongly typed wrapper for GDScript node `MyGDScriptNode2`
# Script Path: res://src/new_script2.gd
module Godot
  class MyGDScriptNode2 < Godot::Node
    # Wrap a native pointer to an existing MyGDScriptNode2 instance
    def initialize(pointer : Void* = Pointer(Void).null)
      super(pointer)
    end
    # Helper to wrap any Godot node into a typed MyGDScriptNode2
    def self.from(node : Godot::Object) : self
      new(node.pointer)
    end
    # Property `this_is_new_var` (Int64)
    def this_is_new_var : Int64
      call_i64("get", "this_is_new_var")
    end
    def this_is_new_var=(val) : Void
      call("set", "this_is_new_var", val)
    end
  end
end

alias MyGDScriptNode2 = Godot::MyGDScriptNode2
