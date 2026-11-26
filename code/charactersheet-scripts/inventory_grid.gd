extends Control
## The inventory: a 6 x 6 grid where you draw the shape of each item.
##
## One control draws the whole grid itself (cells, symbols, outlines) and takes the mouse. What an
## inventory is and how it is saved: see inventory_items.gd. The items live in the character's
## `inventory`, and every change is saved with one set_inventory() call.
##
## Drawing:
##   drag across empty cells ....... draws a new item (a click makes a one-cell item). It gets a
##                                   symbol that no other item has, and a small panel opens next to
##                                   it, ready for you to type a name and a note.
##   click an item ................. opens its panel: name, note, symbol, delete
##   Shift + click or drag ......... while an item's panel is open: adds empty cells to that item, or
##                                   takes its own cells away
##   right click or right drag ..... erases cells (an item with no cells left is gone)
##   hover an item ................. after a moment, shows its name and note
##   Esc, Enter in the name box, Done, or a click anywhere else closes the panel.
##
## Where the grid sits: put this script on a Control and give that Control the position and size
## of the grid on your sheet (the cells are the size divided by 6 x 6). Or leave the 36 old
## inventory buttons in the scene: the first of them adds a grid over them and removes them.
##
## With `read_only` set the grid only shows the items it is given with show_items(), and can't change
## anything. The GM's view of a player's sheet uses that.

const Items := preload("res://code/charactersheet-scripts/inventory_items.gd")

const THEME_PATH := "res://assets/imagefiles/UI/main_menu.tres"
const SYMBOL_FONT_SIZE := 32
const PANEL_WIDTH := 320.0
const PANEL_GAP := 14.0
## While dragging, the mouse is looked at every this many pixels so that no cell is skipped.
const SAMPLE_STEP := 6.0

const FILL_COLOR := Color(0.85, 0.12, 0.12)  # a filled cell, if there is no filled_texture
const SYMBOL_COLOR := Color(1.0, 1.0, 1.0)
const SYMBOL_OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 0.8)
const OUTLINE_COLOR := Color(0.1, 0.05, 0.05, 0.95)
const SELECT_COLOR := Color(1.0, 0.85, 0.3)
const HOVER_COLOR := Color(1.0, 1.0, 1.0, 0.18)
const DRAFT_COLOR := Color(1.0, 0.3, 0.3, 0.6)
const ERASE_COLOR := Color(0.0, 0.0, 0.0, 0.55)

enum Stroke { NONE, DRAW, ADD, ERASE_ITEM, ERASE_ANY, PICK }

## Only show the items given to show_items(), never change them.
@export var read_only: bool = false
## The picture of a filled cell. A plain red square is used if this is empty.
@export var filled_texture: Texture2D = null

var _items: Array = []  # the items (dictionaries, see inventory_items.gd)
var _owner_of: Array[int] = []  # for every cell: the number of the item that has it, -1 if empty

var _hover_cell: int = -1
var _selected: int = -1  # the number of the item whose panel is open, -1 if none

# ---- the mouse stroke that is going on ----
var _stroke: Stroke = Stroke.NONE
var _stroke_button: int = 0
var _stroke_start_cell: int = -1
var _stroke_item: int = -1  # the item an ERASE_ITEM stroke takes cells from
var _stroke_cells: Array[int] = []
var _stroke_symbol: String = ""
var _stroke_last: Vector2 = Vector2.ZERO

# ---- the panel ----
var _layer: CanvasLayer = null
var _panel: PanelContainer = null
var _symbol_label: Label = null
var _name_edit: LineEdit = null
var _note_edit: TextEdit = null
var _picker_toggle: Button = null
var _picker: GridContainer = null
var _picker_buttons: Array[Button] = []
var _filling: bool = false  # true while code fills the panel, so that doesn't count as typing


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	set_process(false)
	_owner_of.resize(Items.CELL_COUNT)
	_owner_of.fill(-1)

	if read_only:
		return

	if GlobalFunctions.character == null:
		push_error("Inventory: there is no open character sheet.")
		queue_free()
		return

	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_adopt_old_buttons()
	GlobalFunctions.character.convert_old_inventory()
	_build_panel()
	_load_items(GlobalFunctions.character.inventory)


## Shows these items (read only grids get their items this way). The list is copied.
func show_items(items: Array) -> void:
	_load_items(items)


