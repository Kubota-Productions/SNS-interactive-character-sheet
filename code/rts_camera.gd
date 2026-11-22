extends Node3D
## Simple RTS-style camera rig.
##
## Setup: make a Node3D, attach this script, and give it a Camera3D child:
##
##   CameraRig (Node3D)   <- this script
##   └─ Camera3D
##
## The rig sits on the ground at the point the camera is looking at; this script moves the
## Camera3D back and up from it, so you never need to position the Camera3D yourself.
##
## Controls
##   W A S D / arrow keys   -> pan (hold Shift to go faster)
##   Q / E                  -> rotate around the focus point
##   Mouse wheel            -> zoom in / out
##   Mouse at screen edge   -> pan (only if edge_scroll is turned on)

@export var camera: Camera3D

@export_group("Start")
## Where the camera looks at on start (the middle of a 20x20 grid).
@export var start_focus := Vector3(10.0, 0.0, 10.0)
@export var start_distance: float = 22.0

@export_group("Movement")
## Pan speed in metres/second when the camera is 10 m away (scales with zoom distance).
@export var pan_speed: float = 12.0
@export var fast_multiplier: float = 2.5
@export var edge_scroll: bool = false
@export var edge_margin: float = 12.0
## Higher = snappier, lower = floatier.
@export var smoothing: float = 10.0

@export_group("Rotation")
@export var rotate_speed_deg: float = 90.0
## Angle the camera looks down at the ground (90 = straight down).
@export_range(15.0, 89.0) var pitch_deg: float = 55.0

@export_group("Zoom")
@export var min_distance: float = 4.0
@export var max_distance: float = 60.0
## Each wheel notch multiplies the distance by this (lower = bigger steps).
@export_range(0.5, 0.99) var zoom_factor: float = 0.88

var _target_pos := Vector3.ZERO
var _target_yaw := 0.0
var _target_dist := 20.0
var _yaw := 0.0
var _dist := 20.0
## True while the mouse is over the board. When the board is shown inside a SubViewportContainer
## this follows the container, so keys typed elsewhere (a text field on the sheet) don't move it.
var _mouse_over := true


func _ready() -> void:
	if camera == null:
		camera = get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		push_error("rts_camera: add a Camera3D as a child of this node.")
		set_process(false)
		set_process_unhandled_input(false)
		return

	_target_pos = start_focus
	global_position = start_focus
	_target_dist = clampf(start_distance, min_distance, max_distance)
	_dist = _target_dist
	_yaw = rotation.y
	_target_yaw = _yaw
	_apply()
	_hook_container()


func _hook_container() -> void:
	var container := get_viewport().get_parent() as SubViewportContainer
	if container == null:
		return # the scene is running on its own, so the whole window is the board
	_mouse_over = false
	container.mouse_entered.connect(func(): _mouse_over = true)
	container.mouse_exited.connect(func(): _mouse_over = false)


func _is_combat_viewport_active() -> bool:
	return _mouse_over

func _unhandled_input(event: InputEvent) -> void:
	if not _is_combat_viewport_active():
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_dist = clampf(
				_target_dist * zoom_factor,
				min_distance,
				max_distance
			)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_dist = clampf(
				_target_dist / zoom_factor,
				min_distance,
				max_distance
			)

func _process(delta: float) -> void:
	var input := Vector2.ZERO

	# Only accept movement when the mouse is over the combat viewport.
	if _is_combat_viewport_active():
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
			input.x -= 1.0
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
			input.x += 1.0
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
			input.y -= 1.0
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
			input.y += 1.0

		if edge_scroll:
			input += _edge_scroll_input()

		if input != Vector2.ZERO:
			var speed := pan_speed * (_dist / 10.0)

			if Input.is_physical_key_pressed(KEY_SHIFT):
				speed *= fast_multiplier

			var dir := input.limit_length(1.0)
			var move := Basis(Vector3.UP, _target_yaw) * Vector3(dir.x, 0.0, dir.y)
			_target_pos += move * speed * delta

		if Input.is_physical_key_pressed(KEY_Q):
			_target_yaw += deg_to_rad(rotate_speed_deg) * delta
		if Input.is_physical_key_pressed(KEY_E):
			_target_yaw -= deg_to_rad(rotate_speed_deg) * delta

	# Always smooth, even when the mouse leaves the combat viewport.
	var t := 1.0 - exp(-smoothing * delta)
	global_position = global_position.lerp(_target_pos, t)
	_yaw = lerp_angle(_yaw, _target_yaw, t)
	_dist = lerpf(_dist, _target_dist, t)
	_apply()


func _apply() -> void:
	rotation.y = _yaw
	# Tilt down by pitch_deg, then back the camera away from the focus point along its view.
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(-pitch_deg))
	camera.transform = Transform3D(tilt, tilt * Vector3(0.0, 0.0, _dist))


func _edge_scroll_input() -> Vector2:
	var vp := get_viewport()
	var size := vp.get_visible_rect().size
	var m := vp.get_mouse_position()
	if m.x < 0.0 or m.y < 0.0 or m.x > size.x or m.y > size.y:
		return Vector2.ZERO # mouse is outside the window
	var v := Vector2.ZERO
	if m.x <= edge_margin:
		v.x -= 1.0
	elif m.x >= size.x - edge_margin:
		v.x += 1.0
	if m.y <= edge_margin:
		v.y -= 1.0
	elif m.y >= size.y - edge_margin:
		v.y += 1.0
	return v
