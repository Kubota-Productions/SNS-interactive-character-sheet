
extends Camera2D

@export var move_speed: float = 400.0
@export var left_limit: float
@export var right_limit: float
@export var up_limit: float
@export var down_limit: float
@export var mouse_sensitivity: float = 1.0

@export var zoom_step: float = 0.1
@export var min_zoom: float = 1.0
@export var max_zoom: float = 3.0

# Drag the instanced CombatScene root Control into this field.
@export var combat_scene: Control

var camera_pos_x = 960.0
var camera_pos_y = 540.0

var dragging: bool = false
var mouse_over_combat: bool = false

var combat_container: SubViewportContainer


func _ready() -> void:
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
	if mouse_over_combat or _in_text_field():
		return

	var input_dir := 0.0

	if Input.is_action_pressed("ui_left") or Input.is_action_pressed("move_left"):
		input_dir -= 1.0

	if Input.is_action_pressed("ui_right") or Input.is_action_pressed("move_right"):
		input_dir += 1.0

	if input_dir != 0.0:
		camera_pos_x += input_dir * move_speed * delta

	camera_pos_x = clampf(camera_pos_x, left_limit, right_limit)
	camera_pos_y = clampf(camera_pos_y, up_limit, down_limit)

	position.x = camera_pos_x
	position.y = camera_pos_y


func _input(event: InputEvent) -> void:
	# Completely ignore mouse input while over the RTS scene.
	if mouse_over_combat:
		dragging = false
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not _in_text_field():
			dragging = event.pressed
		else:
			dragging = false

	if event is InputEventMouseMotion and dragging and not _in_text_field():
		camera_pos_x -= event.relative.x * mouse_sensitivity
		camera_pos_y -= event.relative.y * mouse_sensitivity

	if event is InputEventMouseButton and not _in_text_field():
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_change_zoom(zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_change_zoom(-zoom_step)


func _change_zoom(amount: float) -> void:
	var world_mouse_before = get_global_mouse_position()

	var new_zoom = clampf(zoom.x + amount, min_zoom, max_zoom)
	zoom = Vector2(new_zoom, new_zoom)

	var world_mouse_after = get_global_mouse_position()
	var offset = world_mouse_before - world_mouse_after

	camera_pos_x += offset.x
	camera_pos_y += offset.y


func _in_text_field() -> bool:
	var focus_owner = get_viewport().gui_get_focus_owner()

	return (
		focus_owner is LineEdit
		or focus_owner is TextEdit
		or focus_owner is OptionButton
		or focus_owner is HSlider
	)
