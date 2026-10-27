class_name SettingsMenu
extends Control
## The one settings screen for the whole game.
## Open or close it from anywhere with: SettingsMenu.toggle(get_tree())

const SCENE_PATH := "res://scenes/settings.tscn"  # loaded at runtime: preloading it here would be a cyclic reference

static var _instance: SettingsMenu = null

## Set by toggle() before the menu enters the tree. The main menu hides the button.
var show_back_to_menu := true

var previous_window_size: Vector2i = Vector2i(1152, 648) # default fallback

@onready var ui_volume_slider: HSlider = %UIVolume
@onready var back_to_menu_button: Button = get_node_or_null("%BackToMenuButton")


## Opens the settings menu, or closes it if it's already open.
static func toggle(tree: SceneTree, with_back_button: bool = true) -> void:
	if is_instance_valid(_instance):
		_instance.queue_free()
		return

	var menu := (load(SCENE_PATH) as PackedScene).instantiate() as SettingsMenu
	menu.show_back_to_menu = with_back_button

	# Own CanvasLayer so the sheet's Camera2D pan/zoom can't move or scale the menu.
	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.add_child(menu)
	menu.tree_exited.connect(func():
		if is_instance_valid(layer):
			layer.queue_free()
	)
	tree.root.add_child(layer)
	_instance = menu


func _ready() -> void:
	previous_window_size = DisplayServer.window_get_size()

	if back_to_menu_button:
		back_to_menu_button.visible = show_back_to_menu

	ui_volume_slider.min_value = 0.0
	ui_volume_slider.max_value = 1.0
	ui_volume_slider.step = 0.01

	# This scene is re-created every time the menu opens, so start from the bus's real volume.
	var bus := AudioServer.get_bus_index(UISounds.BUS)
	if bus != -1:
		ui_volume_slider.set_value_no_signal(db_to_linear(AudioServer.get_bus_volume_db(bus)))
	else:
		push_warning("No '%s' audio bus found. Add it in the Audio tab." % UISounds.BUS)

	ui_volume_slider.value_changed.connect(_on_ui_volume_changed)
	ui_volume_slider.drag_ended.connect(_on_ui_volume_drag_ended)


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


#region UI volume
func _on_ui_volume_changed(value: float) -> void:
	var bus := AudioServer.get_bus_index(UISounds.BUS)
	if bus != -1:
		AudioServer.set_bus_volume_db(bus, linear_to_db(value))


func _on_ui_volume_drag_ended(_value_changed: bool) -> void:
	UISounds.play_click()  # lets the player hear the new level when they let go
#endregion


#region signals connected in settings.tscn
func _on_volume_value_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(0, value)


func _on_mute_toggled(toggled_on: bool) -> void:
	AudioServer.set_bus_mute(0, toggled_on)


func _on_resolutions_item_selected(index: int) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

	match index:
		0:
			DisplayServer.window_set_size(Vector2i(2560, 1440))
		1:
			DisplayServer.window_set_size(Vector2i(1920, 1080))
		2:
			DisplayServer.window_set_size(Vector2i(1366, 768))
		3:
			DisplayServer.window_set_size(Vector2i(1280, 720))
		4:
			DisplayServer.window_set_size(Vector2i(1920, 1200))
		5:
			DisplayServer.window_set_size(Vector2i(1680, 1050))
		6:
			DisplayServer.window_set_size(Vector2i(1440, 900))
		7:
			DisplayServer.window_set_size(Vector2i(1280, 800))
		8:
			DisplayServer.window_set_size(Vector2i(1024, 768))
		9:
			DisplayServer.window_set_size(Vector2i(800, 600))
		10:
			DisplayServer.window_set_size(Vector2i(640, 480))

func _on_fullscreen_toggled(toggled_on: bool) -> void:
	if toggled_on:
		# Save window size before going fullscreen
		previous_window_size = DisplayServer.window_get_size()
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(previous_window_size)

func _on_graphics_item_selected(_index: int) -> void:
	pass # Replace with function body.

func _on_exit_button_pressed() -> void:
	queue_free()

func _on_back_to_menu_button_pressed() -> void:
	GlobalFunctions.flush()  # make sure the sheet's last edits are written first
	queue_free()
	get_tree().change_scene_to_file("res://scenes/game_root.tscn")
#endregion
