extends Control
#region character sheet variables
@onready var scroll_container: ScrollContainer = $ScrollContainerplayer
@onready var v_box_container: VBoxContainer = $ScrollContainerplayer/HBoxContainer
@onready var warning_dialog_character: AcceptDialog = $VBoxContainer/HBoxContainer/VBoxContainerplayer/LoadASheet/AcceptDialog
var selected_save_file: String = ""
var selected_save_file_storyteller: String = ""
#endregion

#region st sheet variables
@onready var st_scroll_container: ScrollContainer = $ScrollContainerstoryteller
@onready var st_v_box_container: VBoxContainer = $ScrollContainerstoryteller/HBoxContainer
@onready var warning_dialog_storyteller: AcceptDialog = $VBoxContainer/HBoxContainer/VBoxContainerstoryteller/LoadAScreen/AcceptDialog
var st_selected_save_file: String = ""
var st_selected_save_file_storyteller: String = ""

#endregion

func _enter_tree() -> void:
	list_save_files()
	st_list_save_files()

#region character sheet
func _on_load_a_sheet_pressed() -> void:
	if selected_save_file != "" and GlobalFunctions.load_character(selected_save_file):
		get_parent()._switch_to(preload("res://scenes/player_character_creator_scene.tscn"))
	else:
		warning_dialog_character.popup_centered()

func _on_add_a_sheet_pressed() -> void:
	GlobalFunctions.new_character()
	get_parent()._switch_to(preload("res://scenes/player_character_creator_scene.tscn"))

func _on_delete_a_sheet_pressed() -> void:
	if selected_save_file != "":
		GlobalFunctions.delete_character(selected_save_file)
		selected_save_file = ""
		list_save_files()
	else:
		print("No file selected to delete.")

func list_save_files() -> void:
	selected_save_file = _fill_list(
		$ScrollContainerplayer/HBoxContainer,
		GlobalFunctions.list_characters(),
		selected_save_file,
		func(save_name: String): selected_save_file = save_name
	)

#endregion

func _fill_list(container: Node, names: PackedStringArray, selected: String, on_select: Callable) -> String:
	for child in container.get_children():
		child.queue_free()

	var group := ButtonGroup.new()  # one group per list, so characters and storytellers don't interfere
	var selection_found := false

	for save_name in names:
		var button := Button.new()
		button.text = save_name
		button.toggle_mode = true
		button.button_group = group
		button.toggled.connect(func(toggled_on: bool):
			if toggled_on:
				on_select.call(save_name)
		)
		container.add_child(button)

		# The list is rebuilt whenever the window regains focus, so re-highlight the current pick.
		# The no_signal version avoids firing `toggled` for something that isn't a new click.
		if save_name == selected:
			button.set_pressed_no_signal(true)
			selection_found = true

	return selected if selection_found else ""

#region promotional links
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

#endregion
	
#region file explorer
func _on_open_folder_pressed() -> void:
	var folder_path = OS.get_user_data_dir()
	print("Opening save folder:", folder_path)
	OS.shell_open(folder_path)
	
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		# Reload save files when the player returns to the game
		print("Game regained focus, refreshing save files...")
		list_save_files()
#endregion

#region storyteller screen
func _on_load_a_stscreen_pressed() -> void:
	if st_selected_save_file != "" and GlobalFunctions.load_storyteller(st_selected_save_file):
		get_parent()._switch_to(preload("res://scenes/Storyteller_scene.tscn"))
	else:
		warning_dialog_storyteller.popup_centered()

func _on_add_a_stscreen_pressed() -> void:
	GlobalFunctions.new_storyteller()
	get_parent()._switch_to(preload("res://scenes/Storyteller_scene.tscn"))

func _on_delete_a_stscreen_pressed() -> void:
	if st_selected_save_file != "":
		GlobalFunctions.delete_storyteller(st_selected_save_file)
		st_selected_save_file = ""
		st_list_save_files()
	else:
		print("No file selected to delete.")

func st_list_save_files() -> void:
	st_selected_save_file = _fill_list(
		$ScrollContainerstoryteller/HBoxContainer,
		GlobalFunctions.list_storytellers(),
		st_selected_save_file,
		func(save_name: String): st_selected_save_file = save_name
	)
#endregion

#region auxilery 

func _on_settings_pressed() -> void:
	SettingsMenu.toggle(get_tree(), false)  
			
func _on_exit_pressed() -> void:
	get_tree().quit()
	
#endregion


func _on_add_a_screen_pressed() -> void:
	_on_add_a_stscreen_pressed()


func _on_delete_a_screen_2_pressed() -> void:
	_on_delete_a_stscreen_pressed()


func _on_load_a_screen_pressed() -> void:
	_on_load_a_stscreen_pressed()
