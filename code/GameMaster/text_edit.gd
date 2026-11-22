extends TextEdit

@export var index: int = 1

func _ready() -> void:
	text = GlobalFunctions.storyteller.get_text(index)

func _on_text_changed() -> void:
	GlobalFunctions.storyteller.set_text(index, text)
