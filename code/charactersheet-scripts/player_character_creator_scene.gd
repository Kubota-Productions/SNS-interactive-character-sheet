extends Node2D

func _enter_tree() -> void:
	# The menu normally loads/creates the sheet before switching here.
	# This fallback lets you run the scene on its own with F6.
	if GlobalFunctions.character == null:
		GlobalFunctions.new_character()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		GlobalFunctions.flush()
		SettingsMenu.toggle(get_tree())
