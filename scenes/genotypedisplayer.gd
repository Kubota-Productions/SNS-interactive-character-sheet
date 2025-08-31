extends Control

@onready var malesyllabub: Node3D = $SubViewportContainer/SubViewport/malesyllabub
@onready var femalesyllabub: Node3D = $SubViewportContainer/SubViewport/femalesyllabub
@onready var datadoll: Node3D = $SubViewportContainer/SubViewport/Datadoll
@onready var cognitive: Node3D = $SubViewportContainer/SubViewport/Cognitive
@onready var hellion: Node3D = $SubViewportContainer/SubViewport/Hellion

# Rotation speed in degrees per second
@export var rotation_speed: float = 90.0  # degrees per second

# Flags to track if buttons are being held
var rotating_left: bool = false
var rotating_right: bool = false


func _process(delta: float) -> void:
	# Rotate left if the left button is held
	if rotating_left:
		_get_active_model().rotate_z(deg_to_rad(rotation_speed * delta))
	# Rotate right if the right button is held
	if rotating_right:
		_get_active_model().rotate_z(deg_to_rad(-rotation_speed * delta))


func _on_leftbutton_button_down() -> void:
	rotating_left = true

func _on_leftbutton_button_up() -> void:
	rotating_left = false

func _on_rightbutton_button_down() -> void:
	rotating_right = true

func _on_rightbutton_button_up() -> void:
	rotating_right = false


func _on_option_button_item_selected(index: int) -> void:
	# Hide all models
	malesyllabub.visible = false
	femalesyllabub.visible = false
	datadoll.visible = false
	cognitive.visible = false
	hellion.visible = false

	# Show only the selected one
	match index:
		0: malesyllabub.visible = true
		1: femalesyllabub.visible = true
		2: datadoll.visible = true
		3: cognitive.visible = true
		4: hellion.visible = true
		
	$HBoxContainer/OptionButton.release_focus()
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = get_viewport().get_mouse_position()
	Input.parse_input_event(ev)

func _get_active_model() -> Node3D:
	# Return whichever model is currently visible
	if malesyllabub.visible: return malesyllabub
	if femalesyllabub.visible: return femalesyllabub
	if datadoll.visible: return datadoll
	if cognitive.visible: return cognitive
	if hellion.visible: return hellion
	return malesyllabub # fallback
