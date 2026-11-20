
extends TextureRect

@export_file("*.pdf") var pdf_path: String = ""
@export_range(0.1, 4.0, 0.1) var render_scale: float = 2.0

var pdf_document
var current_page: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	if not pdf_path.is_empty():
		load_pdf(pdf_path)


func load_pdf(path: String) -> void:
	pdf_document = PDFDocument.new()

	var error = pdf_document.load_from_file(path)

	if error != OK:
		push_error("Failed to load PDF: " + str(error))
		return

	current_page = 0
	display_page()


func display_page() -> void:
	var page = pdf_document.get_page(current_page)

	if page == null:
		return

	var img: Image = page.render_to_image(render_scale)

	if img == null or img.is_empty():
		return

	texture = ImageTexture.create_from_image(img)

	print("Displaying PDF page: ", current_page + 1)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:

			# Only respond when clicking inside this TextureRect
			var mouse_position = get_global_mouse_position()

			if get_global_rect().has_point(mouse_position):
				next_page()
				get_viewport().set_input_as_handled()


func next_page() -> void:
	if pdf_document == null:
		return

	current_page += 1

	# Return to page one at the end
	if pdf_document.get_page(current_page) == null:
		current_page = 0

	display_page()
