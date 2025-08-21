extends Node

var data : Array[String]
var player_name : String = "charactersheet"

func _ready() -> void:
	var file = FileAccess.open(str("user://"+player_name+"0savedata.json"),FileAccess.READ)
	if file:
		var all_data :Array[String]
		all_data = file.get_var()
		data = all_data

func _update_data() -> void:
	var file = FileAccess.open(str("user://"+player_name+"0savedata.json"),FileAccess.READ)
	if file:
		var all_data :Array[String]
		all_data = file.get_var()
		data = all_data
		store_data_all()

func store_data_all():
			data.resize(100)
			var file = FileAccess.open(str("user://"+player_name+"0savedata.json"),FileAccess.WRITE)
			if file:
				file.store_var(data)
				file.close()
				print("just_finished_editing")

func store_data(index : int, string : String):
			data.resize(100)
			data[index] = string
			var file = FileAccess.open(str("user://"+player_name+"0savedata.json"),FileAccess.WRITE)
			if file:
				file.store_var(data)
				file.close()
				print("just_finished_editing")

func set_player_name(name : String):
	player_name = name
	_update_data()

func return_player_name():
	return player_name
	
	