# ------------------------------------------------------------------ the old inventory buttons

## Where the grid belongs, worked out from the 36 buttons of the old inventory (the buttons with
## index 75 to 110): {"rect": Rect2, "texture": Texture2D}, or an empty dictionary if there are
## none. The first and the last button give the distance between cells.
static func layout_from_old_buttons(buttons: Array) -> Dictionary:
	if buttons.is_empty():
		return {}

	var first = null
	var last = null
	var everything := Rect2()
	var started := false
	for button in buttons:
		var index = button.get("index")
		if index == Items.OLD_FIRST_INDEX:
			first = button
		elif index == Items.OLD_LAST_INDEX:
			last = button
		var rect := Rect2(button.position, button.size)
		everything = rect if not started else everything.merge(rect)
		started = true

	if first == null or last == null:
		return {"rect": everything, "texture": buttons[0].texture_pressed}

	var step: Vector2 = (last.position - first.position) / float(Items.COLUMNS - 1)
	return {
		"rect": Rect2(first.position, step * Vector2(Items.COLUMNS, Items.ROWS)),
		"texture": first.texture_pressed,
	}


## If the scene still has the old inventory buttons: takes their place and removes them.
func _adopt_old_buttons() -> void:
	var grid_container := get_parent().get_node_or_null("GridContainer")
	if grid_container == null:
		return

	var buttons: Array = []

	for child in grid_container.get_children():
		if child is TextureButton and Items.is_old_button_index(child.get("index")):
			buttons.append(child)

	if buttons.is_empty():
		return

	var layout := layout_from_old_buttons(buttons)

	var container_transform: Transform2D = get_parent().get_global_transform_with_canvas()
	var local_rect: Rect2 = container_transform.affine_inverse() * (
		grid_container.get_global_transform_with_canvas() * layout["rect"]
	)

	position = local_rect.position
	size = local_rect.size

	if filled_texture == null:
		filled_texture = layout["texture"]

	for button in buttons:
		button.queue_free()


# ------------------------------------------------------------------ the items

func _load_items(raw: Array) -> void:
	_items = Items.clean_items(raw)
	_rebuild()


## Works out which item has which cell. Call after _items changed.
func _rebuild() -> void:
	_owner_of.fill(-1)
	for i in _items.size():
		for cell in _items[i]["cells"]:
			_owner_of[cell] = i
	if _selected >= _items.size():
		_deselect()
	if _panel != null and _panel.visible:
		_update_picker()
	queue_redraw()


## Call after the items were changed by the user: shows the change and saves it. `keep` is the item
## that stays open (null to close the panel).
func _changed(keep = null) -> void:
	_selected = _items.find(keep) if keep != null else -1
	_rebuild()
	if _selected < 0:
		_deselect()
	_save()


func _save() -> void:
	if not read_only:
		GlobalFunctions.character.set_inventory(_items)


func _used_symbols() -> Array:
	var used: Array = []
	for item in _items:
		used.append(item["symbol"])
	return used


func _remove_cells(cells: Array[int]) -> void:
	var keep = _items[_selected] if _selected >= 0 else null
	for item in _items:
		var left: Array = []
		for cell in item["cells"]:
			if not cells.has(cell):
				left.append(cell)
		item["cells"] = left
	_items = _items.filter(func(item: Dictionary) -> bool: return not item["cells"].is_empty())
	_changed(keep)


# ------------------------------------------------------------------ cells and the mouse

func _cell_size() -> Vector2:
	return size / Vector2(Items.COLUMNS, Items.ROWS)


func _cell_rect(cell: int) -> Rect2:
	var cell_size := _cell_size()
	return Rect2(Vector2(Items.column_of(cell), Items.row_of(cell)) * cell_size, cell_size)


## The cell under a point (in this control's coordinates), -1 if none.
func _cell_at(point: Vector2) -> int:
	if size.x <= 0.0 or size.y <= 0.0 or not Rect2(Vector2.ZERO, size).has_point(point):
		return -1
	var cell_size := _cell_size()
	var column := clampi(int(point.x / cell_size.x), 0, Items.COLUMNS - 1)
	var row := clampi(int(point.y / cell_size.y), 0, Items.ROWS - 1)
	return row * Items.COLUMNS + column


