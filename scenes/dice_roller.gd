extends Control

const DICE_SIDES: Dictionary[String, int] = {
	"d2": 2,
	"d4": 4,
	"d6": 6,
	"d8": 8,
	"d10": 10,
	"d12": 12,
	"d20": 20,
}

const DICE_BUTTONS: Dictionary[String, String] = {
	"d2": "D2Button",
	"d4": "D4Button",
	"d6": "D6Button",
	"d8": "D8Button",
	"d10": "D10Button",
	"d12": "D12Button",
	"d20": "D20Button",
}

@export var dice_image_root: String = "res://assets/imagefiles/dice/"

@onready var image_rect: TextureRect = $DiceResult
@onready var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	
	if not image_rect:
		push_warning("DiceResult TextureRect not found! Check the node path.")
		return
	
	for die in DICE_SIDES.keys():
		var btn_name: String = DICE_BUTTONS.get(die, "")
		if btn_name == "":
			push_warning("No button mapping for die: %s" % die)
			continue
		
		var btn: Button = $VBoxContainer.get_node_or_null(btn_name) as Button
		if btn:
			var die_name: String = String(die)
			btn.pressed.connect(func(): roll_dice(die_name))
		else:
			push_warning("Button node not found: %s" % btn_name)

func roll_dice(die: String) -> void:
	var sides: int = DICE_SIDES.get(die, 0)
	if sides <= 0:
		push_warning("Unknown die: %s" % die)
		return

	var result: int = rng.randi_range(1, sides)

	# Build path for your naming scheme
	var img_path: String = "%s%s/%s-%d.png" % [dice_image_root, die, die, result]
	
	if not ResourceLoader.exists(img_path):
		push_warning("Image file not found: %s" % img_path)
		return
	
	var tex: Texture2D = load(img_path)
	if tex:
		image_rect.texture = tex
	else:
		push_warning("Failed to load image: %s" % img_path)

	print("Rolled %s: %d" % [die, result])
