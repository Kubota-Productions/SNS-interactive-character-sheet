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
		get_parent()._switch_to(load("res://scenes/Storyteller_scene.tscn"))
	else:
		warning_dialog_storyteller.popup_centered()

func _on_add_a_stscreen_pressed() -> void:
	GlobalFunctions.new_storyteller()
	get_parent()._switch_to(load("res://scenes/Storyteller_scene.tscn"))

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
	


#region STEAM MULTIPLAYER

const MAX_PLAYERS: int = 8
const LOBBY_TYPE_FRIENDS_ONLY: int = 1  # same value as Steam.LOBBY_TYPE_FRIENDS_ONLY

## GodotSteam is a GDExtension. It is looked up at runtime instead of writing `Steam.` in code,
## so if the extension is missing from a build this script still loads and the menu buttons work.
## It stays null when GodotSteam isn't available.
var steam = null

var steam_peer: MultiplayerPeer = null
var steam_lobby_id: int = 0

var player_name: String = "Player"
var players: Dictionary = {}
var is_ready: bool = false

@onready var lobby_status: Label = $VBoxContainer/HBoxContainerMultiplayer/MultiplayerLobby/Label
@onready var player_list: VBoxContainer = $VBoxContainer/HBoxContainerMultiplayer/MultiplayerLobby/PlayerList
@onready var player_name_input: LineEdit = $VBoxContainer/HBoxContainerMultiplayer/MultiplayerLobby/PlayerNameInput
@onready var ready_button: Button = $VBoxContainer/HBoxContainerMultiplayer/MultiplayerLobby/Ready


func _ready() -> void:
	# Look up GodotSteam. It is missing if the GDExtension didn't load in this build.
	if not Engine.has_singleton("Steam"):
		push_error("GodotSteam is not loaded in this build, Steam multiplayer is disabled.")
		lobby_status.text = "Steam not available"
		set_process(false)
		return
	steam = Engine.get_singleton("Steam")

	# Start Steamworks
	var init_result: Dictionary = steam.steamInitEx()

	if init_result["status"] > 0:
		push_error("Steam initialization failed: " + str(init_result))
		lobby_status.text = "Steam initialization failed"
		return

	print("Steam initialized!")
	print("Steam username: ", steam.getPersonaName())

	# Multiplayer connection signals.
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	# Steam lobby signals.
	steam.lobby_created.connect(_on_steam_lobby_created)
	steam.lobby_joined.connect(_on_steam_lobby_joined)
	steam.join_requested.connect(_on_steam_join_requested)

	# Create extra lobby buttons.
	var invite_button := Button.new()
	invite_button.text = "Invite Friends"
	invite_button.pressed.connect(invite_friends)
	player_list.get_parent().add_child(invite_button)

	var leave_button := Button.new()
	leave_button.text = "Leave Lobby"
	leave_button.pressed.connect(disconnect_from_game)
	player_list.get_parent().add_child(leave_button)

	lobby_status.text = "Not connected to a Steam lobby"

	# Handle an invitation accepted while the game was closed.
	var args := OS.get_cmdline_args()
	for i in range(args.size() - 1):
		if args[i] == "+connect_lobby":
			steam.joinLobby(int(args[i + 1]))
			break


func _process(_delta: float) -> void:
	# Steam callbacks must be processed.
	if steam != null:
		steam.run_callbacks()


# HOST A STEAM LOBBY
func host_game() -> void:
	if steam == null:
		lobby_status.text = "Steam not available"
		return

	if steam_peer != null or steam_lobby_id != 0:
		print("Already in a Steam lobby!")
		return

	print("Creating Steam friends-only lobby...")
	lobby_status.text = "Creating Steam lobby..."

	steam.createLobby(LOBBY_TYPE_FRIENDS_ONLY, MAX_PLAYERS)


func _on_steam_lobby_created(result: int, lobby_id: int) -> void:
	if result != 1:
		print("Failed to create Steam lobby: ", result)
		lobby_status.text = "Failed to create lobby"
		return

	steam_lobby_id = lobby_id

	steam.setLobbyData(
		steam_lobby_id,
		"name",
		steam.getPersonaName() + "'s Game"
	)

	steam.setLobbyJoinable(steam_lobby_id, true)

	print("Steam lobby created: ", steam_lobby_id)

	# Create the Steam multiplayer host.
	var new_peer = ClassDB.instantiate("SteamMultiplayerPeer")

	if new_peer == null:
		push_error("SteamMultiplayerPeer is not registered in this build.")
		steam.leaveLobby(steam_lobby_id)
		steam_lobby_id = 0
		return

	var error = new_peer.create_host(0)

	if error != OK:
		push_error("Failed to create Steam host: " + str(error))
		steam.leaveLobby(steam_lobby_id)
		steam_lobby_id = 0
		return

	steam_peer = new_peer
	multiplayer.multiplayer_peer = steam_peer

	lobby_status.text = "Hosting Steam lobby!"

	print("Steam host started!")
	print("Your multiplayer ID: ", multiplayer.get_unique_id())

	register_player()


