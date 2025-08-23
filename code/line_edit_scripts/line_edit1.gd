extends LineEdit
var was_just_editing = true
@export var index = 1 
var player_name = GlobalFunctions.return_player_name()

# Changed this to 'ready' so it runs SECOND after the scene script's '_enter_tree'.
# NOTE: Originally these nodes EaCH loaded the file individually, instead i'm loading the data globally ONCE, and these nodes just access that array.
func _ready() -> void: 
	# Check if global data array exists and is sufficient size. (Without this, creating a 'new sheet' crashes cause there's no save data.
	if GlobalFunctions.data != null && GlobalFunctions.data.size() > index:
		# Grab the value directly from global data
		self.text = GlobalFunctions.data[index];

func _on_editing_toggled(toggled_on: bool) -> void:
	if toggled_on == true:
		was_just_editing = true
	if toggled_on == false:
		if was_just_editing == true:
			GlobalFunctions.store_data(index,(self.text))
			was_just_editing = false
