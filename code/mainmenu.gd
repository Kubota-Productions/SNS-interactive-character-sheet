extends Control

func _on_load_a_sheet_pressed() -> void:
	get_parent()._switch_to(preload("res://scenes/main_scene.tscn"))

func _on_add_a_sheet_pressed() -> void:
	pass # Replace with function body.
	
func _on_delete_a_sheet_pressed() -> void:
	pass # Replace with function body.

func _on_exit_pressed() -> void:
	get_tree().quit()



	
