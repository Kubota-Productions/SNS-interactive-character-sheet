extends Control
## Explicit indexed state API. Connect value_changed for an existing save system,
## or set save_path to opt into debounced JSON autosave.

signal value_changed(index: int, value: Variant)
signal field_activated(index: int, tag: String)
signal save_failed(path: String, error: Error)

const FieldScript = preload("field.gd")
@export var save_path: String = ""
var _fields: Dictionary = {}
var _timer: Timer
var _dirty := false
var _applying := false
var _valid := true
var _tags: Dictionary = {}

func _ready() -> void:
	_register(self)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = 0.5
	add_child(_timer)
	_timer.timeout.connect(flush)
	if save_path != "" and FileAccess.file_exists(save_path):
		load_state(save_path)

func _register(node: Node) -> void:
	if node.get_script() == FieldScript:
		if node.index < 1:
			_valid = false
			push_error("PDF field save indices must be positive")
		if not _fields.has(node.index):
			_fields[node.index] = []
		for previous in _fields[node.index]:
			if previous.pdf_name == "" or previous.pdf_name != node.pdf_name or previous.field_type != node.field_type or previous.tag != node.tag:
				_valid = false
				push_error("Conflicting PDF field save index: %s" % node.index)
		_fields[node.index].append(node)
		if node.tag != "":
			if _tags.has(node.tag) and _tags[node.tag] != node.index:
				_valid = false
				push_error("Duplicate PDF field tag: " + node.tag)
			_tags[node.tag] = node.index
		node.value_changed.connect(_changed.bind(node.index, node))
		node.activated.connect(func(index, tag): field_activated.emit(index, tag))
	for child in node.get_children():
		_register(child)

func _changed(value: Variant, index: int, source: Control) -> void:
	if _applying or not _valid:
		return
	_applying = true
	for field in _fields[index]:
		# Reassigning text on the active editor resets its caret and selection.
		# Its value is already current; only synchronize the other PDF widgets.
		if field != source:
			field.set_value(value)
	_applying = false
	_dirty = true
	value_changed.emit(index, value)
	if save_path != "":
		_timer.start()

func snapshot() -> Dictionary:
	var values := {}
	var tags := {}
	var types := {}
	for index in _fields:
		var fields: Array = _fields[index]
		var value: Variant = fields[0].get_value()
		if value == null:
			continue
		if fields[0].field_type == "radio":
			for field in fields:
				if field.button_pressed:
					value = field.radio_option
		var key := str(index)
		values[key] = value
		types[key] = fields[0].field_type
		if fields[0].tag != "":
			tags[fields[0].tag] = key
	return {"version": 1, "values": values, "types": types, "tags": tags}

func apply_snapshot(state: Dictionary, by_tag: bool = false) -> int:
	if not _valid or state.get("version") != 1:
		return 0
	var values: Variant = state.get("values", {})
	var tags: Variant = state.get("tags", {})
	var types: Variant = state.get("types", {})
	if not values is Dictionary or not tags is Dictionary or not types is Dictionary:
		return 0
	var count := 0
	_applying = true
	for index in _fields:
		var fields: Array = _fields[index]
		var key: String = str(index)
		if by_tag:
			if fields[0].tag == "" or not tags.has(fields[0].tag):
				continue
			key = str(tags[fields[0].tag])
		if not values.has(key) or types.get(key) != fields[0].field_type:
			continue
		if not fields[0].accepts(values[key]):
			continue
		if fields[0].field_type == "radio" and values[key] != "":
			var found := false
			for field in fields:
				found = found or field.radio_option == values[key]
			if not found:
				continue
		for field in fields:
			field.set_value(values[key])
		count += 1
	_applying = false
	return count

func load_state(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	var state: Variant = JSON.parse_string(file.get_as_text())
	if not state is Dictionary or state.get("version") != 1 or not state.get("values") is Dictionary or not state.get("types") is Dictionary:
		return ERR_PARSE_ERROR
	apply_snapshot(state)
	return OK

func flush() -> Error:
	if not _dirty or save_path == "":
		return OK
	var error := save_state(save_path)
	if error == OK:
		_dirty = false
	else:
		save_failed.emit(save_path, error)
		if is_inside_tree():
			_timer.start(2.0)
	return error

func save_state(path: String) -> Error:
	if not _valid:
		return ERR_INVALID_DATA
	var absolute := ProjectSettings.globalize_path(path)
	var error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if error != OK:
		return error
	var temporary := absolute + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(snapshot()))
	file.flush()
	error = file.get_error()
	file.close()
	if error != OK:
		return error
	return DirAccess.rename_absolute(temporary, absolute)

func _exit_tree() -> void:
	flush()
