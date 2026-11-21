extends Node2D

const MENU_SCENE := "res://scenes/main_menu.tscn"

var current_scene: Node = null

func _ready() -> void:
	_switch_to(load(MENU_SCENE))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _switch_to(scene: PackedScene) -> void:
	if scene == null:
		push_error("Scene failed to load, staying on the current screen.")
		return
	if current_scene:
		current_scene.queue_free()
	current_scene = scene.instantiate()
	add_child(current_scene)
