extends Node2D

@onready var menu_scene: PackedScene = preload("res://scenes/main_menu.tscn")
@onready var main_scene: PackedScene = preload("res://scenes/player_character_creator_scene.tscn")

var current_scene: Node = null

func _ready() -> void:
	_switch_to(menu_scene)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _switch_to(scene: PackedScene) -> void:
	if current_scene:
		current_scene.queue_free()
	current_scene = scene.instantiate()
	add_child(current_scene)
