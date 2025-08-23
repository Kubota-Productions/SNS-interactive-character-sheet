extends TextureButton

var was_just_editing = true
@export var index = 1 
var player_name = GlobalFunctions.return_player_name()

func _enter_tree() -> void:
	button_pressed = false
	var file = FileAccess.open(str("user://"+player_name+"0savedata.json"),FileAccess.READ)
	if file:
		var all_data :Array[String]
		all_data = file.get_var()
		if all_data[index] == "true":
			button_pressed = true

func _on_toggled(toggled_on: bool) -> void:
	GlobalFunctions.store_data(index,(str(toggled_on)))
