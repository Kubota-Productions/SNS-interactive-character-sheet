extends TextureButton

@export var index: int = 1

# Shared singleton popup
static var canvas_layer: CanvasLayer
static var popup: PopupPanel
static var hbox: HBoxContainer
static var current_button: TextureButton  # which button triggered the popup

var symbol_label: Label  # only created for buttons that support symbols

var symbolslist1 := ["★","☆","✦","✧","✩","✱","✫","✯","●","○","◍","◌"]
var symbolslist2 := ["◐","◑","◒","◓","◔","◕","◉","☐","☒","▲","△","▼","▽"]
var symbolslist3 := ["◆","◇","◈","◊","■","□","▣","▥","☾","❅","↔","∞","∑"]
var symbolslist4 := ["≤","≥","∆","∇","π","Ω","√","±","÷","×","≈","≠","✣"]

func _ready() -> void:
	var sheet := GlobalFunctions.character

	# No-signal version so loading doesn't trigger a save.
	set_pressed_no_signal(sheet.get_toggle(index))

	if index >= 75 and index <= 110:
		if not canvas_layer:
			canvas_layer = CanvasLayer.new()
			get_tree().current_scene.add_child.call_deferred(canvas_layer)

			popup = PopupPanel.new()
			canvas_layer.add_child(popup)

			hbox = HBoxContainer.new()
			hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
			popup.add_child(hbox)

			_add_symbol_column(symbolslist1)
			_add_symbol_column(symbolslist2)
			_add_symbol_column(symbolslist3)
			_add_symbol_column(symbolslist4)

		symbol_label = Label.new()
		add_child(symbol_label)
		symbol_label.text = sheet.get_symbol(index)
		symbol_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		symbol_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		symbol_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		symbol_label.add_theme_font_size_override("font_size", 32)
		symbol_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _add_symbol_column(symbols: Array) -> void:
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for s in symbols:
		var btn := Button.new()
		btn.text = s
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.pressed.connect(func():
			_on_symbol_selected(s)
		)
		vbox.add_child(btn)
	hbox.add_child(vbox)


func _on_toggled(toggled_on: bool) -> void:
	GlobalFunctions.character.set_toggle(index, toggled_on)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if index >= 75 and index <= 110 and popup:
			current_button = self
			popup.position = get_global_mouse_position()
			popup.popup()


func _on_symbol_selected(symbol: String) -> void:
	if current_button:
		current_button.symbol_label.text = symbol
		GlobalFunctions.character.set_symbol(current_button.index, symbol)
	popup.hide()
