extends TextEdit

@export var index: int = 1

func _ready() -> void:
	text = GlobalFunctions.gamemaster.get_text(index)

func _on_text_changed() -> void:
	GlobalFunctions.gamemaster.set_text(index, text)
