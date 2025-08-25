extends TextureButton

@onready var audio_stream_player_2d: AudioStreamPlayer2D = $"../AudioStreamPlayer2D"

var paused: bool = false

func _ready() -> void:
	self.toggle_mode = true
	toggled.connect(_on_toggled)


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

func _on_toggled(toggled_on: bool) -> void:
	var playback := audio_stream_player_2d.get_stream_playback()
	if playback == null:
		# No audio loaded, revert button
		self.set_pressed(false)
		return
	
	if playback.is_playing():
		if toggled_on:
			# Pause: stop playback without resetting position
			playback.stop()
		else:
			# Resume playback from the paused position
			playback.play()
	else:
		# Audio isn't playing at all, revert button
		self.set_pressed(false)
