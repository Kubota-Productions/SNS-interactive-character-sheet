extends RefCounted
## A VIEW-ONLY copy of one player's character sheet, kept on the GM's machine.
##
## It has the same getters as CharacterSaveData (get_text, get_toggle, get_symbol, ...) so it can be
## read the same way, but it has no setters and it is never saved to disk or sent back to the player.
## Only SheetSync (the network side) calls the apply_* functions, with what the player sent.

## kind is "all" (everything was replaced), "text", "toggle", "symbol", "name" or "image".
## index is the widget index for "text", "toggle" and "symbol", otherwise -1.
signal updated(kind: String, index: int)

const MAX_IMAGE_SIDE := 2048

var character_name: String = ""
var texts: Dictionary = {}
var toggles: Dictionary = {}
var symbols: Dictionary = {}
var appearance_texture: ImageTexture = null


func get_text(index: int) -> String:
	return texts.get(index, "")


func get_toggle(index: int) -> bool:
	return toggles.get(index, false)


func get_symbol(index: int) -> String:
	return symbols.get(index, "")


func get_appearance_texture() -> ImageTexture:
	return appearance_texture


# ------------------------------------------------------------------ called by SheetSync only

## Replaces everything (the player opened a sheet, or switched to another character).
## `state` has already been checked by SheetSync.
func apply_full(state: Dictionary) -> void:
	character_name = state.get("name", "")
	texts = state.get("texts", {})
	toggles = state.get("toggles", {})
	symbols = state.get("symbols", {})
	updated.emit("all", -1)


## Applies only what changed. A text or symbol that is now empty, or a toggle that is now false,
## is simply the player clearing it. `delta` has already been checked by SheetSync.
func apply_delta(delta: Dictionary) -> void:
	if delta.has("name"):
		character_name = delta["name"]
		updated.emit("name", -1)

	var changed_texts: Dictionary = delta.get("texts", {})
	for index in changed_texts:
		if changed_texts[index] == "":
			texts.erase(index)
		else:
			texts[index] = changed_texts[index]
		updated.emit("text", index)

	var changed_toggles: Dictionary = delta.get("toggles", {})
	for index in changed_toggles:
		if changed_toggles[index]:
			toggles[index] = true
		else:
			toggles.erase(index)
		updated.emit("toggle", index)

	var changed_symbols: Dictionary = delta.get("symbols", {})
	for index in changed_symbols:
		if changed_symbols[index] == "":
			symbols.erase(index)
		else:
			symbols[index] = changed_symbols[index]
		updated.emit("symbol", index)


## `bytes` is a PNG or JPG picture (or empty, meaning "no picture").
func apply_image(bytes: PackedByteArray) -> void:
	appearance_texture = null
	if not bytes.is_empty():
		var image := Image.new()
		var err := ERR_FILE_UNRECOGNIZED
		if bytes.size() > 2 and bytes[0] == 0x89 and bytes[1] == 0x50:
			err = image.load_png_from_buffer(bytes)
		elif bytes.size() > 2 and bytes[0] == 0xFF and bytes[1] == 0xD8:
			err = image.load_jpg_from_buffer(bytes)
		if err == OK and image.get_width() <= MAX_IMAGE_SIDE and image.get_height() <= MAX_IMAGE_SIDE:
			appearance_texture = ImageTexture.create_from_image(image)
	updated.emit("image", -1)