func _item_at(cell: int) -> int:
	return _owner_of[cell] if cell >= 0 else -1


## The cells the mouse passed over between two points (so a fast drag doesn't skip any).
func _cells_along(from: Vector2, to: Vector2) -> Array[int]:
	var out: Array[int] = []
	var steps := maxi(1, int(ceil(from.distance_to(to) / SAMPLE_STEP)))
	for step in range(1, steps + 1):
		var cell := _cell_at(from.lerp(to, float(step) / steps))
		if cell >= 0 and not out.has(cell):
			out.append(cell)
	return out


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null:
		if read_only:
			return
		if button.button_index != MOUSE_BUTTON_LEFT and button.button_index != MOUSE_BUTTON_RIGHT:
			return  # the wheel etc. are left alone (the camera uses the wheel to zoom)
		if button.pressed:
			if _stroke == Stroke.NONE:
				_begin_stroke(button)
		elif button.button_index == _stroke_button and _stroke != Stroke.NONE:
			_end_stroke(button.position)
		return

	var motion := event as InputEventMouseMotion
	if motion != null:
		if _stroke != Stroke.NONE:
			if not Input.is_mouse_button_pressed(_stroke_button):
				_end_stroke(motion.position)  # the button was let go where this control didn't see it
				return
			for cell in _cells_along(_stroke_last, motion.position):
				_stroke_touch(cell)
			_stroke_last = motion.position
			queue_redraw()
		else:
			_set_hover(_cell_at(motion.position))


func _begin_stroke(button: InputEventMouseButton) -> void:
	# The camera also pans when you drag with the left button. It has already seen this click
	# (it looks at input before the controls do), so tell it to let go.
	var camera := get_viewport().get_camera_2d()
	if camera != null and "dragging" in camera:
		camera.set("dragging", false)

	# Clicking here ends any typing in a text field.
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner != null:
		focus_owner.release_focus()

	var cell := _cell_at(button.position)
	var held := _item_at(cell)

	if button.button_index == MOUSE_BUTTON_RIGHT:
		_stroke = Stroke.ERASE_ANY
	elif button.shift_pressed and _selected >= 0:
		_stroke = Stroke.ERASE_ITEM if held == _selected else Stroke.ADD
		_stroke_item = _selected
		_stroke_symbol = _items[_selected]["symbol"]
	elif held >= 0:
		_stroke = Stroke.PICK
	else:
		_stroke_symbol = Items.free_symbol(_used_symbols())
		if _stroke_symbol == "":
			return
		_deselect()
		_stroke = Stroke.DRAW

	_stroke_button = button.button_index
	_stroke_start_cell = cell
	_stroke_cells.clear()
	_stroke_touch(cell)
	_stroke_last = button.position
	_set_hover(-1)
	accept_event()
	queue_redraw()


## Adds a cell to the stroke if this kind of stroke takes it.
func _stroke_touch(cell: int) -> void:
	if cell < 0 or _stroke_cells.has(cell):
		return
	var held := _owner_of[cell]
	match _stroke:
		Stroke.DRAW, Stroke.ADD:
			if held < 0:
				_stroke_cells.append(cell)
		Stroke.ERASE_ITEM:
			if held == _stroke_item:
				_stroke_cells.append(cell)
		Stroke.ERASE_ANY:
			if held >= 0:
				_stroke_cells.append(cell)


func _end_stroke(point: Vector2) -> void:
	var mode := _stroke
	var cells: Array[int] = []
	cells.assign(_stroke_cells)
	var end_cell := _cell_at(point)
	_stroke = Stroke.NONE
	_stroke_cells.clear()

	match mode:
		Stroke.DRAW:
			if not cells.is_empty():
				var item := Items.new_item(Items.free_symbol(_used_symbols()), cells)
				_items.append(item)
				_changed(item)
				_open_panel(true)
		Stroke.ADD:
			if not cells.is_empty() and _selected >= 0:
				var item: Dictionary = _items[_selected]
				var all_cells: Array = item["cells"] + cells
				all_cells.sort()
				item["cells"] = all_cells
				_changed(item)
		Stroke.ERASE_ITEM, Stroke.ERASE_ANY:
			if not cells.is_empty():
				_remove_cells(cells)
		Stroke.PICK:
			# Only a click counts (not a drag that ends somewhere else).
			var picked := _item_at(end_cell)
			if end_cell == _stroke_start_cell and picked >= 0:
				_selected = picked
				_open_panel(false)

	_hover_cell = -1
	_set_hover(end_cell)
	queue_redraw()