# JOIN A STEAM LOBBY AFTER ACCEPTING AN INVITE
func _on_steam_join_requested(lobby_id: int, _friend_id: int) -> void:
	print("Steam invitation received: ", lobby_id)

	if steam_peer != null:
		disconnect_from_game()

	steam.joinLobby(lobby_id)


func _on_steam_lobby_joined(
	lobby_id: int,
	_permissions: int,
	_locked: bool,
	response: int
) -> void:

	if response != 1:
		print("Failed to join Steam lobby: ", response)
		lobby_status.text = "Failed to join lobby"
		return

	steam_lobby_id = lobby_id

	var host_steam_id: int = steam.getLobbyOwner(lobby_id)

	# The host also receives lobby_joined for its own lobby.
	if host_steam_id == steam.getSteamID():
		return

	print("Joined Steam lobby: ", lobby_id)
	print("Lobby owner Steam ID: ", host_steam_id)

	var new_peer = ClassDB.instantiate("SteamMultiplayerPeer")

	if new_peer == null:
		push_error("SteamMultiplayerPeer is not registered in this build.")
		return

	var error = new_peer.create_client(host_steam_id, 0)

	if error != OK:
		push_error("Failed to connect to Steam host: " + str(error))
		return

	steam_peer = new_peer
	multiplayer.multiplayer_peer = steam_peer

	lobby_status.text = "Connecting to host..."


# OPEN STEAM'S INVITE OVERLAY
func invite_friends() -> void:
	if steam_lobby_id == 0:
		print("You need to host a Steam lobby first!")
		return

	steam.activateGameOverlayInviteDialog(steam_lobby_id)


# Existing Join button can also open the invite overlay.
func _on_join_pressed() -> void:
	invite_friends()


func _persona_name() -> String:
	return steam.getPersonaName() if steam != null else ""


# PLAYER NAME REGISTRATION
func register_player() -> void:
	player_name = player_name_input.text.strip_edges()

	if player_name.is_empty():
		player_name = _persona_name()

	if player_name.is_empty():
		player_name = "Player"

	print("Registering player: ", player_name)

	if multiplayer.is_server():
		players[1] = player_name
		update_lobby.rpc(players)
	else:
		request_player_registration.rpc_id(1, player_name)


func _on_player_name_input_text_submitted(new_text: String) -> void:
	player_name = new_text.strip_edges()

	if player_name.is_empty():
		player_name = _persona_name()

	register_player()


@rpc("any_peer", "call_remote", "reliable")
func request_player_registration(pname: String) -> void:
	if not multiplayer.is_server():
		return

	var sender_id = multiplayer.get_remote_sender_id()
	players[sender_id] = pname

	update_lobby.rpc(players)


# UPDATE THE PLAYER BUTTONS
@rpc("authority", "call_local", "reliable")
func update_lobby(updated_players: Dictionary) -> void:
	players = updated_players

	for child in player_list.get_children():
		player_list.remove_child(child)
		child.queue_free()

	for id in players:
		var player_button := Button.new()
		player_button.text = "%s (ID: %s)" % [players[id], id]
		player_button.custom_minimum_size = Vector2(200, 40)
		player_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		player_list.add_child(player_button)

	lobby_status.text = "Players connected: %d" % players.size()


# READY BUTTON
func _on_ready_button_pressed() -> void:
	is_ready = not is_ready

	if is_ready:
		ready_button.text = "Ready!"
	else:
		ready_button.text = "Not Ready"


# DISCONNECT FROM STEAM
func disconnect_from_game() -> void:
	if steam_peer == null and steam_lobby_id == 0:
		print("Already disconnected.")
		return

	print("Leaving Steam multiplayer...")

	if steam_lobby_id != 0:
		steam.leaveLobby(steam_lobby_id)
		steam_lobby_id = 0

	if steam_peer != null:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		steam_peer.close()
		steam_peer = null

	players.clear()
	is_ready = false

	for child in player_list.get_children():
		player_list.remove_child(child)
		child.queue_free()

	lobby_status.text = "Not connected"
	ready_button.text = "Not Ready"

	print("Disconnected from Steam!")


# MULTIPLAYER CONNECTION EVENTS
func _on_peer_connected(id: int) -> void:
	print("Player connected! ID: ", id)


func _on_peer_disconnected(id: int) -> void:
	print("Player disconnected! ID: ", id)

	if multiplayer.is_server():
		players.erase(id)
		update_lobby.rpc(players)


func _on_connected_to_server() -> void:
	print("Successfully connected to Steam host!")
	register_player()
	lobby_status.text = "Connected to Steam host!"


func _on_connection_failed() -> void:
	print("Steam connection failed!")
	disconnect_from_game()


func _on_server_disconnected() -> void:
	print("Steam host disconnected!")
	disconnect_from_game()


# SIMPLE MULTIPLAYER CHAT
func send_chat_message(message: String) -> void:
	if steam_peer == null:
		print("You are not connected to multiplayer.")
		return

	if message.strip_edges().is_empty():
		return

	rpc("receive_chat_message", multiplayer.get_unique_id(), message)


@rpc("any_peer", "call_local", "reliable")
func receive_chat_message(sender_id: int, message: String) -> void:
	print("[Player ", sender_id, "]: ", message)


func is_multiplayer_active() -> bool:
	return steam_peer != null and steam_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

#endregion
