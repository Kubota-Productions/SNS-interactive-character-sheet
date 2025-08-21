extends Node2D

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		# Use the preloaded reference in GameRoot
		get_node("/root/GameRoot")._switch_to(get_node("/root/GameRoot").menu_scene)


""
