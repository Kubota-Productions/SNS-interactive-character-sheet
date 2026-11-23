extends Node3D

const HistoryPanelScript := preload("res://code/dice_history_panel.gd")

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

# The die that was just thrown and is still rolling, and how many sides it has.
var _rolling_die: Node = null
var _rolling_sides: int = 0


func _ready() -> void:
	print("DiceRoller ready. Buttons connected via signals.")

	# The "Roll history" button and panel (the rolls are kept by /root/Lobby/DiceSync).
	add_child(HistoryPanelScript.new())


## When the die that was thrown comes to rest, its number is written to the roll history.
func _process(_delta: float) -> void:
	if _rolling_die == null:
		return
	if not is_instance_valid(_rolling_die):
		_rolling_die = null
		return
	if _rolling_die.get("has_stopped_rolling") != true:
		return

	var label = _rolling_die.get("dice_number_label")
	var sides := _rolling_sides
	_rolling_die = null
	if label != null and String(label.text).is_valid_int():
		var sync := get_node_or_null("/root/Lobby/DiceSync")
		if sync != null:
			sync.report_roll(sides, int(label.text))


func _sides_of(die_packed_scene: PackedScene) -> int:
	if die_packed_scene == d2_scene:
		return 2
	if die_packed_scene == d4_scene:
		return 4
	if die_packed_scene == d6_scene:
		return 6
	if die_packed_scene == d8_scene:
		return 8
	if die_packed_scene == d10_scene:
		return 10
	if die_packed_scene == d12_scene:
		return 12
	if die_packed_scene == d20_scene:
		return 20
	return 0

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

	# Remember this die, so the result can be recorded once it has stopped. (A die that is
	# replaced by a new throw before it stops is not recorded.)
	_rolling_die = die_instance
	_rolling_sides = _sides_of(die_packed_scene)

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
	


	
		
