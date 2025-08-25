extends BoxContainer

@onready var audio_stream_player_2d: AudioStreamPlayer2D = $"AudioStreamPlayer2D"

var audio_files: Array[String] = [
	"res://assets/audiofiles/frozen feels extended.wav",
	"res://assets/audiofiles/Terminal 2.wav",
] # list all your audio files here
var current_index: int = 0
var paused_position: float = 0.0

func _ready() -> void:
	if audio_files.size() > 0:
		var stream := load(audio_files[current_index])
		if stream is AudioStream:
			audio_stream_player_2d.stream = stream
			paused_position = 0.0

func _on_audioplaybutton_pressed() -> void:
	if audio_files.size() == 0:
		return
	
	if not audio_stream_player_2d.playing:
		var stream := load(audio_files[current_index])
		if stream is AudioStream:
			audio_stream_player_2d.stream = stream
			if paused_position > 0.0:
				audio_stream_player_2d.play(paused_position)
			else:
				audio_stream_player_2d.play()

func _on_audiopausebutton_toggled(toggled_on: bool) -> void:
	if toggled_on and audio_stream_player_2d.playing:
		paused_position = audio_stream_player_2d.get_playback_position()
		audio_stream_player_2d.stop()
	else:
		audio_stream_player_2d.play(paused_position)

func _on_audioskipbutton_pressed() -> void:
	if audio_files.size() == 0:
		return
	
	# Move to next track
	current_index += 1
	if current_index >= audio_files.size():
		current_index = 0 # loop back to first track
	
	var stream := load(audio_files[current_index])
	if stream is AudioStream:
		audio_stream_player_2d.stream = stream
		audio_stream_player_2d.play()
		paused_position = 0.0
