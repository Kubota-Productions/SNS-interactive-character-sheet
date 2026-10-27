extends Node
## Autoload "GlobalFunctions": owns the currently open character sheet / storyteller screen
## and handles loading, autosaving, renaming, deleting and listing their save files.

const SAVE_SUFFIX := "_savedata"
const SAVE_EXT := ".res"  # compact binary. Use ".tres" while debugging to get readable saves.
const CHARACTER_DIR := "user://characters/"
const STORYTELLER_DIR := "user://storytellers/"
const AUTOSAVE_DELAY := 0.5  # seconds after the last edit

## The sheet / screen currently open. The main menu sets these before switching scenes.
var character: CharacterSaveData = null
var storyteller: StorytellerSaveData = null

var _character_dirty := false
var _storyteller_dirty := false
var _autosave_timer := Timer.new()


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(CHARACTER_DIR)
	DirAccess.make_dir_recursive_absolute(STORYTELLER_DIR)

	_autosave_timer.one_shot = true
	_autosave_timer.wait_time = AUTOSAVE_DELAY
	_autosave_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_autosave_timer.timeout.connect(flush)
	add_child(_autosave_timer)

	_migrate_legacy_saves()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		flush()


## Writes pending changes to disk right now. Call this before leaving a scene.
func flush() -> void:
	_autosave_timer.stop()
	if _character_dirty and character != null:
		_character_dirty = false
		_write(character, _path(CHARACTER_DIR, character.character_name))
	if _storyteller_dirty and storyteller != null:
		_storyteller_dirty = false
		_write(storyteller, _path(STORYTELLER_DIR, storyteller.storyteller_name))


#region characters
func new_character() -> void:
	var sheet := CharacterSaveData.new()
	sheet.character_name = _unique_name(CHARACTER_DIR, "new_player")
	_set_character(sheet)  # no file is written until the first edit

func load_character(character_name: String) -> bool:
	var loaded := _load(_path(CHARACTER_DIR, character_name)) as CharacterSaveData
	if loaded == null:
		push_error("Could not load character '%s'." % character_name)
		return false
	loaded.character_name = character_name  # the filename wins if someone renamed it by hand
	_set_character(loaded)
	return true

## Renames the open character (and its file). Returns the name actually in effect,
## so a LineEdit can show it (it reverts if the name was empty or already taken).
func rename_character(new_name: String) -> String:
	var final_name := _rename_file(CHARACTER_DIR, character.character_name, new_name)
	if final_name != character.character_name:
		character.character_name = final_name
		character.emit_changed()
		flush()
	return final_name

func delete_character(character_name: String) -> void:
	if character != null and character.character_name == character_name:
		_character_dirty = false  # don't let a pending autosave resurrect it
		character = null
	DirAccess.remove_absolute(_path(CHARACTER_DIR, character_name))

func list_characters() -> PackedStringArray:
	return _list(CHARACTER_DIR)

func _set_character(sheet: CharacterSaveData) -> void:
	flush()  # write the previous sheet's pending edits first
	if character != null:
		character.changed.disconnect(_on_character_changed)
	character = sheet
	character.changed.connect(_on_character_changed)

func _on_character_changed() -> void:
	_character_dirty = true
	_autosave_timer.start()  # restarts the countdown, so typing is debounced
#endregion


#region storyteller screens
func new_storyteller() -> void:
	var screen := StorytellerSaveData.new()
	screen.storyteller_name = _unique_name(STORYTELLER_DIR, "new_story")
	_set_storyteller(screen)

func load_storyteller(storyteller_name: String) -> bool:
	var loaded := _load(_path(STORYTELLER_DIR, storyteller_name)) as StorytellerSaveData
	if loaded == null:
		push_error("Could not load storyteller screen '%s'." % storyteller_name)
		return false
	loaded.storyteller_name = storyteller_name
	_set_storyteller(loaded)
	return true

func rename_storyteller(new_name: String) -> String:
	var final_name := _rename_file(STORYTELLER_DIR, storyteller.storyteller_name, new_name)
	if final_name != storyteller.storyteller_name:
		storyteller.storyteller_name = final_name
		storyteller.emit_changed()
		flush()
	return final_name

func delete_storyteller(storyteller_name: String) -> void:
	if storyteller != null and storyteller.storyteller_name == storyteller_name:
		_storyteller_dirty = false
		storyteller = null
	DirAccess.remove_absolute(_path(STORYTELLER_DIR, storyteller_name))

func list_storytellers() -> PackedStringArray:
	return _list(STORYTELLER_DIR)

func _set_storyteller(screen: StorytellerSaveData) -> void:
	flush()
	if storyteller != null:
		storyteller.changed.disconnect(_on_storyteller_changed)
	storyteller = screen
	storyteller.changed.connect(_on_storyteller_changed)

func _on_storyteller_changed() -> void:
	_storyteller_dirty = true
	_autosave_timer.start()
#endregion


#region file helpers
func _path(dir: String, save_name: String) -> String:
	return dir + save_name + SAVE_SUFFIX + SAVE_EXT

