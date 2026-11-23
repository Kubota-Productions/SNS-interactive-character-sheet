extends Control
#region character sheet variables
@onready var scroll_container: ScrollContainer = $ScrollContainerplayer
@onready var v_box_container: VBoxContainer = $ScrollContainerplayer/HBoxContainer
@onready var warning_dialog_character: AcceptDialog = $VBoxContainer/HBoxContainer/VBoxContainerplayer/LoadASheet/AcceptDialog
var selected_save_file: String = ""
#endregion

#region GM screen variables
@onready var warning_dialog_gamemaster: AcceptDialog = _find_gm_warning_dialog()
var gm_selected_save_file: String = ""

#endregion

func _enter_tree() -> void:
	list_save_files()
	gm_list_save_files()

#region character sheet
func _on_load_a_sheet_pressed() -> void:
	if selected_save_file != "" and GlobalFunctions.load_character(selected_save_file):
		get_parent()._switch_to(load("res://scenes/player_character_creator_scene.tscn"))
	else:
		warning_dialog_character.popup_centered()

func _on_add_a_sheet_pressed() -> void:
	GlobalFunctions.new_character()
	get_parent()._switch_to(load("res://scenes/player_character_creator_scene.tscn"))

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

	var group := ButtonGroup.new()  # one group per list, so characters and GM screens don't interfere
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

#region GM screen
## The GM (GameMaster) screen. Its saves are listed by GlobalFunctions.
const GM_SCENE_PATH := "res://scenes/GameMaster_scene.tscn"

func _gm_scene() -> PackedScene:
	if ResourceLoader.exists(GM_SCENE_PATH):
		return load(GM_SCENE_PATH) as PackedScene
	push_error("The GM scene was not found: " + GM_SCENE_PATH)
	return null


## The list of GM screens is the menu's other ScrollContainer (the character list is
## ScrollContainerplayer). Looked up by structure so it doesn't depend on what the node is called.
func _gm_list() -> Node:
	for child in get_children():
		if child is ScrollContainer and child.name != &"ScrollContainerplayer":
			return child.get_node_or_null("HBoxContainer")
	push_error("Main menu: could not find the list of GM screens.")
	return null


## The "nothing selected / could not load" popup that belongs to the Load button of the GM column.
## Found by the button's name, so it still works if the column's container was renamed.
func _find_gm_warning_dialog() -> AcceptDialog:
	var load_button := find_child("LoadAScreen", true, false)
	if load_button != null:
		for child in load_button.get_children():
			if child is AcceptDialog:
				return child
	push_warning("Main menu: could not find the AcceptDialog under the LoadAScreen button.")
	return null


func _show_gm_warning() -> void:
	if warning_dialog_gamemaster != null:
		warning_dialog_gamemaster.popup_centered()


func _on_load_a_gm_screen_pressed() -> void:
	var scene := _gm_scene()
	if gm_selected_save_file != "" and scene != null and GlobalFunctions.load_gamemaster(gm_selected_save_file):
		get_parent()._switch_to(scene)
	else:
		_show_gm_warning()

func _on_add_a_gm_screen_pressed() -> void:
	var scene := _gm_scene()
	if scene == null:
		_show_gm_warning()
		return
	GlobalFunctions.new_gamemaster()
	get_parent()._switch_to(scene)

func _on_delete_a_gm_screen_pressed() -> void:
	if gm_selected_save_file != "":
		GlobalFunctions.delete_gamemaster(gm_selected_save_file)
		gm_selected_save_file = ""
		gm_list_save_files()
	else:
		print("No file selected to delete.")

func gm_list_save_files() -> void:
	var list := _gm_list()
	if list == null:
		return
	gm_selected_save_file = _fill_list(
		list,
		GlobalFunctions.list_gamemasters(),
		gm_selected_save_file,
		func(save_name: String): gm_selected_save_file = save_name
	)
#endregion

#region auxilery 

func _on_settings_pressed() -> void:
	SettingsMenu.toggle(get_tree(), false)  
			
func _on_exit_pressed() -> void:
	get_tree().quit()
	
#endregion


func _on_add_a_screen_pressed() -> void:
	_on_add_a_gm_screen_pressed()


