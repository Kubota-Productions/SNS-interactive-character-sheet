extends Node
## Keeps the history of every dice roll, in the order the rolls happened.
## The Lobby autoload creates this node as /root/Lobby/DiceSync, so it sits at the same node path
## on every machine (RPCs find their target by node path).
##
## How it works
##   * Every machine reports its own finished rolls here (report_roll, called by dice_roller.gd).
##   * The GM (the host, or anyone playing without a lobby) is the one who keeps the history. A
##     player's roll is sent to the host, who writes down who rolled, which die and the result.
##     The host stamps the time, so the order is the order in which the host received the rolls.
##   * The host saves the history in the GM save data (its "roll_history" list), so it is still
##     there the next time that GM screen is opened.
##   * The host also sends every new roll to the players, so everybody sees the same history.
##     The GM can switch on "hide my rolls from players": their rolls are still saved, but are not
##     sent to the players.
##
## A roll is a small dictionary: { "t": unix time, "who": name, "d": number of sides, "r": result }
## (plus "h": true for a GM roll that was hidden from the players).

## Something was added to the history (the new roll).
signal entry_added(entry: Dictionary)
## The whole history was replaced (a player just joined, or left the lobby). Read it again.
signal history_reset

const SIDES := [2, 4, 6, 8, 10, 12, 20]
## A player who joins gets this many of the latest rolls (not the whole saved history).
const JOIN_BACKLOG := 100
## On a player's machine, and on the GM's machine while there is no GM save open, only this many
## rolls are kept in memory.
const MAX_FEED := 500
## The host ignores a player who rolls faster than this (seconds).
const MIN_ROLL_INTERVAL := 0.25
const MAX_NAME_LENGTH := 40

## GM only: rolls made on the GM's machine are saved but not shown to the players.
var hide_gm_rolls: bool = false

## The rolls this machine knows about when they are not in a GM save: what a player has been sent,
## or what the GM rolled while no GM screen was open.
var _feed: Array = []
var _last_roll_time: Dictionary = {}  # peer id -> time of their last roll (host side)
var _warned_missing_property: bool = false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	get_parent().connect("lobby_left", _on_lobby_left)


# ------------------------------------------------------------------ who is who

func _is_online() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null \
		and not (peer is OfflineMultiplayerPeer) \
		and peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED


## The GM (the host), or anyone playing without a lobby: this machine keeps the history.
func is_authority() -> bool:
	return not _is_online() or multiplayer.is_server()


## True on the GM's machine while a lobby is open.
func is_host() -> bool:
	return _is_online() and multiplayer.is_server()


func _can_send_to_host() -> bool:
	return _is_online() and not multiplayer.is_server() \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _has_peers() -> bool:
	return not multiplayer.get_peers().is_empty()


func _display_name(peer_id: int) -> String:
	var lobby := get_parent()
	var players = lobby.get("players")
	if players is Dictionary and players.has(peer_id):
		return str(players[peer_id]).left(MAX_NAME_LENGTH)
	if not _is_online():
		var typed = lobby.get("typed_name")
		return str(typed).left(MAX_NAME_LENGTH) if typed != null and str(typed) != "" else "You"
	return "GM" if peer_id == 1 else "Player"


# ------------------------------------------------------------------ reading the history

## Every roll this machine knows about, oldest first. Don't change the array.
func entries() -> Array:
	var saved = _saved_history()
	if saved != null:
		return saved
	return _feed


## The roll list inside the open GM save, or null if there is none (a player, or no GM screen is
## open, or the GM save data has no "roll_history" yet).
func _saved_history():
	if not is_authority():
		return null
	var gm = _gm_save()
	if gm == null:
		return null
	if not ("roll_history" in gm):
		if not _warned_missing_property:
			_warned_missing_property = true
			push_warning("Dice history: the GM save data has no 'roll_history'. Add  @export var roll_history: Array = []  to it, or rolls won't be saved.")
		return null
	return gm.get("roll_history")


func _gm_save():
	var globals := get_node_or_null("/root/GlobalFunctions")
	if globals == null:
		return null
	return globals.get("gamemaster")


