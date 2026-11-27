extends Button

@onready var file_dialog: FileDialog = $"../FileDialog"
@onready var image_display: TextureRect = $TextureRect

func _ready() -> void:
	pressed.connect(_on_add_image_pressed)

	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.filters = PackedStringArray([
		"*.png ; PNG Images",
		"*.jpg ; JPEG Images"
	])
	file_dialog.file_selected.connect(_on_file_selected)

	var saved := GlobalFunctions.character.get_appearance_texture()
	if saved:
		image_display.texture = saved


func _on_add_image_pressed() -> void:
	file_dialog.popup_centered()


func _on_file_selected(path: String) -> void:
	var image := Image.new()
	var err := image.load(path)
	if err != OK:
		push_error("Failed to load image '%s': %s" % [path, error_string(err)])
		return
	GlobalFunctions.character.set_appearance(image)  # autosaves into the sheet's save file
	image_display.texture = ImageTexture.create_from_image(image)
