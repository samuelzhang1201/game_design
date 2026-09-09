extends GutTest
## The detail column's cards (user request 2026-09-09, after Azgaar's burg
## editor): heraldry, a field grid, feature and goods glyphs, money, and a
## preview of the map around the place — for towns and the player's own
## provinces; lines for everything else and only the basics abroad.

func _panel() -> MapDetailPanel:
	var p := MapDetailPanel.new()
	add_child_autofree(p)
	p.ask_enabled = true
	return p

func _grid_texts(p: MapDetailPanel) -> Array[String]:
	var out: Array[String] = []
	for l in p.fields().get_children():
		out.append((l as Label).text)
	return out

func test_a_town_gets_a_card() -> void:
	Game.start_campaign(42)
	var p := _panel()
	await wait_frames(1)
	var realm: Dictionary = Game.data.kingdoms[Game.data.resolve_realm("player_realm")]
	var code := String(realm["capital_burg"])
	p.show_entry({"title": "x", "lines": ["y"], "ask": "?", "obj": {"kind": "burg", "code": code}})
	await wait_frames(1)
	assert_true(p.visible)
	assert_eq(p.title_label().text, String(Game.data.burgs[code]["label"]))
	assert_true(p.subtitle_label().visible, "the province and kingdom line")
	var texts := _grid_texts(p)
	assert_has(texts, "Population")
	assert_has(texts, "Culture")
	assert_gt(p.features_row().get_child_count(), 1, "feature glyphs after their label")
	assert_gt(p.production_box().get_child_count(), 1, "goods rows after their label")
	assert_true(p.preview().visible, "a window onto the map")
	assert_not_null(p.preview().texture)
	assert_true(p.ask_button().visible)
	assert_eq(p.rows().get_child_count(), 0, "no plain lines on a card")

func test_own_province_gets_a_card_and_foreign_land_the_basics() -> void:
	Game.start_campaign(42)
	var p := _panel()
	await wait_frames(1)
	var mine := MapOwnership.provinces_of(Game.data, Game.state, Game.data.resolve_realm("player_realm"))[0]
	p.show_province(mine)
	await wait_frames(1)
	assert_true(p.visible)
	assert_has(_grid_texts(p), "Held by")
	assert_has(_grid_texts(p), "Towns")
	assert_true(p.preview().visible)
	assert_false(p.hint_label().visible)
	var foreign := ""
	for code: String in Game.data.provinces:
		if String(Game.data.provinces[code]["kingdom_code"]) != Game.data.resolve_realm("player_realm"):
			foreign = code
			break
	p.show_province(foreign)
	await wait_frames(1)
	var texts := _grid_texts(p)
	assert_has(texts, "Held by")
	assert_false(texts.has("Population"), "no details abroad")
	assert_false(p.preview().visible, "no window onto foreign land")
	assert_true(p.hint_label().visible)
	assert_string_contains(p.hint_label().text, "Little more is known")

func test_other_objects_keep_their_lines() -> void:
	Game.start_campaign(42)
	var p := _panel()
	await wait_frames(1)
	var route: String = Game.data.routes.keys()[0]
	p.show_entry({"title": "A road", "lines": ["Road", "Length: 3 km"], "ask": "?",
		"obj": {"kind": "route", "code": route}})
	await wait_frames(1)
	assert_eq(p.title_label().text, "A road")
	assert_eq(p.rows().get_child_count(), 2)
	assert_eq(p.fields().get_child_count(), 0)
	assert_false(p.preview().visible)
	p.show_entry({})
	assert_false(p.visible)
