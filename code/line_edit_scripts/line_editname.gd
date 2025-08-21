extends LineEdit

var player_name = GlobalFunctions.return_player_name()
# Called when the node enters the scene tree for the first time.
func _enter_tree() -> void:
	self.text = player_name
