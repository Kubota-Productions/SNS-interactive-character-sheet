extends Node2D
## Simple 2D virtual tabletop (VTT) grid.
## Attach this to a Node2D root node and run the scene.
##
## Controls
##   Left click (empty tile)    -> place a shape
##   Left click + drag (shape)  -> move it (snaps to the nearest tile on release)
##   Right click                -> delete the shape on that tile, otherwise the line under the cursor
##   Middle mouse click + drag  -> draw a measuring line (1 tile = 1 metre by default)
##   Keys 1 / 2 / 3             -> choose circle / square / triangle for new shapes
##   +1 / +10 buttons           -> grow the grid by 1 or 10 rows/columns on that side

enum ShapeType { CIRCLE, SQUARE, TRIANGLE }
enum Side { TOP, BOTTOM, LEFT, RIGHT }

const BTN_SIZE := Vector2(48, 36)
const BTN_GAP := 6.0
const NO_HOVER := Vector2i(1000000, 1000000)

@export_group("Grid")
## Starting size of the grid in tiles (columns, rows).
@export var start_size := Vector2i(20, 20)
@export var tile_size: float = 48.0
## Centers the grid in the window on start. Turn off if you use your own Camera2D.
@export var center_on_start: bool = true

@export_group("Measuring")
@export var metres_per_tile: float = 1.0
## Line ends snap to tile centers. Turn off for free-form measuring.
@export var snap_lines_to_tile_centers: bool = true
## true = diagonal counts the same as straight (D&D 5e style). false = true distance.
@export var count_diagonals_as_one: bool = false
## How close (in pixels) a right click must be to a line to delete it.
@export var line_hit_distance: float = 10.0

@export_group("Shapes")
@export var current_shape: ShapeType = ShapeType.CIRCLE
@export var shape_palette: Array[Color] = [
	Color.CRIMSON,
	Color.DODGER_BLUE,
	Color.FOREST_GREEN,
	Color.ORANGE,
	Color.MEDIUM_PURPLE,
]


class Token:
	var cell: Vector2i
	var pos: Vector2 # current center in local pixels (follows the mouse while dragging)
	var shape: int
	var color: Color


class Measurement:
	var from: Vector2
	var to: Vector2


# The grid in cell coordinates. Cells can be negative: expanding up/left just moves
# the rect's position, so existing shapes and lines never have to move.
var _grid_rect := Rect2i()

var _tokens: Array[Token] = []
var _measurements: Array[Measurement] = []

var _dragged: Token = null
var _drag_offset := Vector2.ZERO

var _measuring := false
var _measure_start := Vector2.ZERO
var _measure_end := Vector2.ZERO

var _hover_cell := NO_HOVER
var _color_index := 0

var _side_buttons: Dictionary = {} # Side -> [Button (+1), Button (+10)]


func _ready() -> void:
	_grid_rect = Rect2i(Vector2i.ZERO, start_size)

	if center_on_start:
		var size_px := Vector2(start_size) * tile_size
		position = ((get_viewport_rect().size - size_px) / 2.0).floor()

	_create_buttons()
	_layout_buttons()


# ------------------------------------------------------------------ input

func _input(event: InputEvent) -> void:
	# Releases are handled here (before the GUI sees them) so a drag or measurement
	# can never get "stuck" if the mouse is released while over an expand button.
	if event is InputEventMouseButton and not event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT: _left_released()
			MOUSE_BUTTON_MIDDLE: _finish_measuring()


func _unhandled_input(event: InputEvent) -> void:
	# _unhandled_input means clicks on the expand buttons never reach the grid.
	if event is InputEventMouseButton and event.pressed:
		_on_mouse_pressed(event)
	elif event is InputEventMouseMotion:
		_on_mouse_motion()
	elif event is InputEventKey:
		_on_key(event)


func _on_key(event: InputEventKey) -> void:
	if not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1: current_shape = ShapeType.CIRCLE
		KEY_2: current_shape = ShapeType.SQUARE
		KEY_3: current_shape = ShapeType.TRIANGLE


func _on_mouse_pressed(event: InputEventMouseButton) -> void:
	# get_local_mouse_position() already accounts for camera, zoom and node position.
	var mouse := get_local_mouse_position()
	match event.button_index:
		MOUSE_BUTTON_LEFT: _left_pressed(mouse)
		MOUSE_BUTTON_RIGHT: _right_pressed(mouse)
		MOUSE_BUTTON_MIDDLE: _start_measuring(mouse)


func _on_mouse_motion() -> void:
	var mouse := get_local_mouse_position()
	_hover_cell = _pos_to_cell(mouse)
	if _dragged:
		_dragged.pos = mouse + _drag_offset
	if _measuring:
		_measure_end = _snap_point(mouse)
	queue_redraw()


# ------------------------------------------------------------------ shapes