func _on_delete_a_screen_2_pressed() -> void:
	_on_delete_a_gm_screen_pressed()


func _on_load_a_screen_pressed() -> void:
	_on_load_a_gm_screen_pressed()
	


#region STEAM MULTIPLAYER (menu side)
## The lobby itself lives in the Lobby autoload (code/singleton/lobby.gd), so it survives leaving
## this menu. This part only shows it and passes the button presses on.
## It is looked up at runtime so the menu still works if the autoload hasn't been added yet.
var lobby = null

var is_ready: bool = false

@onready var lobby_status: Label = $VBoxContainer/HBoxContainerMultiplayer/MultiplayerLobby/Label
@onready var player_list: VBoxContainer = $VBoxContainer/HBoxContainerMultiplayer/MultiplayerLobby/PlayerList
@onready var player_name_input: LineEdit = $VBoxContainer/HBoxContainerMultiplayer/MultiplayerLobby/PlayerNameInput
@onready var ready_button: Button = $VBoxContainer/HBoxContainerMultiplayer/MultiplayerLobby/Ready


func _ready() -> void:
	lobby = get_node_or_null("/root/Lobby")
	if lobby == null:
		push_error("The Lobby autoload is missing. Add code/singleton/lobby.gd as an autoload named Lobby.")
		lobby_status.text = "Lobby autoload missing"
		return

	lobby.status_changed.connect(_on_lobby_status_changed)
	lobby.players_changed.connect(_refresh_player_list)

	# Keep what was typed, even if the menu is closed and opened again later.
	player_name_input.text = lobby.typed_name
	player_name_input.text_changed.connect(func(new_text: String): lobby.typed_name = new_text)

	if lobby.steam_ready:
		var invite_button := Button.new()
		invite_button.text = "Invite Friends"
		invite_button.pressed.connect(_on_join_pressed)
		player_list.get_parent().add_child(invite_button)

		var leave_button := Button.new()
		leave_button.text = "Leave Lobby"
		leave_button.pressed.connect(disconnect_from_game)
		player_list.get_parent().add_child(leave_button)

	# Only in debug builds (running from the editor): test the multiplayer on this PC, no Steam
	# or friend needed. Run two copies of the game, press "host" in one and "join" in the other.
	if OS.is_debug_build():
		var test_host := Button.new()
		test_host.text = "TEST: host on this PC"
		test_host.pressed.connect(Callable(lobby, "debug_host_local"))
		player_list.get_parent().add_child(test_host)

		var test_join := Button.new()
		test_join.text = "TEST: join on this PC"
		test_join.pressed.connect(Callable(lobby, "debug_join_local"))
		player_list.get_parent().add_child(test_join)

	lobby_status.text = lobby.status
	_refresh_player_list()


func _on_lobby_status_changed(text: String) -> void:
	lobby_status.text = text


func _refresh_player_list() -> void:
	for child in player_list.get_children():
		player_list.remove_child(child)
		child.queue_free()

	if lobby == null:
		return

	for id in lobby.players:
		var player_button := Button.new()
		player_button.text = "%s (ID: %s)" % [lobby.players[id], id]
		player_button.custom_minimum_size = Vector2(200, 40)
		player_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		player_list.add_child(player_button)


# HOST A STEAM LOBBY (the Host button)
func host_game() -> void:
	if lobby != null:
		lobby.host_game()


# The Join button opens Steam's invite overlay.
func _on_join_pressed() -> void:
	if lobby != null:
		lobby.invite_friends()


func _on_player_name_input_text_submitted(new_text: String) -> void:
	if lobby == null:
		return
	lobby.typed_name = new_text
	lobby.register_player()


# This scene still has a leftover connection to this method; it does nothing.
func _on_ip_input_text_changed(_new_text: String) -> void:
	pass


# READY BUTTON
func _on_ready_button_pressed() -> void:
	is_ready = not is_ready

	if is_ready:
		ready_button.text = "Ready!"
	else:
		ready_button.text = "Not Ready"


# LEAVE THE LOBBY (the Disconnect button)
func disconnect_from_game() -> void:
	if lobby != null:
		lobby.leave()

	is_ready = false
	ready_button.text = "Not Ready"

#endregion
