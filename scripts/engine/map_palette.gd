class_name MapPalette
extends RefCounted
## The game's own political colours (user ruling 2026-09-09: the render is
## terrain only, so every kingdom's colour is ours to choose). Read from
## data/political_palette.csv: a realm slot's kingdom takes the slot's
## colour, every other kingdom takes other_1, other_2, ... in state order,
## and the line colours (state_border, province_line, hover_border) are
## named rows. Engine-pure.

const FALLBACK := Color(0.6, 0.6, 0.6)

## A named palette entry (state_border, hover_border, ...), or FALLBACK.
static func named(data: DataRepository, key: String) -> Color:
	var hex := String(data.palette.get(key, ""))
	return Color(hex) if hex != "" else FALLBACK

## The colour of a kingdom: its realm slot's colour when it is bound to one,
## else the next other_N in state order, else the pack's own colour.
static func color_of(data: DataRepository, kingdom_code: String) -> Color:
	var slot := slot_of(data, kingdom_code)
	if slot != "" and data.palette.has(slot):
		return named(data, slot)
	var n := 0
	for code: String in _in_state_order(data):
		if slot_of(data, code) != "":
			continue
		n += 1
		if code == kingdom_code:
			var key := "other_%d" % n
			if data.palette.has(key):
				return named(data, key)
			break
	var hex := String((data.kingdoms.get(kingdom_code, {}) as Dictionary).get("color", ""))
	return Color(hex) if hex != "" else FALLBACK

## The realm slot a kingdom is bound to ("" when none).
static func slot_of(data: DataRepository, kingdom_code: String) -> String:
	for slot: String in data.realm_bindings:
		if String(data.realm_bindings[slot]) == kingdom_code:
			return slot
	return ""

static func _in_state_order(data: DataRepository) -> Array:
	var codes: Array = data.kingdoms.keys()
	codes.sort_custom(func(a: String, b: String) -> bool:
		return int(data.kingdoms[a]["state_id"]) < int(data.kingdoms[b]["state_id"]))
	return codes
