extends TextEdit
var was_just_editing = true
@export var index = 1 
var st_name = GlobalFunctions.return_st_name()

func _ready() -> void:

	# Check if global data array exists and is sufficient size. (Without this, creating a 'new sheet' crashes cause there's no save data.
	if GlobalFunctions.st_data != null && GlobalFunctions.st_data.size() > index:
		# Grab the value directly from global data
		self.text = GlobalFunctions.st_data[index]
		print("loaded_data")

func _on_text_changed() -> void:
			GlobalFunctions.st_store_data(index,(self.text))
			print("saved")
