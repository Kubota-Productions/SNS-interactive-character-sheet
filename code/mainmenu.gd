extends Control

@onready var scroll_container: ScrollContainer = $ScrollContainer
@onready var v_box_container: VBoxContainer = $ScrollContainer/VBoxContainer
var selected_save_file: String = ""

# Keep a reference to the settings scene instance if added
var settings_instance: Node = null


func _enter_tree() -> void:
	list_save_files()


func _on_load_a_sheet_pressed() -> void:
	get_parent()._switch_to(preload("res://scenes/main_scene.tscn"))


func _on_add_a_sheet_pressed() -> void:
	pass # Replace with function body.


func _on_delete_a_sheet_pressed() -> void:
	if selected_save_file != "":
		delete_save_file(selected_save_file)
		selected_save_file = ""  # reset selection
	else:
		print("No file selected to delete.")


func _on_options_pressed() -> void:
	var game_root = get_tree().root # adjust if nested deeper
	if settings_instance == null:
			var settings_scene = preload("res://scenes/settings.tscn")
			settings_instance = settings_scene.instantiate()
			game_root.add_child(settings_instance)
	else:
		if settings_instance and settings_instance.is_inside_tree():
			settings_instance.queue_free()
			settings_instance = null


func _on_exit_pressed() -> void:
	get_tree().quit()


func list_save_files() -> void:
	# Clear existing buttons
	for child in $ScrollContainer/VBoxContainer.get_children():
		child.queue_free()

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


func show_save_files(save_files: Array) -> void:
	for save_file in save_files:
		var button = Button.new()
		button.text = save_file
		$ScrollContainer/VBoxContainer.add_child(button)

		# Connect to select this file when pressed
		button.pressed.connect(func():
			selected_save_file = save_file
			print("Selected file:", selected_save_file)
		)


func delete_save_file(file_name: String) -> void:
	var dir = DirAccess.open("user://")
	if dir:
		var file_path = "user://" + file_name
		if dir.file_exists(file_path):
			var error = dir.remove(file_path)
			if error == OK:
				print("Deleted file:", file_name)
				# Refresh the buttons after deletion
				list_save_files()
			else:
				print("Failed to delete file:", file_name, "Error code:", error)
		else:
			print("File does not exist:", file_name)
	else:
		print("Failed to open user folder.")
