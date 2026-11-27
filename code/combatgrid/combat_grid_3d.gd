extends Node3D
## 3D virtual tabletop (VTT) grid with adjustable tile heights.
##
## Setup: attach this to the root Node3D of a new scene (keep it at the origin) and add
## the rts_camera.gd rig (a Node3D with a Camera3D child). Lighting, environment and all
## UI are created in code. 1 world unit = 1 metre = 1 tile.
##
## Controls
##   Left click (empty tile)       -> place a shape
##   Left drag (a shape)           -> move it to another tile
##   Left drag (empty tile)        -> select an area
##   Left drag (inside selection)  -> pull the mouse up to raise / down to lower the area
##                                    (below ground level digs a pit)
##   Ctrl + left drag (anywhere)   -> grab the current selection from anywhere on screen
##                                    (handy when a deep pit's floor is hidden from view)
##   Page Up / Page Down           -> raise/lower the selection by one step
##   Shift + click (raised tile)   -> hollow out the level you clicked: it turns see-through and
##                                    becomes an interior (click it again to fill it back in).
##                                    If the tile is inside the selection, the same level is
##                                    toggled on every selected tile, so you can make rooms fast.
##                                    Hollow levels are outlined in white so the grid still shows.
##   Left click (floor of a room)  -> place a shape inside it
##   Esc                           -> clear the selection
##   Right click                   -> delete the shape under the cursor, otherwise the line
##   Middle mouse drag             -> draw a measuring line
##   Keys 1 / 2 / 3                -> choose circle / square / triangle for new shapes
##   +1 / +10 buttons              -> grow the grid by that many rows/columns on that side
##
## Multiplayer (host-authoritative; see the Lobby and CombatSync autoloads)
##   The host is the storyteller: every tool above works for them and they own the board.
##   Every connected player gets one shape with their name floating above it. Players can only
##   drag their own shape, draw measuring lines (middle drag) and delete their own lines.
##   They cannot change the terrain, hollow out levels, resize the grid or touch anyone else's
##   shape. The host checks every request and then copies the result to everybody.
##   Without a lobby this behaves exactly like the single player version.

enum ShapeType { CIRCLE, SQUARE, TRIANGLE }
enum Side { NORTH, SOUTH, WEST, EAST }
enum Mode { IDLE, PENDING, SELECTING, PULLING, DRAGGING_TOKEN, MEASURING }

const TILE_VISUAL := 0.96     # tiles are drawn slightly smaller, leaving a thin grid line
const SLAB_DEPTH := 0.1       # thickness of a flat tile (and of the floor under a hollow level)
const TOKEN_RADIUS := 0.35
const TOKEN_HEIGHT := 0.7
const DRAG_LIFT := 0.3        # shapes hover this high while being moved
const DRAG_THRESHOLD := 6.0   # pixels of movement before a click turns into a drag
const MIN_PULL_PIXELS := 8.0  # least mouse travel per height level (matters for top-down views)
const NO_CELL := Vector2i(1000000, 1000000)
const BTN_SIZE := Vector2(48, 36)
const BTN_GAP := 6.0
const EDGE_OFFSET := 1.2      # how far outside the grid the +1/+10 buttons are anchored
const NET_FLUSH_INTERVAL := 0.1        # seconds between terrain updates sent to the players
const NAME_TAG_HEIGHT := 0.5          # how far above a shape its name floats
const MAX_LINES_PER_PLAYER := 10      # a player's oldest line goes when they draw more than this
const MAX_LINE_LENGTH := 500.0
const PENDING_LINE_TIMEOUT_MS := 5000 # how long a player's new line waits for the host's OK
const UI_REFERENCE_HEIGHT := 1080.0   # labels/buttons are normal size in a viewport this tall
const HOST_ID := 1
const NPC_OWNER := 0                  # owner of the shapes the storyteller placed

const COL_BASE := Color.WHITE
const COL_HOVER := Color(0.82, 0.9, 1.0)
const COL_SELECT := Color(0.45, 0.7, 1.0)
# Tints of the see-through interiors (how see-through they are is the interior_opacity setting)
const GLASS_TINT := Color(0.7, 0.88, 1.0)
const GLASS_TINT_HOVER := Color(0.8, 0.92, 1.0)
const GLASS_TINT_SELECT := Color(0.45, 0.7, 1.0)
const EDGE_LIFT := 0.004      # white outlines float this far off the surfaces so they never flicker

const NEIGHBORS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]

@export_group("Grid")
## Starting size of the grid in tiles (columns, rows).
@export var start_size := Vector2i(20, 20)
## Metres per height level.
@export var height_step: float = 1.0
## Highest allowed level (above the ground).
@export var max_height: int = 30
## Lowest allowed level (negative = below the ground, so you can dig pits).
@export_range(-100, 0) var min_height: int = -10

@export_group("Measuring")
## Line ends snap to the center of a tile (at shape height). Turn off for free-form measuring.
@export var snap_lines_to_tile_centers: bool = true
## true = diagonals count the same as straight lines (D&D 5e style). false = true distance.
@export var count_diagonals_as_one: bool = false
## How close (in screen pixels) a right click must be to a line to delete it.
@export var line_hit_distance: float = 12.0

@export_group("Shapes")
@export var current_shape: ShapeType = ShapeType.CIRCLE
@export var shape_palette: Array[Color] = [
	Color.CRIMSON,
	Color.DODGER_BLUE,
	Color.FOREST_GREEN,
	Color.ORANGE,
	Color.MEDIUM_PURPLE,
]

@export_group("Interiors")
## How see-through hollow levels are (0 = invisible, 1 = solid). The white outlines stay either way.
@export_range(0.0, 1.0) var interior_opacity: float = 0.18

@export_group("Scene")
## Adds a sun and a background/ambient light so you don't need to set them up.
@export var add_default_lighting: bool = true


class Token:
	var cell: Vector2i
	var segment: int = -1 # -1 = on top of the tile, k = standing inside the hollow level k
	var shape: int
	var color: Color
	var node: MeshInstance3D
	var id := 0
	var owner_peer := 0 # NPC_OWNER = placed by the storyteller, else the peer id of the player it belongs to
	var tag: Label3D    # the player's name floating above the shape


class Measurement:
	var from: Vector3
	var to: Vector3
	var line: MeshInstance3D
	var label: Label3D
	var mat: StandardMaterial3D
	var id := 0         # 0 = a player's new line that the host hasn't confirmed yet
	var owner_peer := 0
	var born_msec := 0


class Hit:
	var cell: Vector2i
	var point: Vector3
	var token: Token = null
	var top_face := false # true if the ray landed on the top of a solid part (a roof or a floor)
	var t: float


# The grid in cell coordinates (x = world X, y = world Z). Cells can be negative:
# expanding north/west just moves the rect's position, so nothing else has to move.
var _grid_rect := Rect2i()
var _levels: Dictionary = {} # Vector2i -> int (missing = level 0)

var _multimesh: MultiMesh      # one plain column per tile
var _extra_solid: MultiMesh    # solid floors/walls/roofs of tiles that have a hollow level
var _extra_glass: MultiMesh    # the see-through volumes
var _extras_dirty := false
var _edge_mesh: ArrayMesh      # white outlines around the hollow levels
var _edge_verts := PackedVector3Array()
var _ground: MeshInstance3D

# Hollow levels: Vector2i -> { level index (int): true }. Level k of a tile is the 1 step tall
# slice between k * height_step and (k + 1) * height_step above the ground.
var _interiors: Dictionary = {}

var _tokens: Array[Token] = []
var _measurements: Array[Measurement] = []
var _measure: Measurement = null # the line currently being drawn

var _mode := Mode.IDLE
var _press_cell := NO_CELL
var _press_mouse := Vector2.ZERO
var _press_point := Vector3.ZERO
var _press_in_selection := false
var _press_segment := -1
var _handle_only := false # Ctrl+drag: a pull handle, so a plain click does nothing

var _selection := Rect2i()
var _has_selection := false
var _pull_start_levels: Dictionary = {}
var _pull_delta := 0
var _pull_pixels := 40.0 # mouse travel per level, worked out from the camera when a pull starts

var _dragged: Token = null
var _drag_cell := NO_CELL
var _drag_segment := -1

var _hover_cell := NO_CELL
var _color_index := 0

var _ui: CanvasLayer
var _status: Label
var _side_buttons: Dictionary = {} # Side -> [Button (+1), Button (+10)]


