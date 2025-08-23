extends Node2D

# Enter Tree -> loads the save data BEFORE the rest of the elements seek the Global Data array.
func _enter_tree() -> void:
	print("LOADING SAVE DATA to -> GlobalFunctions.data");
	GlobalFunctions._update_data(); #Load data to global array to be used by the components

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		GlobalFunctions._update_data()
		# Use the preloaded reference in GameRoot
		get_node("/root/GameRoot")._switch_to(get_node("/root/GameRoot").menu_scene)


func _on_texture_button_5_toggled(toggled_on: bool) -> void:
	pass # Replace with function body.


func _on_texture_button_6_toggled(toggled_on: bool) -> void:
	pass # Replace with function body.
