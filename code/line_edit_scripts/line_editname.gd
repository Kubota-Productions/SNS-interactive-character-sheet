extends LineEdit

var was_just_editing = true
var player_name = GlobalFunctions.return_player_name()
# Called when the node enters the scene tree for the first time.
func _enter_tree() -> void:
	self.text = player_name

func _on_editing_toggled(toggled_on: bool) -> void:
	if toggled_on == true:
		was_just_editing = true
	if toggled_on == false:
		if was_just_editing == true:
			GlobalFunctions.player_name = self.text
			was_just_editing = false
