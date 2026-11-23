extends Node
## Network relay that lets the GM (the host) see every connected player's character sheet live.
## The Lobby autoload creates this node as /root/Lobby/SheetSync, so it sits at the same node path
## on every machine (RPCs find their target by node path).
##
## ONE WAY ONLY: players -> GM.
##   * A player's game watches their own sheet (GlobalFunctions.character) and sends what changed.
##   * The host keeps a view-only copy (SheetModel) of each player's sheet.
##   * There is no message that goes from the GM to a player's sheet. The host never sends sheet
##     data anywhere, and the only functions other machines can call here are the three "submit_"
##     functions below, which do nothing unless they run on the host.
##
## The GM screen (gm_sheet_wall.gd) reads the copies and draws them. Nothing on that screen can
## write back, to the players or even to the GM's own saved files.

const SheetModelScript := preload("res://code/sheet_model.gd")

## How long to wait after a change before sending, so fast typing makes a few small messages
## instead of one per key press.
const SEND_DELAY := 0.12
## Safety net: also look for changes this often, in case something changed without a signal.
const POLL_INTERVAL := 1.0

## The appearance picture is shrunk before it is sent (the whole message must stay well under
## Steam's 512 KB limit).
const IMAGE_MAX_SIDE := 512
const IMAGE_MAX_BYTES := 200000

## Limits the host enforces on what a player sends (so a broken or hacked game can't flood it).
const MAX_ENTRIES := 600
const MAX_INDEX := 9999
const MAX_TEXT_LENGTH := 30000
const MAX_NAME_LENGTH := 80
const MAX_IMAGE_BYTES_ACCEPTED := 400000

## Host side: a new player's sheet has arrived / a player's sheet is gone.
signal sheet_added(peer_id: int)
signal sheet_removed(peer_id: int)

## Host side: peer id -> SheetModel (the view-only copy of that player's sheet).
var models: Dictionary = {}

# ---- player side ----
var _watched = null  # the sheet being mirrored (GlobalFunctions.character)
var _sent: Dictionary = {}  # what the host has been told so far
var _image_signature: int = 0  # fingerprint of the picture the host has
var _need_full: bool = true
var _dirty: bool = false
var _send_timer: float = 0.0
var _poll_timer: float = 0.0
var _was_connected: bool = false


func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	var lobby := get_parent()
	lobby.connect("lobby_left", _on_lobby_left)


# ------------------------------------------------------------------ who is who

func _is_online() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null \
		and not (peer is OfflineMultiplayerPeer) \
		and peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED


## True for a player who is fully connected to the host. (The host itself never sends a sheet.)
func _can_send_to_host() -> bool:
	return _is_online() and not multiplayer.is_server() \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func name_of(peer_id: int) -> String:
	var lobby := get_parent()
	if lobby.has_method("name_of"):
		return lobby.call("name_of", peer_id)
	return "Player"


func _local_sheet():
	var globals := get_node_or_null("/root/GlobalFunctions")
	if globals == null:
		return null
	return globals.get("character")


# ------------------------------------------------------------------ player side: watch + send

func _process(delta: float) -> void:
	var connected := _can_send_to_host()
	if not connected:
		_was_connected = false
		if _watched != null:
			_stop_watching()
		return

	# Just connected (or reconnected): the host knows nothing about this sheet yet.
	if not _was_connected:
		_was_connected = true
		_need_full = true

	var sheet = _local_sheet()
	if sheet != _watched:
		_start_watching(sheet)
	if _watched == null:
		return

	_poll_timer += delta
	if _poll_timer >= POLL_INTERVAL:
		_poll_timer = 0.0
		_dirty = true

	if _dirty or _need_full:
		_send_timer -= delta
		if _send_timer <= 0.0:
			_send_timer = SEND_DELAY
			_flush()


func _start_watching(sheet) -> void:
	_stop_watching()
	_watched = sheet
	_need_full = true
	if _watched != null and _watched.has_signal("changed"):
		_watched.connect("changed", _on_sheet_changed)


func _stop_watching() -> void:
	if _watched != null and is_instance_valid(_watched) and _watched.is_connected("changed", _on_sheet_changed):
		_watched.disconnect("changed", _on_sheet_changed)
	_watched = null
	_sent = {}
	_image_signature = 0


func _on_sheet_changed() -> void:
	_dirty = true


func _on_lobby_left(_was_host: bool, _was_client: bool) -> void:
	_stop_watching()
	_was_connected = false
	_need_full = true
	for id in models.keys():
		_remove_sheet(id)


func _flush() -> void:
	_dirty = false
	if _watched == null or not is_instance_valid(_watched) or not _can_send_to_host():
		return

	var now := _snapshot(_watched)

	if _need_full:
		_need_full = false
		_sent = now
		submit_full.rpc_id(1, now)
		_send_image(true)
		return

	var delta := {}
	if now["name"] != _sent["name"]:
		delta["name"] = now["name"]
	var texts := _diff(_sent["texts"], now["texts"], "")
	if not texts.is_empty():
		delta["texts"] = texts
	var toggles := _diff(_sent["toggles"], now["toggles"], false)
	if not toggles.is_empty():
		delta["toggles"] = toggles
	var symbols := _diff(_sent["symbols"], now["symbols"], "")
	if not symbols.is_empty():
		delta["symbols"] = symbols

	if not delta.is_empty():
		_sent = now
		submit_delta.rpc_id(1, delta)

	_send_image(false)


