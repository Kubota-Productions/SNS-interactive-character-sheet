extends Camera2D
## The 2D camera of the character sheet and the GM screen.
##
## Moving:   arrow keys (or move_left / move_right), or drag with the left mouse button.
##           Alt + drag works from anywhere, even from inside a text box.
## Zooming:  mouse wheel (towards the mouse). Ctrl + wheel works from anywhere, even from inside
##           a text box. Ctrl + "+" / Ctrl + "-" zoom from the keyboard, Ctrl + 0 shows everything.
## Bounds:   automatic. The camera can't leave the content that is on screen (the pages, text
##           boxes, buttons, pictures and the combat view), and it can zoom out until all of that
##           content fits in the window. Content that appears later (for example the players'
##           sheets on the GM screen) is picked up by itself.
##           To keep a node out of the bounds, add it to the group "camera_ignore".

@export var move_speed: float = 400.0
@export var mouse_sensitivity: float = 1.0

@export_group("Zoom")
## How much one mouse wheel notch (or one key press) zooms.
@export var zoom_factor: float = 1.15
@export var max_zoom: float = 4.0
## The camera never zooms out further than this, however big the content is.
@export var min_zoom: float = 0.05

@export_group("Bounds")
## Free space around the content that the camera may show (in pixels of the scene).
@export var bounds_margin: float = 80.0
## How often the content is measured again (in seconds).
@export var bounds_refresh_interval: float = 0.25

@export_group("Old limits (not used any more)")
## The bounds are automatic now. These are only kept so existing scenes keep loading.
@export var left_limit: float
@export var right_limit: float
@export var up_limit: float
@export var down_limit: float

@export_group("")
# Drag the instanced CombatScene root Control into this field.
@export var combat_scene: Control

const IGNORE_GROUP := &"camera_ignore"

## Where the camera is looking (the centre of the screen), in scene coordinates.
var camera_pos_x: float = 960.0
var camera_pos_y: float = 540.0

var dragging: bool = false
var mouse_over_combat: bool = false

## True while an Alt + drag is panning the camera.
var alt_dragging: bool = false

var combat_container: SubViewportContainer

# The area covered by the content, measured by update_bounds().
var _bounds := Rect2()
var _has_bounds: bool = false
var _refresh_timer: float = 0.0
# Used while measuring.
var _found_rect := Rect2()
var _found_any: bool = false


## Added to the scene as its LAST child. Godot hands input to the bottom-most nodes first, so this
## sees mouse clicks before anything else in the scene (text fields, the PDF viewer, buttons...)
## and can claim them for Alt + drag before those get a chance to react.
class AltPanCatcher extends Node:
	var camera = null

	func _input(event: InputEvent) -> void:
		if camera != null and camera.alt_pan_input(event):
			get_viewport().set_input_as_handled()


func _ready() -> void:
	# Alt + drag pans from anywhere. (Deferred: the parent is still setting up its children.)
	var catcher := AltPanCatcher.new()
	catcher.name = "AltPanCatcher"
	catcher.camera = self
	get_parent().add_child.call_deferred(catcher)

	if combat_scene == null:
		push_error("Main camera: Combat Scene has not been assigned.")
		return

	combat_container = combat_scene.get_node_or_null(
		"SubViewportContainer"
	) as SubViewportContainer

	if combat_container == null:
		push_error("Main camera: Could not find SubViewportContainer in CombatScene.")
		return

	# Make sure the container receives mouse enter/exit events.
	combat_container.mouse_filter = Control.MOUSE_FILTER_STOP

	combat_container.mouse_entered.connect(_on_combat_mouse_entered)
	combat_container.mouse_exited.connect(_on_combat_mouse_exited)


func _on_combat_mouse_entered() -> void:
	mouse_over_combat = true
	dragging = false


func _on_combat_mouse_exited() -> void:
	mouse_over_combat = false
	dragging = false