func _left_pressed(mouse: Vector2) -> void:
	if _measuring:
		return
	var cell := _pos_to_cell(mouse)
	if not _in_grid(cell):
		return

	var token := _token_at(cell)
	if token:
		# Start dragging, keeping the grab offset so the shape doesn't jump to the cursor.
		_dragged = token
		_drag_offset = token.pos - mouse
	else:
		_add_token(cell)
	queue_redraw()


func _left_released() -> void:
	if _dragged == null:
		return

	# Snap to the tile the shape's center is over.
	var target := _clamp_cell(_pos_to_cell(_dragged.pos))

	# If another shape already occupies that tile, send it back where it came from.
	var blocker := _token_at(target)
	if blocker != null and blocker != _dragged:
		target = _dragged.cell

	_dragged.cell = target
	_dragged.pos = _cell_to_pos(target)
	_dragged = null
	queue_redraw()


func _add_token(cell: Vector2i) -> void:
	var t := Token.new()
	t.cell = cell
	t.pos = _cell_to_pos(cell)
	t.shape = current_shape
	t.color = Color.CORNFLOWER_BLUE
	if not shape_palette.is_empty():
		t.color = shape_palette[_color_index % shape_palette.size()]
		_color_index += 1
	_tokens.append(t)


func _token_at(cell: Vector2i) -> Token:
	for t in _tokens:
		if t.cell == cell:
			return t
	return null


# ------------------------------------------------------------------ deleting

func _right_pressed(mouse: Vector2) -> void:
	if _dragged or _measuring:
		return

	# Shapes take priority over lines (lines often start/end on top of shapes).
	var token := _token_at(_pos_to_cell(mouse))
	if token:
		_tokens.erase(token)
	else:
		# Check top-most (newest) lines first.
		for i in range(_measurements.size() - 1, -1, -1):
			var m := _measurements[i]
			var closest := Geometry2D.get_closest_point_to_segment(mouse, m.from, m.to)
			if closest.distance_to(mouse) <= line_hit_distance:
				_measurements.remove_at(i)
				break
	queue_redraw()


# ------------------------------------------------------------------ measuring

func _start_measuring(mouse: Vector2) -> void:
	if _dragged:
		return
	_measuring = true
	_measure_start = _snap_point(mouse)
	_measure_end = _measure_start
	queue_redraw()


func _finish_measuring() -> void:
	if not _measuring:
		return
	_measuring = false
	# Ignore accidental middle clicks that didn't actually drag anywhere.
	if _measure_start.distance_to(_measure_end) > 4.0:
		var m := Measurement.new()
		m.from = _measure_start
		m.to = _measure_end
		_measurements.append(m)
	queue_redraw()


func _snap_point(p: Vector2) -> Vector2:
	var rect := _pixel_rect()
	p = p.clamp(rect.position, rect.end)
	if snap_lines_to_tile_centers:
		return _cell_to_pos(_clamp_cell(_pos_to_cell(p)))
	return p


func _format_distance(from: Vector2, to: Vector2) -> String:
	var delta := (to - from).abs()
	var pixels := maxf(delta.x, delta.y) if count_diagonals_as_one else delta.length()
	var tiles := pixels / tile_size
	var metres := tiles * metres_per_tile
	# e.g. "1 metre (1 tile)", "2.5 metres (2.5 tiles)"
	return "%s (%s)" % [
		_amount_text(metres, "metre", "metres"),
		_amount_text(tiles, "tile", "tiles"),
	]


func _amount_text(value: float, singular: String, plural: String) -> String:
	var rounded := snappedf(value, 0.1)
	var num: String
	if is_equal_approx(rounded, roundf(rounded)):
		num = str(int(rounded))
	else:
		num = "%.1f" % rounded
	var unit := singular if is_equal_approx(rounded, 1.0) else plural
	return "%s %s" % [num, unit]


# ------------------------------------------------------------------ expanding the grid

func _create_buttons() -> void:
	for side in [Side.TOP, Side.BOTTOM, Side.LEFT, Side.RIGHT]:
		var noun := "rows" if side == Side.TOP or side == Side.BOTTOM else "columns"
		var pair: Array[Button] = []
		for amount in [1, 10]:
			var b := Button.new()
			b.text = "+%d" % amount
			b.tooltip_text = "Add %d %s to the %s" % [amount, noun.trim_suffix("s") if amount == 1 else noun, Side.keys()[side].to_lower()]
			b.custom_minimum_size = BTN_SIZE
			b.size = BTN_SIZE
			b.focus_mode = Control.FOCUS_NONE # keep keyboard focus off so 1/2/3 keep working
			b.pressed.connect(_expand.bind(side, amount))
			add_child(b)
			pair.append(b)
		_side_buttons[side] = pair


func _expand(side: int, amount: int) -> void:
	match side:
		Side.TOP:
			_grid_rect.position.y -= amount
			_grid_rect.size.y += amount
		Side.BOTTOM:
			_grid_rect.size.y += amount
		Side.LEFT:
			_grid_rect.position.x -= amount
			_grid_rect.size.x += amount
		Side.RIGHT:
			_grid_rect.size.x += amount
	_layout_buttons()
	queue_redraw()


