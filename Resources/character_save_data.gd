class_name CharacterSaveData
extends Resource

## Bump this if you ever remove/rename a field. Adding new @export fields needs no bump:
## older saves just load with the defaults declared here.
const CURRENT_VERSION := 1

@export var version: int = CURRENT_VERSION
@export var character_name: String = ""

## LineEdit / TextEdit contents, keyed by each node's exported `index`.
@export var texts: Dictionary[int, String] = {}
## TextureButton toggle states, keyed by each button's `index`.
@export var toggles: Dictionary[int, bool] = {}
## Symbol chosen from the right-click popup, keyed by the button's `index`.
@export var symbols: Dictionary[int, String] = {}
## Appearance image stored as PNG bytes (far smaller than a raw Image resource).
@export var appearance_png: PackedByteArray = PackedByteArray()


func get_text(index: int) -> String:
	return texts[index] if texts.has(index) else ""

func set_text(index: int, value: String) -> void:
	if get_text(index) == value:
		return
	if value.is_empty():
		texts.erase(index)
	else:
		texts[index] = value
	emit_changed()


func get_toggle(index: int) -> bool:
	return toggles[index] if toggles.has(index) else false

func set_toggle(index: int, value: bool) -> void:
	if get_toggle(index) == value:
		return
	toggles[index] = value
	emit_changed()


func get_symbol(index: int) -> String:
	return symbols[index] if symbols.has(index) else ""

func set_symbol(index: int, value: String) -> void:
	if get_symbol(index) == value:
		return
	if value.is_empty():
		symbols.erase(index)
	else:
		symbols[index] = value
	emit_changed()


func set_appearance(image: Image) -> void:
	appearance_png = image.save_png_to_buffer()
	emit_changed()

## Returns null if no appearance has been set.
func get_appearance_texture() -> ImageTexture:
	if appearance_png.is_empty():
		return null
	var image := Image.new()
	if image.load_png_from_buffer(appearance_png) != OK:
		push_error("Saved appearance image for '%s' is corrupt." % character_name)
		return null
	return ImageTexture.create_from_image(image)
