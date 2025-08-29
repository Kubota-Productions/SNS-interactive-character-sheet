extends Node3D

@export var d2_scene: PackedScene
@export var d4_scene: PackedScene
@export var d6_scene: PackedScene
@export var d8_scene: PackedScene
@export var d10_scene: PackedScene
@export var d12_scene: PackedScene
@export var d20_scene: PackedScene

@onready var spawn_point: Node3D = $SubViewportContainer/SpawnPoint
@onready var dice_container: Node3D = $SubViewportContainer/DiceContainer


@export var camera_2d: Camera2D = null

func _ready() -> void:
	print("DiceRoller ready. Buttons connected via signals.")

func roll_dice(die_packed_scene: PackedScene) -> void:
	for child in spawn_point.get_children():
		child.queue_free()
	var die_instance: RigidBody3D = die_packed_scene.instantiate()
	spawn_point.add_child(die_instance)
	

	# Apply random impulse and torque
	
	var direction = Vector3(randf_range(-1,1), 0, randf_range(-1,-1)).normalized()
	var magnitude = randf_range(5,15) 
	#var push = Vector3(randf_range(-10,10), randf_range(-0.1,0.1), randf_range(-10,10))
	die_instance.linear_velocity = direction * magnitude
	die_instance.angular_velocity = direction * magnitude

	print("Rolled dice: %s" % die_instance)

# --- Button signal handlers ---
func _on_d_2_button_pressed() -> void:
	roll_dice(d2_scene)

func _on_d_4_button_pressed() -> void:
	roll_dice(d4_scene)

func _on_d_6_button_pressed() -> void:
	roll_dice(d6_scene)

func _on_d_8_button_pressed() -> void:
	roll_dice(d8_scene)

func _on_d_10_button_pressed() -> void:
	roll_dice(d10_scene)

func _on_d_12_button_pressed() -> void:
	roll_dice(d12_scene)

func _on_d_20_button_pressed() -> void:
	roll_dice(d20_scene)
	


	
		
