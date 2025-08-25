extends Button

@onready var file_dialog: FileDialog = $"../FileDialog"
@onready var image_display: TextureRect = $TextureRect

func _ready() -> void:
	# Connect button press
	pressed.connect(_on_add_image_pressed)

	# Setup FileDialog
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.filters = PackedStringArray([
		"*.png ; PNG Images",
		"*.jpg ; JPEG Images"
	])
	file_dialog.file_selected.connect(_on_file_selected)

	# Try to load character's saved appearance on startup
	_load_saved_image()


func _on_add_image_pressed() -> void:
	file_dialog.popup_centered()


func _on_file_selected(path: String) -> void:
	var image := Image.new()
	if image.load(path) == OK:
		# Show in TextureRect
		var texture = ImageTexture.create_from_image(image)
		image_display.texture = texture

		# Save using character name
		var character_name = GlobalFunctions.player_name
		if character_name == "" or character_name == null:
			character_name = "unnamed"  # fallback if no name set

		var save_path = "user://%s_appearance.png" % character_name

		var err = image.save_png(save_path)
		if err == OK:
			print("Image saved to:", save_path)
		else:
			push_error("Failed to save image: %s" % err)
	else:
		push_error("Failed to load image: %s" % path)


func _load_saved_image() -> void:
	var character_name = GlobalFunctions.player_name
	if character_name == "" or character_name == null:
		character_name = "unnamed"

	var load_path = "user://%s_appearance.png" % character_name

	if FileAccess.file_exists(load_path):
		var image := Image.new()
		if image.load(load_path) == OK:
			var texture = ImageTexture.create_from_image(image)
			image_display.texture = texture
			print("Loaded saved appearance for:", character_name)
		else:
			push_error("Failed to load saved image for: %s" % character_name)
	else:
		print("No saved appearance found for:", character_name)
