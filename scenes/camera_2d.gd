extends Camera2D

@export var move_speed: float = 400.0
@export var left_limit: float = -1000.0
@export var right_limit: float = 1000.0
@export var mouse_sensitivity: float = 1.0

var dragging: bool = false

func _process(delta: float) -> void:
	var input_dir := 0.0

	# Keyboard input (WASD + Arrows)
	if Input.is_action_pressed("ui_left") or Input.is_action_pressed("move_left"):
		input_dir -= 1.0
	if Input.is_action_pressed("ui_right") or Input.is_action_pressed("move_right"):
		input_dir += 1.0

	if input_dir != 0.0:
		position.x += input_dir * move_speed * delta
		_clamp_to_limits()

func _input(event: InputEvent) -> void:
	# Start / stop dragging with left mouse button
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		dragging = event.pressed

	# While dragging, move camera based on mouse motion
	if event is InputEventMouseMotion and dragging:
		position.x -= event.relative.x * mouse_sensitivity
		_clamp_to_limits()

func _clamp_to_limits() -> void:
	position.x = clamp(position.x, left_limit, right_limit)
