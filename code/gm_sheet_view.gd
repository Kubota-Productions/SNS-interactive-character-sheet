extends Node2D
## One connected player's character sheet, drawn on the GM screen. VIEW ONLY.
##
## It builds a copy of the real player sheet scene and then makes it inert:
##   * everything that does something is removed (the camera, dice roller, 3D combat board, PDF
##     viewer, music player, file dialog)
##   * every script on the copy is removed and every signal connection to those scripts is cut,
##     so nothing can react to a click, a key press or a change
##   * every control ignores the mouse and can't take keyboard focus
## What is left is the sheet's pictures and its text boxes / buttons, which this script fills in
## from the SheetModel (the view-only copy of the player's sheet) and keeps up to date.
## Nothing in here is ever saved, and nothing is ever sent back to the player.

const SHEET_SCENE_PATH := "res://scenes/player_character_creator_scene.tscn"

## The sheet is about this big (the widgets reach x = 2389, y = 1071).
const SHEET_SIZE := Vector2(2420, 1080)

## Parts of the sheet scene that must not exist on the GM screen. A node is removed if its name,
## its script, the scene it came from, or its type is on one of these lists.
const REMOVE_NAMES := ["Camera2D", "backgrounddots", "DiceRoller", "3Dcombatscene", "PDF"]
const REMOVE_SCRIPTS := ["camera_2d.gd", "gamepdf.gd", "audioplayerscript.gd", "mousefollowmenuui.gd", "dice_roller.gd"]
const REMOVE_SCENES := ["combat_scene_3D.tscn", "3D_DiceRoller.tscn"]
const REMOVE_TYPES := ["Camera2D", "Camera3D", "AudioStreamPlayer", "AudioStreamPlayer2D", "AudioStreamPlayer3D", "Window"]

## The sheet's right-click symbol popup works on buttons with these indexes (see
## texture_button_leverage.gd); each of those shows a symbol on top of the button.
const SYMBOL_INDEX_FIRST := 75
const SYMBOL_INDEX_LAST := 110

var peer_id: int = 0
var player_name: String = ""

var _model = null  # the SheetModel being shown

var _text_widgets: Dictionary = {}  # index -> [LineEdit or TextEdit]
var _toggle_widgets: Dictionary = {}  # index -> [button]
var _symbol_labels: Dictionary = {}  # index -> Label
var _name_widgets: Array = []  # the LineEdits that show the character's name
var _appearance_rect: TextureRect = null
var _default_appearance: Texture2D = null
var _tag: Label = null


## Builds the view. Returns false if the sheet scene couldn't be loaded.
func setup(p_peer_id: int, p_player_name: String, model) -> bool:
	peer_id = p_peer_id
	player_name = p_player_name
	_model = model

	var scene := load(SHEET_SCENE_PATH) as PackedScene
	if scene == null:
		push_error("GM sheet view: could not load " + SHEET_SCENE_PATH)
		return false

	# A plain dark panel behind the sheet, so it is clear where this player's sheet ends.
	var backing := ColorRect.new()
	backing.name = "Backing"
	backing.color = Color(0.07, 0.07, 0.09)
	backing.size = SHEET_SIZE
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backing)

	# The copy is made inert BEFORE it is added to the scene, so none of its code ever runs.
	var sheet := scene.instantiate()
	sheet.name = "Sheet"
	_make_inert(sheet)
	add_child(sheet)

	_tag = Label.new()
	_tag.name = "NameTag"
	_tag.position = Vector2(1545, 10)
	_tag.size = Vector2(860, 80)
	_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tag.clip_text = true
	_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag.add_theme_font_size_override("font_size", 40)
	_tag.add_theme_color_override("font_color", Color.WHITE)
	_tag.add_theme_color_override("font_outline_color", Color.BLACK)
	_tag.add_theme_constant_override("outline_size", 8)
	add_child(_tag)

	_model.updated.connect(_on_model_updated)
	_refresh_all()
	return true


func set_player_name(new_name: String) -> void:
	player_name = new_name
	_refresh_tag()


# ------------------------------------------------------------------ making the copy inert

