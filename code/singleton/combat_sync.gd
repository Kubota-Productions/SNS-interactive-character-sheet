extends Node
## Network relay for the 3D combat board. The Lobby autoload creates this node as
## /root/Lobby/CombatSync, so it sits at the same node path on every machine. That matters:
## Godot finds the target of an RPC by node path, and the combat board itself lives in different
## scenes (the storyteller screen on the host, the character sheet for the players).
##
## This script only carries messages. The rules (who may change what) are in combat_grid_3d.gd.
##
## Players -> host ("requests", the host checks every one):
##   request_board, request_move_token, request_add_measure, request_remove_measure
## Host -> everybody ("results"; only the host can send these, Godot refuses them from anyone else):
##   rpc_snapshot, rpc_terrain, rpc_token_added / moved / removed, rpc_measure_added / removed

## The combat board that is currently open on this machine, if any.
var grid = null  # untyped: the board's methods are looked up when called
## The host's board, kept while no board is open (for example while the host is in the menu).
var host_state: Dictionary = {}
## Host side: players who have asked for the board. They get a shape of their own.
var joined: Dictionary = {}


func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	var lobby := get_parent()
	lobby.connect("players_changed", _on_players_changed)
	lobby.connect("lobby_left", _on_lobby_left)


# ------------------------------------------------------------------ who is who

## True while this game is hosting or has joined a lobby.
func is_online() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null \
		and not (peer is OfflineMultiplayerPeer) \
		and peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED


## The storyteller (the host), or anyone playing without a lobby.
func is_authority() -> bool:
	return not is_online() or multiplayer.is_server()


func name_of(peer_id: int) -> String:
	var lobby := get_parent()
	if lobby.has_method("name_of"):
		return lobby.call("name_of", peer_id)
	return "Player"


func _has_remote_peers() -> bool:
	return not multiplayer.get_peers().is_empty()


## A player can only send requests once the connection to the host is fully up.
func _can_send_to_host() -> bool:
	var peer := multiplayer.multiplayer_peer
	return is_online() and not multiplayer.is_server() \
		and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


# ------------------------------------------------------------------ a board opens or closes

func register_grid(g) -> void:
	# The new scene is created before the old one is freed, so for a moment two boards can
	# exist. Take over the old board's contents first.
	if grid != null and is_instance_valid(grid) and grid != g and is_authority():
		host_state = grid.make_snapshot()
	grid = g

	if is_authority():
		if not host_state.is_empty():
			g.net_load_state(host_state)
		var ids: Array = []
		for id in multiplayer.get_peers():
			if joined.has(id):
				ids.append(id)
		g.net_authority_ready(ids)
	elif is_online():
		send_request_board()


func unregister_grid(g) -> void:
	if grid != g:
		return
	if is_authority():
		host_state = g.make_snapshot()
	grid = null


# ------------------------------------------------------------------ connection events

func _on_peer_disconnected(id: int) -> void:
	joined.erase(id)
	if grid != null and multiplayer.is_server():
		grid.net_peer_left(id)


func _on_connected_to_server() -> void:
	if grid != null:
		grid.net_refresh()
		send_request_board()


func _on_players_changed() -> void:
	if grid != null:
		grid.net_names_changed()


func _on_lobby_left(was_host: bool, was_client: bool) -> void:
	joined.clear()
	if grid != null:
		grid.net_on_left_lobby(was_host, was_client)


# ------------------------------------------------------------------ player -> host

func send_request_board() -> void:
	if _can_send_to_host():
		request_board.rpc_id(1)


func send_move_token(token_id: int, cell: Vector2i, segment: int) -> void:
	if _can_send_to_host():
		request_move_token.rpc_id(1, token_id, cell, segment)


func send_add_measure(from: Vector3, to: Vector3) -> void:
	if _can_send_to_host():
		request_add_measure.rpc_id(1, from, to)


func send_remove_measure(measure_id: int) -> void:
	if _can_send_to_host():
		request_remove_measure.rpc_id(1, measure_id)


