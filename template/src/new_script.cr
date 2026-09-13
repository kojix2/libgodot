require "libgodot"

# new_script node
node NewScript < Node do
  def _ready : Void
	Godot.print("new_script initialized")
  end

  def _process(delta : Float64) : Void

  end
end
