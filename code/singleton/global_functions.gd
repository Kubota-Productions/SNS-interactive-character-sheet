extends Node

var data : Array[String]
var player_name : String = ""
var names_index = 0

func _ready() -> void:
	var file = FileAccess.open(str("user://"+player_name+"0savedata.json"),FileAccess.READ)
	if file:
		var all_data :Array[String]
		print("LOAD DATA -> " + str(all_data));
		all_data = file.get_var()
		data = all_data


func _update_data() -> void:
	var file = FileAccess.open(str("user://"+player_name+"0savedata.json"),FileAccess.READ)
	if file:
		var all_data :Array[String]
		all_data = file.get_var()
		print("UPDATE DATA -> " + str(all_data));
		data = all_data
		store_data_all()
	else:
		print("FILE INVALID");

func store_data_all():
			data.resize(300)
			print("STORE ALL DATA -> " + str(data));
			var file = FileAccess.open(str("user://"+player_name+"0savedata.json"),FileAccess.WRITE)
			if file:
				file.store_var(data)
				file.close()
				print("just_finished_editing")

func store_data(index : int, string : String):
	data.resize(max(300, index + 1))  # ensure array is big enough
	data[index] = string
	var file = FileAccess.open("user://"+player_name+"0savedata.json", FileAccess.WRITE)
	if file:
		file.store_var(data)
		file.close()
		print("just_finished_editing")

func set_player_name(name : String, update_data : bool = false):
	player_name = name
	if update_data == true:
		_update_data()

func return_player_name():
	return player_name

func new_player():
	data = []
	var dir = DirAccess.open("user://")
	var new_player_prefix :String = "new_player"
	if dir:
		var file_names = dir.get_files()
		var found_matching_name = true
		while found_matching_name == true:
			found_matching_name = false
			for file_name in file_names:
				if file_name.replace("user://","").replace("0savedata.json","") == str(new_player_prefix+str(names_index)):
					names_index +=1
					print(names_index)
					found_matching_name = true
	player_name = str(new_player_prefix+str(names_index))
	
	
