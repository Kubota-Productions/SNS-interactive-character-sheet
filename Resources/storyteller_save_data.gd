class_name StorytellerSaveData
extends Resource

const CURRENT_VERSION := 1

@export var version: int = CURRENT_VERSION
@export var storyteller_name: String = ""
@export var texts: Dictionary[int, String] = {}


func get_text(index: int) -> String:
	return texts[index] if texts.has(index) else ""

func set_text(index: int, value: String) -> void:
	if get_text(index) == value:
		return
	if value.is_empty():
		texts.erase(index)
	else:
		texts[index] = value
	emit_changed()
