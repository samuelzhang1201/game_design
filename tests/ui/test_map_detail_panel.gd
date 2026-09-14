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
	assert_not_null(p.preview().mesh, "drawn from the terrain mesh, not a picture")
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

## A manor gets a card with its orders (MANOR_SYSTEM.md §3): a BUY button
## for another house's manor, which runs the order through Game and redraws
## the card as the crown's, with SELL and BUILD buttons in its place.
func test_a_manor_card_buys_the_manor_from_its_button() -> void:
	Game.start_campaign(42)
	Game.state.metrics["treasury"] = 100000.0
	# A manor the lord may buy (owner 2026-09-14): another house's, in a
	# province bordering the crown's own, paid from the lord's purse.
	Game.state.metrics["lord_gold"] = 100000.0
	Game.state.metrics["lord_civil"] = 100000.0
	var p := _panel()
	await wait_frames(1)
	var realm := Game.data.resolve_realm("player_realm")
	var cell := -1
	for province: String in MapOwnership.provinces_of(Game.data, Game.state, realm):
		for c: int in MapManors.manors_of_province(Game.data, province):
			if not MapManors.is_crowns(Game.data, Game.state, c) \
					and String(MapManors.purchase_kind(Game.data, Game.state, c)["kind"]) == "domestic":
				cell = c
				break
		if cell >= 0:
			break
	p.show_entry({"title": "x", "lines": [], "ask": "?", "obj": {"kind": "manor", "cell": cell}})
	await wait_frames(1)
	assert_true(p.visible)
	assert_eq(p.shown_manor(), cell)
	assert_eq(p.title_label().text, MapManors.label_of(Game.data, cell))
	assert_string_contains(p.stat_tooltip("manor_price"), "Asking price", "the price is an icon with its tooltip")
	var buttons := p.actions_box().get_children()
	assert_eq(buttons.size(), 1, "BUY only, seizing off")
	var buy := buttons[0] as Button
	assert_false(buy.disabled)
	assert_true(buy.text.begins_with("BUY"))
	buy.pressed.emit()
	await wait_frames(1)
	assert_true(MapManors.is_crowns(Game.data, Game.state, cell), "the order ran")
	assert_eq(p.stat_text("manor_owner"), "The crown", "the card redrew from the new state")
	var after: Array[String] = []
	for b in p.actions_box().get_children():
		after.append((b as Button).text.get_slice(" ", 0) if b is Button else String(b.name))
	assert_has(after, "SELL")
	assert_has(after, "BuildRow", "the buildings are one dropdown (owner 2026-09-14)")

## The slot row (owner 2026-09-13): one box per slot; a BUILD fills one with
## the work's icon and its days, and the cross beneath it pulls it down.
func test_a_manor_card_shows_its_slots_and_a_build_fills_one() -> void:
	Game.start_campaign(42)
	Game.state.metrics["treasury"] = 100000.0
	Game.state.metrics["lord_gold"] = 100000.0
	Game.state.metrics["lord_civil"] = 100000.0
	var p := _panel()
	await wait_frames(1)
	var cell := -1
	for c: int in MapManors.manors_of_house(Game.data, Game.state, MapManors.crown(Game.state),
			Game.data.resolve_realm("player_realm")):
		cell = c
		break
	p.show_entry({"title": "x", "lines": [], "ask": "?", "obj": {"kind": "manor", "cell": cell}})
	await wait_frames(1)
	var slots := MapManors.slots_of(Game.data, cell)
	assert_eq(p.slots_row().get_child_count(), slots, "one box per slot")
	assert_not_null(p.slots_row().find_child("Slot_empty_0", true, false), "all empty")
	assert_null(p.slots_row().find_child("DEMOLISH_mill", true, false))
	# The buildings are ONE dropdown (owner 2026-09-14): pick the first one the
	# manor may raise now, and BUILD it.
	assert_not_null(p.build_menu(), "a build dropdown")
	var code := ""
	for i in p.build_menu().item_count:
		if not p.build_menu().is_item_disabled(i):
			code = String(p.build_menu_codes()[i])
			break
	assert_ne(code, "", "something can be built on the crown's manor")
	var row: Dictionary = Game.data.manor_buildings[code]
	assert_true(p.select_build(code))
	assert_true(p.build_menu().get_item_text(p.build_menu().selected).ends_with("d"), "the days are on the entry")
	assert_string_contains(p.build_menu().get_item_tooltip(p.build_menu().selected), String(row["label"]),
		"the entry says what the building yields")
	assert_false(p.build_button().disabled)
	p.build_button().pressed.emit()
	await wait_frames(1)
	assert_true(MapManors.is_building(Game.state, cell, code), "the order ran")
	var ghost: Control = p.slots_row().find_child("Slot_" + code, true, false)
	assert_not_null(ghost, "the slot took the work")
	var ghost_style := ghost.get_theme_stylebox("panel") as StyleBoxFlat
	assert_not_null(ghost_style)
	assert_lt(ghost_style.bg_color.a, 0.5, "a work is a see-through box")
	assert_eq(ghost_style.border_width_left, 0, "its edge is the drawn dashes, not a solid border")
	var days: Label = p.slots_row().find_child("Days", true, false)
	assert_not_null(days, "a work shows its days")
	assert_eq(days.text, "%dd" % int(float(row["build_days"])))
	# Gold hurries the masons (spec 2026-09-14 §5): one HURRY button per work.
	var hurry: Button = p.actions_box().find_child("MANOR_RUSH_" + code, true, false)
	assert_not_null(hurry, "a work in progress offers to be hurried")
	var per_click := int(Game.data.bal("manor_rush_days_per_click"))
	assert_eq(hurry.text, "HURRY %s — %dg" % [String(row["label"]).to_upper(),
		per_click * int(Game.data.bal("build_rush_gold_per_day"))])
	assert_false(hurry.disabled)
	hurry.pressed.emit()
	await wait_frames(1)
	assert_eq(MapManors.work_days_left(Game.state, cell, code),
		int(float(row["build_days"])) - per_click, "the days came off")
	assert_eq(p.slots_row().get_child_count(), slots)
	assert_false(p.build_menu_codes().has(code), "no second one offered")
	var cross: Button = p.slots_row().find_child("DEMOLISH_" + code, true, false)
	assert_not_null(cross)
	assert_false(cross.disabled)
	cross.pressed.emit()
	await wait_frames(1)
	assert_false(MapManors.is_building(Game.state, cell, code), "stopped")
	assert_null(p.slots_row().find_child("Slot_" + code, true, false))
	assert_true(p.build_menu_codes().has(code), "offered again")
	# A finished building fills its slot with its art, solid, not a ghost.
	assert_true(MapManors.build(Game.data, Game.state, cell, code, "test: stood"))
	p.show_manor(cell)
	await wait_frames(1)
	var done: Control = p.slots_row().find_child("Slot_" + code, true, false)
	assert_not_null(done)
	assert_null(done.find_child("Days", true, false), "no days on a standing building")
	var icon: ResourceIcon = done.find_child("*", true, false) as ResourceIcon
	if icon == null:
		for n in done.find_children("*", "", true, false):
			if n is ResourceIcon:
				icon = n
				break
	assert_not_null(icon, "the building's icon stands in its slot")
	assert_eq(icon.modulate.a, 1.0, "solid, not a ghost")