# --- multiplayer ---
var _sync = null          # the CombatSync node under the Lobby autoload (null = no Lobby: single player)
var _online := false      # connected to a lobby
var _authority := true    # the storyteller, or playing without a lobby: may edit the board
var _my_id := HOST_ID
var _mouse_over := true   # false while the board is shown in a container the mouse isn't over
var _next_token_id := 1
var _next_measure_id := 1
var _net_dirty_levels: Dictionary = {}    # Vector2i -> true: terrain changes not sent yet
var _net_dirty_interiors: Dictionary = {}
var _net_rect_dirty := false
var _net_timer := 0.0
var _pending_lines: Array[Measurement] = [] # my lines waiting for the host to confirm them


func _ready() -> void:
	_isolate_world()
	_grid_rect = Rect2i(Vector2i.ZERO, start_size)
	if add_default_lighting:
		_add_default_lighting()
	_setup_grid_mesh()
	_create_ui()
	_rebuild_grid()
	_update_status()
	if get_viewport().get_camera_3d() == null:
		push_warning("vtt_grid_3d: no Camera3D found. Add the rts_camera.gd rig (Node3D + Camera3D child).")
	_hook_container()
	_net_setup()


func _exit_tree() -> void:
	if is_instance_valid(_sync):
		_sync.unregister_grid(self)


func _process(delta: float) -> void:
	_refresh_role()
	_layout_buttons()
	if _extras_dirty:
		_rebuild_extras()
	_release_failsafe()
	_expire_pending_lines()
	if _authority and _online:
		_net_timer += delta
		if _net_timer >= NET_FLUSH_INTERVAL:
			_net_timer = 0.0
			_flush_terrain()


## The combat view lives in a SubViewport. Giving it its own 3D world keeps its tiles, sun and sky
## apart from the dice roller / genotype viewers, which would otherwise share one world with it.
func _isolate_world() -> void:
	var vp := get_viewport()
	if vp is SubViewport and not vp.own_world_3d:
		vp.own_world_3d = true


## When the board is shown inside a SubViewportContainer, remember whether the mouse is over it,
## so keys typed somewhere else (a text field on the sheet, say) aren't read as board shortcuts.
func _hook_container() -> void:
	var container := get_viewport().get_parent() as SubViewportContainer
	if container == null:
		return
	_mouse_over = false
	container.mouse_entered.connect(func(): _mouse_over = true)
	container.mouse_exited.connect(func():
		_mouse_over = false
		_set_hover(NO_CELL)
	)


## A mouse release that happens outside the container can be missed. If no button is held any
## more, finish whatever the grid thought was still going on so it can't get stuck.
func _release_failsafe() -> void:
	match _mode:
		Mode.IDLE:
			return
		Mode.MEASURING:
			if not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
				_finish_measuring()
		_:
			if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				_left_released()


# ------------------------------------------------------------------ setup

func _add_default_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	sun.light_energy = 0.7
	sun.shadow_enabled = true
	add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.14, 0.18)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.45
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


func _setup_grid_mesh() -> void:
	# Plain tiles are ONE MultiMesh of unit boxes, each stretched to its tile's size.
	var solid_mat := StandardMaterial3D.new()
	solid_mat.vertex_color_use_as_albedo = true # per-tile colour = selection/hover highlight
	solid_mat.roughness = 0.9
	_multimesh = _make_multimesh(solid_mat, true)

	# Tiles with a hollow level are drawn by two extra MultiMeshes instead (_rebuild_extras):
	# their solid floors/walls/roofs, and the see-through volumes.
	_extra_solid = _make_multimesh(solid_mat, true)
	var glass_mat := StandardMaterial3D.new()
	glass_mat.vertex_color_use_as_albedo = true
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.roughness = 0.2
	_extra_glass = _make_multimesh(glass_mat, false)

	# White outlines along the edges of every hollow level, so the grid and the levels can
	# still be seen inside the see-through volumes.
	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.albedo_color = Color.WHITE
	_edge_mesh = ArrayMesh.new()
	var edges := MeshInstance3D.new()
	edges.mesh = _edge_mesh
	edges.material_override = line_mat
	edges.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(edges)

	# Dark base plate: shows through the gaps between tiles and reads as grid lines.
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.18, 0.19, 0.22)
	ground_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var plane := PlaneMesh.new()
	plane.material = ground_mat
	_ground = MeshInstance3D.new()
	_ground.mesh = plane
	_ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ground)


func _make_multimesh(mat: Material, casts_shadow: bool) -> MultiMesh:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	box.material = mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = box

	var instance := MultiMeshInstance3D.new()
	instance.multimesh = mm
	if not casts_shadow:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return mm


func _create_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)

	_status = Label.new()
	_status.position = Vector2(14, 10)
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_status.add_theme_constant_override("outline_size", 6)
	_ui.add_child(_status)

	for side in [Side.NORTH, Side.SOUTH, Side.WEST, Side.EAST]:
		var noun := "rows" if side == Side.NORTH or side == Side.SOUTH else "columns"
		var pair: Array[Button] = []
		for amount in [1, 10]:
			var b := Button.new()
			b.text = "+%d" % amount
			b.tooltip_text = "Add %d %s to the %s" % [
				amount,
				noun.trim_suffix("s") if amount == 1 else noun,
				Side.keys()[side].to_lower(),
			]
			b.size = BTN_SIZE
			b.focus_mode = Control.FOCUS_NONE # keep keyboard focus off so 1/2/3 keep working
			b.pressed.connect(_expand.bind(side, amount))
			_ui.add_child(b)
			pair.append(b)
		_side_buttons[side] = pair


# ------------------------------------------------------------------ input

func _input(event: InputEvent) -> void:
	# Releases are handled here (before the GUI sees them) so a drag can never get
	# "stuck" if the mouse is released while hovering one of the expand buttons.
	if event is InputEventMouseButton and not event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT: _left_released()
			MOUSE_BUTTON_MIDDLE: _finish_measuring()


func _unhandled_input(event: InputEvent) -> void:
	# _unhandled_input means clicks on the UI buttons never reach the grid.
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT: _left_pressed()
			MOUSE_BUTTON_RIGHT: _right_pressed()
			MOUSE_BUTTON_MIDDLE: _start_measuring()
	elif event is InputEventMouseMotion:
		_on_mouse_motion()
	elif event is InputEventKey:
		_on_key(event)


func _on_key(event: InputEventKey) -> void:
	if not _authority or not _mouse_over:
		return # players have no shortcuts, and keys typed elsewhere are not for the board
	if not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1: current_shape = ShapeType.CIRCLE
		KEY_2: current_shape = ShapeType.SQUARE
		KEY_3: current_shape = ShapeType.TRIANGLE
		KEY_PAGEUP: _shift_selection(1)
		KEY_PAGEDOWN: _shift_selection(-1)
		KEY_ESCAPE:
			if _has_selection:
				_set_selection(Rect2i(), false)
				get_viewport().set_input_as_handled()


func _left_pressed() -> void:
	if _mode != Mode.IDLE:
		return

	# Players can only pick up their own shape. Nothing else on the board answers to them.
	if not _authority:
		var mine := _pick()
		if mine and mine.token and mine.token.owner_peer == _my_id:
			_begin_token_drag(mine.token)
		return

	# Ctrl + drag grabs the current selection whatever is under the cursor, so a pit that is
	# too deep to see the bottom of can still be pulled back up.
	if _has_selection and Input.is_key_pressed(KEY_CTRL):
		_press_cell = _selection.position
		_press_point = _selection_handle_point()
		_press_mouse = get_viewport().get_mouse_position()
		_press_in_selection = true
		_handle_only = true
		_mode = Mode.PENDING
		return

	# Shift + click hollows out (or fills back in) the level that was clicked.
	if Input.is_key_pressed(KEY_SHIFT):
		var column := _pick(false) # shapes don't get in the way
		if column:
			_toggle_interior(column)
		return

	_handle_only = false
	var hit := _pick()
	if hit == null:
		_set_selection(Rect2i(), false) # clicking empty space deselects
		return

	_press_cell = hit.cell
	_press_point = hit.point
	_press_mouse = get_viewport().get_mouse_position()

	if hit.token:
		_begin_token_drag(hit.token)
	else:
		# Not decided yet: a plain click places a shape, a drag selects or pulls.
		_press_segment = _standing_segment(hit)
		_press_in_selection = _has_selection and _selection.has_point(hit.cell)
		_mode = Mode.PENDING


func _begin_token_drag(t: Token) -> void:
	_mode = Mode.DRAGGING_TOKEN
	_dragged = t
	_drag_cell = t.cell
	_drag_segment = t.segment
	_place_token_at(_dragged, _drag_cell, _drag_segment, DRAG_LIFT)


