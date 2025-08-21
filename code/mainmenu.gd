extends Control

@onready var scroll_container: ScrollContainer = $ScrollContainer
@onready var v_box_container: VBoxContainer = $ScrollContainer/VBoxContainer

func _on_load_a_sheet_pressed() -> void:
	get_parent()._switch_to(preload("res://scenes/main_scene.tscn"))

func _enter_tree() -> void:
	list_save_files()

func list_save_files():
	var save_files: Array = []
	var dir = DirAccess.open("user://")
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name != "." and file_name != ".." and !dir.current_is_dir():
				save_files.append(file_name)
				print("Found file:", file_name)
			file_name = dir.get_next()
		dir.list_dir_end()
	else:
		print("Failed to open user folder.")
	
	show_save_files(save_files)

func _on_add_a_sheet_pressed() -> void:
	pass # Replace with function body.
	
func _on_delete_a_sheet_pressed() -> void:
	pass # Replace with function body.

func _on_exit_pressed() -> void:
	get_tree().quit()
	
func show_save_files(save_files):
	if save_files: 
		for save_file in save_files:
			var button = Button.new()
			button.text = save_file  # properly set the button label
			$ScrollContainer/VBoxContainer.add_child(button)