## The manor card's face (owner 2026-09-14): the estate's painting pinned over
## the card at a third of its height (when its file is installed), the facts
## as icons with a short value and a full tooltip, and the output a month
## good by good — the same line the month's settlement reads.
func test_a_manor_card_shows_its_painting_its_facts_as_icons_and_its_output_rates() -> void:
	Game.start_campaign(42)
	var p := _panel()
	p.size = Vector2(240, 600)
	await wait_frames(1)
	var cell := -1
	for c: int in MapManors.manors_of_house(Game.data, Game.state, MapManors.crown(Game.state),
			Game.data.resolve_realm("player_realm")):
		cell = c
		break
	assert_gt(cell, -1)
	p.show_entry({"title": "x", "lines": [], "ask": "?", "obj": {"kind": "manor", "cell": cell}})
	await wait_process_frames(2)
	var card := MapObjects.manor_card(Game.data, Game.state, cell)
	var path := String(card["painting"])
	assert_string_contains(path, "res://assets/manors/paint/", "every manor names its painting")
	assert_eq(p.painting_box().visible, UiPalette.load_art(path) != null, "shown when the art is installed")
	if p.painting_box().visible:
		assert_almost_eq(p.painting_box().custom_minimum_size.y, maxf(p.size.y / 3.0, 72.0), 1.0,
			"a third of the card")
	assert_eq(p.fields().get_child_count(), 0, "a manor has no text rows, only icons")
	for key in ["manor_owner", "manor_province", "manor_people", "manor_tax", "manor_focus",
			"manor_defence", "manor_slots", "manor_value", "manor_price"]:
		assert_ne(p.stat_text(key), "", key)
		assert_ne(p.stat_tooltip(key), "", "%s explains itself" % key)
	assert_string_contains(p.stat_tooltip("manor_tax"), "gold a month")
	var line := ManorEconomy.line_of(Game.data, Game.state, cell, Game.state.tick)
	var units: Dictionary = line["units"]
	assert_false(units.is_empty(), "the crown's manor makes something")
	for good: String in units:
		var row := p.rates_box().find_child("Rate_" + good, true, false)
		assert_not_null(row, "%s has its rate" % good)
		if row != null:
			assert_eq((row.find_child("Rate", true, false) as Label).text, "+%d / mo" % int(units[good]))
			var icon_path := String(Game.data.goods_icons.get(good, ""))
			if icon_path != "" and ResourceLoader.exists(icon_path):
				var pic := row.get_child(0) as TextureRect
				assert_not_null(pic, "%s draws its art" % good)
				if pic != null:
					assert_eq(pic.texture.resource_path, icon_path, "%s wears its colour icon" % good)
					assert_eq(pic.modulate, Color.WHITE, "a colour icon is not tinted")
