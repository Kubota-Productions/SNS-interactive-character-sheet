extends Node2D

func _enter_tree() -> void:
	if GlobalFunctions.gamemaster == null:
		GlobalFunctions.new_gamemaster()

func _ready() -> void:
	# Shows every connected player's character sheet on this screen (live, view only).
	var sheet_wall = load("res://code/gm_sheet_wall.gd")
	if sheet_wall != null:
		add_child(sheet_wall.new())

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		GlobalFunctions.flush()
		SettingsMenu.toggle(get_tree())
