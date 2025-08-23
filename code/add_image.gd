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

func _on_add_image_pressed() -> void:
	file_dialog.popup_centered()

func _on_file_selected(path: String) -> void:
	var image := Image.new()
	if image.load(path) == OK:
		var texture = ImageTexture.create_from_image(image)
		image_display.texture = texture
	else:
		push_error("Failed to load image: %s" % path)