func _left_released() -> void:
	match _mode:
		Mode.PENDING:
			# The mouse never moved far enough to count as a drag: it was a click.
			if not _handle_only:
				if not _press_in_selection:
					_set_selection(Rect2i(), false)
				if _token_at(_press_cell, _press_segment) == null:
					_add_token(_press_cell, _press_segment)
		Mode.DRAGGING_TOKEN:
			_commit_token_move(_dragged, _drag_cell, _drag_segment)
			_dragged = null
		Mode.SELECTING, Mode.PULLING:
			pass # selection / new heights simply stay as they are
		_:
			return # IDLE or MEASURING: nothing to finish
	_mode = Mode.IDLE


func _on_mouse_motion() -> void:
	var mouse := get_viewport().get_mouse_position()

	# A press becomes a drag once the mouse has moved a few pixels.
	if _mode == Mode.PENDING and mouse.distance_to(_press_mouse) > DRAG_THRESHOLD:
		if _press_in_selection:
			_begin_pull()
		else:
			_mode = Mode.SELECTING

	match _mode:
		Mode.PULLING:
			# Mouse up = raise, mouse down = lower.
			_set_pull(roundi((_press_mouse.y - mouse.y) / _pull_pixels))
		Mode.SELECTING:
			var hit := _pick(false)
			if hit:
				_set_selection(_rect_from_cells(_press_cell, hit.cell), true)
		Mode.DRAGGING_TOKEN:
			var hit := _pick(false) # ignore shapes so we find the tile underneath
			if hit:
				var segment := _standing_segment(hit)
				var other := _token_at(hit.cell, segment)
				if other == null or other == _dragged:
					_drag_cell = hit.cell
					_drag_segment = segment
					_place_token_at(_dragged, _drag_cell, _drag_segment, DRAG_LIFT)
		Mode.MEASURING:
			var hit := _pick()
			if hit:
				_measure.to = _measure_point(hit)
				_update_measurement(_measure)
		Mode.IDLE:
			var hit := _pick()
			_set_hover(hit.cell if hit else NO_CELL)


# ------------------------------------------------------------------ picking

## Casts a ray from the mouse and returns the first column (or shape) it touches, or null.
func _pick(include_tokens: bool = true) -> Hit:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var mouse := get_viewport().get_mouse_position()
	var origin := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)

	var best := _raycast_columns(origin, dir)
	var best_t := INF
	if best:
		best_t = best.t

	if include_tokens:
		var half := Vector3(TOKEN_RADIUS, TOKEN_HEIGHT / 2.0, TOKEN_RADIUS)
		for t in _tokens:
			var box := AABB(t.node.position - half, half * 2.0)
			var p = box.intersects_ray(origin, dir) # Vector3 or null
			if p != null:
				var dist := origin.distance_to(p)
				if dist < best_t:
					best_t = dist
					best = _make_hit(t.cell, p, dist)
					best.token = t
	return best


## Walks the ray through the grid one cell at a time (a 2D "DDA" in the XZ plane) and
## stops at the first column whose top the ray passes below.
func _raycast_columns(origin: Vector3, dir: Vector3) -> Hit:
	var min_p := Vector3(_grid_rect.position.x, min_height * height_step, _grid_rect.position.y)
	var max_p := Vector3(_grid_rect.end.x, max_height * height_step, _grid_rect.end.y)

	# Clip the ray to the grid's bounding box first (slab method).
	var t_enter := 0.0
	var t_exit := INF
	for axis in 3:
		if absf(dir[axis]) < 0.000001:
			if origin[axis] < min_p[axis] or origin[axis] > max_p[axis]:
				return null
		else:
			var t1: float = (min_p[axis] - origin[axis]) / dir[axis]
			var t2: float = (max_p[axis] - origin[axis]) / dir[axis]
			t_enter = maxf(t_enter, minf(t1, t2))
			t_exit = minf(t_exit, maxf(t1, t2))
	if t_enter > t_exit:
		return null

	var start := origin + dir * (t_enter + 0.0001)
	var cell := _clamp_cell(Vector2i(floori(start.x), floori(start.z)))

	var step_x := 1 if dir.x > 0.0 else -1
	var step_z := 1 if dir.z > 0.0 else -1
	var t_delta_x := INF
	var t_delta_z := INF
	var t_next_x := INF
	var t_next_z := INF
	if absf(dir.x) > 0.000001:
		t_delta_x = absf(1.0 / dir.x)
		t_next_x = (cell.x + (1 if dir.x > 0.0 else 0) - origin.x) / dir.x
	if absf(dir.z) > 0.000001:
		t_delta_z = absf(1.0 / dir.z)
		t_next_z = (cell.y + (1 if dir.z > 0.0 else 0) - origin.z) / dir.z

	var t_in := t_enter
	while t_in <= t_exit:
		var t_out := minf(minf(t_next_x, t_next_z), t_exit)
		var found := _ray_vs_cell(cell, origin, dir, t_in, t_out) # (t, entered through a top face?)
		if found.x < INF:
			var h := _make_hit(cell, origin + dir * found.x, found.x)
			h.top_face = found.y > 0.5
			return h

		if t_next_x < t_next_z:
			cell.x += step_x
			t_in = t_next_x
			t_next_x += t_delta_x
		else:
			cell.y += step_z
			t_in = t_next_z
			t_next_z += t_delta_z
		if not _in_grid(cell):
			break
	return null


## Tests the part of the ray that is inside one cell against that cell's solid parts. A plain
## tile is solid all the way down; a tile with hollow levels only has its floor/walls/roofs, so
## rays pass straight through the hollow parts (that's how you click on a room's floor).
## Returns Vector2(t of first contact or INF, 1.0 if that was a top face).
func _ray_vs_cell(cell: Vector2i, origin: Vector3, dir: Vector3, t_in: float, t_out: float) -> Vector2:
	if not _is_hollow(cell):
		return _ray_vs_slab(origin.y, dir.y, t_in, t_out, -1000000.0, _top_y(cell))
	var best := Vector2(INF, 0.0)
	for run in _cell_runs(cell, -1000000.0):
		if run.z > 0.5:
			continue # a hollow part: nothing to hit
		var r := _ray_vs_slab(origin.y, dir.y, t_in, t_out, run.x, run.y)
		if r.x < best.x:
			best = r
	return best


## One solid slab (lo <= y <= hi) spanning the whole cell footprint.
func _ray_vs_slab(oy: float, dy: float, t_in: float, t_out: float, lo: float, hi: float) -> Vector2:
	var y_in := oy + dy * t_in
	var y_out := oy + dy * t_out
	if y_in >= lo and y_in <= hi: # came in through a side wall (or started inside)
		return Vector2(t_in, 0.0)
	if dy < -0.000001 and y_in > hi and y_out <= hi: # came down onto the top
		return Vector2((hi - oy) / dy, 1.0)
	if dy > 0.000001 and y_in < lo and y_out >= lo: # came up into the underside
		return Vector2((lo - oy) / dy, 0.0)
	return Vector2(INF, 0.0)


func _make_hit(cell: Vector2i, point: Vector3, t: float) -> Hit:
	var h := Hit.new()
	h.cell = cell
	h.point = point
	h.t = t
	return h


# ------------------------------------------------------------------ heights

func _level(cell: Vector2i) -> int:
	return _levels.get(cell, 0)


func _set_level(cell: Vector2i, level: int) -> void:
	if level == 0:
		_levels.erase(cell)
	else:
		_levels[cell] = level
	if _authority and _online:
		_net_dirty_levels[cell] = true


func _top_y(cell: Vector2i) -> float:
	return _level(cell) * height_step


func _begin_pull() -> void:
	_pull_start_levels.clear()
	for c in _cells_in(_selection):
		_pull_start_levels[c] = _level(c)
	_pull_delta = 0
	_mode = Mode.PULLING

	# Measure how far one level moves on screen at the spot that was grabbed, so the surface
	# stays under the cursor as you pull (instead of lagging behind or racing ahead of it).
	var cam := get_viewport().get_camera_3d()
	if cam and not cam.is_position_behind(_press_point):
		var a := cam.unproject_position(_press_point)
		var b := cam.unproject_position(_press_point + Vector3.UP * height_step)
		_pull_pixels = maxf(a.distance_to(b), MIN_PULL_PIXELS)
	else:
		_pull_pixels = 40.0


## Every selected tile moves by the same amount from where it started, so any relief
## inside the selection is kept (tiles just stop at min_height / max_height).
func _set_pull(delta_levels: int) -> void:
	if not _authority:
		return
	if delta_levels == _pull_delta:
		return
	_pull_delta = delta_levels
	for c in _pull_start_levels:
		_set_level(c, clampi(_pull_start_levels[c] + delta_levels, min_height, max_height))
	_refresh_area(_selection)
	_refresh_tokens()
	_update_status()


