@tool
extends Control
## Attach to an ordinary LineEdit, TextEdit, CheckBox, TextureButton, OptionButton, or Button.
## Index is the save key. Tag optionally identifies values across fresh imports.

signal value_changed(value: Variant)
signal activated(index: int, tag: String)

@export_range(1, 1000000) var index: int = 1
@export var tag: String = ""
@export_enum("text", "multiline", "checkbox", "radio", "choice", "button", "image", "symbol", "unsupported") var field_type: String = "text"
@export var pdf_name: String = ""
@export var radio_option: String = ""
@export var option_values: PackedStringArray = []
@export var symbols: PackedStringArray = ["", "●", "■", "★"]

var _widget: Variant = self
var _image_png: String = ""
var _image_view: TextureRect
var _dialog: FileDialog

func _get_configuration_warnings() -> PackedStringArray:
	if not _compatible():
		return ["Field Type must match this node's native type. Use Godot's Change Type command when changing between text, choice, and button controls."]
	return []

func _compatible() -> bool:
	match field_type:
		"text": return _widget is LineEdit
		"multiline": return _widget is TextEdit
		"choice": return _widget is OptionButton
		"checkbox", "radio": return _widget is BaseButton and _widget.toggle_mode
		_: return _widget is Button

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if not _compatible():
		push_error("PDF field type does not match its native control: " + str(get_path()))
		return
	if _widget is LineEdit or _widget is TextEdit:
		_widget.text_changed.connect(func(_unused = null): value_changed.emit(get_value()))
	elif _widget is OptionButton:
		_widget.item_selected.connect(func(_item): value_changed.emit(get_value()))
	elif _widget is BaseButton:
		if field_type == "checkbox" or field_type == "radio":
			_widget.toggled.connect(func(on):
				if field_type == "radio" and not on:
					_radio_released.call_deferred()
				else:
					value_changed.emit(get_value()))
		else:
			_widget.pressed.connect(_pressed)

func _radio_released() -> void:
	if _widget.button_group == null or _widget.button_group.get_pressed_button() == null:
		value_changed.emit("")

func _pressed() -> void:
	match field_type:
		"symbol":
			if symbols.is_empty():
				return
			_widget.text = symbols[(symbols.find(_widget.text) + 1) % symbols.size()]
			value_changed.emit(get_value())
		"image":
			if not is_instance_valid(_dialog):
				_dialog = FileDialog.new()
				_dialog.access = FileDialog.ACCESS_FILESYSTEM
				_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
				_dialog.filters = ["*.png,*.jpg,*.jpeg,*.webp; Images"]
				add_child(_dialog)
				_dialog.file_selected.connect(_select_image)
			_dialog.popup_centered(Vector2i(800, 600))
		_:
			activated.emit(index, tag)

func _select_image(path: String) -> void:
	var image := Image.load_from_file(path)
	if image == null:
		push_error("Could not load image: " + path)
		return
	set_value(Marshalls.raw_to_base64(image.save_png_to_buffer()))
	value_changed.emit(get_value())

func get_value() -> Variant:
	if not _compatible():
		return null
	match field_type:
		"checkbox": return _widget.button_pressed
		"radio": return radio_option if _widget.button_pressed else ""
		"choice": return option_values[_widget.selected] if _widget.selected >= 0 and _widget.selected < option_values.size() else ""
		"image": return _image_png
		"text", "multiline", "symbol": return _widget.text
	return null

func accepts(value: Variant) -> bool:
	if not _compatible():
		return false
	if field_type == "checkbox":
		return value is bool
	if not value is String:
		return false
	if field_type == "choice":
		return value == "" or option_values.has(value)
	return field_type in ["text", "multiline", "radio", "image", "symbol"]

func set_value(value: Variant) -> void:
	if not accepts(value):
		return
	match field_type:
		"checkbox": _widget.set_pressed_no_signal(value)
		"radio": _widget.set_pressed_no_signal(value == radio_option)
		"choice": _widget.select(option_values.find(value))
		"text", "multiline", "symbol": _widget.text = value
		"image":
			var image := Image.new()
			if value != "" and image.load_png_from_buffer(Marshalls.base64_to_raw(value)) != OK:
				return
			_image_png = value
			if not is_instance_valid(_image_view):
				_image_view = TextureRect.new()
				_image_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
				_image_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				_image_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				add_child(_image_view)
				_image_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			_image_view.texture = ImageTexture.create_from_image(image) if value != "" else null