func _process(delta: float) -> void:
	# If the mouse button was let go while the game wasn't watching, stop the Alt drag.
	if alt_dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		alt_dragging = false

	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		update_bounds()

	# Only the keyboard movement is switched off over the combat view or in a text field. The
	# position below must always be applied, or an Alt + drag would do nothing in those cases.
	if not mouse_over_combat and not _in_text_field():
		var move := Vector2.ZERO

		if Input.is_action_pressed("ui_left") or Input.is_action_pressed("move_left"):
			move.x -= 1.0
		if Input.is_action_pressed("ui_right") or Input.is_action_pressed("move_right"):
			move.x += 1.0
		if Input.is_action_pressed("ui_up"):
			move.y -= 1.0
		if Input.is_action_pressed("ui_down"):
			move.y += 1.0

		if move != Vector2.ZERO:
			# Divided by the zoom, so the speed on screen is the same at every zoom level.
			camera_pos_x += move.x * move_speed * delta / zoom.x
			camera_pos_y += move.y * move_speed * delta / zoom.y

	_apply_bounds()
	position = Vector2(camera_pos_x, camera_pos_y)


# ------------------------------------------------------------------ dragging

## Alt + left drag moves the camera no matter what is under the mouse or has keyboard focus
## (a text field, the PDF viewer, the combat view). Returns true if the event was used, so the
## caller can stop it from reaching anything else.
func alt_pan_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and event.alt_pressed:
			alt_dragging = true
			dragging = false
			return true
		if not event.pressed and alt_dragging:
			alt_dragging = false
			return true
	elif event is InputEventMouseMotion and alt_dragging:
		# Divided by the zoom, so the sheet follows the mouse exactly.
		camera_pos_x -= event.relative.x / zoom.x * mouse_sensitivity
		camera_pos_y -= event.relative.y / zoom.y * mouse_sensitivity
		return true
	return false


func _input(event: InputEvent) -> void:
	# Completely ignore mouse input while over the RTS scene.
	if mouse_over_combat:
		dragging = false
		return

	var button := event as InputEventMouseButton
	if button != null:
		if button.button_index == MOUSE_BUTTON_LEFT:
			dragging = button.pressed and not _in_text_field()
		elif button.pressed and (
			button.button_index == MOUSE_BUTTON_WHEEL_UP
			or button.button_index == MOUSE_BUTTON_WHEEL_DOWN
		):
			# Ctrl + wheel zooms even from inside a text box.
			if button.ctrl_pressed or not _in_text_field():
				var factor := zoom_factor if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / zoom_factor
				_zoom_by(factor, true)
				if button.ctrl_pressed:
					get_viewport().set_input_as_handled()
		return

	var motion := event as InputEventMouseMotion
	if motion != null and dragging and not _in_text_field():
		# Divided by the zoom, so the sheet follows the mouse exactly.
		camera_pos_x -= motion.relative.x / zoom.x * mouse_sensitivity
		camera_pos_y -= motion.relative.y / zoom.y * mouse_sensitivity


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or not key.ctrl_pressed or mouse_over_combat:
		return

	match key.keycode:
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			_zoom_by(zoom_factor, false)
			get_viewport().set_input_as_handled()
		KEY_MINUS, KEY_KP_SUBTRACT:
			_zoom_by(1.0 / zoom_factor, false)
			get_viewport().set_input_as_handled()
		KEY_0, KEY_KP_0:
			fit_to_content()
			get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ zoom

## Zooms by `factor` (above 1 = closer). With towards_mouse the point under the mouse stays where
## it is on screen; without, the zoom is around the middle of the screen.
func _zoom_by(factor: float, towards_mouse: bool) -> void:
	var old_zoom := zoom.x
	var new_zoom := clampf(old_zoom * factor, _lowest_zoom(), max_zoom)
	if is_equal_approx(new_zoom, old_zoom):
		return

	# Make the camera node sit where the camera is meant to be before measuring.
	position = Vector2(camera_pos_x, camera_pos_y)
	var before := get_global_mouse_position()
	zoom = Vector2(new_zoom, new_zoom)
	if towards_mouse:
		var after := get_global_mouse_position()
		camera_pos_x += before.x - after.x
		camera_pos_y += before.y - after.y


