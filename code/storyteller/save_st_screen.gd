extends LineEdit

var was_just_editing = true
var st_name = GlobalFunctions.return_st_name()
# Called when the node enters the scene tree for the first time.
func _enter_tree() -> void:
	self.text = st_name

func _on_editing_toggled(toggled_on: bool) -> void:
	if toggled_on == true:
		was_just_editing = true
	if toggled_on == false:
		if was_just_editing == true:
			GlobalFunctions.st_name = self.text
			GlobalFunctions.st_store_data_all()
			was_just_editing = false