## The middle of the selection's surface, used to work out how far the mouse must travel
## per level when the selection is grabbed with Ctrl.
func _selection_handle_point() -> Vector3:
	var middle := _selection.position + _selection.size / 2
	return Vector3(
		_selection.position.x + _selection.size.x / 2.0,
		_top_y(middle),
		_selection.position.y + _selection.size.y / 2.0
	)


func _shift_selection(levels: int) -> void:
	if not _authority:
		return
	if not _has_selection or _mode != Mode.IDLE:
		return
	for c in _cells_in(_selection):
		_set_level(c, clampi(_level(c) + levels, min_height, max_height))
	_refresh_area(_selection)
	_refresh_tokens()
	_update_status()


# ------------------------------------------------------------------ levels & interiors

func _is_interior(cell: Vector2i, k: int) -> bool:
	if k < 0 or not _interiors.has(cell):
		return false
	return k < _level(cell) and _interiors[cell].has(k)


## True if the tile has at least one hollow level that currently exists.
## (If a tile is lowered below a hollow level, that level's flag just goes dormant, and it
## comes back if the tile is raised again.)
func _is_hollow(cell: Vector2i) -> bool:
	if not _interiors.has(cell):
		return false
	var level := _level(cell)
	for k in _interiors[cell]:
		if k < level:
			return true
	return false


func _set_interior(cell: Vector2i, k: int, hollow: bool) -> void:
	if hollow:
		if not _interiors.has(cell):
			_interiors[cell] = {}
		_interiors[cell][k] = true
	elif _interiors.has(cell):
		_interiors[cell].erase(k)
		if _interiors[cell].is_empty():
			_interiors.erase(cell)
	_extras_dirty = true
	if _authority and _online:
		_net_dirty_interiors[cell] = true


## Height shapes stand at on top of a tile: the highest solid surface (the roof, or the floor
## of the top level if that level has been hollowed out).
func _surface_y(cell: Vector2i) -> float:
	var level := _level(cell)
	if level <= 0:
		return level * height_step
	var k := level - 1
	while k >= 0 and _is_interior(cell, k):
		k -= 1
	return (k + 1) * height_step


## Where a shape stands: on the floor of hollow level `segment`, or (-1) on top of the tile.
func _floor_y_for(cell: Vector2i, segment: int) -> float:
	if segment >= 0 and _is_interior(cell, segment):
		return segment * height_step
	return _surface_y(cell)


## If the ray landed on the floor of a hollow level, which level is it (so a shape can be put
## inside). Otherwise -1: the shape goes on top of the tile.
func _standing_segment(hit: Hit) -> int:
	if hit.top_face:
		var k := roundi(hit.point.y / height_step)
		if _is_interior(hit.cell, k):
			return k
	return -1


## Which level of the tile did the ray touch? -1 if the tile isn't raised (nothing to hollow).
func _segment_under_hit(hit: Hit) -> int:
	var level := _level(hit.cell)
	if level <= 0:
		return -1
	var s := hit.point.y / height_step
	if hit.top_face:
		# Landed on a top face. If the level above it is a room, that's the one meant (so
		# clicking a room's floor fills it back in); otherwise the level just below.
		var above := roundi(s)
		if _is_interior(hit.cell, above):
			return above
		return clampi(above - 1, 0, level - 1)
	return clampi(floori(s), 0, level - 1)


func _toggle_interior(hit: Hit) -> void:
	if not _authority:
		return
	var k := _segment_under_hit(hit)
	if k < 0:
		_status.text = "Raise the tile first, then Shift + click one of its levels to hollow it out"
		return
	var hollow := not _is_interior(hit.cell, k)

	# Inside the selection? Then change that level on every selected tile at once.
	var area := Rect2i(hit.cell, Vector2i.ONE)
	if _has_selection and _selection.has_point(hit.cell):
		area = _selection
	for c in _cells_in(area):
		if _level(c) > k:
			_set_interior(c, k, hollow)
	_refresh_area(area)
	_refresh_tokens()


## The solid and hollow parts of a tile, bottom to top, as Vector3(low y, high y, 1 if hollow).
## `bottom` is where the lowest solid part starts.
func _cell_runs(cell: Vector2i, bottom: float) -> Array[Vector3]:
	var runs: Array[Vector3] = []
	var level := _level(cell)
	if level <= 0:
		runs.append(Vector3(bottom, level * height_step, 0.0))
		return runs
	if _is_interior(cell, 0):
		runs.append(Vector3(bottom, 0.0, 0.0)) # the floor under a hollow ground level
	var k := 0
	while k < level:
		var hollow := _is_interior(cell, k)
		var start := k
		while k < level and _is_interior(cell, k) == hollow:
			k += 1
		var low := bottom if (start == 0 and not hollow) else start * height_step
		runs.append(Vector3(low, k * height_step, 1.0 if hollow else 0.0))
	return runs


# ------------------------------------------------------------------ selection

func _set_selection(rect: Rect2i, has: bool) -> void:
	if has == _has_selection and rect == _selection:
		return
	var old_rect := _selection
	var had := _has_selection
	_selection = rect
	_has_selection = has
	if had:
		for c in _cells_in(old_rect):
			_update_cell_color(c)
	if has:
		for c in _cells_in(rect):
			_update_cell_color(c)
	_update_status()


func _set_hover(cell: Vector2i) -> void:
	if cell == _hover_cell:
		return
	var old := _hover_cell
	_hover_cell = cell
	_update_cell_color(old)
	_update_cell_color(cell)


func _rect_from_cells(a: Vector2i, b: Vector2i) -> Rect2i:
	var lo := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
	var hi := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y))
	return Rect2i(lo, hi - lo + Vector2i.ONE)