func _set_hover(cell: int) -> void:
	if cell == _hover_cell:
		return
	var before := _item_at(_hover_cell)
	var after := _item_at(cell)
	_hover_cell = cell
	if before != after:
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _stroke == Stroke.NONE:
		_set_hover(-1)


## A click anywhere else (outside this grid and its panel) closes the panel.
func _input(event: InputEvent) -> void:
	if _selected < 0 or _panel == null:
		return
	var click := event as InputEventMouseButton
	if click == null or not click.pressed:
		return
	if click.button_index != MOUSE_BUTTON_LEFT and click.button_index != MOUSE_BUTTON_RIGHT:
		return
	if _panel.get_global_rect().has_point(click.position):
		return
	var on_screen: Rect2 = get_global_transform_with_canvas() * Rect2(Vector2.ZERO, size)
	if on_screen.has_point(click.position):
		return  # a click on the grid is dealt with by the grid
	_deselect()


# ------------------------------------------------------------------ the hover note

func _get_tooltip(at_position: Vector2) -> String:
	if _stroke != Stroke.NONE:
		return ""
	var number := _item_at(_cell_at(at_position))
	if number < 0:
		return ""
	var item: Dictionary = _items[number]
	if String(item["name"]).strip_edges().is_empty() and String(item["note"]).strip_edges().is_empty():
		return ""
	return String(item["name"]) + "\n" + String(item["note"])  # the name never has a line break


func _make_custom_tooltip(for_text: String) -> Object:
	var newline := for_text.find("\n")
	var item_name := for_text.left(newline) if newline >= 0 else for_text
	var note := for_text.substr(newline + 1) if newline >= 0 else ""
	var box := VBoxContainer.new()

	if not item_name.strip_edges().is_empty():
		var title := Label.new()
		title.text = item_name
		title.add_theme_font_size_override("font_size", 22)
		box.add_child(title)

	if not note.strip_edges().is_empty():
		var body := Label.new()
		body.text = note
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(clampf(note.length() * 9.0, 120.0, 320.0), 0.0)
		body.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
		box.add_child(body)
	return box


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	var font := get_theme_default_font()

	# The filled cells with their symbols.
	for cell in Items.CELL_COUNT:
		var number := _owner_of[cell]
		if number < 0:
			continue
		var rect := _cell_rect(cell)
		if filled_texture != null:
			draw_texture_rect(filled_texture, rect, false)
		else:
			draw_rect(rect, FILL_COLOR)
		_draw_symbol(font, rect, _items[number]["symbol"])

	# Highlight the item under the mouse.
	var hovered := _item_at(_hover_cell)
	if _stroke == Stroke.NONE and hovered >= 0:
		for cell in _items[hovered]["cells"]:
			draw_rect(_cell_rect(cell), HOVER_COLOR)

	# A line around every item, so neighbouring items can be told apart.
	for cell in Items.CELL_COUNT:
		if _owner_of[cell] >= 0:
			_draw_edges(cell, OUTLINE_COLOR, 3.0)

	# A brighter line around the open item.
	if _selected >= 0:
		for cell in _items[_selected]["cells"]:
			_draw_edges(cell, SELECT_COLOR, 4.0)

	# The cells of the stroke that is being dragged out (nothing is saved until the mouse is let go).
	match _stroke:
		Stroke.DRAW, Stroke.ADD:
			for cell in _stroke_cells:
				var rect := _cell_rect(cell)
				draw_rect(rect, DRAFT_COLOR)
				draw_rect(rect, Color.WHITE, false, 2.0)
				_draw_symbol(font, rect, _stroke_symbol)
		Stroke.ERASE_ITEM, Stroke.ERASE_ANY:
			for cell in _stroke_cells:
				var rect := _cell_rect(cell)
				draw_rect(rect, ERASE_COLOR)
				draw_rect(rect, Color(1.0, 0.3, 0.3), false, 2.0)