## Shows all of the content at once.
func fit_to_content() -> void:
	update_bounds()
	if not _has_bounds:
		return
	var area := _bounds.grow(bounds_margin)
	var fit := _fit_zoom(area)
	zoom = Vector2(fit, fit)
	camera_pos_x = area.get_center().x
	camera_pos_y = area.get_center().y


func _fit_zoom(area: Rect2) -> float:
	var window := get_viewport_rect().size
	var fit := minf(window.x / area.size.x, window.y / area.size.y)
	return clampf(fit, min_zoom, max_zoom)


## The furthest the camera may zoom out: far enough to see all of the content, but never further
## out than 1 (no point shrinking content that already fits), and never below min_zoom.
func _lowest_zoom() -> float:
	if not _has_bounds:
		return min_zoom
	return minf(_fit_zoom(_bounds.grow(bounds_margin)), 1.0)


# ------------------------------------------------------------------ automatic bounds

## Measures the content again. Called a few times a second, and can be called by anything that
## has just added or removed content (for example the GM sheet wall).
func update_bounds() -> void:
	_refresh_timer = bounds_refresh_interval
	_found_any = false
	_found_rect = Rect2()

	var scene_root := get_parent()
	if scene_root != null:
		_scan(scene_root)

	_has_bounds = _found_any
	_bounds = _found_rect

	# Content that got smaller can raise the lowest zoom.
	var lowest := _lowest_zoom()
	if zoom.x < lowest:
		zoom = Vector2(lowest, lowest)


func _scan(node: Node) -> void:
	# Not part of the scrolling world: the camera itself, anything drawn on screen (CanvasLayer),
	# separate windows and 3D.
	if node == self or node is CanvasLayer or node is Window or node is Node3D:
		return
	if node is CanvasItem and not (node as CanvasItem).visible:
		return  # hidden, and so is everything inside it
	if node.is_in_group(IGNORE_GROUP):
		return

	if node is Control:
		var control := node as Control
		if _is_content(control):
			_add_rect(control.get_global_transform() * Rect2(Vector2.ZERO, control.size))
		if control is SubViewportContainer:
			return  # what is inside it is drawn in another viewport
	elif node is Sprite2D:
		var sprite := node as Sprite2D
		if sprite.texture != null:
			_add_rect(sprite.get_global_transform() * sprite.get_rect())

	for child in node.get_children():
		_scan(child)


## Things people look at. Plain backgrounds (ColorRect, Panel) and empty containers don't count,
## so the big decorative backdrop doesn't stretch the bounds.
func _is_content(control: Control) -> bool:
	if control is TextureRect:
		return (control as TextureRect).texture != null
	return control is LineEdit \
		or control is TextEdit \
		or control is BaseButton \
		or control is Label \
		or control is RichTextLabel \
		or control is SubViewportContainer


func _add_rect(rect: Rect2) -> void:
	rect = rect.abs()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	if _found_any:
		_found_rect = _found_rect.merge(rect)
	else:
		_found_rect = rect
		_found_any = true


## Keeps the view inside the content. If the content is smaller than the window along one
## direction, the camera sits in the middle of it instead.
func _apply_bounds() -> void:
	if not _has_bounds:
		return
	var area := _bounds.grow(bounds_margin)
	var view := get_viewport_rect().size / zoom
	camera_pos_x = _keep_inside(camera_pos_x, area.position.x, area.end.x, view.x)
	camera_pos_y = _keep_inside(camera_pos_y, area.position.y, area.end.y, view.y)


func _keep_inside(value: float, low: float, high: float, view_length: float) -> float:
	if high - low <= view_length:
		return (low + high) * 0.5
	return clampf(value, low + view_length * 0.5, high - view_length * 0.5)


func _in_text_field() -> bool:
	var focus_owner = get_viewport().gui_get_focus_owner()

	return (
		focus_owner is LineEdit
		or focus_owner is TextEdit
		or focus_owner is OptionButton
		or focus_owner is HSlider
	)
