@tool
extends TextureRect
## PDF viewer. Shows one page of a PDF at a time, with previous / next buttons and a box to type
## the page number you want. It also draws the page in the editor, so you can set it up without
## running the game.
##
## In the Inspector:
##   Pdf Path          the PDF to show (the imported .pdf file in your project)
##   Page              the page to show (1 = first page). Change it in the editor to see that page
##                     right there, and it is also the page the game starts on.
##   Render Scale      sharpness of the page (2.0 = 144 dpi). Higher is sharper but slower.
##   Show Controls     the little "< Page [ 3 ] / 12 >" bar at the bottom of the viewer
##   Wrap Around       next on the last page goes to the first page (and the other way round)
##   Click To Advance  left click (without dragging) on the page turns to the next page
##   Preview In Editor turn off if loading the PDF in the editor is too slow
##
## From other scripts:
##   $PDF.go_to_page(5)   $PDF.next_page()   $PDF.previous_page()
##   $PDF.get_page_count()   $PDF.get_current_page()   $PDF.load_pdf("res://other.pdf")
##   signal page_changed(page, page_count)

## The page on screen changed (page counts from 1).
signal page_changed(page: int, page_count: int)
## A PDF was opened.
signal document_loaded(page_count: int)

## How many drawn pages are kept so that turning back to them is instant.
const CACHE_SIZE := 6
## A click that moves the mouse more than this many pixels is a drag (camera pan), not a click.
const CLICK_SLOP := 8.0

@export_file("*.pdf") var pdf_path: String = "":
	set(value):
		pdf_path = value
		_close_document()
		_queue_refresh()

## The page to show. 1 is the first page.
@export_range(1, 9999, 1, "or_greater") var page: int = 1:
	get:
		return _page
	set(value):
		_set_page(value)

@export_range(0.1, 4.0, 0.1) var render_scale: float = 2.0:
	set(value):
		render_scale = value
		_clear_cache()
		_queue_refresh()

@export var show_controls: bool = true:
	set(value):
		show_controls = value
		_update_controls()

@export var wrap_around: bool = false:
	set(value):
		wrap_around = value
		_update_controls()

@export var click_to_advance: bool = false

@export var preview_in_editor: bool = true:
	set(value):
		preview_in_editor = value
		_queue_refresh()

var _page: int = 1
var _doc = null  # a PDFDocument (untyped, so this script still loads if the extension doesn't)
var _count: int = 0
var _load_failed: bool = false
var _problem: String = ""

var _cache: Dictionary = {}  # page number -> ImageTexture
var _cache_order: Array[int] = []  # oldest first
var _refresh_queued: bool = false
var _announced_page: int = -1
var _announced_count: int = -1
var _press_position: Vector2 = Vector2.ZERO

var _bar: PanelContainer = null
var _prev_button: Button = null
var _next_button: Button = null
var _spin: SpinBox = null
var _total_label: Label = null
var _syncing: bool = false  # true while the controls are being updated by code


func _enter_tree() -> void:
	_queue_refresh()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_build_controls()
	_queue_refresh()


# ------------------------------------------------------------------ using the viewer

## Opens another PDF (and shows its first page, or start_page).
func load_pdf(path: String, start_page: int = 1) -> void:
	_page = maxi(1, start_page)
	pdf_path = path


## How many pages the PDF has (0 if there is no PDF or it could not be opened).
func get_page_count() -> int:
	_ensure_document()
	return _count


## The page on screen, counting from 1.
func get_current_page() -> int:
	return _page


## Shows that page (counting from 1). A page that doesn't exist is moved to the nearest one that
## does. Returns true if the page you asked for exists.
func go_to_page(number: int) -> bool:
	_ensure_document()
	var exists := number >= 1 and (_count == 0 or number <= _count)
	_set_page(number)
	return exists


func next_page() -> void:
	var count := get_page_count()
	if count < 1:
		return
	if _page >= count:
		if wrap_around:
			_set_page(1)
		return
	_set_page(_page + 1)


func previous_page() -> void:
	var count := get_page_count()
	if count < 1:
		return
	if _page <= 1:
		if wrap_around:
			_set_page(count)
		return
	_set_page(_page - 1)


func _set_page(value: int) -> void:
	var wanted := maxi(1, value)
	if _count > 0:
		wanted = mini(wanted, _count)
	if wanted == _page:
		return
	_page = wanted
	_queue_refresh()


func _gui_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not click_to_advance:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_position = event.position
		elif event.position.distance_to(_press_position) <= CLICK_SLOP:
			next_page()
			accept_event()


# ------------------------------------------------------------------ drawing the page

## Redraws at the end of the frame, so a burst of changes (dragging a slider in the Inspector)
## only draws once.
func _queue_refresh() -> void:
	if _refresh_queued or not is_inside_tree():
		return
	_refresh_queued = true
	_refresh.call_deferred()


func _refresh() -> void:
	_refresh_queued = false
	if not is_inside_tree():
		return
	if _bar == null or not is_instance_valid(_bar):
		_build_controls()

	if Engine.is_editor_hint() and not preview_in_editor:
		_close_document()
		texture = null
		_update_controls()
		return

	if not _ensure_document():
		texture = null
		_update_controls()
		return

	var clamped := clampi(_page, 1, maxi(_count, 1))
	if clamped != _page:
		_page = clamped
		if Engine.is_editor_hint():
			notify_property_list_changed()

	var drawn := _page_texture(_page)
	if drawn != null:
		texture = drawn
	else:
		push_warning("PDF viewer (%s): could not draw page %d." % [name, _page])

	_update_controls()

	if _page != _announced_page or _count != _announced_count:
		_announced_page = _page
		_announced_count = _count
		page_changed.emit(_page, _count)


