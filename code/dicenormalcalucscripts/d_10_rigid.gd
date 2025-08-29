extends RigidBody3D

var has_stopped_rolling: bool = false
@onready var dice_number_label: Label3D = $Label3D

# Map local face normals to die values
var face_normals: Array = [
	Vector3.LEFT,
	Vector3.RIGHT,
	Vector3.FORWARD,
	Vector3.BACK,
]

	

func _process(_delta: float) -> void:
	if not has_stopped_rolling and linear_velocity.length() < 0.2: 
		get_up_face()
		dice_number_label.global_position.y = global_position.y + 0.5
		dice_number_label.text = str(randi_range(1,10))
		dice_number_label.visible = true
		has_stopped_rolling = true


func get_up_face() -> int:
	var best_dot = 1
	var _best_normal: Vector3
	for local_normal in face_normals:
		#print("localnormal:" + str(local_normal))
		var world_normal = global_transform.basis * local_normal
		#print("worldnormal:" + str(world_normal))
		var dot = world_normal.dot(Vector3.UP)
		print("dot" + str(dot))
		
		if dot < best_dot:
			best_dot = dot
			
			_best_normal = world_normal
		
	return best_dot
