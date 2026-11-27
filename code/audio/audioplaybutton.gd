extends TextureButton

@onready var audio_stream_player_2d: AudioStreamPlayer2D = $"../AudioStreamPlayer2D"

func _ready() -> void:
	pressed.connect(_on_pressed)

func _on_pressed() -> void:
	# Do nothing if audio is already playing
	if audio_stream_player_2d.playing:
		return
	
	var dir := DirAccess.open("res://assets/audiofiles/")
	if dir == null:
		push_warning("Could not open audiofiles directory")
		return
	
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if !dir.current_is_dir() and file_name.get_extension().to_lower() in ["wav", "ogg", "mp3"]:
			var audio_path := "res://assets/audiofiles/" + file_name
			var stream := load(audio_path)
			if stream is AudioStream:
				audio_stream_player_2d.stream = stream
				audio_stream_player_2d.play()
				return # only play the first audio file found
		file_name = dir.get_next()
	
	push_warning("No audio files found in audiofiles folder")
