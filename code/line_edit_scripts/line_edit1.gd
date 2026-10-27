extends LineEdit

@export var index: int = 1

func _ready() -> void:
	text = GlobalFunctions.character.get_text(index)

func _on_editing_toggled(toggled_on: bool) -> void:
	if not toggled_on:
		GlobalFunctions.character.set_text(index, text)
