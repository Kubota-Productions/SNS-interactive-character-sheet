extends TextureButton

var was_just_editing = true
@export var index: int = 1
var player_name = GlobalFunctions.return_player_name()

# Shared singleton popup
static var canvas_layer: CanvasLayer
static var popup: PopupPanel
static var hbox: HBoxContainer
static var current_button: TextureButton  # track which button triggered the popup

@onready var symbol_label: Label = Label.new()

# Symbols grouped into 4 categories (columns)
var symbolslist1 := ["★","☆","✦","✧","✩","✱","✫","✯","●","○","◍","◌"]
var symbolslist2 := ["◐","◑","◒","◓","◔","◕","◉","☐","☒","▲","△","▼","▽"]
var symbolslist3 := ["◆","◇","◈","◊","■","□","▣","▥","☾","❅","↔","∞","∑"]
var symbolslist4 := ["≤","≥","∆","∇","π","Ω","√","±","÷","×","≈","≠","✣"]

func _ready() -> void:
	button_pressed = false

	if index >= 75 and index <= 110:
		# Setup shared popup once
		if not canvas_layer:
			canvas_layer = CanvasLayer.new()
			get_tree().current_scene.add_child(canvas_layer)

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

		# Symbol label overlay
		add_child(symbol_label)
		symbol_label.text = ""
		symbol_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		symbol_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		symbol_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		symbol_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		symbol_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		symbol_label.add_theme_font_size_override("font_size", 32)

	# Initialize toggle state
	if GlobalFunctions.data != null and GlobalFunctions.data.size() > index:
		if GlobalFunctions.data[index] == "true":
			button_pressed = true

	# Initialize symbol from saved data (offset +111)
	if GlobalFunctions.data != null and GlobalFunctions.data.size() > index + 111:
		var saved_symbol = GlobalFunctions.data[index + 111]
		if saved_symbol != "" and saved_symbol != "true" and saved_symbol != "false":
			symbol_label.text = saved_symbol


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
	GlobalFunctions.store_data(index, str(toggled_on))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if index >= 75 and index <= 110 and popup:
			current_button = self  # track which button was clicked
			popup.position = get_global_mouse_position()
			popup.popup()


func _on_symbol_selected(symbol: String) -> void:
	if current_button:
		current_button.symbol_label.text = symbol
		# store symbol starting from index 111 to avoid overwriting toggles
		GlobalFunctions.store_data(current_button.index + 111, symbol)
	popup.hide()
