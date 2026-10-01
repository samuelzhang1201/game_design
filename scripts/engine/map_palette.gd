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
	var hex := String(data.palette.get(table_key(data, data.palette, key), ""))
	return Color(hex) if hex != "" else FALLBACK

## THE WAR TABLE (owner 2026-10-01): the map is printed on a vellum sheet, so
## its marks wear paper ink — while balance ui_war_table is on, a palette row
## `<key>_table` stands in for `<key>` when one is authored. Data only.
static func war_table(data: DataRepository) -> bool:
	return data != null and data.balance.has("ui_war_table") and data.bal("ui_war_table") > 0.0

static func table_key(data: DataRepository, table: Dictionary, key: String) -> String:
	if war_table(data) and table.has(key + "_table"):
		return key + "_table"
	return key

## A kingdom's colour cannot change while a pack is loaded — it is read from
## realm_bindings, the palette and the pack's own kingdoms, all load-time data
## — but resolving one sorts the kingdom list and rescans the bindings once per
## kingdom, and the map asks for a colour once per terrain mark per frame
## (~11k marks on the beria pack). Memoised per repository, so a pack swap in
## the same process cannot be served a stale colour.
static var _color_cache: Dictionary = {}

## A house's colour on the MANORS layer (MANOR_SYSTEM.md §6): a hue drawn
## from the family name, so every house has a fixed colour with nothing
## authored, at the saturation and value balance.csv sets. The crown does
## not come through here — it wears its realm's colour.
static func house_color(data: DataRepository, family: String) -> Color:
	var hue := float(absi(family.hash()) % 360) / 360.0
	return Color.from_hsv(hue, data.bal("map_manor_house_sat"), data.bal("map_manor_house_val"))

static func forget_colors() -> void:
	_color_cache.clear()

## The colour of a kingdom: its realm slot's colour when it is bound to one,
## else the next other_N in state order, else the pack's own colour.
static func color_of(data: DataRepository, kingdom_code: String) -> Color:
	var key := "%d:%s" % [data.get_instance_id(), kingdom_code]
	if _color_cache.has(key):
		return _color_cache[key]
	var c := _resolve_color(data, kingdom_code)
	_color_cache[key] = c
	return c

static func _resolve_color(data: DataRepository, kingdom_code: String) -> Color:
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
