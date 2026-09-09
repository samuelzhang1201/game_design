extends GutTest
## The game's own political colours (user ruling 2026-09-09): the render is
## terrain only, so kingdoms are painted from data/political_palette.csv.

var data: DataRepository

func before_each() -> void:
	data = DataRepository.load_all("res://data")

func test_every_kingdom_has_a_distinct_colour() -> void:
	var seen: Dictionary = {}
	for code: String in data.kingdoms:
		var c := MapPalette.color_of(data, code)
		assert_ne(c, MapPalette.FALLBACK, "%s is coloured from the palette" % code)
		assert_false(seen.has(c.to_html()), "%s shares a colour with %s" % [code, seen.get(c.to_html(), "")])
		seen[c.to_html()] = code

func test_bound_realms_take_their_slots_colour() -> void:
	for slot: String in data.realm_bindings:
		if data.palette.has(slot):
			assert_eq(MapPalette.color_of(data, data.resolve_realm(slot)), MapPalette.named(data, slot),
				"%s wears the %s colour" % [data.resolve_realm(slot), slot])

func test_unbound_kingdoms_take_other_colours_in_state_order() -> void:
	var n := 0
	var codes: Array = data.kingdoms.keys()
	codes.sort_custom(func(a: String, b: String) -> bool:
		return int(data.kingdoms[a]["state_id"]) < int(data.kingdoms[b]["state_id"]))
	for code: String in codes:
		if MapPalette.slot_of(data, code) != "":
			continue
		n += 1
		assert_eq(MapPalette.color_of(data, code), MapPalette.named(data, "other_%d" % n))
	assert_gt(n, 0, "some kingdom is unbound")

func test_line_colours_are_named() -> void:
	for key in ["state_border", "province_line", "hover_border"]:
		assert_ne(MapPalette.named(data, key), MapPalette.FALLBACK, key)
	assert_eq(MapPalette.named(data, "no_such_key"), MapPalette.FALLBACK)
	assert_eq(MapPalette.color_of(data, "no_such_kingdom"), MapPalette.FALLBACK)
