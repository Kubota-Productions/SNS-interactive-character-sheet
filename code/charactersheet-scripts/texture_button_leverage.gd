extends TextureButton
## A checkbox-style button of the character sheet (leverage, torpor, hypo, ...). Whether it is
## pressed is saved in the character data under its `index`.
##
## The buttons with index 75 to 110 used to be the cells of the inventory. The inventory is one
## InventoryGrid now (see inventory_grid.gd). If those buttons are still in the scene, the first of
## them adds the grid over them, and the grid removes them. You can delete them from the scene and
## put an InventoryGrid in their place yourself, then this script no longer has anything to do
## with the inventory.

const InventoryGrid := preload("res://code/charactersheet-scripts/inventory_grid.gd")
const Items := preload("res://code/charactersheet-scripts/inventory_items.gd")
const GRID_ADDED := &"inventory_grid_added"

@export var index: int = 1


func _ready() -> void:
	if Items.is_old_button_index(index):
		_add_inventory_grid()
		return

	# No-signal version so loading doesn't trigger a save.
	set_pressed_no_signal(GlobalFunctions.character.get_toggle(index))


func _add_inventory_grid() -> void:
	var parent := get_parent()
	if parent == null or parent.has_meta(GRID_ADDED):
		return  # one grid for all 36 buttons
	parent.set_meta(GRID_ADDED, true)

	for sibling in parent.get_children():
		if sibling.get_script() == InventoryGrid:
			return  # the scene already has a grid of its own

	var grid := InventoryGrid.new()
	grid.name = "InventoryGrid"
	parent.add_child.call_deferred(grid)  # the parent is still setting up its children


func _on_toggled(toggled_on: bool) -> void:
	if Items.is_old_button_index(index):
		return  # old inventory cell, the inventory grid looks after those
	GlobalFunctions.character.set_toggle(index, toggled_on)
