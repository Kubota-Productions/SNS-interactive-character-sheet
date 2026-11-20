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
	

#region multiplayer

const MULTIPLAYER_PORT: int = 7777
const MAX_PLAYERS: int = 8

var multiplayer_peer: ENetMultiplayerPeer
var entered_ip: String = ""

var player_name: String = "Player"
var players: Dictionary = {}
var is_ready: bool = false

@onready var lobby_status: Label = $VBoxContainer/HBoxContainerMultiplayer/MultiplayerLobby/Label
@onready var player_list: VBoxContainer = $VBoxContainer/HBoxContainerMultiplayer/MultiplayerLobby/PlayerList
@onready var player_name_input: LineEdit = $VBoxContainer/HBoxContainerMultiplayer/MultiplayerLobby/PlayerNameInput
@onready var ready_button: Button = $VBoxContainer/HBoxContainerMultiplayer/MultiplayerLobby/Ready

func _ready() -> void:
	# Listen for multiplayer connection events.
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func register_player() -> void:
	player_name = player_name_input.text.strip_edges()

	if player_name.is_empty():
		player_name = "Player"

	var my_id = multiplayer.get_unique_id()

	print("Registering player: ", player_name)

	if multiplayer.is_server():
		players[1] = player_name
		update_lobby.rpc(players)
	else:
		# Display your own name immediately.
		players[my_id] = player_name
		update_lobby(players)

		# Tell the host your name.
		request_player_registration.rpc_id(1, player_name)

func _on_player_name_input_text_submitted(new_text: String) -> void:
	print("Name submitted: ", new_text)

	player_name = new_text.strip_edges()

	if player_name.is_empty():
		player_name = "Player"

	register_player()

@rpc("any_peer", "call_remote", "reliable")
func request_player_registration(pname: String) -> void:
	if not multiplayer.is_server():
		return

	var sender_id = multiplayer.get_remote_sender_id()
	players[sender_id] = pname

	update_lobby.rpc(players)


@rpc("authority", "call_local", "reliable")
func update_lobby(updated_players: Dictionary) -> void:
	print("Updating lobby: ", updated_players)

	players = updated_players

	# Remove old player buttons.
	for child in player_list.get_children():
		player_list.remove_child(child)
		child.queue_free()

	# Create a button for every player.
	for id in players:
		var player_button := Button.new()

		player_button.text = "%s (ID: %s)" % [players[id], id]
		player_button.custom_minimum_size = Vector2(200, 40)
		player_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		player_list.add_child(player_button)

	lobby_status.text = "Players connected: %d" % players.size()

# HOST A GAME
func host_game() -> void:
	# Don't attempt to host if already connected.
	if multiplayer.multiplayer_peer != null:
		print("Already connected or hosting!")
		return

	var new_peer := ENetMultiplayerPeer.new()

	var error := new_peer.create_server(
		MULTIPLAYER_PORT,
		MAX_PLAYERS
	)

	if error != OK:
		print("Failed to create server!")
		print("ENet error: ", error)
		print("Error description: ", error_string(error))
		new_peer.close()
		return

	multiplayer_peer = new_peer
	multiplayer.multiplayer_peer = multiplayer_peer

	print("Hosting multiplayer game!")
	print("Your player ID: ", multiplayer.get_unique_id())

	register_player()

func _on_join_pressed() -> void:
	if entered_ip.is_empty():
		print("Please enter an IP address!")
		return

	join_game(entered_ip)

# JOIN A GAME
func join_game(ip_address: String) -> void:
	if multiplayer.multiplayer_peer != null:
		print("Already connected or hosting!")
		return

	ip_address = ip_address.strip_edges()

	if ip_address.is_empty():
		print("Please enter an IP address!")
		return

	var new_peer := ENetMultiplayerPeer.new()

	var error := new_peer.create_client(
		ip_address,
		MULTIPLAYER_PORT
	)

	if error != OK:
		print("Failed to create client!")
		print("ENet error: ", error)
		print("Error description: ", error_string(error))
		new_peer.close()
		return

	multiplayer_peer = new_peer
	multiplayer.multiplayer_peer = multiplayer_peer

	print("Attempting to connect to: ", ip_address)

func _on_ready_button_pressed() -> void:
	is_ready = not is_ready

	if is_ready:
		ready_button.text = "Ready!"
	else:
		ready_button.text = "Not Ready"

func _on_ip_input_text_changed(new_text: String) -> void:
	entered_ip = new_text.strip_edges()

# DISCONNECT FROM GAME
func disconnect_from_game() -> void:
	if multiplayer.multiplayer_peer == null:
		print("Already disconnected.")
		return

	print("Disconnecting from multiplayer...")

	# Save a reference to the current connection.
	var old_peer = multiplayer.multiplayer_peer

	# Remove it from the multiplayer API.
	multiplayer.multiplayer_peer = null

	# Close the old ENet connection.
	old_peer.close()

	multiplayer_peer = null

	# Reset local lobby information.
	players.clear()
	is_ready = false

	for child in player_list.get_children():
		player_list.remove_child(child)
		child.queue_free()
	lobby_status.text = "Not connected"
	ready_button.text = "Not Ready"

	print("Disconnected successfully!")

func _on_peer_connected(id: int) -> void:
	print("Player connected! ID: ", id)

func _on_peer_disconnected(id: int) -> void:
	print("Player disconnected! ID: ", id)

	if multiplayer.is_server():
		players.erase(id)
		update_lobby(players)
		update_lobby.rpc(players)

func _on_connected_to_server() -> void:
	print("Successfully connected to host!")
	register_player()

func _on_connection_failed() -> void:
	print("Connection failed!")
	disconnect_from_game()

func _on_server_disconnected() -> void:
	print("Host disconnected!")
	disconnect_from_game()

# SIMPLE MULTIPLAYER CHAT
func send_chat_message(message: String) -> void:
	if multiplayer.multiplayer_peer == null:
		print("You are not connected to multiplayer.")
		return

	if message.strip_edges().is_empty():
		return

	rpc("receive_chat_message", multiplayer.get_unique_id(), message)


@rpc("any_peer", "call_local", "reliable")
func receive_chat_message(sender_id: int, message: String) -> void:
	print("[Player ", sender_id, "]: ", message)


# CHECK CONNECTION STATUS
func is_multiplayer_active() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

#endregion
