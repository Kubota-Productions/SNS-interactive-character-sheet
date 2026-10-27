extends Node2D

func _enter_tree() -> void:
	if GlobalFunctions.storyteller == null:
		GlobalFunctions.new_storyteller()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		GlobalFunctions.flush()
		SettingsMenu.toggle(get_tree())