func _draw_symbol(font: Font, rect: Rect2, symbol: String) -> void:
	var baseline_y := rect.position.y + rect.size.y * 0.5 \
		+ (font.get_ascent(SYMBOL_FONT_SIZE) - font.get_descent(SYMBOL_FONT_SIZE)) * 0.5
	var at := Vector2(rect.position.x, baseline_y)
	draw_string_outline(font, at, symbol, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, SYMBOL_FONT_SIZE, 4, SYMBOL_OUTLINE_COLOR)
	draw_string(font, at, symbol, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, SYMBOL_FONT_SIZE, SYMBOL_COLOR)


## Draws the sides of this cell that have no cell of the same item next to them.
func _draw_edges(cell: int, color: Color, width: float) -> void:
	var number := _owner_of[cell]
	var rect := _cell_rect(cell)
	var column := Items.column_of(cell)
	var row := Items.row_of(cell)
	var top_left := rect.position
	var top_right := rect.position + Vector2(rect.size.x, 0.0)
	var bottom_left := rect.position + Vector2(0.0, rect.size.y)
	var bottom_right := rect.end

	if _owner_at(column, row - 1) != number:
		_edge(top_left, top_right, color, width)
	if _owner_at(column, row + 1) != number:
		_edge(bottom_left, bottom_right, color, width)
	if _owner_at(column - 1, row) != number:
		_edge(top_left, bottom_left, color, width)
	if _owner_at(column + 1, row) != number:
		_edge(top_right, bottom_right, color, width)