## The drawn page, from the cache if it is there. Null if the page could not be drawn.
func _page_texture(number: int) -> Texture2D:
	if _cache.has(number):
		_cache_order.erase(number)
		_cache_order.append(number)
		return _cache[number]

	var pdf_page = _doc.get_page(number - 1)  # the extension counts pages from 0
	if pdf_page == null:
		return null
	var img = pdf_page.render_to_image(render_scale)
	if not (img is Image) or img.is_empty():
		return null

	var drawn := ImageTexture.create_from_image(img)
	_cache[number] = drawn
	_cache_order.append(number)
	while _cache_order.size() > CACHE_SIZE:
		_cache.erase(_cache_order.pop_front())
	return drawn


func _clear_cache() -> void:
	_cache.clear()
	_cache_order.clear()


# ------------------------------------------------------------------ opening the PDF

func _close_document() -> void:
	_doc = null
	_count = 0
	_load_failed = false
	_problem = ""
	_clear_cache()
	_announced_page = -1
	_announced_count = -1
	_update_warnings()


## Opens the PDF if it isn't open yet. Returns true if a PDF is open.
func _ensure_document() -> bool:
	if _doc != null:
		return true
	if _load_failed or pdf_path.is_empty():
		return false
	_open_document(pdf_path)
	return _doc != null


func _open_document(path: String) -> void:
	_problem = ""
	if not ClassDB.class_exists("PDFDocument"):
		_fail("The PDFium-GDE extension is not loaded, so PDFs can't be shown (in the editor, try restarting it).")
		return

	# 1. The PDF as Godot imported it. This is what works in an exported game.
	if ResourceLoader.exists(path):
		var imported = load(path)
		if _is_open_document(imported):
			_use_document(imported)
			return

	# 2. The PDF file itself (works for res://, user:// and full paths on this computer).
	var source := _source_path(path)
	if source != "":
		for candidate in [source, ProjectSettings.globalize_path(source)]:
			var doc = ClassDB.instantiate("PDFDocument")
			var err = doc.load_from_file(candidate)
			if (typeof(err) != TYPE_INT or err == OK) and _is_open_document(doc):
				_use_document(doc)
				return

	_fail("Could not open the PDF '%s'." % path)


func _use_document(doc) -> void:
	_doc = doc
	_count = int(doc.get_page_count())
	_load_failed = false
	_update_warnings()
	document_loaded.emit(_count)


static func _is_open_document(candidate) -> bool:
	return candidate is Object \
		and candidate.has_method("get_page_count") \
		and int(candidate.get_page_count()) > 0


## A uid:// path turned into the path of the file it stands for.
static func _source_path(path: String) -> String:
	if path.begins_with("uid://"):
		var id := ResourceUID.text_to_id(path)
		if ResourceUID.has_id(id):
			return ResourceUID.get_id_path(id)
		return ""
	return path


func _fail(message: String) -> void:
	_load_failed = true
	_problem = message
	push_error("PDF viewer (%s): %s" % [name, message])
	_update_warnings()


# ------------------------------------------------------------------ the page controls

func _build_controls() -> void:
	var old := get_node_or_null("PageControls")
	if old != null:
		old.free()

	_bar = PanelContainer.new()
	_bar.name = "PageControls"  # no owner is set, so it is never saved into the scene
	_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bar.offset_bottom = -12.0
	add_child(_bar)

	var row := HBoxContainer.new()
	_bar.add_child(row)

	_prev_button = Button.new()
	_prev_button.text = "<"
	_prev_button.tooltip_text = "Previous page"
	_prev_button.focus_mode = Control.FOCUS_NONE  # so it doesn't hold on to the keyboard
	_prev_button.pressed.connect(previous_page)
	row.add_child(_prev_button)

	var page_label := Label.new()
	page_label.text = "Page"
	page_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(page_label)

	_spin = SpinBox.new()
	_spin.min_value = 1
	_spin.max_value = 1
	_spin.step = 1
	_spin.rounded = true
	_spin.tooltip_text = "Type a page number and press Enter"
	_spin.value_changed.connect(_on_spin_changed)
	var line := _spin.get_line_edit()
	line.select_all_on_focus = true
	# After Enter, give the keyboard back (a focused text field stops the camera from moving).
	line.text_submitted.connect(func(_text: String) -> void: line.release_focus())
	row.add_child(_spin)

	_total_label = Label.new()
	_total_label.text = "/ 0"
	_total_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_total_label)

	_next_button = Button.new()
	_next_button.text = ">"
	_next_button.tooltip_text = "Next page"
	_next_button.focus_mode = Control.FOCUS_NONE
	_next_button.pressed.connect(next_page)
	row.add_child(_next_button)

	_update_controls()


func _on_spin_changed(value: float) -> void:
	if _syncing:
		return
	go_to_page(int(value))


func _update_controls() -> void:
	if _bar == null or not is_instance_valid(_bar):
		return
	_bar.visible = show_controls and _count > 0

	_syncing = true
	_spin.max_value = maxi(_count, 1)
	_spin.set_value_no_signal(_page)
	_syncing = false

	_total_label.text = "/ %d" % _count
	_prev_button.disabled = _count < 2 or (_page <= 1 and not wrap_around)
	_next_button.disabled = _count < 2 or (_page >= _count and not wrap_around)


# ------------------------------------------------------------------ editor warnings

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if pdf_path.is_empty():
		warnings.append("Set 'Pdf Path' to the PDF this viewer should show.")
	elif _problem != "":
		warnings.append(_problem)
	return warnings


func _update_warnings() -> void:
	if Engine.is_editor_hint() and is_inside_tree():
		update_configuration_warnings()
