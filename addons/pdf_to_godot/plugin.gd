@tool
extends EditorPlugin

var _window: ConfirmationDialog
var _pdf: LineEdit
var _output: LineEdit
var _config: LineEdit
var _scale: SpinBox
var _dpi: SpinBox
var _picker: EditorFileDialog
var _message: AcceptDialog
var _thread: Thread
var _busy := false
var _last_result: Dictionary = {}

func _enter_tree() -> void:
	_window = ConfirmationDialog.new()
	_window.title = "Import PDF as a new scene"
	_window.ok_button_text = "Create Scene"
	_window.min_size = Vector2i(660, 360)
	var form := VBoxContainer.new()
	_window.add_child(form)
	_pdf = _path_row(form, "PDF", "Choose a PDF…", EditorFileDialog.ACCESS_FILESYSTEM, "*.pdf; PDF documents")
	_output = _path_row(form, "New output folder", "res://imports/my_sheet", EditorFileDialog.ACCESS_RESOURCES, "")
	_output.text = "res://imports/my_sheet"
	_config = _path_row(form, "Field overrides (optional)", "JSON file, or leave empty", EditorFileDialog.ACCESS_FILESYSTEM, "*.json; Field overrides")
	_scale = _number_row(form, "Scene pixels per PDF point", 0.1, 10.0, 0.1, 1.2)
	_dpi = _number_row(form, "Artwork DPI", 36, 600, 1, 144)
	var help := Label.new()
	help.text = "Each import creates a new folder containing sheet.tscn and its artwork.\nConversion runs inside Godot using the PDF engine bundled with this addon."
	form.add_child(help)
	_window.confirmed.connect(_start)
	get_editor_interface().get_base_control().add_child(_window)
	_message = AcceptDialog.new()
	_message.title = "PDF to Godot"
	_message.min_size = Vector2i(600, 200)
	get_editor_interface().get_base_control().add_child(_message)
	add_tool_menu_item("Import PDF as Scene…", func(): _window.popup_centered())
	set_process(false)

func _path_row(form: VBoxContainer, label: String, placeholder: String, access: int, filter: String) -> LineEdit:
	var caption := Label.new()
	caption.text = label
	form.add_child(caption)
	var row := HBoxContainer.new()
	form.add_child(row)
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	var browse := Button.new()
	browse.text = "Browse…"
	row.add_child(browse)
	browse.pressed.connect(func():
		if is_instance_valid(_picker):
			_picker.queue_free()
		_picker = EditorFileDialog.new()
		_picker.access = access
		_picker.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE if edit == _output else EditorFileDialog.FILE_MODE_OPEN_FILE
		_picker.title = "Choose a NEW folder name" if edit == _output else "Choose " + label
		if filter != "":
			_picker.add_filter(filter)
		_picker.file_selected.connect(func(path): edit.text = path)
		get_editor_interface().get_base_control().add_child(_picker)
		_picker.popup_centered_ratio(0.7))
	return edit

func _number_row(form: VBoxContainer, label: String, minimum: float, maximum: float, step: float, value: float) -> SpinBox:
	var row := HBoxContainer.new()
	var caption := Label.new()
	caption.text = label
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(caption)
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = value
	row.add_child(spin)
	form.add_child(row)
	return spin

func _show_message(message: String) -> void:
	var lines := message.split("\n")
	if lines.size() > 12:
		print(message)
		_message.dialog_text = "\n".join(lines.slice(0, 10)) + "\n…\nOpen Godot's Output panel for the complete import report."
	else:
		_message.dialog_text = message
	_message.popup_centered()