func _cells_in(rect: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cy in range(rect.position.y, rect.end.y):
		for cx in range(rect.position.x, rect.end.x):
			out.append(Vector2i(cx, cy))
	return out


func _update_status() -> void:
	if not _authority:
		_status.text = "Drag your own shape to move it   |   Middle-drag to measure   |   Right-click a line you drew to remove it"
		return
	if not _has_selection:
		_status.text = "Drag across the grid to select an area"
		return
	var lo := max_height
	var hi := min_height
	for c in _cells_in(_selection):
		lo = mini(lo, _level(c))
		hi = maxi(hi, _level(c))
	var height_text := _num(lo * height_step) + " m"
	if lo != hi:
		height_text = "%s to %s m" % [_num(lo * height_step), _num(hi * height_step)]
	_status.text = "Selected %d x %d tiles  |  height: %s" % [_selection.size.x, _selection.size.y, height_text]


# ------------------------------------------------------------------ shapes

## Storyteller only: puts a new shape on the board (and on every player's screen).
func _add_token(cell: Vector2i, segment: int = -1) -> void:
	if not _authority:
		return
	var t := _spawn_token(_alloc_token_id(), cell, segment, current_shape, _next_color(), NPC_OWNER)
	_broadcast_token_added(t)


func _next_color() -> Color:
	var color := Color.CORNFLOWER_BLUE
	if not shape_palette.is_empty():
		color = shape_palette[_color_index % shape_palette.size()]
		_color_index += 1
	return color


func _alloc_token_id() -> int:
	_next_token_id += 1
	return _next_token_id - 1


## Builds a shape's node (plus the floating name for a player's shape) and registers it.
func _spawn_token(id: int, cell: Vector2i, segment: int, shape: int, color: Color, owner_peer: int) -> Token:
	var t := Token.new()
	t.id = id
	t.cell = cell
	t.segment = segment
	t.shape = shape
	t.color = color
	t.owner_peer = owner_peer

	var mat := StandardMaterial3D.new()
	mat.albedo_color = t.color
	t.node = MeshInstance3D.new()
	t.node.mesh = _make_token_mesh(t.shape)
	t.node.material_override = mat
	add_child(t.node)

	if owner_peer != NPC_OWNER:
		t.tag = Label3D.new()
		t.tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		t.tag.no_depth_test = true # readable even when the shape is behind a wall
		t.tag.pixel_size = 0.008
		t.tag.font_size = 56
		t.tag.outline_size = 14
		t.tag.position = Vector3(0.0, TOKEN_HEIGHT / 2.0 + NAME_TAG_HEIGHT, 0.0)
		t.node.add_child(t.tag) # a child of the shape, so it follows the shape around
		_style_tag(t)

	_tokens.append(t)
	_place_token(t)
	return t


func _style_tag(t: Token) -> void:
	if t.tag == null:
		return
	t.tag.text = _name_for(t.owner_peer)
	# Your own name is yellow so you can find yourself.
	t.tag.modulate = Color(1.0, 0.9, 0.45) if (_online and t.owner_peer == _my_id) else Color.WHITE


func _refresh_tags() -> void:
	for t in _tokens:
		_style_tag(t)


func _name_for(peer_id: int) -> String:
	if is_instance_valid(_sync):
		return _sync.name_of(peer_id)
	return "Player"


## Local only: takes a shape off this machine's board (the callers tell the other players).
func _remove_token(t: Token) -> void:
	if t == _dragged:
		_dragged = null
		_mode = Mode.IDLE
	t.node.queue_free()
	_tokens.erase(t)


func _make_token_mesh(shape: int) -> Mesh:
	if shape == ShapeType.SQUARE:
		var box := BoxMesh.new()
		box.size = Vector3(TOKEN_RADIUS * 2.0, TOKEN_HEIGHT, TOKEN_RADIUS * 2.0)
		return box
	# A cylinder with 3 sides is a triangular prism.
	var cyl := CylinderMesh.new()
	cyl.top_radius = TOKEN_RADIUS
	cyl.bottom_radius = TOKEN_RADIUS
	cyl.height = TOKEN_HEIGHT
	cyl.radial_segments = 3 if shape == ShapeType.TRIANGLE else 24
	return cyl


## Stands a shape where it belongs (on its tile, or on the floor of the room it is in).
func _place_token(t: Token, lift: float = 0.0) -> void:
	_place_token_at(t, t.cell, t.segment, lift)


## Same, for a tile/level it isn't on yet (used while a shape is being dragged, with a little lift).
func _place_token_at(t: Token, cell: Vector2i, segment: int, lift: float = 0.0) -> void:
	t.node.position = Vector3(cell.x + 0.5, _floor_y_for(cell, segment) + TOKEN_HEIGHT / 2.0 + lift, cell.y + 0.5)


func _refresh_tokens() -> void:
	for t in _tokens:
		if t != _dragged:
			_place_token(t)


func _token_at(cell: Vector2i, segment: int = -1) -> Token:
	for t in _tokens:
		if t.cell == cell and t.segment == segment:
			return t
	return null


# ------------------------------------------------------------------ deleting

func _right_pressed() -> void:
	if _mode != Mode.IDLE:
		return

	# Players can only remove the lines they drew themselves.
	if not _authority:
		var mine := _measurement_under_mouse(_my_id)
		if mine >= 0:
			_sync.send_remove_measure(_measurements[mine].id)
		return

	# Shapes take priority over lines (lines usually start/end on a shape).
	var hit := _pick()
	if hit and hit.token:
		if hit.token.owner_peer == NPC_OWNER: # a player's own shape stays until they leave
			var token_id := hit.token.id
			_remove_token(hit.token)
			_broadcast_token_removed(token_id)
		return

	var i := _measurement_under_mouse()
	if i >= 0:
		var line_id := _measurements[i].id
		_remove_measurement(_measurements[i])
		if _online:
			_sync.broadcast_measure_removed(line_id)


## Lines are tested in screen space, so they're easy to click however far away they are.
func _measurement_under_mouse(owner_filter: int = -1) -> int:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return -1
	var mouse := get_viewport().get_mouse_position()
	for i in range(_measurements.size() - 1, -1, -1): # newest first
		var m := _measurements[i]
		if owner_filter >= 0 and m.owner_peer != owner_filter:
			continue # a player can only pick their own lines
		if cam.is_position_behind(m.from) or cam.is_position_behind(m.to):
			continue
		var a := cam.unproject_position(m.from)
		var b := cam.unproject_position(m.to)
		var closest := Geometry2D.get_closest_point_to_segment(mouse, a, b)
		if closest.distance_to(mouse) <= line_hit_distance:
			return i
	return -1


# ------------------------------------------------------------------ measuring

func _start_measuring() -> void:
	if _mode != Mode.IDLE:
		return
	var hit := _pick()
	if hit == null:
		return
	_mode = Mode.MEASURING
	_measure = _make_measurement(Color.ORANGE)
	_measure.from = _measure_point(hit)
	_measure.to = _measure.from
	_update_measurement(_measure)


func _finish_measuring() -> void:
	if _mode != Mode.MEASURING:
		return
	_mode = Mode.IDLE
	var m := _measure
	_measure = null
	# Ignore accidental middle clicks that didn't actually drag anywhere.
	if m.from.distance_to(m.to) <= 0.1:
		_free_measurement(m)
		return

	m.mat.albedo_color = Color.RED
	m.owner_peer = _my_id
	if not _authority:
		# Shown right away; the host's copy replaces it once the host has confirmed the line.
		m.born_msec = Time.get_ticks_msec()
		_pending_lines.append(m)
		_sync.send_add_measure(m.from, m.to)
		return

	m.id = _alloc_measure_id()
	_measurements.append(m)
	if _online:
		_sync.broadcast_measure_added(m.id, m.owner_peer, m.from, m.to)


func _measure_point(hit: Hit) -> Vector3:
	if snap_lines_to_tile_centers:
		# Center of the tile (or of the room clicked), at the height of a shape's middle.
		var segment := hit.token.segment if hit.token else _standing_segment(hit)
		return Vector3(hit.cell.x + 0.5, _floor_y_for(hit.cell, segment) + TOKEN_HEIGHT / 2.0, hit.cell.y + 0.5)
	return hit.point


func _make_measurement(color: Color) -> Measurement:
	var m := Measurement.new()

	m.mat = StandardMaterial3D.new()
	m.mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.mat.albedo_color = color
	m.mat.no_depth_test = true # always visible, even behind raised tiles

	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.04
	cyl.bottom_radius = 0.04
	cyl.height = 1.0 # stretched to the real length in _update_measurement
	cyl.radial_segments = 8
	cyl.rings = 1
	cyl.material = m.mat

	m.line = MeshInstance3D.new()
	m.line.mesh = cyl
	m.line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m.line)

	m.label = Label3D.new()
	m.label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	m.label.no_depth_test = true
	m.label.pixel_size = 0.01
	m.label.font_size = 40
	m.label.outline_size = 12
	add_child(m.label)
	return m


func _update_measurement(m: Measurement) -> void:
	var delta := m.to - m.from
	var length := delta.length()
	var mid := (m.from + m.to) * 0.5

	m.line.visible = length > 0.001
	if length > 0.001:
		m.line.position = mid
		m.line.quaternion = Quaternion(Vector3.UP, delta / length) # cylinder's Y axis -> line
		m.line.scale = Vector3(1.0, length, 1.0)
	m.label.position = mid + Vector3.UP * 0.5
	m.label.text = _line_prefix(m) + _format_distance(m.from, m.to)


func _free_measurement(m: Measurement) -> void:
	m.line.queue_free()
	m.label.queue_free()


func _format_distance(from: Vector3, to: Vector3) -> String:
	var delta := (to - from).abs()
	var metres: float
	if count_diagonals_as_one:
		metres = maxf(maxf(delta.x, delta.y), delta.z)
	else:
		metres = delta.length()
	# 1 tile = 1 metre, e.g. "1 metre (1 tile)", "2.5 metres (2.5 tiles)"
	return "%s (%s)" % [
		_amount_text(metres, "metre", "metres"),
		_amount_text(metres, "tile", "tiles"),
	]


func _amount_text(value: float, singular: String, plural: String) -> String:
	var unit := singular if is_equal_approx(snappedf(value, 0.1), 1.0) else plural
	return "%s %s" % [_num(value), unit]


## 2.0 -> "2", 2.5 -> "2.5"
func _num(value: float) -> String:
	var r := snappedf(value, 0.1)
	if is_equal_approx(r, roundf(r)):
		return str(int(r))
	return "%.1f" % r


# ------------------------------------------------------------------ expanding the grid

func _expand(side: int, amount: int) -> void:
	if not _authority:
		return # only the storyteller resizes the grid
	match side:
		Side.NORTH:
			_grid_rect.position.y -= amount
			_grid_rect.size.y += amount
		Side.SOUTH:
			_grid_rect.size.y += amount
		Side.WEST:
			_grid_rect.position.x -= amount
			_grid_rect.size.x += amount
		Side.EAST:
			_grid_rect.size.x += amount
	_rebuild_grid()
	if _online:
		_net_rect_dirty = true