## A plain copy of the sheet's data (ordinary dictionaries, ready to be sent).
func _snapshot(sheet) -> Dictionary:
	return {
		"name": str(sheet.get("character_name")),
		"texts": _plain(sheet.get("texts")),
		"toggles": _plain(sheet.get("toggles")),
		"symbols": _plain(sheet.get("symbols")),
	}


func _plain(source) -> Dictionary:
	var out := {}
	if source is Dictionary:
		for key in source:
			out[key] = source[key]
	return out


## What changed between two dictionaries. Entries that were removed come back as `empty_value`.
func _diff(previous: Dictionary, current: Dictionary, empty_value) -> Dictionary:
	var out := {}
	for key in current:
		if not previous.has(key) or previous[key] != current[key]:
			out[key] = current[key]
	for key in previous:
		if not current.has(key):
			out[key] = empty_value
	return out


func _send_image(force: bool) -> void:
	var raw: PackedByteArray = _watched.get("appearance_png")
	var signature := raw.size() * 31 + hash(raw)
	if not force and signature == _image_signature:
		return
	_image_signature = signature
	if raw.is_empty():
		if not force:
			submit_image.rpc_id(1, PackedByteArray())  # the picture was removed
		return
	var small := _shrink_image(raw)
	if not small.is_empty():
		submit_image.rpc_id(1, small)


## Makes the picture small enough to send: at most IMAGE_MAX_SIDE pixels wide or tall, and
## IMAGE_MAX_BYTES in size. Returns an empty array if that isn't possible.
func _shrink_image(png: PackedByteArray) -> PackedByteArray:
	var image := Image.new()
	if image.load_png_from_buffer(png) != OK:
		return PackedByteArray()

	var side := IMAGE_MAX_SIDE
	for attempt in 4:
		var copy := image.duplicate() as Image
		var longest := maxi(copy.get_width(), copy.get_height())
		if longest > side:
			var ratio := float(side) / float(longest)
			copy.resize(maxi(1, int(copy.get_width() * ratio)), maxi(1, int(copy.get_height() * ratio)), Image.INTERPOLATE_LANCZOS)
		var bytes := copy.save_png_to_buffer()
		if bytes.size() > IMAGE_MAX_BYTES:
			copy.convert(Image.FORMAT_RGB8)  # JPG has no transparency
			bytes = copy.save_jpg_to_buffer(0.85)
		if bytes.size() <= IMAGE_MAX_BYTES:
			return bytes
		side = side / 2
	return PackedByteArray()


# ------------------------------------------------------------------ player -> host
# These can be called by any player but only do something on the host, and the host files the
# data under the id of whoever sent it, so nobody can write into somebody else's copy.

@rpc("any_peer", "call_remote", "reliable")
func submit_full(state: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var clean := {
		"name": _clean_string(state.get("name", ""), MAX_NAME_LENGTH),
		"texts": _clean_strings(state.get("texts", null)),
		"toggles": _clean_toggles(state.get("toggles", null)),
		"symbols": _clean_strings(state.get("symbols", null)),
	}

	var is_new := not models.has(id)
	if is_new:
		models[id] = SheetModelScript.new()
	models[id].apply_full(clean)
	if is_new:
		sheet_added.emit(id)


@rpc("any_peer", "call_remote", "reliable")
func submit_delta(delta: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if not models.has(id):
		return  # the full sheet always arrives first; ignore anything else

	var clean := {}
	if delta.has("name"):
		clean["name"] = _clean_string(delta["name"], MAX_NAME_LENGTH)
	if delta.has("texts"):
		clean["texts"] = _clean_strings(delta["texts"], true)
	if delta.has("toggles"):
		clean["toggles"] = _clean_toggles(delta["toggles"])
	if delta.has("symbols"):
		clean["symbols"] = _clean_strings(delta["symbols"], true)
	models[id].apply_delta(clean)


@rpc("any_peer", "call_remote", "reliable")
func submit_image(bytes: PackedByteArray) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if not models.has(id) or bytes.size() > MAX_IMAGE_BYTES_ACCEPTED:
		return
	models[id].apply_image(bytes)


# ------------------------------------------------------------------ host: checking what arrives

static func _clean_string(value, max_length: int) -> String:
	if typeof(value) != TYPE_STRING:
		return ""
	return (value as String).left(max_length)


## Keeps only entries whose key is a sensible whole number and whose value is text.
## With keep_empty the empty ones stay (a delta uses "" to mean "cleared").
static func _clean_strings(source, keep_empty: bool = false) -> Dictionary:
	var out := {}
	if typeof(source) != TYPE_DICTIONARY:
		return out
	for key in source:
		if out.size() >= MAX_ENTRIES:
			break
		if typeof(key) != TYPE_INT or key < 0 or key > MAX_INDEX:
			continue
		if typeof(source[key]) != TYPE_STRING:
			continue
		var text: String = (source[key] as String).left(MAX_TEXT_LENGTH)
		if text.is_empty() and not keep_empty:
			continue
		out[key] = text
	return out


static func _clean_toggles(source) -> Dictionary:
	var out := {}
	if typeof(source) != TYPE_DICTIONARY:
		return out
	for key in source:
		if out.size() >= MAX_ENTRIES:
			break
		if typeof(key) != TYPE_INT or key < 0 or key > MAX_INDEX:
			continue
		if typeof(source[key]) != TYPE_BOOL:
			continue
		out[key] = source[key]
	return out


# ------------------------------------------------------------------ host: players leaving

func _on_peer_disconnected(id: int) -> void:
	_remove_sheet(id)


func _remove_sheet(id: int) -> void:
	if models.has(id):
		models.erase(id)
		sheet_removed.emit(id)
