extends Node
## The dice roll history: a small "Roll history" button in the bottom right corner of the screen
## that opens a panel listing every roll, oldest at the top and newest at the bottom.
## dice_roller.gd adds one of these to itself. The rolls themselves are kept by DiceSync
## (/root/Lobby/DiceSync); this script only shows them.

const THEME_PATH := "res://assets/imagefiles/UI/main_menu.tres"
const PANEL_SIZE := Vector2(400, 460)

var _sync = null
var _toggle: Button = null
var _panel: PanelContainer = null
var _log: RichTextLabel = null
var _hide_box: CheckBox = null

var _unread: int = 0
var _out_of_date: bool = true  # the list has to be drawn again before it is next shown


func _ready() -> void:
	_sync = get_node_or_null("/root/Lobby/DiceSync")
	if _sync == null:
		push_warning("Dice history: /root/Lobby/DiceSync is missing, so no history can be shown.")
		return

	var layer := CanvasLayer.new()
	layer.name = "DiceHistoryLayer"
	layer.layer = 15
	add_child(layer)

	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE  # only the button and the panel take clicks
	if ResourceLoader.exists(THEME_PATH):
		root.theme = load(THEME_PATH) as Theme
	layer.add_child(root)

	_toggle = Button.new()
	_toggle.text = "Roll history"
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_toggle.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_toggle.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toggle.offset_right = -8.0
	_toggle.offset_bottom = -8.0
	_toggle.pressed.connect(_on_toggle_pressed)
	root.add_child(_toggle)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_right = -8.0
	_panel.offset_bottom = -56.0  # just above the button
	_panel.custom_minimum_size = PANEL_SIZE
	_panel.visible = false
	root.add_child(_panel)

	var column := VBoxContainer.new()
	_panel.add_child(column)

	var title := Label.new()
	title.text = "Dice roll history"
	column.add_child(title)

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true  # stays at the newest roll
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_log)

	_hide_box = CheckBox.new()
	_hide_box.text = "Hide my rolls from the players"
	_hide_box.focus_mode = Control.FOCUS_NONE
	_hide_box.button_pressed = _sync.hide_gm_rolls
	_hide_box.toggled.connect(_on_hide_toggled)
	column.add_child(_hide_box)

	_sync.entry_added.connect(_on_entry_added)
	_sync.history_reset.connect(_on_history_reset)


func _on_toggle_pressed() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		_unread = 0
		_hide_box.visible = _sync.is_host()  # only the GM can hide rolls
		_hide_box.set_pressed_no_signal(_sync.hide_gm_rolls)
		if _out_of_date:
			_redraw()
	_update_toggle_text()


func _on_hide_toggled(pressed: bool) -> void:
	_sync.hide_gm_rolls = pressed


func _on_entry_added(entry: Dictionary) -> void:
	if _panel.visible:
		_log.append_text(_format(entry) + "\n")
	else:
		_unread += 1
		_out_of_date = true
		_update_toggle_text()


func _on_history_reset() -> void:
	_out_of_date = true
	if _panel.visible:
		_redraw()


func _update_toggle_text() -> void:
	_toggle.text = "Roll history" if _unread == 0 else "Roll history (%d new)" % _unread


## Draws the whole history again.
func _redraw() -> void:
	_out_of_date = false
	_log.clear()
	for entry in _sync.entries():
		_log.append_text(_format(entry) + "\n")


func _format(entry: Dictionary) -> String:
	var who := str(entry.get("who", "?")).replace("[", "[lb]")  # so a name can't be read as formatting
	var note := ""
	if entry.get("h", false):
		note = "  [color=gray](hidden from players)[/color]"
	return "[color=gray]%s[/color]  %s  d%d  [b]%d[/b]%s" % [
		_time_text(int(entry.get("t", 0))),
		who,
		int(entry.get("d", 0)),
		int(entry.get("r", 0)),
		note,
	]


## "11-23 14:32" in the time zone of this computer.
func _time_text(unix_time: int) -> String:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	var date := Time.get_datetime_dict_from_unix_time(unix_time + bias * 60)
	return "%02d-%02d %02d:%02d" % [date["month"], date["day"], date["hour"], date["minute"]]
