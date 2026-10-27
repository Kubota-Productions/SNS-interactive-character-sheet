extends Node
## Autoload "UISounds" (scene: scenes/ui_sounds.tscn).
## Gives every BaseButton in the game the same sounds and a hover/press animation.
## Nothing needs to be added to individual buttons or scenes.

## Audio bus the sounds play on (create it in the Audio tab). If it doesn't exist,
## Godot falls back to Master.
const BUS := &"UI"

## Put a button in one of these groups (Node dock > Groups) to opt out.
const GROUP_SILENT := &"ui_silent"      # no hover or click sound
const GROUP_NO_ANIM := &"ui_no_anim"    # no scale animation

const _META_BASE_SCALE := &"_ui_base_scale"
const _META_TWEEN := &"_ui_tween"

@export var click_sound: AudioStream
## Optional. Leave empty for no hover sound.
@export var hover_sound: AudioStream

@export_group("Animation")
@export_range(1.0, 1.3, 0.01) var hover_scale := 1.06
@export_range(0.5, 1.0, 0.01) var press_scale := 0.94
@export_range(0.01, 0.5, 0.01, "suffix:s") var anim_time := 0.08

var _click_player: AudioStreamPlayer
var _hover_player: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # keep working if the game is ever paused
	_click_player = _make_player(click_sound)
	_hover_player = _make_player(hover_sound)
	# Autoloads are ready before the main scene exists, so this catches every button.
	get_tree().node_added.connect(_on_node_added)


func _make_player(stream: AudioStream) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = BUS
	player.max_polyphony = 4  # rapid clicks overlap instead of cutting each other off
	add_child(player)
	return player


## Also callable from anywhere for non-button feedback, e.g. UISounds.play_click().
func play_click() -> void:
	_play(_click_player)

func play_hover() -> void:
	_play(_hover_player)

func _play(player: AudioStreamPlayer) -> void:
	if player.stream != null:
		player.play()


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_register(node as BaseButton)


func _register(button: BaseButton) -> void:
	if button.has_meta(_META_BASE_SCALE):
		return  # already wired (node was removed and re-added)
	# Remember the scale authored in the scene so animations are relative to it.
	button.set_meta(_META_BASE_SCALE, button.scale)
	button.mouse_entered.connect(_on_mouse_entered.bind(button))
	button.mouse_exited.connect(_on_mouse_exited.bind(button))
	button.button_down.connect(_on_button_down.bind(button))
	button.button_up.connect(_on_button_up.bind(button))


func _on_mouse_entered(button: BaseButton) -> void:
	if button.disabled:
		return
	if not button.is_in_group(GROUP_SILENT):
		play_hover()
	_animate(button, hover_scale)


func _on_mouse_exited(button: BaseButton) -> void:
	_animate(button, 1.0)


func _on_button_down(button: BaseButton) -> void:
	if not button.is_in_group(GROUP_SILENT):
		play_click()
	_animate(button, press_scale)


func _on_button_up(button: BaseButton) -> void:
	_animate(button, hover_scale if button.is_hovered() else 1.0)


func _animate(button: BaseButton, factor: float) -> void:
	if button.is_in_group(GROUP_NO_ANIM):
		return
	if button.has_meta(_META_TWEEN):
		var old: Tween = button.get_meta(_META_TWEEN)
		old.kill()  # stop the previous animation so they don't fight
	var base: Vector2 = button.get_meta(_META_BASE_SCALE)
	button.pivot_offset = button.size / 2.0  # scale from the centre
	var tween := button.create_tween()  # tied to the button, dies with it
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", base * factor, anim_time)
	button.set_meta(_META_TWEEN, tween)
