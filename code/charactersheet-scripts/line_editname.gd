extends LineEdit

func _enter_tree() -> void:
	text = GlobalFunctions.character.character_name

func _on_editing_toggled(toggled_on: bool) -> void:
	if not toggled_on:
		# Shows the name that was actually applied (reverts if empty or already taken)
		text = GlobalFunctions.rename_character(text)
