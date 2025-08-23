extends TextEdit
var was_just_editing = true
@export var index = 1 
var player_name = GlobalFunctions.return_player_name()

func _enter_tree() -> void:
	var file = FileAccess.open(str("user://"+player_name+"0savedata.json"),FileAccess.READ)
	if file:
		var all_data :Array[String]
		all_data = file.get_var()
		self.text = all_data[index]

func _on_text_changed() -> void:
			GlobalFunctions.store_data(index,(self.text))
