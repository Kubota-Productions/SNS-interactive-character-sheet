extends Control

@onready var scroll_container: ScrollContainer = $ScrollContainer
@onready var v_box_container: VBoxContainer = $ScrollContainer/VBoxContainer
@onready var warning_dialog: AcceptDialog = $VBoxContainer/LoadASheet/AcceptDialog
var selected_save_file: String = ""

# Keep a reference to the settings scene instance if added
var settings_instance: Node = null

func _enter_tree() -> void:
	list_save_files()

func _on_load_a_sheet_pressed() -> void:
	if selected_save_file != "":
		get_parent()._switch_to(preload("res://scenes/main_scene.tscn"))
	else:
		warning_dialog.popup_centered()

func _on_add_a_sheet_pressed() -> void:
	await GlobalFunctions.new_player()
	get_parent()._switch_to(preload("res://scenes/main_scene.tscn"))

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
			if file_name != "." and file_name != ".." and !dir.current_is_dir() and file_name.rfind("0savedata.json") > 0:
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
		button.text = save_file.replace("user://","").replace("0savedata.json","")
		$ScrollContainer/VBoxContainer.add_child(button)

		# Connect to select this file when pressed
		button.pressed.connect(func():
			selected_save_file = save_file
			GlobalFunctions.set_player_name(selected_save_file.replace("user://","").replace("0savedata.json","")))
		print("Selected file:", selected_save_file)
	


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
		var file_path_png = str(file_path.replace("user://","").replace("0savedata.json","")+"_appearance.png")
		if dir.file_exists(file_path_png):
			var error = dir.remove(file_path_png)
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

func _on_website_pressed() -> void:
	OS.shell_open("https://synesthesiasynthetica.com/")

func _on_socials_pressed() -> void:
	OS.shell_open("https://bsky.app/profile/kubotaproductions.bsky.social")

func _on_join_the_discord_pressed() -> void:
	OS.shell_open("https://discord.gg/4Mmxzm8sGX")

func _on_itch_io_pressed() -> void:
	OS.shell_open("https://kubota-productions.itch.io/sns")

func _on_drivethrurpg_pressed() -> void:
	OS.shell_open("https://www.drivethrurpg.com/en/product/504031/sns-1-7-synesthesia-synthetica.")
	
func _on_open_folder_pressed() -> void:
	var folder_path = OS.get_user_data_dir()
	print("Opening save folder:", folder_path)
	OS.shell_open(folder_path)
	
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		# Reload save files when the player returns to the game
		print("Game regained focus, refreshing save files...")
		list_save_files()