## Keeps a +1 / +10 pair near the middle of each edge of the grid. The buttons follow the
## edges as the camera moves, and slide to the screen border if the edge is off-screen.
func _layout_buttons() -> void:
	var view := get_viewport().get_visible_rect().size
	# The board can be drawn into a very large SubViewport that is shown scaled down, so the
	# labels and buttons are scaled up to stay readable.
	var ui_scale := maxf(view.y / UI_REFERENCE_HEIGHT, 1.0)
	_ui.scale = Vector2(ui_scale, ui_scale)

	var cam := get_viewport().get_camera_3d()
	if cam == null or not _authority:
		# Players don't get the grid-size buttons.
		for buttons in _side_buttons.values():
			for b in buttons:
				b.visible = false
		return

	var screen := view / ui_scale
	var r := _grid_rect
	var cx := r.position.x + r.size.x / 2.0
	var cz := r.position.y + r.size.y / 2.0

	var anchors := {
		Side.NORTH: Vector3(cx, 0.0, r.position.y - EDGE_OFFSET),
		Side.SOUTH: Vector3(cx, 0.0, r.end.y + EDGE_OFFSET),
		Side.WEST: Vector3(r.position.x - EDGE_OFFSET, 0.0, cz),
		Side.EAST: Vector3(r.end.x + EDGE_OFFSET, 0.0, cz),
	}

	var pair_w := BTN_SIZE.x * 2.0 + BTN_GAP
	for side in anchors:
		var pair: Array = _side_buttons[side]
		var world_pos: Vector3 = anchors[side]
		var behind := cam.is_position_behind(world_pos)
		for b in pair:
			b.visible = not behind
		if behind:
			continue

		var p := cam.unproject_position(world_pos) / ui_scale
		p.x = clampf(p.x, pair_w / 2.0 + 4.0, screen.x - pair_w / 2.0 - 4.0)
		p.y = clampf(p.y, BTN_SIZE.y / 2.0 + 4.0, screen.y - BTN_SIZE.y / 2.0 - 4.0)
		for i in 2:
			pair[i].position = Vector2(p.x - pair_w / 2.0 + i * (BTN_SIZE.x + BTN_GAP), p.y - BTN_SIZE.y / 2.0)


# ------------------------------------------------------------------ grid helpers

## Rebuilds every tile. Needed whenever the grid is resized, because the instance
## indexes shift when it grows north or west.
func _rebuild_grid() -> void:
	_multimesh.instance_count = _grid_rect.size.x * _grid_rect.size.y
	for cy in range(_grid_rect.position.y, _grid_rect.end.y):
		for cx in range(_grid_rect.position.x, _grid_rect.end.x):
			_update_cell(Vector2i(cx, cy))
	_update_ground()
	_extras_dirty = true


## The dark base plate sits just under the lowest tile, so it only shows through the thin gaps
## between tiles (the grid lines).
func _update_ground() -> void:
	var lowest := 0
	for level in _levels.values():
		lowest = mini(lowest, level)
	var size := Vector2(_grid_rect.size)
	var plane := _ground.mesh as PlaneMesh
	plane.size = size
	_ground.position = Vector3(
		_grid_rect.position.x + size.x / 2.0,
		lowest * height_step - SLAB_DEPTH - 0.02,
		_grid_rect.position.y + size.y / 2.0
	)


## Refreshes a rectangle of tiles plus a one-tile border: a tile's thickness (its side walls)
## depends on its neighbours, so when heights change the neighbours have to be redrawn too.
func _refresh_area(rect: Rect2i) -> void:
	for c in _cells_in(rect.grow(1).intersection(_grid_rect)):
		_update_cell(c)
	_update_ground()


func _update_cell(cell: Vector2i) -> void:
	var index := _index_of(cell)
	if _is_hollow(cell):
		# Drawn by the extra MultiMeshes instead; shrink the plain column to nothing.
		var hidden := Basis.from_scale(Vector3.ONE * 0.0001)
		_multimesh.set_instance_transform(index, Transform3D(hidden, Vector3(cell.x + 0.5, 0.0, cell.y + 0.5)))
	else:
		_multimesh.set_instance_transform(index, _cell_transform(cell))
	_multimesh.set_instance_color(index, _color_for(cell))
	if _interiors.has(cell):
		_extras_dirty = true


## Draws every tile that has a hollow level: its solid parts (floor, walls, roof) and its
## see-through parts. Only the (few) tiles with interiors are touched, and this runs at most
## once per frame.
func _rebuild_extras() -> void:
	_extras_dirty = false
	var solid_xf: Array[Transform3D] = []
	var solid_col: Array[Color] = []
	var glass_xf: Array[Transform3D] = []
	var glass_col: Array[Color] = []
	_edge_verts.clear()

	for cell in _interiors:
		if not _in_grid(cell) or not _is_hollow(cell):
			continue
		var solid_color := _color_for(cell)
		var glass_color := _glass_color_for(cell)
		for run in _cell_runs(cell, _bottom_y(cell)):
			var xf := _box_transform(cell, run.x, run.y)
			if run.z > 0.5:
				glass_xf.append(xf)
				glass_col.append(glass_color)
				_add_edges(cell, run.x, run.y)
			else:
				solid_xf.append(xf)
				solid_col.append(solid_color)

	_extra_solid.instance_count = solid_xf.size()
	for i in solid_xf.size():
		_extra_solid.set_instance_transform(i, solid_xf[i])
		_extra_solid.set_instance_color(i, solid_col[i])
	_extra_glass.instance_count = glass_xf.size()
	for i in glass_xf.size():
		_extra_glass.set_instance_transform(i, glass_xf[i])
		_extra_glass.set_instance_color(i, glass_col[i])

	_edge_mesh.clear_surfaces()
	if not _edge_verts.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _edge_verts
		_edge_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)


## White outline for one hollow stretch of a tile: a ring at every level boundary (so each
## level reads as its own cell) plus the four vertical corner edges.
func _add_edges(cell: Vector2i, low: float, high: float) -> void:
	var half := TILE_VISUAL / 2.0 + EDGE_LIFT
	var x0 := cell.x + 0.5 - half
	var x1 := cell.x + 0.5 + half
	var z0 := cell.y + 0.5 - half
	var z1 := cell.y + 0.5 + half

	var levels := maxi(roundi((high - low) / height_step), 1)
	for i in levels + 1:
		var y := low + i * (high - low) / levels + EDGE_LIFT
		_edge_verts.append_array(PackedVector3Array([
			Vector3(x0, y, z0), Vector3(x1, y, z0),
			Vector3(x1, y, z0), Vector3(x1, y, z1),
			Vector3(x1, y, z1), Vector3(x0, y, z1),
			Vector3(x0, y, z1), Vector3(x0, y, z0),
		]))

	var y0 := low + EDGE_LIFT
	var y1 := high + EDGE_LIFT
	_edge_verts.append_array(PackedVector3Array([
		Vector3(x0, y0, z0), Vector3(x0, y1, z0),
		Vector3(x1, y0, z0), Vector3(x1, y1, z0),
		Vector3(x1, y0, z1), Vector3(x1, y1, z1),
		Vector3(x0, y0, z1), Vector3(x0, y1, z1),
	]))


func _cell_transform(cell: Vector2i) -> Transform3D:
	return _box_transform(cell, _bottom_y(cell), _top_y(cell))


## A unit box stretched to fill one tile between two heights.
func _box_transform(cell: Vector2i, low: float, high: float) -> Transform3D:
	var size := Basis.from_scale(Vector3(TILE_VISUAL, high - low, TILE_VISUAL))
	return Transform3D(size, Vector3(cell.x + 0.5, (low + high) / 2.0, cell.y + 0.5))


## How far down a tile's column reaches. A flat tile is just a thin slab. It only gets taller
## where a neighbour is lower (that is its side wall), and next to a hollow tile it goes all
## the way to the ground so the walls around the room are solid. Beyond the edge of the grid
## counts as ground level.
func _bottom_y(cell: Vector2i) -> float:
	var low := 0 if _is_hollow(cell) else _level(cell)
	for d in NEIGHBORS:
		var n := cell + d
		var n_level := 0
		if _in_grid(n) and not _is_hollow(n):
			n_level = _level(n)
		low = mini(low, n_level)
	return low * height_step - SLAB_DEPTH


func _update_cell_color(cell: Vector2i) -> void:
	if not _in_grid(cell):
		return
	_multimesh.set_instance_color(_index_of(cell), _color_for(cell))
	if _interiors.has(cell):
		_extras_dirty = true


func _color_for(cell: Vector2i) -> Color:
	if _has_selection and _selection.has_point(cell):
		return COL_SELECT
	if cell == _hover_cell:
		return COL_HOVER
	return COL_BASE


