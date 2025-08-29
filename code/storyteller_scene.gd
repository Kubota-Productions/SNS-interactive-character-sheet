extends Node2D

var settings_instance: Node = null

func _enter_tree() -> void:
	print("LOADING SAVE DATA to -> GlobalFunctions.data");
	GlobalFunctions.st_update_data(); #Load data to global array to be used by the components

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		GlobalFunctions.st_update_data()
		
		var game_root = get_tree().root  # Adjust if you want it under a specific node
		
		if settings_instance == null:
			# Load and instantiate the settings scene
			var settings_scene = preload("res://scenes/player_character_creator_scene_settings.tscn")
			settings_instance = settings_scene.instantiate()
			game_root.add_child(settings_instance)
		else:
			# If already exists, remove it
			if settings_instance.is_inside_tree():
				settings_instance.queue_free()
			settings_instance = null
