extends Node2D
## Shows every connected player's character sheet on the GM screen, live and VIEW ONLY.
##
## Add it to the GM scene with one line (see GameMaster_scene.gd):
##     add_child(load("res://code/gm_sheet_wall.gd").new())
##
## The sheets sit in a row to the right of the 3D combat view, one per player, in the order the
## players' sheets arrived. A small bar at the top of the screen jumps the camera to a sheet.
## Where the data comes from: SheetSync (/root/Lobby/SheetSync) keeps a view-only copy of every
## connected player's sheet, and each gm_sheet_view.gd draws one of those copies.

const ViewScript := preload("res://code/gm_sheet_view.gd")

## Where the first sheet goes: just right of the combat view, which ends at x = 3843.
const FIRST_SHEET_X := 3963.0
const SHEET_TOP := 0.0
## Distance from one sheet to the next (a sheet is 2420 wide).
const SHEET_SPACING := 2520.0

var _sync = null
var _lobby = null
var _camera = null

var _views: Dictionary = {}  # peer id -> sheet view
var _slots: Dictionary = {}  # peer id -> position in the row (0 = first)

var _bar: PanelContainer = null
var _bar_row: HBoxContainer = null


func _ready() -> void:
	name = "SheetWall"

	_sync = get_node_or_null("/root/Lobby/SheetSync")
	_lobby = get_node_or_null("/root/Lobby")
	if _sync == null or _lobby == null:
		push_warning("GM sheet wall: /root/Lobby/SheetSync is missing, so no player sheets can be shown.")
		return

	_sync.sheet_added.connect(_add_view)
	_sync.sheet_removed.connect(_remove_view)
	_lobby.players_changed.connect(_on_players_changed)

	_build_bar()
	_find_camera()

	# Players whose sheets arrived before this screen was opened.
	for id in _sync.models:
		_add_view(id)


# ------------------------------------------------------------------ the sheets

func _add_view(id: int) -> void:
	if _views.has(id) or not _sync.models.has(id):
		return

	var slot := _free_slot()
	var view = ViewScript.new()
	view.name = "Sheet_%d" % id
	view.position = Vector2(FIRST_SHEET_X + slot * SHEET_SPACING, SHEET_TOP)
	add_child(view)

	if not view.setup(id, _sync.name_of(id), _sync.models[id]):
		view.queue_free()
		return

	_views[id] = view
	_slots[id] = slot
	_refresh_camera_bounds()
	_rebuild_bar()


func _remove_view(id: int) -> void:
	if _views.has(id):
		_views[id].queue_free()
		_views.erase(id)
	_slots.erase(id)
	_refresh_camera_bounds()
	_rebuild_bar()


## The first free place in the row. A player who leaves frees their place; the other sheets stay
## where they are, so nothing jumps around while the GM is looking at it.
func _free_slot() -> int:
	var used := _slots.values()
	var slot := 0
	while slot in used:
		slot += 1
	return slot


func _on_players_changed() -> void:
	for id in _views:
		_views[id].set_player_name(_sync.name_of(id))
	_rebuild_bar()


# ------------------------------------------------------------------ the camera

func _find_camera() -> void:
	_camera = get_viewport().get_camera_2d()


## The camera measures the content by itself a few times a second, so the sheets are picked up
## without this. This just makes it happen right away.
func _refresh_camera_bounds() -> void:
	if _camera != null and _camera.has_method("update_bounds"):
		_camera.update_bounds()


func _jump_to(id: int) -> void:
	if _camera == null or not _views.has(id):
		return
	if not ("camera_pos_x" in _camera):
		return
	var view: Node2D = _views[id]
	var half_screen: Vector2 = get_viewport_rect().size / _camera.zoom / 2.0
	# The sheet's top-left corner ends up in the top-left corner of the screen.
	_camera.camera_pos_x = view.position.x + half_screen.x
	_camera.camera_pos_y = view.position.y + half_screen.y


# ------------------------------------------------------------------ the jump bar

func _build_bar() -> void:
	var layer := CanvasLayer.new()
	layer.name = "SheetBarLayer"
	layer.layer = 20
	add_child(layer)

	_bar = PanelContainer.new()
	_bar.name = "SheetBar"
	_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_bar.offset_top = 6.0
	_bar.visible = false
	layer.add_child(_bar)

	_bar_row = HBoxContainer.new()
	_bar.add_child(_bar_row)


func _rebuild_bar() -> void:
	if _bar_row == null:
		return
	for child in _bar_row.get_children():
		_bar_row.remove_child(child)
		child.queue_free()

	var heading := Label.new()
	heading.text = "Player sheets (view only):"
	_bar_row.add_child(heading)

	var ids := _views.keys()
	ids.sort_custom(func(a, b): return _slots[a] < _slots[b])
	for id in ids:
		var button := Button.new()
		button.text = _sync.name_of(id)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_jump_to.bind(id))
		_bar_row.add_child(button)

	_bar.visible = not _views.is_empty()
	_bar.reset_size.call_deferred()