func _glass_color_for(cell: Vector2i) -> Color:
	if _has_selection and _selection.has_point(cell):
		return Color(GLASS_TINT_SELECT, minf(interior_opacity * 2.1, 1.0))
	if cell == _hover_cell:
		return Color(GLASS_TINT_HOVER, minf(interior_opacity * 1.7, 1.0))
	return Color(GLASS_TINT, interior_opacity)


func _index_of(cell: Vector2i) -> int:
	return (cell.y - _grid_rect.position.y) * _grid_rect.size.x + (cell.x - _grid_rect.position.x)


func _in_grid(cell: Vector2i) -> bool:
	return _grid_rect.has_point(cell)


func _clamp_cell(cell: Vector2i) -> Vector2i:
	return cell.clamp(_grid_rect.position, _grid_rect.end - Vector2i.ONE)



# ------------------------------------------------------------------ multiplayer
# The rules: only the host (the storyteller) changes the board. A player's requests (move my
# shape, add or remove my line) are checked by the host, applied there, then copied to everybody.
# Everything below named net_* is called by CombatSync. The ones that start with net_request_ run
# on the host and treat the sender as untrusted.

func _net_setup() -> void:
	_sync = get_node_or_null("/root/Lobby/CombatSync")
	if _sync == null:
		return # no Lobby autoload: a plain single player board
	_refresh_role()
	_sync.register_grid(self)


## Works out whether this machine is the storyteller, a player, or offline. Runs every frame
## (it is cheap) so a lobby that starts or ends while the board is open is noticed.
func _refresh_role() -> void:
	var online := false
	var authority := true
	var my_id := HOST_ID
	if is_instance_valid(_sync) and _sync.is_online():
		online = true
		authority = multiplayer.is_server()
		my_id = multiplayer.get_unique_id()
	if online == _online and authority == _authority and my_id == _my_id:
		return
	_online = online
	_authority = authority
	_my_id = my_id
	_reset_interaction()
	_refresh_tags()
	_refresh_lines()
	_update_status()


## Drops anything half done (a drag, a selection) when the role changes.
func _reset_interaction() -> void:
	if _dragged != null:
		_place_token(_dragged)
		_dragged = null
	if _measure != null:
		_free_measurement(_measure)
		_measure = null
	_mode = Mode.IDLE
	if not _authority:
		_set_selection(Rect2i(), false)


func _token_by_id(id: int) -> Token:
	for t in _tokens:
		if t.id == id:
			return t
	return null


func _token_of_peer(peer_id: int) -> Token:
	for t in _tokens:
		if t.owner_peer == peer_id:
			return t
	return null


func _measurement_by_id(id: int) -> Measurement:
	for m in _measurements:
		if m.id == id:
			return m
	return null


func _alloc_measure_id() -> int:
	_next_measure_id += 1
	return _next_measure_id - 1


## Called when a shape is dropped. The storyteller's move is final and is copied to everybody. A
## player's move is shown at once but is only a request: the host's answer decides.
func _commit_token_move(t: Token, cell: Vector2i, segment: int) -> void:
	var moved := t.cell != cell or t.segment != segment
	t.cell = cell
	t.segment = segment
	_place_token(t)
	if not moved or not _online:
		return
	if _authority:
		_sync.broadcast_token_moved(t.id, cell, segment)
	else:
		_sync.send_move_token(t.id, cell, segment)


func _broadcast_token_added(t: Token) -> void:
	if _online and _authority:
		_sync.broadcast_token_added(t.id, t.cell, t.segment, t.shape, t.color, t.owner_peer)


func _broadcast_token_removed(token_id: int) -> void:
	if _online and _authority:
		_sync.broadcast_token_removed(token_id)


## Local only (the callers tell the other players).
func _remove_measurement(m: Measurement) -> void:
	_free_measurement(m)
	_measurements.erase(m)


func _spawn_measurement(line_id: int, owner_peer: int, from: Vector3, to: Vector3) -> Measurement:
	var m := _make_measurement(Color.RED)
	m.id = line_id
	m.owner_peer = owner_peer
	m.from = from
	m.to = to
	_update_measurement(m)
	_measurements.append(m)
	return m


## Other people's lines say whose they are ("Alex: 4 metres (4 tiles)").
func _line_prefix(m: Measurement) -> String:
	if _online and m.owner_peer != _my_id and m.owner_peer != NPC_OWNER:
		return _name_for(m.owner_peer) + ": "
	return ""


func _refresh_lines() -> void:
	for m in _measurements:
		_update_measurement(m)


## A player's new line is shown straight away while the host's confirmation travels back. If the
## host never confirms it (it was refused), it is taken down again after a few seconds.
func _expire_pending_lines() -> void:
	if _pending_lines.is_empty():
		return
	var now := Time.get_ticks_msec()
	while not _pending_lines.is_empty() and now - _pending_lines[0].born_msec > PENDING_LINE_TIMEOUT_MS:
		_free_measurement(_pending_lines.pop_front())


## The empty tile nearest the middle of the grid, spiralling outwards.
func _find_free_cell() -> Vector2i:
	var center := _grid_rect.position + _grid_rect.size / 2
	var max_ring := maxi(_grid_rect.size.x, _grid_rect.size.y)
	for ring in range(0, max_ring + 1):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var c := center + Vector2i(dx, dy)
				if _in_grid(c) and _token_at(c, -1) == null:
					return c
	return center


func _make_player_token(peer_id: int) -> Token:
	return _spawn_token(_alloc_token_id(), _find_free_cell(), -1, ShapeType.CIRCLE, _next_color(), peer_id)


func _valid_point(p: Vector3) -> bool:
	if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
		return false
	var footprint := Rect2(Vector2(_grid_rect.position) - Vector2(5, 5), Vector2(_grid_rect.size) + Vector2(10, 10))
	return footprint.has_point(Vector2(p.x, p.z)) \
		and p.y >= (min_height - 5) * height_step and p.y <= (max_height + 5) * height_step


## Keeps a player from covering the board in lines: their oldest one goes first.
func _enforce_line_limit(peer_id: int) -> void:
	if peer_id == HOST_ID:
		return
	var mine: Array[Measurement] = []
	for m in _measurements:
		if m.owner_peer == peer_id:
			mine.append(m)
	while mine.size() > MAX_LINES_PER_PLAYER:
		var oldest: Measurement = mine.pop_front()
		var line_id := oldest.id
		_remove_measurement(oldest)
		_sync.broadcast_measure_removed(line_id)


# ---- saving and loading the whole board

func make_snapshot() -> Dictionary:
	var levels := PackedInt32Array()
	for c in _levels:
		levels.push_back(c.x)
		levels.push_back(c.y)
		levels.push_back(_levels[c])
	var interiors := []
	for c in _interiors:
		var ks := PackedInt32Array()
		for k in _interiors[c]:
			ks.push_back(k)
		interiors.append([c, ks])
	var tokens := []
	for t in _tokens:
		tokens.append([t.id, t.cell, t.segment, t.shape, t.color, t.owner_peer])
	var lines := []
	for m in _measurements:
		lines.append([m.id, m.owner_peer, m.from, m.to])
	return {
		"rect": _grid_rect,
		"levels": levels,
		"interiors": interiors,
		"tokens": tokens,
		"measures": lines,
		"next_token": _next_token_id,
		"next_measure": _next_measure_id,
		"color_index": _color_index,
	}


## Replaces everything on this machine's board with the snapshot. `keep_owner` (optional) is a
## Callable(owner_peer) -> bool that can leave out shapes and lines of players who are gone.
func _apply_snapshot(data: Dictionary, keep_owner: Callable = Callable()) -> void:
	_clear_all()

	var rect: Rect2i = data.get("rect", Rect2i(Vector2i.ZERO, start_size))
	if rect.size.x < 1 or rect.size.y < 1:
		rect = Rect2i(Vector2i.ZERO, start_size)
	_grid_rect = rect

	var levels: PackedInt32Array = data.get("levels", PackedInt32Array())
	for i in range(0, levels.size() - 2, 3):
		_levels[Vector2i(levels[i], levels[i + 1])] = levels[i + 2]
	for entry in data.get("interiors", []):
		var cell: Vector2i = entry[0]
		var ks: PackedInt32Array = entry[1]
		for k in ks:
			if not _interiors.has(cell):
				_interiors[cell] = {}
			_interiors[cell][k] = true

	for e in data.get("tokens", []):
		var owner_peer: int = e[5]
		if keep_owner.is_valid() and not keep_owner.call(owner_peer):
			continue
		_spawn_token(e[0], e[1], e[2], e[3], e[4], owner_peer)
	for e in data.get("measures", []):
		var line_owner: int = e[1]
		if keep_owner.is_valid() and not keep_owner.call(line_owner):
			continue
		_spawn_measurement(e[0], line_owner, e[2], e[3])

	_next_token_id = int(data.get("next_token", 1))
	_next_measure_id = int(data.get("next_measure", 1))
	_color_index = int(data.get("color_index", 0))

	_rebuild_grid()
	_refresh_tokens()
	_update_status()


