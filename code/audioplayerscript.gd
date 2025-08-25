extends TextureButton
var file_name : String
var dir : DirAccess
@onready var audio_stream_player_2d: AudioStreamPlayer2D = $"../AudioStreamPlayer2D"

var paused_position: float = 0.0
func _ready() -> void:
		
		# Only start new audio if nothing is currently playing
		if audio_stream_player_2d.playing:
			return
		$"../audiopausebutton".button_pressed = false
		dir = DirAccess.open("res://assets/audiofiles/")
		if dir == null:
			push_warning("Could not open audiofiles directory")
			return
		
		dir.list_dir_begin()
		file_name = dir.get_next()
		while file_name != "":
			if !dir.current_is_dir() and file_name.get_extension().to_lower() in ["wav", "ogg", "mp3"]:
				var audio_path := "res://assets/audiofiles/" + file_name
				var stream := load(audio_path)
				if stream is AudioStream:
					audio_stream_player_2d.stream = stream
					audio_stream_player_2d.play()  # start from beginning
					self.set_pressed(false)  # make sure toggle is off
					return # only play the first audio file found
			file_name = dir.get_next()
	

		
func _physics_process(delta: float) -> void:
	if $".".button_pressed:
		if file_name:
			if dir:
				var audio_path := "res://assets/audiofiles/" + file_name
				var stream := load(audio_path)
				if stream is AudioStream:
					audio_stream_player_2d.stream = stream
					audio_stream_player_2d.play()  # start from beginning
					self.set_pressed(false)  # make sure toggle is off
					$"../audiopausebutton".button_pressed = false
		
		
	if $"../audioskipbutton".button_pressed:
		if file_name:
			if dir:
				file_name = dir.get_next()
				var audio_path := "res://assets/audiofiles/" + file_name
				var stream := load(audio_path)
				if stream is AudioStream:
					audio_stream_player_2d.stream = stream
					audio_stream_player_2d.play()  # start from beginning
					self.set_pressed(false)  # make sure toggle is off
					$"../audiopausebutton".button_pressed = false

			
		
		

func _on_toggled(toggled_on: bool) -> void:
	if audio_stream_player_2d.playing:
		paused_position = audio_stream_player_2d.get_playback_position()
		audio_stream_player_2d.stop()
	else:
		audio_stream_player_2d.play()  
		audio_stream_player_2d.call_deferred("seek", paused_position)
		
