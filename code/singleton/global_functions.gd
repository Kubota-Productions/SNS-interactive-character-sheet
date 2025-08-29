extends Node

#region player variables
var data : Array[String]
var player_name : String = ""
var names_index = 0

#endregion

#region storyteller variables
var st_data : Array[String]
var st_name : String = ""
var st_names_index = 0

#endregion


#region player

func _ready() -> void:
	var file = FileAccess.open(str("user://"+player_name+"0savedata.json"),FileAccess.READ)
	if file:
		var all_data :Array[String]
		print("LOAD DATA -> " + str(all_data));
		all_data = file.get_var()
		data = all_data
		
		
	var st_file = FileAccess.open(str("user://"+st_name+"1savedata.json"),FileAccess.READ)
	if st_file:
		var st_all_data :Array[String]
		print("LOAD DATA -> " + str(st_all_data));
		st_all_data = st_file.get_var()
		st_data = st_all_data


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

func set_player_name(name_ : String, update_data : bool = false):
	player_name = name_
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

#endregion


#region storyscreen
func st_update_data() -> void:
	var file = FileAccess.open(str("user://"+st_name+"1savedata.json"),FileAccess.READ)
	if file:
		var all_data :Array[String]
		all_data = file.get_var()
		print("UPDATE DATA -> " + str(all_data));
		st_data = all_data
		st_store_data_all()
	else:
		print("FILE INVALID");

func st_store_data_all():
			st_data.resize(300)
			print("STORE ALL DATA -> " + str(st_data));
			var file = FileAccess.open(str("user://"+st_name+"1savedata.json"),FileAccess.WRITE)
			if file:
				file.store_var(st_data)
				file.close()
				print("just_finished_editing")

func st_store_data(index : int, string : String):
	st_data.resize(max(300, index + 1))  # ensure array is big enough
	st_data[index] = string
	var file = FileAccess.open("user://"+st_name+"1savedata.json", FileAccess.WRITE)
	if file:
		file.store_var(st_data)
		file.close()
		print("just_finished_editing")

func set_st_name(name_ : String, update_data : bool = false):
	st_name = name_
	if update_data == true:
		st_update_data()

func return_st_name():
	return st_name


func new_st():
	st_data = []
	var dir = DirAccess.open("user://")
	var new_story_prefix :String = "new_story"
	if dir:
		var file_names = dir.get_files()
		var found_matching_name = true
		while found_matching_name == true:
			found_matching_name = false
			for file_name in file_names:
				if file_name.replace("user://","").replace("1savedata.json","") == str(new_story_prefix+str(st_names_index)):
					st_names_index +=1
					print(st_names_index)
					found_matching_name = true
	st_name = str(new_story_prefix+str(st_names_index))
	
#endregion