@rpc("any_peer", "call_remote", "reliable")
func request_board() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	joined[sender] = true
	if grid != null:
		grid.net_peer_joined(sender)


@rpc("any_peer", "call_remote", "reliable")
func request_move_token(token_id: int, cell: Vector2i, segment: int) -> void:
	if multiplayer.is_server() and grid != null:
		grid.net_request_move(multiplayer.get_remote_sender_id(), token_id, cell, segment)


@rpc("any_peer", "call_remote", "reliable")
func request_add_measure(from: Vector3, to: Vector3) -> void:
	if multiplayer.is_server() and grid != null:
		grid.net_request_measure(multiplayer.get_remote_sender_id(), from, to)


@rpc("any_peer", "call_remote", "reliable")
func request_remove_measure(measure_id: int) -> void:
	if multiplayer.is_server() and grid != null:
		grid.net_request_remove_measure(multiplayer.get_remote_sender_id(), measure_id)


# ------------------------------------------------------------------ host -> players

func broadcast_snapshot(data: Dictionary) -> void:
	if _has_remote_peers():
		rpc_snapshot.rpc(data)


func send_snapshot(peer_id: int, data: Dictionary) -> void:
	rpc_snapshot.rpc_id(peer_id, data)


func broadcast_terrain(rect: Rect2i, levels: PackedInt32Array, interiors: Array) -> void:
	if _has_remote_peers():
		rpc_terrain.rpc(rect, levels, interiors)


func broadcast_token_added(token_id: int, cell: Vector2i, segment: int, shape: int, color: Color, owner_peer: int) -> void:
	if _has_remote_peers():
		rpc_token_added.rpc(token_id, cell, segment, shape, color, owner_peer)


func broadcast_token_moved(token_id: int, cell: Vector2i, segment: int) -> void:
	if _has_remote_peers():
		rpc_token_moved.rpc(token_id, cell, segment)


## Used to put a player's shape back where the host says it is (their move was refused).
func send_token_moved_to(peer_id: int, token_id: int, cell: Vector2i, segment: int) -> void:
	rpc_token_moved.rpc_id(peer_id, token_id, cell, segment)


func broadcast_token_removed(token_id: int) -> void:
	if _has_remote_peers():
		rpc_token_removed.rpc(token_id)


func broadcast_measure_added(measure_id: int, owner_peer: int, from: Vector3, to: Vector3) -> void:
	if _has_remote_peers():
		rpc_measure_added.rpc(measure_id, owner_peer, from, to)


func broadcast_measure_removed(measure_id: int) -> void:
	if _has_remote_peers():
		rpc_measure_removed.rpc(measure_id)


@rpc("authority", "call_remote", "reliable")
func rpc_snapshot(data: Dictionary) -> void:
	if grid != null:
		grid.net_apply_snapshot(data)


@rpc("authority", "call_remote", "reliable")
func rpc_terrain(rect: Rect2i, levels: PackedInt32Array, interiors: Array) -> void:
	if grid != null:
		grid.net_apply_terrain(rect, levels, interiors)


@rpc("authority", "call_remote", "reliable")
func rpc_token_added(token_id: int, cell: Vector2i, segment: int, shape: int, color: Color, owner_peer: int) -> void:
	if grid != null:
		grid.net_token_added(token_id, cell, segment, shape, color, owner_peer)


@rpc("authority", "call_remote", "reliable")
func rpc_token_moved(token_id: int, cell: Vector2i, segment: int) -> void:
	if grid != null:
		grid.net_token_moved(token_id, cell, segment)


@rpc("authority", "call_remote", "reliable")
func rpc_token_removed(token_id: int) -> void:
	if grid != null:
		grid.net_token_removed(token_id)


@rpc("authority", "call_remote", "reliable")
func rpc_measure_added(measure_id: int, owner_peer: int, from: Vector3, to: Vector3) -> void:
	if grid != null:
		grid.net_measure_added(measure_id, owner_peer, from, to)


@rpc("authority", "call_remote", "reliable")
func rpc_measure_removed(measure_id: int) -> void:
	if grid != null:
		grid.net_measure_removed(measure_id)
