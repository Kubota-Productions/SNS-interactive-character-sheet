extends Control

var previous_window_size: Vector2i = Vector2i(1152, 648) # default fallback

func _ready() -> void:
	# store the current window size at start
	previous_window_size = DisplayServer.window_get_size()
	

func _on_volume_value_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(0,value)


func _on_mute_toggled(toggled_on: bool) -> void:
	AudioServer.set_bus_mute(0,toggled_on)


func _on_resolutions_item_selected(index: int) -> void:
	DisplayServer.window_set_mode(0) 

	match index:
		0:
			DisplayServer.window_set_size(Vector2i(2560, 1440))
		1:
			DisplayServer.window_set_size(Vector2i(1920, 1080))
		2:
			DisplayServer.window_set_size(Vector2i(1366, 768))
		3:
			DisplayServer.window_set_size(Vector2i(1280, 720))
		4:
			DisplayServer.window_set_size(Vector2i(1920, 1200))
		5:
			DisplayServer.window_set_size(Vector2i(1680, 1050))
		6:
			DisplayServer.window_set_size(Vector2i(1440, 900))
		7:
			DisplayServer.window_set_size(Vector2i(1280, 800))
		8:
			DisplayServer.window_set_size(Vector2i(1024, 768))
		9:
			DisplayServer.window_set_size(Vector2i(800, 600))
		10:
			DisplayServer.window_set_size(Vector2i(640, 480))

func _on_exit_button_pressed() -> void:
	queue_free()


func _on_fullscreen_toggled(toggled_on: bool) -> void:
	if toggled_on:
		# Save window size before going fullscreen
		previous_window_size = DisplayServer.window_get_size()
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(previous_window_size)

func _on_graphics_item_selected(_index: int) -> void:
	pass # Replace with function body.

func _on_back_to_menu_button_pressed() -> void:
	queue_free()
	get_tree().change_scene_to_file("res://scenes/game_root.tscn")
	
