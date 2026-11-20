extends RefCounted
## Optional bridge to SNS CharacterSaveData's existing public methods.
## Keep this adapter alive for as long as the sheet is in use.

var _sheet: WeakRef
var _character: Variant
var _types: Dictionary
var _name_index := ""
var _image_index := ""

func bind_sheet(sheet: Control, character: Resource) -> void:
	disconnect_sheet()
	_sheet = weakref(sheet)
	_character = character
	var state: Dictionary = sheet.snapshot()
	_types = state.types
	_name_index = str(state.tags.get("character.name", ""))
	_image_index = str(state.tags.get("character.appearance", ""))
	for key in state.values:
		if key == _name_index:
			state.values[key] = character.character_name
		elif key == _image_index:
			state.values[key] = "" if character.appearance_png.is_empty() else Marshalls.raw_to_base64(character.appearance_png)
		else:
			match _types[key]:
				"text", "multiline": state.values[key] = character.get_text(int(key))
				"checkbox": state.values[key] = character.get_toggle(int(key))
				"symbol": state.values[key] = character.get_symbol(int(key))
	# Read saved values before connecting edits, so opening a sheet never dirties it.
	sheet.apply_snapshot(state)
	sheet.value_changed.connect(_changed)

func disconnect_sheet() -> void:
	if _sheet != null and _sheet.get_ref() != null:
		var sheet: Variant = _sheet.get_ref()
		if sheet.value_changed.is_connected(_changed):
			sheet.value_changed.disconnect(_changed)
	_sheet = null
	_character = null

func _changed(index: int, value: Variant) -> void:
	var key := str(index)
	if key == _name_index:
		_character.character_name = value
		_character.emit_changed()
	elif key == _image_index:
		if value == "":
			_character.appearance_png = PackedByteArray()
			_character.emit_changed()
		else:
			var image := Image.new()
			if image.load_png_from_buffer(Marshalls.base64_to_raw(value)) == OK:
				_character.set_appearance(image)
	else:
		match _types.get(key, ""):
			"text", "multiline": _character.set_text(index, value)
			"checkbox": _character.set_toggle(index, value)
			"symbol": _character.set_symbol(index, value)