func _clear_all() -> void:
	for t in _tokens:
		t.node.queue_free()
	_tokens.clear()
	for m in _measurements:
		_free_measurement(m)
	_measurements.clear()
	for m in _pending_lines:
		_free_measurement(m)
	_pending_lines.clear()
	if _measure != null:
		_free_measurement(_measure)
		_measure = null
	_levels.clear()
	_interiors.clear()
	_pull_start_levels.clear()
	_net_dirty_levels.clear()
	_net_dirty_interiors.clear()
	_net_rect_dirty = false
	_dragged = null
	_mode = Mode.IDLE
	_selection = Rect2i()
	_has_selection = false
	_hover_cell = NO_CELL
	_next_token_id = 1
	_next_measure_id = 1
	_color_index = 0
	_extras_dirty = true


# ---- host: sending terrain changes

## Sends the terrain changes made since the last call (rate limited by _process).
func _flush_terrain() -> void:
	if _net_dirty_levels.is_empty() and _net_dirty_interiors.is_empty() and not _net_rect_dirty:
		return
	var levels := PackedInt32Array()
	for c in _net_dirty_levels:
		levels.push_back(c.x)
		levels.push_back(c.y)
		levels.push_back(_level(c))
	var interiors := []
	for c in _net_dirty_interiors:
		var ks := PackedInt32Array()
		if _interiors.has(c):
			for k in _interiors[c]:
				ks.push_back(k)
		interiors.append([c, ks]) # an empty list means "no hollow levels any more"
	_net_dirty_levels.clear()
	_net_dirty_interiors.clear()
	_net_rect_dirty = false
	_sync.broadcast_terrain(_grid_rect, levels, interiors)


# ---- host: handling a player's request (the sender is never trusted)

## A player opened the board: give them a shape (if they have none) and send them the board.
func net_peer_joined(peer_id: int) -> void:
	if not (_authority and _online):
		return
	var t := _token_of_peer(peer_id)
	var created := false
	if t == null:
		t = _make_player_token(peer_id)
		created = true
	_sync.send_snapshot(peer_id, make_snapshot())
	if created:
		_broadcast_token_added(t)


## A player left: their shape and lines go.
func net_peer_left(peer_id: int) -> void:
	if not _authority:
		return
	var t := _token_of_peer(peer_id)
	if t != null:
		var token_id := t.id
		_remove_token(t)
		_broadcast_token_removed(token_id)
	for m in _measurements.duplicate():
		if m.owner_peer == peer_id:
			var line_id: int = m.id
			_remove_measurement(m)
			if _online:
				_sync.broadcast_measure_removed(line_id)


## The board just opened on the host's screen: make sure every player who is waiting has a shape,
## then send everybody the board (some of them may have opened theirs before the host did).
func net_authority_ready(peer_ids: Array) -> void:
	for id in peer_ids:
		if _token_of_peer(id) == null:
			_make_player_token(id)
	if _online:
		_sync.broadcast_snapshot(make_snapshot())


## Restores the host's board from before (shapes of players who have left are dropped).
func net_load_state(state: Dictionary) -> void:
	var peers := multiplayer.get_peers()
	_apply_snapshot(state, func(owner_peer: int) -> bool:
		return owner_peer == NPC_OWNER or owner_peer == HOST_ID or peers.has(owner_peer)
	)


## A player wants to move their shape. Only their own shape, only onto a free, valid spot.
func net_request_move(sender: int, token_id: int, cell: Vector2i, segment: int) -> void:
	if not (_authority and _online):
		return
	var t := _token_by_id(token_id)
	if t == null or t.owner_peer != sender:
		return # not their shape: ignored completely

	var ok := _in_grid(cell) and segment >= -1 and segment <= max_height
	if ok and segment >= 0 and not _is_interior(cell, segment):
		ok = false
	if ok:
		var other := _token_at(cell, segment)
		ok = other == null or other == t

	if ok:
		t.cell = cell
		t.segment = segment
		_place_token(t)
		_sync.broadcast_token_moved(t.id, cell, segment)
	else:
		_sync.send_token_moved_to(sender, t.id, t.cell, t.segment) # puts their copy back


## A player drew a measuring line.
func net_request_measure(sender: int, from: Vector3, to: Vector3) -> void:
	if not (_authority and _online):
		return
	if not _valid_point(from) or not _valid_point(to) or from.distance_to(to) > MAX_LINE_LENGTH:
		return
	var m := _spawn_measurement(_alloc_measure_id(), sender, from, to)
	_sync.broadcast_measure_added(m.id, sender, from, to)
	_enforce_line_limit(sender)


## A player wants to remove a line: only their own.
func net_request_remove_measure(sender: int, line_id: int) -> void:
	if not (_authority and _online):
		return
	var m := _measurement_by_id(line_id)
	if m == null or m.owner_peer != sender:
		return
	_remove_measurement(m)
	_sync.broadcast_measure_removed(line_id)


# ---- players: applying what the host sends

func net_apply_snapshot(data: Dictionary) -> void:
	_apply_snapshot(data)


func net_apply_terrain(rect: Rect2i, levels: PackedInt32Array, interiors: Array) -> void:
	var rect_changed := rect != _grid_rect
	var bounds := Rect2i()
	var has_bounds := false
	_grid_rect = rect

	for i in range(0, levels.size() - 2, 3):
		var c := Vector2i(levels[i], levels[i + 1])
		_set_level(c, levels[i + 2])
		bounds = bounds.merge(Rect2i(c, Vector2i.ONE)) if has_bounds else Rect2i(c, Vector2i.ONE)
		has_bounds = true
	for entry in interiors:
		var c: Vector2i = entry[0]
		var ks: PackedInt32Array = entry[1]
		_interiors.erase(c)
		for k in ks:
			_set_interior(c, k, true)
		bounds = bounds.merge(Rect2i(c, Vector2i.ONE)) if has_bounds else Rect2i(c, Vector2i.ONE)
		has_bounds = true

	_extras_dirty = true
	if rect_changed:
		_rebuild_grid()
	elif has_bounds:
		_refresh_area(bounds)
	_refresh_tokens()
	_update_status()


func net_token_added(token_id: int, cell: Vector2i, segment: int, shape: int, color: Color, owner_peer: int) -> void:
	var t := _token_by_id(token_id)
	if t == null:
		_spawn_token(token_id, cell, segment, shape, color, owner_peer)
		return
	t.cell = cell
	t.segment = segment
	if t != _dragged:
		_place_token(t)


func net_token_moved(token_id: int, cell: Vector2i, segment: int) -> void:
	var t := _token_by_id(token_id)
	if t == null:
		return
	t.cell = cell
	t.segment = segment
	if t != _dragged: # while I'm dragging my own shape, my drop will decide
		_place_token(t)


func net_token_removed(token_id: int) -> void:
	var t := _token_by_id(token_id)
	if t != null:
		_remove_token(t)


func net_measure_added(line_id: int, owner_peer: int, from: Vector3, to: Vector3) -> void:
	if _measurement_by_id(line_id) != null:
		return
	if owner_peer == _my_id and not _pending_lines.is_empty():
		_free_measurement(_pending_lines.pop_front()) # the host's copy replaces my preview
	_spawn_measurement(line_id, owner_peer, from, to)


func net_measure_removed(line_id: int) -> void:
	var m := _measurement_by_id(line_id)
	if m != null:
		_remove_measurement(m)


# ---- events from CombatSync

## The connection state changed (for example this game just connected to the host).
func net_refresh() -> void:
	_refresh_role()


func net_names_changed() -> void:
	_refresh_tags()
	_refresh_lines()


func net_on_left_lobby(was_host: bool, was_client: bool) -> void:
	_refresh_role() # offline again: this machine is its own storyteller
	if was_client:
		# The board belonged to the host. Start a fresh, empty one.
		_clear_all()
		_grid_rect = Rect2i(Vector2i.ZERO, start_size)
		_rebuild_grid()
		_update_status()
	elif was_host:
		# Everybody is gone, so are their shapes and lines. The storyteller's own stay.
		for t in _tokens.duplicate():
			if t.owner_peer != NPC_OWNER:
				_remove_token(t)
		for m in _measurements.duplicate():
			if m.owner_peer != HOST_ID:
				_remove_measurement(m)