## A line that sticks out half its width at both ends, so lines meet cleanly at the corners.
func _edge(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var direction := (to - from).normalized() * width * 0.5
	draw_line(from - direction, to + direction, color, width)


func _owner_at(column: int, row: int) -> int:
	if column < 0 or column >= Items.COLUMNS or row < 0 or row >= Items.ROWS:
		return -1
	return _owner_of[row * Items.COLUMNS + column]


# ------------------------------------------------------------------ the item panel

func _build_panel() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 14
	add_child(_layer)

	_panel = PanelContainer.new()
	_panel.visible = false
	if ResourceLoader.exists(THEME_PATH):
		_panel.theme = load(THEME_PATH) as Theme
	_layer.add_child(_panel)

	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	_panel.add_child(column)

	# Symbol and name.
	var top := HBoxContainer.new()
	column.add_child(top)

	_symbol_label = Label.new()
	_symbol_label.custom_minimum_size = Vector2(44.0, 0.0)
	_symbol_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_symbol_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_symbol_label.add_theme_font_size_override("font_size", SYMBOL_FONT_SIZE)
	top.add_child(_symbol_label)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Name this item"
	_name_edit.max_length = Items.MAX_NAME_LENGTH
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_changed.connect(func(_text: String) -> void: _write_info())
	_name_edit.text_submitted.connect(func(_text: String) -> void: _deselect())
	_name_edit.gui_input.connect(_on_panel_key)
	top.add_child(_name_edit)

	# Note.
	_note_edit = TextEdit.new()
	_note_edit.placeholder_text = "Note (shown when you hover the item)"
	_note_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_note_edit.custom_minimum_size = Vector2(0.0, 84.0)
	_note_edit.text_changed.connect(_write_info)
	_note_edit.gui_input.connect(_on_panel_key)
	column.add_child(_note_edit)

	# Symbol picker (hidden until asked for).
	_picker_toggle = Button.new()
	_picker_toggle.text = "Change symbol"
	_picker_toggle.toggle_mode = true
	_picker_toggle.focus_mode = Control.FOCUS_NONE
	_picker_toggle.toggled.connect(_on_picker_toggled)
	column.add_child(_picker_toggle)

	_picker = GridContainer.new()
	_picker.columns = 13
	_picker.visible = false
	column.add_child(_picker)
	for symbol in Items.SYMBOLS:
		var pick := Button.new()
		pick.text = symbol
		pick.custom_minimum_size = Vector2(32.0, 32.0)
		pick.focus_mode = Control.FOCUS_NONE
		pick.pressed.connect(_on_symbol_picked.bind(symbol))
		_picker.add_child(pick)
		_picker_buttons.append(pick)

	# Delete and Done.
	var bottom := HBoxContainer.new()
	column.add_child(bottom)

	var delete_button := Button.new()
	delete_button.text = "Delete item"
	delete_button.focus_mode = Control.FOCUS_NONE
	delete_button.pressed.connect(_delete_selected)
	bottom.add_child(delete_button)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(spacer)

	var done_button := Button.new()
	done_button.text = "Done"
	done_button.focus_mode = Control.FOCUS_NONE
	done_button.pressed.connect(_deselect)
	bottom.add_child(done_button)

	var hint := Label.new()
	hint.text = "Shift + drag adds cells.  Right-drag erases."
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	column.add_child(hint)


## Opens the panel for the selected item.
func _open_panel(focus_name: bool) -> void:
	if _selected < 0 or _panel == null:
		return
	var item: Dictionary = _items[_selected]

	_filling = true
	_symbol_label.text = item["symbol"]
	_name_edit.text = item["name"]
	_note_edit.text = item["note"]
	_filling = false

	_picker_toggle.set_pressed_no_signal(false)
	_picker.visible = false
	_update_picker()

	_panel.visible = true
	_panel.reset_size()
	_place_panel()
	set_process(true)
	if focus_name:
		_name_edit.grab_focus()
	queue_redraw()


## Closes the panel. (The name and note are saved as they are typed.)
func _deselect() -> void:
	_selected = -1
	if _panel != null:
		_panel.visible = false
		if _name_edit.has_focus():
			_name_edit.release_focus()
		if _note_edit.has_focus():
			_note_edit.release_focus()
	set_process(false)
	queue_redraw()


## Keeps the panel next to the open item, even while the camera moves or zooms.
func _process(_delta: float) -> void:
	if _panel != null and _panel.visible:
		_place_panel()


func _place_panel() -> void:
	if _selected < 0:
		return
	var item_rect := Rect2()
	var first := true
	for cell in _items[_selected]["cells"]:
		item_rect = _cell_rect(cell) if first else item_rect.merge(_cell_rect(cell))
		first = false

	var on_screen: Rect2 = get_global_transform_with_canvas() * item_rect
	var view := get_viewport().get_visible_rect().size
	var panel_size := _panel.size
	var spot := Vector2(on_screen.end.x + PANEL_GAP, on_screen.position.y)
	if spot.x + panel_size.x > view.x:
		spot.x = on_screen.position.x - panel_size.x - PANEL_GAP  # no room on the right
	spot.x = clampf(spot.x, 0.0, maxf(0.0, view.x - panel_size.x))
	spot.y = clampf(spot.y, 0.0, maxf(0.0, view.y - panel_size.y))
	_panel.position = spot


## Saves what is typed in the panel as the name and note of the open item.
func _write_info() -> void:
	if _filling or _selected < 0:
		return

	var note := _note_edit.text
	if note.length() > Items.MAX_NOTE_LENGTH:
		note = note.left(Items.MAX_NOTE_LENGTH)
		_filling = true
		_note_edit.text = note
		var last_line := _note_edit.get_line_count() - 1
		_note_edit.set_caret_line(last_line)
		_note_edit.set_caret_column(_note_edit.get_line(last_line).length())
		_filling = false

	var item: Dictionary = _items[_selected]
	item["name"] = _name_edit.text.replace("\n", " ")
	item["note"] = note
	_save()


## Esc closes the panel (and doesn't also open the settings menu).
func _on_panel_key(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_deselect()
		get_viewport().set_input_as_handled()


func _on_picker_toggled(shown: bool) -> void:
	_picker.visible = shown
	_panel.reset_size.call_deferred()


## Dims the symbols that another item has, and marks the open item's own symbol.
func _update_picker() -> void:
	if _selected < 0:
		return
	var current: String = _items[_selected]["symbol"]
	var used := _used_symbols()
	for i in _picker_buttons.size():
		var symbol := Items.SYMBOLS[i]
		if symbol == current:
			_picker_buttons[i].modulate = SELECT_COLOR
		elif used.has(symbol):
			_picker_buttons[i].modulate = Color(1.0, 1.0, 1.0, 0.45)
		else:
			_picker_buttons[i].modulate = Color.WHITE


func _on_symbol_picked(symbol: String) -> void:
	if _selected < 0:
		return
	var item: Dictionary = _items[_selected]
	if item["symbol"] == symbol:
		return
	item["symbol"] = symbol
	_symbol_label.text = symbol
	_update_picker()
	queue_redraw()
	_save()


func _delete_selected() -> void:
	if _selected < 0:
		return
	_items.remove_at(_selected)
	_changed()
