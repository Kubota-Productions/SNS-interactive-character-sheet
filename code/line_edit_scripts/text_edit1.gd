extends TextEdit
var was_just_editing = true
@export var index = 1 
var player_name = GlobalFunctions.return_player_name()

func _ready() -> void:
	# Check if global data array exists and is sufficient size. (Without this, creating a 'new sheet' crashes cause there's no save data.
	if GlobalFunctions.data != null && GlobalFunctions.data.size() > index:
		# Grab the value directly from global data
		self.text = GlobalFunctions.data[index]

func _on_text_changed() -> void:
			GlobalFunctions.store_data(index,(self.text))