# ------------------------------------------------------------------ adding rolls

## Called by dice_roller.gd when a die on this machine has stopped. Does nothing for a number
## that can't be a roll of that die.
func report_roll(sides: int, result: int) -> void:
	if not (sides in SIDES) or result < 1 or result > sides:
		return
	if is_authority():
		var who := _display_name(multiplayer.get_unique_id())
		_add_entry(_make_entry(who, sides, result, hide_gm_rolls))
	elif _can_send_to_host():
		submit_roll.rpc_id(1, sides, result)


func _make_entry(who: String, sides: int, result: int, hidden: bool) -> Dictionary:
	var entry := {
		"t": int(Time.get_unix_time_from_system()),
		"who": who,
		"d": sides,
		"r": result,
	}
	if hidden:
		entry["h"] = true
	return entry


## Host side: writes a roll down, tells the players, and tells the screens showing the history.
func _add_entry(entry: Dictionary) -> void:
	var saved = _saved_history()
	if saved != null:
		saved.append(entry)
		_gm_save().emit_changed()  # makes the GM save write itself to disk
	else:
		_append_to_feed(entry)

	entry_added.emit(entry)

	if not entry.get("h", false) and _has_peers():
		rpc_entry.rpc(entry)


func _append_to_feed(entry: Dictionary) -> void:
	_feed.append(entry)
	if _feed.size() > MAX_FEED:
		_feed = _feed.slice(_feed.size() - MAX_FEED)


## A roll that arrived over the network, or a saved one, as a dictionary that is safe to use.
## Returns an empty dictionary if it is not a proper roll.
static func _clean_entry(raw) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var sides = raw.get("d")
	var result = raw.get("r")
	if typeof(sides) != TYPE_INT or typeof(result) != TYPE_INT:
		return {}
	if not (sides in SIDES) or result < 1 or result > sides:
		return {}
	var who = raw.get("who", "?")
	var time = raw.get("t", 0)
	var entry := {
		"t": int(time) if typeof(time) == TYPE_INT else 0,
		"who": str(who).left(MAX_NAME_LENGTH) if typeof(who) == TYPE_STRING else "?",
		"d": sides,
		"r": result,
	}
	if raw.get("h", false) == true:
		entry["h"] = true
	return entry


# ------------------------------------------------------------------ player -> host

## A player's roll. Only the host acts on it, and it files the roll under the name of whoever sent
## it, so nobody can roll for somebody else.
@rpc("any_peer", "call_remote", "reliable")
func submit_roll(sides: int, result: int) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()

	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_roll_time.get(id, -100.0)) < MIN_ROLL_INTERVAL:
		return
	_last_roll_time[id] = now

	if not (sides in SIDES) or result < 1 or result > sides:
		return
	_add_entry(_make_entry(_display_name(id), sides, result, false))


# ------------------------------------------------------------------ host -> players

## One new roll.
@rpc("authority", "call_remote", "reliable")
func rpc_entry(entry: Dictionary) -> void:
	var clean := _clean_entry(entry)
	if clean.is_empty():
		return
	_append_to_feed(clean)
	entry_added.emit(clean)


## The latest rolls, sent to a player who has just joined.
@rpc("authority", "call_remote", "reliable")
func rpc_backlog(rolls: Array) -> void:
	_feed = []
	for raw in rolls:
		var clean := _clean_entry(raw)
		if not clean.is_empty():
			_append_to_feed(clean)
	history_reset.emit()


func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var backlog: Array = []
	var history := entries()
	for i in range(maxi(0, history.size() - JOIN_BACKLOG), history.size()):
		if not history[i].get("h", false):  # a hidden roll is never sent
			backlog.append(history[i])
	rpc_backlog.rpc_id(peer_id, backlog)


func _on_peer_disconnected(peer_id: int) -> void:
	_last_roll_time.erase(peer_id)


func _on_lobby_left(_was_host: bool, _was_client: bool) -> void:
	_last_roll_time.clear()
	_feed = []
	history_reset.emit()