## Puts a +1 / +10 pair centered on each edge of the grid, just outside it.
func _layout_buttons() -> void:
	var rect := _pixel_rect()
	var center := rect.get_center()
	var pair_w := BTN_SIZE.x * 2.0 + BTN_GAP
	var pair_h := BTN_SIZE.y * 2.0 + BTN_GAP

	for i in 2:
		var step_x := (BTN_SIZE.x + BTN_GAP) * i
		var step_y := (BTN_SIZE.y + BTN_GAP) * i
		var x := center.x - pair_w / 2.0 + step_x
		var y := center.y - pair_h / 2.0 + step_y

		_side_buttons[Side.TOP][i].position = Vector2(x, rect.position.y - BTN_GAP - BTN_SIZE.y)
		_side_buttons[Side.BOTTOM][i].position = Vector2(x, rect.end.y + BTN_GAP)
		_side_buttons[Side.LEFT][i].position = Vector2(rect.position.x - BTN_GAP - BTN_SIZE.x, y)
		_side_buttons[Side.RIGHT][i].position = Vector2(rect.end.x + BTN_GAP, y)


# ------------------------------------------------------------------ grid helpers

func _pixel_rect() -> Rect2:
	return Rect2(Vector2(_grid_rect.position) * tile_size, Vector2(_grid_rect.size) * tile_size)


func _pos_to_cell(p: Vector2) -> Vector2i:
	return Vector2i((p / tile_size).floor())


func _cell_to_pos(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * tile_size


func _in_grid(cell: Vector2i) -> bool:
	return _grid_rect.has_point(cell)


func _clamp_cell(cell: Vector2i) -> Vector2i:
	return cell.clamp(_grid_rect.position, _grid_rect.end - Vector2i.ONE)


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	_draw_grid()

	# Draw the dragged shape last so it appears on top.
	for t in _tokens:
		if t != _dragged:
			_draw_token(t)
	if _dragged:
		_draw_token(_dragged)

	for m in _measurements:
		_draw_measurement(m.from, m.to, Color.RED)
	if _measuring:
		_draw_measurement(_measure_start, _measure_end, Color.ORANGE)


func _draw_grid() -> void:
	var rect := _pixel_rect()
	draw_rect(rect, Color.WHITE)

	# Light highlight on the hovered tile.
	if _in_grid(_hover_cell):
		var hover_rect := Rect2(Vector2(_hover_cell) * tile_size, Vector2(tile_size, tile_size))
		draw_rect(hover_rect, Color(0.85, 0.92, 1.0))

	var line_color := Color(0.6, 0.6, 0.6)
	for cx in range(_grid_rect.position.x, _grid_rect.end.x + 1):
		var px: float = cx * tile_size
		draw_line(Vector2(px, rect.position.y), Vector2(px, rect.end.y), line_color, 1.0)
	for cy in range(_grid_rect.position.y, _grid_rect.end.y + 1):
		var py: float = cy * tile_size
		draw_line(Vector2(rect.position.x, py), Vector2(rect.end.x, py), line_color, 1.0)

	draw_rect(rect, Color.BLACK, false, 2.0)


func _draw_token(t: Token) -> void:
	var r := tile_size * 0.35
	var outline := Color.BLACK
	match t.shape:
		ShapeType.CIRCLE:
			draw_circle(t.pos, r, t.color)
			draw_arc(t.pos, r, 0.0, TAU, 32, outline, 2.0, true)
		ShapeType.SQUARE:
			var rect := Rect2(t.pos - Vector2(r, r), Vector2(r, r) * 2.0)
			draw_rect(rect, t.color)
			draw_rect(rect, outline, false, 2.0)
		ShapeType.TRIANGLE:
			var pts := PackedVector2Array([
				t.pos + Vector2(0, -r),
				t.pos + Vector2(r, r * 0.8),
				t.pos + Vector2(-r, r * 0.8),
			])
			draw_colored_polygon(pts, t.color)
			pts.append(pts[0]) # close the outline
			draw_polyline(pts, outline, 2.0, true)


func _draw_measurement(from: Vector2, to: Vector2, color: Color) -> void:
	draw_line(from, to, color, 3.0, true)
	draw_circle(from, 5.0, color)
	draw_circle(to, 5.0, color)

	# Label with a dark backing box, centered on the line.
	var font := ThemeDB.fallback_font
	var font_size := 16
	var text := _format_distance(from, to)
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pad := Vector2(6, 3)
	var box_pos := (from + to) / 2.0 - text_size / 2.0 - pad

	draw_rect(Rect2(box_pos, text_size + pad * 2.0), Color(0, 0, 0, 0.8))
	draw_string(
		font,
		box_pos + pad + Vector2(0, font.get_ascent(font_size)),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		Color.WHITE
	)
