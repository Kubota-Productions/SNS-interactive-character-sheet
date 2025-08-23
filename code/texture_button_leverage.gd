extends TextureButton

var was_just_editing = true
@export var index = 1 
var player_name = GlobalFunctions.return_player_name()

func _ready() -> void:
	button_pressed = false
	# Check if global data array exists and is sufficient size. (Without this, creating a 'new sheet' crashes cause there's no save data.
	if GlobalFunctions.data != null && GlobalFunctions.data.size() > index:
		# Grab the value directly from global data
		if GlobalFunctions.data[index] == "true":
			button_pressed = true

func _on_toggled(toggled_on: bool) -> void:
	GlobalFunctions.store_data(index,(str(toggled_on)))
