extends Camera2D

@export var move_speed: float = 400.0
@export var left_limit: float 
@export var right_limit: float 
@export var up_limit: float 
@export var down_limit: float 
@export var mouse_sensitivity: float = 1.0

# Zoom settings
@export var zoom_step: float = 0.1
@export var min_zoom: float = 1
@export var max_zoom: float = 3
var camera_pos_x =960 
var camera_pos_y =540

var dragging: bool = false

func _process(delta: float) -> void:
	var input_dir := 0.0

	# Prevent keyboard camera movement while editing text
	if not _in_text_field():
		if Input.is_action_pressed("ui_left") or Input.is_action_pressed("move_left"):
			input_dir -= 1.0
		if Input.is_action_pressed("ui_right") or Input.is_action_pressed("move_right"):
			input_dir += 1.0

	if input_dir != 0.0:
		camera_pos_x += (input_dir * move_speed * delta)
		
	camera_pos_x = clampf(camera_pos_x,left_limit,right_limit)
	camera_pos_y = clampf(camera_pos_y,up_limit,down_limit)
	position.x = camera_pos_x
	position.y = camera_pos_y
	
	
func _input(event: InputEvent) -> void:
	# Start / stop dragging with left mouse button
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not _in_text_field():
			dragging = event.pressed
		else:
			dragging = false

	# While dragging, move camera based on mouse motion
	if event is InputEventMouseMotion and dragging and not _in_text_field():
		camera_pos_x -= event.relative.x * mouse_sensitivity
		camera_pos_y -= event.relative.y * mouse_sensitivity

	# Mouse wheel zoom (still works while editing text unless you want it blocked)
	if event is InputEventMouseButton and not _in_text_field():
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_change_zoom(zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_change_zoom(-zoom_step)
			
func _change_zoom(amount: float) -> void:
	var world_mouse_before = get_global_mouse_position()

	# Update zoom
	var new_zoom = zoom.x + amount
	new_zoom = clamp(new_zoom, min_zoom, max_zoom)
	zoom = Vector2(new_zoom, new_zoom)

	var world_mouse_after = get_global_mouse_position()

	# Calculate how much the mouse point moved due to zoom
	var ooffset = world_mouse_before - world_mouse_after

	# Apply the offset in the correct direction
	camera_pos_x += ooffset.x
	camera_pos_y += ooffset.y

func _in_text_field() -> bool:
	var focus_owner = get_viewport().gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit or focus_owner is OptionButton or focus_owner is HSlider 
