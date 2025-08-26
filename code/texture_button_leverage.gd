extends TextureButton

var was_just_editing = true
@export var index: int = 1
var player_name = GlobalFunctions.return_player_name()

# Shared singleton popup
static var canvas_layer: CanvasLayer
static var popup: PopupPanel
static var hbox: HBoxContainer

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
			popup.position = get_global_mouse_position()
			popup.popup()


func _on_symbol_selected(symbol: String) -> void:
	symbol_label.text = symbol
	if popup:
		popup.hide()
