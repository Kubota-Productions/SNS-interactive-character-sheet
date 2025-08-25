extends BoxContainer

var file_name : String
var dir : DirAccess
@onready var audio_stream_player_2d: AudioStreamPlayer2D = $"AudioStreamPlayer2D"

var paused_position: float = 0.0

func _ready() -> void:	
	dir = DirAccess.open("res://assets/audiofiles/")
	if dir == null:
		push_warning("Could not open audiofiles directory")
		return
	
	dir.list_dir_begin()
	file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			var ext := file_name.get_extension().to_lower()
			if ext in ["wav"]:
				var audio_path := "res://assets/audiofiles/" + file_name
				var stream := load(audio_path)
				if stream is AudioStream:
					audio_stream_player_2d.stream = stream
					paused_position = 0.0  # first track starts clean
					return
		file_name = dir.get_next()

func _on_audioplaybutton_pressed() -> void:
	if file_name != "":
		if not audio_stream_player_2d.playing:
			var ext := file_name.get_extension().to_lower()
			if ext in ["wav"]:
				var audio_path := "res://assets/audiofiles/" + file_name
				var stream := load(audio_path)
				if stream is AudioStream:
					audio_stream_player_2d.stream = stream
					audio_stream_player_2d.play()
					if paused_position > 0.0:
						audio_stream_player_2d.seek(paused_position)

func _on_audiopausebutton_toggled(toggled_on: bool) -> void:
	if toggled_on:
		print ("pausing")
		paused_position = audio_stream_player_2d.get_playback_position()
		audio_stream_player_2d.stop()
		print("stopping at %s" % paused_position)
	else:
		audio_stream_player_2d.play(paused_position)
		print("resuming at %s" % paused_position)

func _on_audioskipbutton_pressed() -> void:
	file_name = dir.get_next()
	
	# If we reached the end, start from the beginning
	if file_name == "":
		dir.list_dir_begin()
		file_name = dir.get_next()
	
	while file_name != "": # skip invalid files
		if not dir.current_is_dir():
			var ext := file_name.get_extension().to_lower()
			if ext in ["wav"]:
				var audio_path := "res://assets/audiofiles/" + file_name
				var stream := load(audio_path)
				if stream is AudioStream:
					audio_stream_player_2d.stream = stream
					audio_stream_player_2d.play()
					paused_position = 0.0  # reset for new track
					break
		file_name = dir.get_next()
