extends Control

@onready var malesyllabub: Node3D = $SubViewportContainer/SubViewport/malesyllabub
@onready var femalesyllabub: Node3D = $SubViewportContainer/SubViewport/femalesyllabub
@onready var datadoll: Node3D = $SubViewportContainer/SubViewport/Datadoll
@onready var cognitive: Node3D = $SubViewportContainer/SubViewport/Cognitive

# Rotation speed in degrees per second
@export var rotation_speed: float = 90.0  # degrees per second

# Flags to track if buttons are being held
var rotating_left: bool = false
var rotating_right: bool = false


func _process(delta: float) -> void:
	# Rotate left if the left button is held
	if rotating_left:
		datadoll.rotate_z(deg_to_rad(rotation_speed * delta))
		femalesyllabub.rotate_z(deg_to_rad(rotation_speed * delta))
		malesyllabub.rotate_z(deg_to_rad(rotation_speed * delta))
		cognitive.rotate_z(deg_to_rad(rotation_speed * delta))
	# Rotate right if the right button is held
	if rotating_right:
		datadoll.rotate_z(deg_to_rad(-rotation_speed * delta))
		femalesyllabub.rotate_z(deg_to_rad(-rotation_speed * delta))
		malesyllabub.rotate_z(deg_to_rad(-rotation_speed * delta))
		cognitive.rotate_z(deg_to_rad(-rotation_speed * delta))


func _on_leftbutton_button_down() -> void:
	rotating_left = true

func _on_leftbutton_button_up() -> void:
	rotating_left = false

func _on_rightbutton_button_down() -> void:
	rotating_right = true

func _on_rightbutton_button_up() -> void:
	rotating_right = false
