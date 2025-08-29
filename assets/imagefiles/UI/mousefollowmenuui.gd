extends ColorRect

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	var local_mouse = get_local_mouse_position() / size
	material.set_shader_parameter("mouse_pos", local_mouse)
