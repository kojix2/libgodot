require "libgodot"

# new_script node
node MyNode < Node do
  @[Export]
  property my_int : Int32 = 0

  def _ready : Void
	Godot.print("new_script initialized")
  end

  def _process(delta : Float64) : Void
  end
end
