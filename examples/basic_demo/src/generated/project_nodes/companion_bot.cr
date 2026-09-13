# Generated strongly typed wrapper for GDScript node `CompanionBot`
# Script Path: res://scripts/companion.gd
module Godot
  class CompanionBot < Godot::Node
    # Wrap a native pointer to an existing CompanionBot instance
    def initialize(pointer : Void* = Pointer(Void).null)
      super(pointer)
    end
    # Helper to wrap any Godot node into a typed CompanionBot
    def self.from(node : Godot::Object) : self
      new(node.pointer)
    end
    # Property `companion_name` (String)
    def companion_name : String
      call_str("get", "companion_name")
    end
    def companion_name=(val) : Void
      call("set", "companion_name", val)
    end
    # Property `bonus_multiplier` (Float64)
    def bonus_multiplier : Float64
      call_f64("get", "bonus_multiplier")
    end
    def bonus_multiplier=(val) : Void
      call("set", "bonus_multiplier", val)
    end
    # Property `interaction_count` (Int64)
    def interaction_count : Int64
      call_i64("get", "interaction_count")
    end
    def interaction_count=(val) : Void
      call("set", "interaction_count", val)
    end
    # Method `calculate_bonus` -> Int64
    def calculate_bonus(score : Int64) : Int64
      call_i64("calculate_bonus", score)
    end
    # Method `get_system_status` -> String
    def get_system_status() : String
      call_str("get_system_status")
    end
    # Method `cheer` -> String
    def cheer(current_score : Int64) : String
      call_str("cheer", current_score)
    end
    # Method `praise_player` -> String
    def praise_player(player_name : String) : String
      call_str("praise_player", player_name)
    end
  end
end

alias CompanionBot = Godot::CompanionBot