func _ensure_backend() -> String:
	var platform := {"Linux": "linux", "Windows": "windows", "macOS": "macos"}.get(OS.get_name(), "unsupported")
	var architecture := "x86_64" if OS.has_feature("x86_64") else ("aarch64" if OS.has_feature("arm64") else "unsupported")
	var library := {"Linux": "libpdfium.so", "Windows": "pdfium.dll", "macOS": "libpdfium.dylib"}.get(OS.get_name(), "unsupported")
	var engine := "res://addons/pdf_to_godot/native/" + str(platform) + "-" + architecture + "/" + str(library)
	if not FileAccess.file_exists(engine):
		return "This addon package does not contain the PDF engine for %s %s. Install the matching native plugin package." % [OS.get_name(), architecture]
	if not ClassDB.class_exists("PdfToGodotImporter"):
		var status := GDExtensionManager.load_extension("res://addons/pdf_to_godot/native/pdf_to_godot.gdextension")
		if status not in [GDExtensionManager.LOAD_STATUS_OK, GDExtensionManager.LOAD_STATUS_ALREADY_LOADED]:
			return "Godot could not load the bundled PDF engine. Restart the editor after updating the plugin."
	if not ClassDB.class_exists("PdfToGodotImporter"):
		return "The bundled native plugin did not register its PDF importer."
	return ""

func _start() -> void:
	if _busy:
		_show_message("A PDF import is already in progress.")
		return
	var backend_error := _ensure_backend()
	if backend_error != "":
		_show_message(backend_error)
		return
	if not _output.text.begins_with("res://"):
		_show_message("Choose a fresh output folder inside this project (res://…).")
		return
	var output := ProjectSettings.globalize_path(_output.text)
	if DirAccess.dir_exists_absolute(output) or FileAccess.file_exists(output):
		_show_message("That destination exists. Choose another name to preserve your edits.")
		return
	var error := DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	if error != OK:
		_show_message("Could not create output parent directory: " + error_string(error))
		return
	var configuration := "{}"
	if _config.text != "":
		if not FileAccess.file_exists(_config.text):
			_show_message("The selected field overrides file does not exist.")
			return
		configuration = FileAccess.get_file_as_string(_config.text)
	_thread = Thread.new()
	error = _thread.start(_convert.bind(_pdf.text, output, configuration, _scale.value, int(_dpi.value), _output.text.path_join("sheet.tscn")))
	if error != OK:
		_thread = null
		_show_message("Could not start PDF import: " + error_string(error))
		return
	_busy = true
	set_process(true)
	_show_message("Importing PDF… You can continue using the editor.\nThe new scene will open when artwork import finishes.")

func _convert(pdf: String, output: String, configuration: String, scale: float, dpi: int, scene: String) -> Dictionary:
	var backend: RefCounted = ClassDB.instantiate("PdfToGodotImporter")
	var result: Dictionary = backend.call("convert", pdf, output, ProjectSettings.globalize_path("res://"), configuration, scale, dpi)
	result["scene"] = scene
	return result

func _process(_delta: float) -> void:
	if _thread == null or _thread.is_alive():
		return
	var result: Dictionary = _thread.wait_to_finish()
	_last_result = result
	_thread = null
	set_process(false)
	if not result.ok:
		_busy = false
		_show_message("Import failed:\n" + result.message)
		return
	var filesystem := get_editor_interface().get_resource_filesystem()
	var pending := {}
	for file in DirAccess.get_files_at(result.scene.get_base_dir()):
		if file.ends_with(".png"):
			pending[result.scene.get_base_dir().path_join(file)] = true
	var imported := func(paths: PackedStringArray):
		for path in paths:
			pending.erase(path)
	filesystem.resources_reimported.connect(imported)
	filesystem.scan()
	# is_scanning can become false before queued texture imports begin. Wait for
	# completion of every new PNG instead of opening a scene with missing textures.
	var deadline := Time.get_ticks_msec() + 60000
	while not pending.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.1).timeout
	filesystem.resources_reimported.disconnect(imported)
	if not pending.is_empty():
		_busy = false
		_show_message("Scene created, but artwork import did not finish within 60 seconds.\nOpen it after Godot finishes scanning:\n" + result.scene)
		return
	_message.hide()
	get_editor_interface().open_scene_from_path(result.scene)
	_busy = false
	_show_message(result.message)

func _exit_tree() -> void:
	remove_tool_menu_item("Import PDF as Scene…")
	if _thread != null:
		_thread.wait_to_finish()
	_window.queue_free()
	_message.queue_free()
	if is_instance_valid(_picker):
		_picker.queue_free()