func _list(dir: String) -> PackedStringArray:
	var names := PackedStringArray()
	var suffix := SAVE_SUFFIX + SAVE_EXT
	for file_name in DirAccess.get_files_at(dir):
		if file_name.ends_with(suffix):
			names.append(file_name.trim_suffix(suffix))
	names.sort()
	return names

func _load(path: String) -> Resource:
	if not FileAccess.file_exists(path):
		return null
	# CACHE_MODE_IGNORE: always read a fresh copy from disk instead of a cached instance.
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)

func _write(resource: Resource, path: String) -> Error:
	# Save to a temp file, then rename over the real one, so a crash mid-write can't corrupt a save.
	var tmp_path := path.get_basename() + ".tmp." + path.get_extension()
	var err := ResourceSaver.save(resource, tmp_path)
	if err == OK:
		err = DirAccess.rename_absolute(tmp_path, path)
	if err != OK:
		push_error("Failed to save %s: %s" % [path, error_string(err)])
	return err

func _name_taken(dir: String, candidate: String, ignore: String = "") -> bool:
	for existing in _list(dir):
		if existing != ignore and existing.to_lower() == candidate.to_lower():
			return true
	return false

func _unique_name(dir: String, prefix: String) -> String:
	var n := 0
	while _name_taken(dir, "%s%d" % [prefix, n]):
		n += 1
	return "%s%d" % [prefix, n]

## Sanitises the new name and moves the file if it exists. Returns the name in effect afterwards.
func _rename_file(dir: String, old_name: String, new_name: String) -> String:
	var clean := new_name.strip_edges().validate_filename()
	if clean.is_empty() or clean == old_name:
		return old_name
	if _name_taken(dir, clean, old_name):
		push_warning("'%s' already exists." % clean)
		return old_name
	var old_path := _path(dir, old_name)
	if FileAccess.file_exists(old_path):
		if DirAccess.rename_absolute(old_path, _path(dir, clean)) != OK:
			return old_name
	return clean
#endregion


#region legacy migration ("<name>0savedata.json" / "<name>1savedata.json")
const LEGACY_DIR := "user://legacy_backup/"
# Old layout: toggles lived at indices 75-110 and their symbols at index + 111.
const LEGACY_TOGGLE_FIRST := 75
const LEGACY_TOGGLE_LAST := 110
const LEGACY_SYMBOL_OFFSET := 111

func _migrate_legacy_saves() -> void:
	for file_name in DirAccess.get_files_at("user://"):
		if file_name.ends_with("0savedata.json"):
			_migrate_legacy_character(file_name)
		elif file_name.ends_with("1savedata.json"):
			_migrate_legacy_storyteller(file_name)

func _read_legacy_array(file_name: String) -> Array:
	var file := FileAccess.open("user://" + file_name, FileAccess.READ)
	if file == null:
		return []
	var raw: Variant = file.get_var()
	file.close()
	if raw is Array:
		return raw
	return []

func _migrate_legacy_character(file_name: String) -> void:
	var character_name := file_name.trim_suffix("0savedata.json")
	var target := _path(CHARACTER_DIR, character_name)
	if not FileAccess.file_exists(target):
		var sheet := CharacterSaveData.new()
		sheet.character_name = character_name
		var legacy := _read_legacy_array(file_name)
		for i in legacy.size():
			var value := str(legacy[i])
			if value.is_empty():
				continue
			if value == "true" or value == "false":
				sheet.toggles[i] = (value == "true")
			elif i >= LEGACY_TOGGLE_FIRST + LEGACY_SYMBOL_OFFSET \
					and i <= LEGACY_TOGGLE_LAST + LEGACY_SYMBOL_OFFSET:
				sheet.symbols[i - LEGACY_SYMBOL_OFFSET] = value
			else:
				sheet.texts[i] = value
		var png_path := "user://%s_appearance.png" % character_name
		if FileAccess.file_exists(png_path):
			sheet.appearance_png = FileAccess.get_file_as_bytes(png_path)
		if _write(sheet, target) != OK:
			return  # leave the old file alone and retry next launch
	_archive_legacy(file_name)
	_archive_legacy("%s_appearance.png" % character_name)

func _migrate_legacy_storyteller(file_name: String) -> void:
	var storyteller_name := file_name.trim_suffix("1savedata.json")
	var target := _path(STORYTELLER_DIR, storyteller_name)
	if not FileAccess.file_exists(target):
		var screen := StorytellerSaveData.new()
		screen.storyteller_name = storyteller_name
		var legacy := _read_legacy_array(file_name)
		for i in legacy.size():
			var value := str(legacy[i])
			if not value.is_empty():
				screen.texts[i] = value
		if _write(screen, target) != OK:
			return
	_archive_legacy(file_name)

## Moves an old file into user://legacy_backup/ (nothing is deleted).
func _archive_legacy(file_name: String) -> void:
	if not FileAccess.file_exists("user://" + file_name):
		return
	DirAccess.make_dir_recursive_absolute(LEGACY_DIR)
	DirAccess.rename_absolute("user://" + file_name, LEGACY_DIR + file_name)
#endregion
