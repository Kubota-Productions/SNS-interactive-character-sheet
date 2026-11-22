extends Node
## Autoload "Lobby" (Project Settings > Globals > Autoload, name it exactly: Lobby).
##
## Owns everything about the Steam lobby: the connection, the list of players and their names.
## It lives for the whole run of the game, so the lobby survives switching between the menu, the
## character sheet and the storyteller screen. (When this code lived in the menu script, leaving
## the menu threw the lobby away.) It also creates the CombatSync node that carries the 3D combat
## board between players.

signal status_changed(text: String)
signal players_changed
## Emitted after this game has left (or lost) the lobby.
signal lobby_left(was_host: bool, was_client: bool)

const MAX_PLAYERS: int = 8
const LOBBY_TYPE_FRIENDS_ONLY: int = 1  # same value as Steam.LOBBY_TYPE_FRIENDS_ONLY
const MAX_NAME_LENGTH := 24
const DEBUG_PORT := 24565
const CombatSyncScript := preload("res://code/singleton/combat_sync.gd")

## GodotSteam is a GDExtension. It is looked up at runtime instead of writing `Steam.` in code,
## so if the extension is missing from a build this script still loads and the game still runs.
var steam = null
var steam_ready := false  # Steam started successfully

var steam_peer: MultiplayerPeer = null
var steam_lobby_id: int = 0

## Peer id -> display name. The host is always id 1.
var players: Dictionary = {}
## What the player typed into the name box in the menu (kept here so it survives scene changes).
var typed_name: String = ""
var status: String = "Not connected to a Steam lobby"

var combat: Node = null


func _ready() -> void:
	# The combat board works without Steam too (single player), so this comes first.
	combat = CombatSyncScript.new()
	combat.name = "CombatSync"  # must be identical on every machine: RPCs find it by its path
	add_child(combat)

	# Multiplayer connection signals (also used by the local test game, see the bottom).
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	if not Engine.has_singleton("Steam"):
		push_error("GodotSteam is not loaded in this build, Steam multiplayer is disabled.")
		_set_status("Steam not available")
		set_process(false)
		return
	steam = Engine.get_singleton("Steam")

	var init_result: Dictionary = steam.steamInitEx()
	if init_result["status"] > 0:
		push_error("Steam initialization failed: " + str(init_result))
		_set_status("Steam initialization failed")
		set_process(false)
		return

	steam_ready = true
	print("Steam initialized!")
	print("Steam username: ", steam.getPersonaName())

	# Steam lobby signals.
	steam.lobby_created.connect(_on_steam_lobby_created)
	steam.lobby_joined.connect(_on_steam_lobby_joined)
	steam.join_requested.connect(_on_steam_join_requested)

	_set_status("Not connected to a Steam lobby")

	# Handle an invitation accepted while the game was closed.
	var args := OS.get_cmdline_args()
	for i in range(args.size() - 1):
		if args[i] == "+connect_lobby":
			steam.joinLobby(int(args[i + 1]))
			break


func _process(_delta: float) -> void:
	# Steam callbacks must be processed every frame, in every scene (not just the menu).
	if steam_ready:
		steam.run_callbacks()


func _set_status(text: String) -> void:
	status = text
	status_changed.emit(text)


## True while this game is hosting or has joined a lobby.
func is_active() -> bool:
	return steam_peer != null


func name_of(peer_id: int) -> String:
	return players.get(peer_id, "Player")


# ------------------------------------------------------------------ hosting and joining

func host_game() -> void:
	if not steam_ready:
		_set_status("Steam not available")
		return

	if steam_peer != null or steam_lobby_id != 0:
		print("Already in a Steam lobby!")
		return

	print("Creating Steam friends-only lobby...")
	_set_status("Creating Steam lobby...")
	steam.createLobby(LOBBY_TYPE_FRIENDS_ONLY, MAX_PLAYERS)


func _on_steam_lobby_created(result: int, lobby_id: int) -> void:
	if result != 1:
		print("Failed to create Steam lobby: ", result)
		_set_status("Failed to create lobby")
		return

	steam_lobby_id = lobby_id
	steam.setLobbyData(steam_lobby_id, "name", steam.getPersonaName() + "'s Game")
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

	_set_status("Hosting Steam lobby!")
	print("Steam host started!")
	print("Your multiplayer ID: ", multiplayer.get_unique_id())

	register_player()


# JOIN A STEAM LOBBY AFTER ACCEPTING AN INVITE
func _on_steam_join_requested(lobby_id: int, _friend_id: int) -> void:
	print("Steam invitation received: ", lobby_id)

	if steam_peer != null or steam_lobby_id != 0:
		leave()

	steam.joinLobby(lobby_id)


