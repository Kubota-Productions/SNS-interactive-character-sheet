extends LineEdit

func _enter_tree() -> void:
	text = GlobalFunctions.storyteller.storyteller_name

func _on_editing_toggled(toggled_on: bool) -> void:
	if not toggled_on:
		text = GlobalFunctions.rename_storyteller(text)
