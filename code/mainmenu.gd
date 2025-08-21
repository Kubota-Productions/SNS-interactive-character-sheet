extends Control

func _on_start_pressed() -> void:
	get_parent()._switch_to(preload("res://scenes/main_scene.tscn"))

func _on_options_pressed() -> void:
	print("Options pressed")

func _on_exit_pressed() -> void:
	get_tree().quit()
