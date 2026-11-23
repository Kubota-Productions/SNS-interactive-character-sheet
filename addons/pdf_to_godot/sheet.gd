@tool
extends Control
## Explicit indexed state API. Connect value_changed for an existing save system,
## or set save_path to opt into debounced JSON autosave.

signal value_changed(index: int, value: Variant)
signal field_activated(index: int, tag: String)
signal save_failed(path: String, error: Error)

const FieldScript = preload("field.gd")
@export var save_path: String = ""
@export var show_page_navigation := true
@export var side_by_side := false
var _fields: Dictionary = {}
var _timer: Timer
var _dirty := false
var _applying := false
var _valid := true
var _tags: Dictionary = {}
var _page_scroll: ScrollContainer
var _pages: BoxContainer
var _page_navigation: HBoxContainer
var _previous_page: Button
var _next_page: Button
var _page_label: Label

func _ready() -> void:
	_setup_pages()
	if Engine.is_editor_hint():
		return
	_register(self)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = 0.5
	add_child(_timer)
	_timer.timeout.connect(flush)
	if save_path != "" and FileAccess.file_exists(save_path):
		load_state(save_path)

func _setup_pages() -> void:
	_page_scroll = get_node_or_null("Scroll") as ScrollContainer
	if _page_scroll == null:
		return
	_pages = _page_scroll.get_node_or_null("Pages") as BoxContainer
	if Engine.is_editor_hint():
		# The editor canvas must be able to pan/frame every page. A clipped
		# ScrollContainer otherwise hides later pages even when selected.
		_page_scroll.clip_contents = false
		_page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_page_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		return
	_page_scroll.clip_contents = true
	_page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_page_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_page_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if side_by_side:
		_page_scroll.resized.connect(_fit_pages_to_width)
		_fit_pages_to_width.call_deferred()
		return
	if get_page_count() < 2 or not show_page_navigation:
		return
	_page_navigation = HBoxContainer.new()
	_page_navigation.name = "PageNavigation"
	_page_navigation.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_page_navigation.offset_left = 8
	_page_navigation.offset_right = -8
	_page_navigation.offset_top = 4
	_page_navigation.offset_bottom = 36
	_page_navigation.add_theme_constant_override("separation", 12)
	_previous_page = Button.new()
	_previous_page.name = "PreviousPage"
	_previous_page.text = "Previous"
	_previous_page.pressed.connect(func(): go_to_page(get_current_page() - 1))
	_page_navigation.add_child(_previous_page)
	_page_label = Label.new()
	_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_navigation.add_child(_page_label)
	_next_page = Button.new()
	_next_page.name = "NextPage"
	_next_page.text = "Next"
	_next_page.pressed.connect(func(): go_to_page(get_current_page() + 1))
	_page_navigation.add_child(_next_page)
	add_child(_page_navigation)
	_page_scroll.offset_top = 40
	_page_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	_page_scroll.get_v_scroll_bar().value_changed.connect(_update_page_navigation)
	_page_scroll.resized.connect(_update_page_navigation)
	_update_page_navigation.call_deferred()

func _fit_pages_to_width() -> void:
	var total_width := 0.0
	for page in _pages.get_children():
		total_width += Vector2(page.get_meta("page_size")).x
	var gaps := _pages.get_theme_constant("separation") * maxi(0, get_page_count() - 1)
	var available := _page_scroll.size.x - _page_scroll.get_v_scroll_bar().size.x - gaps
	var factor := maxf(0.01, available / maxf(1.0, total_width))
	for page in _pages.get_children():
		page.custom_minimum_size = Vector2(page.get_meta("page_size")) * factor
		page.get_node("Content").scale = Vector2.ONE * factor

func get_page_count() -> int:
	return _pages.get_child_count() if _pages != null else 0

func get_current_page() -> int:
	if get_page_count() == 0:
		return 0
	if side_by_side:
		return 1
	var bar := _page_scroll.get_v_scroll_bar()
	if bar.max_value > bar.page and bar.value >= bar.max_value - bar.page - 1:
		return get_page_count()
	var current := 1
	for i in get_page_count():
		if _pages.get_child(i).position.y <= _page_scroll.scroll_vertical + 1:
			current = i + 1
	return current

func go_to_page(page_number: int) -> void:
	if get_page_count() == 0:
		return
	var page: Control = _pages.get_child(clampi(page_number, 1, get_page_count()) - 1)
	_page_scroll.scroll_vertical = roundi(page.position.y)
	_update_page_navigation()

func _update_page_navigation(_value: float = 0) -> void:
	if _page_navigation == null:
		return
	var current := get_current_page()
	var bar := _page_scroll.get_v_scroll_bar()
	var all_visible := bar.max_value <= bar.page
	_page_label.text = "All %s pages" % get_page_count() if all_visible else "Page %s of %s" % [current, get_page_count()]
	_previous_page.disabled = all_visible or current <= 1
	_next_page.disabled = all_visible or current >= get_page_count()

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
	if not Engine.is_editor_hint():
		flush()