func _make_inert(sheet: Node) -> void:
	# 1. Remove the parts that must not exist here.
	var all_nodes: Array = []
	_collect(sheet, all_nodes)
	for node in all_nodes:
		if node == sheet or not is_instance_valid(node):
			continue  # (a node inside a part that was already removed is gone with it)
		if _should_remove(node):
			node.get_parent().remove_child(node)
			node.free()

	# 2. Look at what is left: note which widgets show which part of the sheet.
	var nodes: Array = []
	_collect(sheet, nodes)
	for node in nodes:
		_note_widget(node)

	# 3. Cut every connection from a node to a script of the sheet (they are the sheet's own
	#    "when this is clicked / typed in, save it" wiring). Connections inside the engine stay.
	for node in nodes:
		for signal_info in node.get_signal_list():
			for connection in node.get_signal_connection_list(signal_info["name"]):
				var callable: Callable = connection["callable"]
				var target = callable.get_object()
				if callable.is_standard() and target != null and target.get_script() != null:
					node.disconnect(signal_info["name"], callable)

	# 4. Remove every script, and make every control ignore the mouse and the keyboard.
	for node in nodes:
		node.set_script(null)
		if node is Control:
			node.mouse_filter = Control.MOUSE_FILTER_IGNORE
			node.focus_mode = Control.FOCUS_NONE


func _collect(node: Node, out: Array) -> void:
	out.append(node)
	for child in node.get_children():
		_collect(child, out)


func _should_remove(node: Node) -> bool:
	if String(node.name) in REMOVE_NAMES:
		return true
	var script: Script = node.get_script()
	if script != null and script.resource_path.get_file() in REMOVE_SCRIPTS:
		return true
	if node.scene_file_path != "" and node.scene_file_path.get_file() in REMOVE_SCENES:
		return true
	for type_name in REMOVE_TYPES:
		if node.is_class(type_name):
			return true
	return false


## Works out what a widget of the sheet shows (this must run while its script is still there:
## the index is a variable of that script).
func _note_widget(node: Node) -> void:
	var script: Script = node.get_script()
	if script == null:
		return
	var file := script.resource_path.get_file()

	if node is LineEdit and (file == "line_editname.gd" or node.name == "LineEditname"):
		_name_widgets.append(node)
		return

	if file == "add_image.gd" or node.name == "Appearancebutton":
		_appearance_rect = node.get_node_or_null("TextureRect") as TextureRect
		if _appearance_rect != null:
			_default_appearance = _appearance_rect.texture
		return

	var index = node.get("index")
	if typeof(index) != TYPE_INT:
		return

	if node is LineEdit or node is TextEdit:
		_add_widget(_text_widgets, index, node)
	elif node is BaseButton:
		_add_widget(_toggle_widgets, index, node)
		if index >= SYMBOL_INDEX_FIRST and index <= SYMBOL_INDEX_LAST:
			# Same look as the label texture_button_leverage.gd puts on these buttons.
			var label := Label.new()
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.add_theme_font_size_override("font_size", 32)
			node.add_child(label)
			label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			_symbol_labels[index] = label


func _add_widget(table: Dictionary, index: int, node: Node) -> void:
	if not table.has(index):
		table[index] = []
	table[index].append(node)


# ------------------------------------------------------------------ showing the data

func _on_model_updated(kind: String, index: int) -> void:
	match kind:
		"all":
			_refresh_all()
		"text":
			_show_text(index)
		"toggle":
			_show_toggle(index)
		"symbol":
			_show_symbol(index)
		"name":
			_show_name()
			_refresh_tag()
		"image":
			_show_image()


func _refresh_all() -> void:
	for index in _text_widgets:
		_show_text(index)
	for index in _toggle_widgets:
		_show_toggle(index)
	for index in _symbol_labels:
		_show_symbol(index)
	_show_name()
	_show_image()
	_refresh_tag()


func _show_text(index: int) -> void:
	var value: String = _model.get_text(index)
	for widget in _text_widgets.get(index, []):
		if widget.text != value:
			widget.text = value


func _show_toggle(index: int) -> void:
	var value: bool = _model.get_toggle(index)
	for button in _toggle_widgets.get(index, []):
		button.set_pressed_no_signal(value)


func _show_symbol(index: int) -> void:
	if _symbol_labels.has(index):
		_symbol_labels[index].text = _model.get_symbol(index)


func _show_name() -> void:
	for widget in _name_widgets:
		if widget.text != _model.character_name:
			widget.text = _model.character_name


func _show_image() -> void:
	if _appearance_rect == null:
		return
	var texture = _model.get_appearance_texture()
	_appearance_rect.texture = texture if texture != null else _default_appearance


func _refresh_tag() -> void:
	if _tag == null:
		return
	var text := player_name
	if _model.character_name != "":
		text += "  -  " + _model.character_name
	_tag.text = text + "   (view only)"