func _on_steam_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != 1:
		print("Failed to join Steam lobby: ", response)
		_set_status("Failed to join lobby")
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
	_set_status("Connecting to host...")


# OPEN STEAM'S INVITE OVERLAY
func invite_friends() -> void:
	if not steam_ready or steam_lobby_id == 0:
		print("You need to host a Steam lobby first!")
		return
	steam.activateGameOverlayInviteDialog(steam_lobby_id)


# ------------------------------------------------------------------ player names

func _persona_name() -> String:
	return steam.getPersonaName() if steam_ready else ""


func _clean_name(raw: String) -> String:
	var cleaned := raw.strip_edges().replace("\n", " ").replace("\t", " ")
	return cleaned.left(MAX_NAME_LENGTH).strip_edges()


## Two players with the same name get " (2)", " (3)"... so their name tags can be told apart.
func _unique_name(candidate: String, for_id: int) -> String:
	var used: Array = []
	for id in players:
		if id != for_id:
			used.append(players[id])
	var result := candidate
	var n := 2
	while used.has(result):
		result = "%s (%d)" % [candidate, n]
		n += 1
	return result


## Sends this player's name to the host. Uses the name typed in the menu, then the Steam name.
func register_player() -> void:
	if not is_active():
		return

	var chosen := _clean_name(typed_name)
	if chosen.is_empty():
		chosen = _clean_name(_persona_name())
	if chosen.is_empty():
		chosen = "Player"
	print("Registering player: ", chosen)

	if multiplayer.is_server():
		players[1] = _unique_name(chosen, 1)
		update_lobby.rpc(players)
	else:
		request_player_registration.rpc_id(1, chosen)


@rpc("any_peer", "call_remote", "reliable")
func request_player_registration(pname: String) -> void:
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	var chosen := _clean_name(pname)
	if chosen.is_empty():
		chosen = "Player"
	players[sender_id] = _unique_name(chosen, sender_id)
	update_lobby.rpc(players)


## The host sends the whole name list to everybody whenever it changes.
@rpc("authority", "call_local", "reliable")
func update_lobby(updated_players: Dictionary) -> void:
	players = updated_players
	_set_status("Players connected: %d" % players.size())
	players_changed.emit()


# ------------------------------------------------------------------ leaving

func leave() -> void:
	if steam_peer == null and steam_lobby_id == 0:
		print("Already disconnected.")
		return

	print("Leaving Steam multiplayer...")
	var was_host := steam_peer != null and multiplayer.is_server()
	var was_client := steam_peer != null and not multiplayer.is_server()

	if steam_lobby_id != 0:
		steam.leaveLobby(steam_lobby_id)
		steam_lobby_id = 0

	if steam_peer != null:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		steam_peer.close()
		steam_peer = null

	players.clear()
	_set_status("Not connected")
	players_changed.emit()
	lobby_left.emit(was_host, was_client)
	print("Disconnected from Steam!")


# ------------------------------------------------------------------ connection events

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
	_set_status("Connected to Steam host!")


func _on_connection_failed() -> void:
	print("Steam connection failed!")
	leave()


func _on_server_disconnected() -> void:
	print("Steam host disconnected!")
	leave()


# ------------------------------------------------------------------ simple chat

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


# ------------------------------------------------------------------ local test game (no Steam)
# For testing on one PC: in the editor open Debug > Customize Run Instances and run 2 instances.
# Press Ctrl+Shift+H in one (host) and Ctrl+Shift+J in the other (join). Only works in debug
# builds (the editor, or a debug export), so players never see it.

func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or not key.ctrl_pressed or not key.shift_pressed:
		return
	if key.keycode == KEY_H:
		debug_host_local()
	elif key.keycode == KEY_J:
		debug_join_local()


func debug_host_local() -> void:
	if steam_peer != null:
		return
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(DEBUG_PORT, MAX_PLAYERS) != OK:
		push_error("Could not start the local test host on port %d." % DEBUG_PORT)
		return
	steam_peer = peer
	multiplayer.multiplayer_peer = peer
	_set_status("Hosting local test game")
	register_player()


func debug_join_local() -> void:
	if steam_peer != null:
		return
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client("127.0.0.1", DEBUG_PORT) != OK:
		push_error("Could not start the local test client.")
		return
	steam_peer = peer
	multiplayer.multiplayer_peer = peer
	_set_status("Connecting to local test game...")
