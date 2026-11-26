extends RefCounted
## What an inventory is made of, and helpers to check and build it. Only static functions, there is
## nothing to instance.
##
## The inventory is a 6 x 6 grid. Its cells are numbered 0 to 35, left to right and then top to
## bottom (cell = row * 6 + column). It holds a list of items, and every item is a small dictionary:
##
##     {
##         "symbol": "★",              the symbol shown in each of its cells
##         "name":   "Combat knife",   may be empty
##         "note":   "Sharp. Ask the GM about the sheath.",   may be empty
##         "cells":  [0, 1, 7],        the cells it covers, lowest first. Cells are never shared.
##     }
##
## CharacterSaveData keeps the list in its `inventory` field, the live view the GM has of a player's
## sheet sends the same list, and inventory_grid.gd draws it.

const COLUMNS := 6
const ROWS := 6
const CELL_COUNT := COLUMNS * ROWS

const MAX_NAME_LENGTH := 40
const MAX_NOTE_LENGTH := 500
const MAX_SYMBOL_LENGTH := 4

## The inventory buttons of the old sheet had these `index` numbers (75 to 110, one per cell).
## They are only looked at to turn old saves into items.
const OLD_FIRST_INDEX := 75
const OLD_LAST_INDEX := OLD_FIRST_INDEX + CELL_COUNT - 1

## The symbols a new item is given, in this order: the first one that no item has yet.
const SYMBOLS: Array[String] = [
	"★", "☆", "✦", "✧", "✩", "✱", "✫", "✯", "●", "○", "◍", "◌",
	"◐", "◑", "◒", "◓", "◔", "◕", "◉", "☐", "☒", "▲", "△", "▼", "▽",
	"◆", "◇", "◈", "◊", "■", "□", "▣", "▥", "☾", "❅", "↔", "∞", "∑",
	"≤", "≥", "∆", "∇", "π", "Ω", "√", "±", "÷", "×", "≈", "≠", "✣",
]


static func column_of(cell: int) -> int:
	return cell % COLUMNS


@warning_ignore("integer_division")
static func row_of(cell: int) -> int:
	return cell / COLUMNS


## The cells that share an edge with this one.
static func neighbours(cell: int) -> Array[int]:
	var out: Array[int] = []
	var column := column_of(cell)
	var row := row_of(cell)
	if column > 0:
		out.append(cell - 1)
	if column < COLUMNS - 1:
		out.append(cell + 1)
	if row > 0:
		out.append(cell - COLUMNS)
	if row < ROWS - 1:
		out.append(cell + COLUMNS)
	return out


## True for the `index` of a button of the old inventory.
static func is_old_button_index(index) -> bool:
	return typeof(index) == TYPE_INT and index >= OLD_FIRST_INDEX and index <= OLD_LAST_INDEX


## The first symbol that is not in `used` ("" if every symbol is taken, which can't happen: there are
## more symbols than cells).
static func free_symbol(used: Array) -> String:
	for symbol in SYMBOLS:
		if not used.has(symbol):
			return symbol
	return ""


static func new_item(symbol: String, cells: Array) -> Dictionary:
	var sorted_cells := cells.duplicate()
	sorted_cells.sort()
	return {"symbol": symbol, "name": "", "note": "", "cells": sorted_cells}


## Turns anything (a saved list, something that came over the network) into a proper list of items:
## cells that don't exist or that another item has are dropped, an item with no cells is dropped,
## texts are cut to their length limits, and an item with no usable symbol is given a free one.
## Always returns a new list, never the one it was given.
static func clean_items(raw) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if typeof(raw) != TYPE_ARRAY:
		return out

	var taken := {}  # cell -> true
	for entry in raw:
		if out.size() >= CELL_COUNT:
			break
		if typeof(entry) != TYPE_DICTIONARY:
			continue

		var cells: Array = []
		var raw_cells = entry.get("cells")
		if typeof(raw_cells) == TYPE_ARRAY or typeof(raw_cells) == TYPE_PACKED_INT32_ARRAY:
			for cell in raw_cells:
				if typeof(cell) == TYPE_INT and cell >= 0 and cell < CELL_COUNT \
						and not taken.has(cell) and not cells.has(cell):
					cells.append(cell)
		if cells.is_empty():
			continue
		for cell in cells:
			taken[cell] = true
		cells.sort()

		var symbol = entry.get("symbol")
		var item_name = entry.get("name")
		var note = entry.get("note")
		out.append({
			"symbol": symbol if typeof(symbol) == TYPE_STRING and symbol.length() <= MAX_SYMBOL_LENGTH else "",
			"name": String(item_name).replace("\n", " ").left(MAX_NAME_LENGTH) if typeof(item_name) == TYPE_STRING else "",
			"note": String(note).left(MAX_NOTE_LENGTH) if typeof(note) == TYPE_STRING else "",
			"cells": cells,
		})

	var used: Array = []
	for item in out:
		if item["symbol"] != "":
			used.append(item["symbol"])
	for item in out:
		if item["symbol"] == "":
			item["symbol"] = free_symbol(used)
			used.append(item["symbol"])
	return out


## Builds items from an inventory saved by the old sheet, where every cell was a button (the
## dictionaries are the old `toggles` and `symbols`, keyed by the buttons' index numbers).
## Cells that touch and have the same symbol become one item. An item whose symbol is missing, or
## that an earlier item already has, is given a new one.
static func items_from_old_cells(toggles: Dictionary, symbols: Dictionary) -> Array[Dictionary]:
	var filled: Array[bool] = []
	var cell_symbols: Array[String] = []
	for cell in CELL_COUNT:
		var index := OLD_FIRST_INDEX + cell
		filled.append(bool(toggles.get(index, false)))
		cell_symbols.append(String(symbols.get(index, "")) if filled[cell] else "")

	var groups: Array = []  # each: {"cells": Array, "symbol": String}
	var seen: Array[bool] = []
	seen.resize(CELL_COUNT)
	for first in CELL_COUNT:
		if not filled[first] or seen[first]:
			continue
		var cells: Array = []
		var queue: Array[int] = [first]
		seen[first] = true
		while not queue.is_empty():
			var cell: int = queue.pop_back()
			cells.append(cell)
			for neighbour in neighbours(cell):
				if filled[neighbour] and not seen[neighbour] and cell_symbols[neighbour] == cell_symbols[first]:
					seen[neighbour] = true
					queue.append(neighbour)
		groups.append({"cells": cells, "symbol": cell_symbols[first]})

	var used: Array = []
	for group in groups:
		var symbol: String = group["symbol"]
		if symbol in SYMBOLS and not used.has(symbol):
			used.append(symbol)
		else:
			group["symbol"] = ""
	for group in groups:
		if group["symbol"] == "":
			group["symbol"] = free_symbol(used)
			used.append(group["symbol"])

	var items: Array = []
	for group in groups:
		items.append(new_item(group["symbol"], group["cells"]))
	return clean_items(items)
