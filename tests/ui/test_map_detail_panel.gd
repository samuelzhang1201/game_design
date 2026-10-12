extends GutTest
## The detail column's cards (user request 2026-09-09, after Azgaar's burg
## editor): heraldry, a field grid, feature and goods glyphs, money, and a
## preview of the map around the place — for towns and the player's own
## provinces; lines for everything else and only the basics abroad.

func _panel() -> MapDetailPanel:
	var p := MapDetailPanel.create()
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
	await wait_process_frames(1)
	var realm: Dictionary = Game.data.kingdoms[Game.data.resolve_realm("player_realm")]
	var code := String(realm["capital_burg"])
	p.show_entry({"title": "x", "lines": ["y"], "ask": "?", "obj": {"kind": "burg", "code": code}})
	await wait_process_frames(1)
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
	await wait_process_frames(1)
	# The crown's OWN province (not merely any province of the realm — the
	# fog, spec 2026-09-28-missive-board-and-spies §1, reads "full" only
	# where the crown itself controls, MapManors.home_province).
	var mine := MapManors.home_province(Game.data, Game.state)
	p.show_province(mine)
	await wait_process_frames(1)
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
	await wait_process_frames(1)
	var texts := _grid_texts(p)
	assert_has(texts, "Held by")
	assert_false(texts.has("Population"), "no details abroad")
	assert_false(p.preview().visible, "no window onto foreign land")
	# The intel rows (People, Wealth, Stance) stand in place of the old
	# blanket hint, which now shows only when there is nothing at all to
	# report.
	assert_false(p.hint_label().visible, "the intel rows replace the hint")
	assert_has(texts, "People", "the fogged row instead of an exact figure")

## The card's shield wears generated arms (owner 2026-09-15): a province its
## house's, a manor its holding house's, a town its province's house's.
func test_a_card_wears_the_arms_of_its_house() -> void:
	Game.start_campaign(42)
	var p := _panel()
	await wait_process_frames(1)
	var mine := MapOwnership.provinces_of(Game.data, Game.state, Game.data.resolve_realm("player_realm"))[0]
	p.show_province(mine)
	await wait_process_frames(1)
	var house := MapObjects.house_name_of(Game.data, mine)
	assert_not_null(p.shield().texture)
	assert_same(p.shield().texture, HouseArms.texture_of_house(Game.data, Game.state, house))
	var cell: int = MapManors.manors_of_province(Game.data, mine, Game.state)[0]
	p.show_manor(cell)
	await wait_process_frames(1)
	assert_same(p.shield().texture,
		HouseArms.texture_of_house(Game.data, Game.state, MapManors.owner_of(Game.data, Game.state, cell)))
	var town := String(Game.data.provinces[mine]["capital_burg"])
	p.show_entry({"title": "x", "lines": [], "ask": "?", "obj": {"kind": "burg", "code": town}})
	await wait_process_frames(1)
	assert_same(p.shield().texture, HouseArms.texture_of_house(Game.data, Game.state, house))

## Clicking a regiment opens its painted card (owner 2026-09-15): its arms as
## icons, the kingdom's arms on the shield, no town sums or map window.
func test_a_regiment_opens_its_painted_card() -> void:
	Game.start_campaign(42)
	var p := _panel()
	await wait_process_frames(1)
	var mine := Game.data.resolve_realm("player_realm")
	var r: Dictionary = MapObjects.regiments_of(Game.data, mine, Game.state)[0]
	p.show_entry({"title": "x", "lines": [], "ask": "?", "obj": {"kind": "army", "code": String(r["regiment_code"])}})
	await wait_process_frames(1)
	assert_true(p.visible)
	assert_eq(p.title_label().text, String(r["label"]))
	assert_gt(p.stats_grid().get_child_count(), 0, "its facts read as icons")
	assert_eq(p.rows().get_child_count(), 0, "no plain lines")
	assert_false(p.preview().visible, "no window onto the map")
	assert_same(p.shield().texture, HouseArms.texture_of_kingdom(Game.data, mine))
	# Regiment review (owner 2026-09-17): its values ("4564 (0 wounded)",
	# "Hills (fortified)") are too wide for the default 4-column (2-pair)
	# grid in the fixed left column, so its card asks for 2 — one
	# icon+value pair a row.
	assert_eq(p.stats_grid().columns, 2, "one icon+value pair a row so its wide values fit")

## A broken supply line (owner 2026-10-11): the card's Line row is written in
## CardWarn, the paper's rubric red; a flowing line in the card's own ink.
func test_a_broken_supply_line_is_written_in_the_warning_ink() -> void:
	Game.start_campaign(42)
	var p := _panel()
	await wait_process_frames(1)
	var mine := Game.data.resolve_realm("player_realm")
	var code := ""
	for r: Dictionary in MapObjects.regiments_of(Game.data, mine, Game.state):
		if String(r.get("is_naval", "0")) != "1" and Game.state.regiments.has(String(r["regiment_code"])):
			code = String(r["regiment_code"])
			break
	var town := String(TownStores.realm_towns(Game.data, Game.state)[0])
	var rec := SupplyLines._new_record(town, 1000, 1)
	rec["state"] = SupplyLines.FRONT
	Game.state.supply_lines[code] = rec
	p.show_entry({"title": "x", "lines": [], "ask": "?", "obj": {"kind": "army", "code": code}})
	await wait_process_frames(1)
	var cell: Label = p.stats_grid().find_child("Stat_army_supply_line", true, false)
	assert_not_null(cell)
	assert_eq(cell.theme_type_variation, &"CardWarn")
	rec["state"] = SupplyLines.FLOWING
	p.show_entry({"title": "x", "lines": [], "ask": "?", "obj": {"kind": "army", "code": code}})
	await wait_process_frames(1)
	cell = p.stats_grid().find_child("Stat_army_supply_line", true, false)
	assert_eq(cell.theme_type_variation, &"CardValue", "a flowing line in the card's own ink")


## A courier's card flies his kingdom's arms, as his regiment's does (b0848aa;
## spec 2026-09-27-courier-core §2).
func test_a_courier_flies_his_kingdoms_arms() -> void:
	Game.start_campaign(42)
	var p := _panel()
	await wait_process_frames(1)
	var mine := Game.data.resolve_realm("player_realm")
	var code := ""
	for r: Dictionary in MapObjects.regiments_of(Game.data, mine, Game.state):
		if String(r.get("is_naval", "0")) != "1":
			code = String(r["regiment_code"])
			break
	var c := CourierSystem.dispatch(Game.data, Game.state, CourierSystem.ORDINARY, code,
		{"action_code": "ARMY_GARRISON"})
	p.show_entry({"title": "x", "lines": [], "ask": "?", "obj": {"kind": "courier", "id": int(c["id"])}})
	await wait_process_frames(1)
	assert_true(p.visible)
	assert_eq(p.title_label().text, CourierCard.title(Game.data, Game.state, int(c["id"])))
	assert_not_null(HouseArms.texture_of_kingdom(Game.data, mine), "the realm has arms to fly")
	assert_same(p.shield().texture, HouseArms.texture_of_kingdom(Game.data, mine))

func test_other_objects_keep_their_lines() -> void:
	Game.start_campaign(42)
	var p := _panel()
	await wait_process_frames(1)
	var route: String = Game.data.routes.keys()[0]
	p.show_entry({"title": "A road", "lines": ["Road", "Length: 3 km"], "ask": "?",
		"obj": {"kind": "route", "code": route}})
	await wait_process_frames(1)
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
	await wait_process_frames(1)
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
	await wait_process_frames(1)
	assert_true(p.visible)
	assert_eq(p.shown_manor(), cell)
	assert_eq(p.title_label().text, MapManors.label_of(Game.data, cell))
	# Fog (spec 2026-09-28-missive-board-and-spies §1): this manor is
	# "general" — a house's, in a realm province the crown does not
	# control — but the price is not one of the fogged figures, so it still
	# carries the exact asking price beside the BUY button that names it.
	assert_string_contains(p.stat_tooltip("manor_price"), "Asking price", "the price is an icon with its tooltip")
	var buttons := p.actions_box().get_children()
	# BUY, seizing off, and every land card's spy button (owner 2026-09-28).
	assert_eq(buttons.size(), 2, "BUY and Send a spy, seizing off")
	var buy := buttons[0] as Button
	assert_false(buy.disabled)
	assert_true(buy.text.begins_with("Buy"), "a command, in title case (ui_command_style)")
	buy.pressed.emit()
	await wait_process_frames(1)
	assert_true(MapManors.is_crowns(Game.data, Game.state, cell), "the order ran")
	assert_eq(p.stat_text("manor_owner"), "The crown", "the card redrew from the new state")
	# The purchase alone does not hand the crown the whole province (its
	# house still holds the rest), so the card stays "general" — but its
	# orders stand exactly as a full card's would: SELL is always the
	# crown's to give, and BUILD (which needs the province itself, not just
	# the manor) still offers its dropdown, disabled with the reason.
	var after: Array[String] = []
	for b in p.actions_box().get_children():
		after.append((b as Button).text.get_slice(" ", 0) if b is Button else String(b.name))
	assert_has(after, "Sell")
	assert_has(after, "BuildRow", "the buildings are one dropdown (owner 2026-09-14)")

## A spy the treasury cannot afford is disabled too (fix round 1, owner
## 2026-09-28) — the same treatment as every other card button, shown here
## on the simplest land card there is.
func test_a_towns_spy_button_is_disabled_when_the_treasury_cannot_pay() -> void:
	Game.start_campaign(42)
	Game.state.metrics["treasury"] = 0.0
	var p := _panel()
	await wait_process_frames(1)
	# A town outside the crown's controlled provinces (those are refused before the purse is asked).
	var code := ""
	var burgs := Game.data.burgs.keys()
	burgs.sort()
	for b: String in burgs:
		if not SpySystem.province_controlled(Game.data, Game.state, String(Game.data.burgs[b].get("province_code", ""))):
			code = b
			break
	assert_ne(code, "", "a town the crown does not control")
	p.show_entry({"title": "x", "lines": [], "ask": "?", "obj": {"kind": "burg", "code": code}})
	await wait_process_frames(1)
	var spy: Button = null
	for b in p.actions_box().get_children():
		if b is Button and String((b as Button).name).begins_with("SPY_SEND"):
			spy = b as Button
	assert_not_null(spy, "the town card offers a spy button")
	assert_true(spy.disabled, "the treasury cannot pay for the spy")
	assert_string_contains(spy.tooltip_text, "afford")

## The slot row (owner 2026-09-13): one box per slot; a BUILD fills one with
## the work's icon and its days, and the cross beneath it pulls it down.
func test_a_manor_card_shows_its_slots_and_a_build_fills_one() -> void:
	Game.start_campaign(42)
	Game.state.metrics["treasury"] = 100000.0
	Game.state.metrics["lord_gold"] = 100000.0
	Game.state.metrics["lord_civil"] = 100000.0
	var p := _panel()
	await wait_process_frames(1)
	var cell := -1
	for c: int in MapManors.manors_of_house(Game.data, Game.state, MapManors.crown(Game.state),
			Game.data.resolve_realm("player_realm")):
		cell = c
		break
	p.show_entry({"title": "x", "lines": [], "ask": "?", "obj": {"kind": "manor", "cell": cell}})
	await wait_process_frames(1)
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
	await wait_process_frames(1)
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
	assert_eq(hurry.text, UiPalette.command_text("HURRY %s — %dg" % [String(row["label"]).to_upper(),
		per_click * int(Game.data.bal("build_rush_gold_per_day"))]))
	assert_false(hurry.disabled)
	hurry.pressed.emit()
	await wait_process_frames(1)
	assert_eq(MapManors.work_days_left(Game.data, Game.state, cell, code),
		int(float(row["build_days"])) - per_click, "the days came off")
	assert_eq(p.slots_row().get_child_count(), slots)
	assert_false(p.build_menu_codes().has(code), "no second one offered")
	var cross: Button = p.slots_row().find_child("DEMOLISH_" + code, true, false)
	assert_not_null(cross)
	assert_false(cross.disabled)
	cross.pressed.emit()
	await wait_process_frames(1)
	assert_false(MapManors.is_building(Game.state, cell, code), "stopped")
	assert_null(p.slots_row().find_child("Slot_" + code, true, false))
	assert_true(p.build_menu_codes().has(code), "offered again")
	# A finished building fills its slot with its art, solid, not a ghost.
	assert_true(MapManors.build(Game.data, Game.state, cell, code, "test: stood"))
	p.show_manor(cell)
	await wait_process_frames(1)
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
	await wait_process_frames(1)
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
	assert_string_contains(path, "res://assets/2D/paintings/estates/", "every manor names its painting")
	assert_eq(p.painting_box().visible, UiPalette.load_art(path) != null, "shown when the art is installed")
	if p.painting_box().visible:
		# Cut to its scene (2026-09-28): a band ui_manor_painting_aspect wide
		# to 1 high, never over ui_manor_painting_max_share of the card.
		var h := p.painting_box().custom_minimum_size.y
		assert_lte(h, maxf(p.size.y * Game.data.bal("ui_manor_painting_max_share"), 72.0) + 1.0,
			"at most its share of the card")
		assert_almost_eq(h, maxf(minf(p.painting_box().size.x / Game.data.bal("ui_manor_painting_aspect"),
			p.size.y * Game.data.bal("ui_manor_painting_max_share")), 72.0), 1.0, "its scene's band")
	assert_eq(p.fields().get_child_count(), 0, "a manor has no text rows, only icons")
	# Named rows in sections (owner 2026-09-28, ui_manor_card_rows): one column.
	assert_eq(p.stats_grid().columns, 1, "a manor's facts are named rows")
	assert_not_null(p.stats_grid().get_node_or_null("Section_holding"), "grouped under their sections")
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
			# Under "Each Month" the figure alone (2026-09-28: the heading says it).
			assert_eq((row.find_child("Rate", true, false) as Label).text, UiPalette.format_int(int(units[good])))
			var icon_path := GameArt.path(GameArt.GOODS_ICONS, good)
			if icon_path != "" and ResourceLoader.exists(icon_path):
				var pic := row.get_child(0) as TextureRect
				assert_not_null(pic, "%s draws its art" % good)
				if pic != null:
					assert_eq(pic.texture.resource_path, icon_path, "%s wears its colour icon" % good)
					assert_eq(pic.modulate, Color.WHITE, "a colour icon is not tinted")

## A reported fact on a card (Task 10's look check, 2026-09-28): in the fixed
## 240 px column "≈ 9,600–18,800 (spy · Spring 5, Year 1)" wrapped over four
## lines beside a label column as wide as itself. The estimate stands alone,
## the tag under it small and in its column's colour, and the label column
## only as wide as its words.
func test_a_reported_fact_wears_a_small_tag_under_its_estimate() -> void:
	Game.start_campaign(42)
	Intel.dev_all = false
	var p := _panel()
	p.size = Vector2(240, 600)
	await wait_process_frames(1)
	var realm := Game.data.resolve_realm("player_realm")
	var cell := -1
	var ids := Game.data.manors.keys()
	ids.sort()
	for c: int in ids:
		var prov := MapManors.province_of(Game.data, c, Game.state)
		if prov != "" and MapOwnership.owner_of(Game.data, Game.state, prov) != realm:
			cell = c
			break
	var at := MapTerrain.cell_center(Game.data, Game.data.cells[cell])
	MissiveLog.add(Game.data, Game.state, SpySystem.report(Game.data, Game.state, at, 900, 0))
	p.show_entry({"title": "x", "lines": [], "ask": "?", "obj": {"kind": "manor", "cell": cell}})
	await wait_process_frames(2)
	var kids := p.fields().get_children()
	var i := kids.find(kids.filter(func(n: Node) -> bool: return n is Label and (n as Label).text == "People")[0])
	var label := kids[i] as Label
	var cell_box := kids[i + 1] as VBoxContainer
	assert_not_null(cell_box, "the estimate and its tag stand in one cell")
	if cell_box == null:
		return
	var value := cell_box.get_child(0) as Label
	var tag := cell_box.get_child(1) as Label
	assert_true(value.text.begins_with("≈") and not value.text.contains("("), "the estimate alone: " + value.text)
	assert_string_contains(tag.text, "spy")
	assert_lt(tag.get_theme_font_size("font_size"), value.get_theme_font_size("font_size"), "the tag is small")
	assert_eq(tag.get_theme_color("font_color"), MapPalette.named(Game.data, "intel_credible"))
	assert_lt(label.size.x, cell_box.size.x, "the label column is only as wide as its words")
	# one letter's facts name it once, under the first
	var tags := kids.filter(func(n: Node) -> bool: return n is VBoxContainer).size()
	assert_eq(tags, 1, "one tag for one letter's run of facts")


## A foreign manor's card (Task 10's look check, 2026-09-28): the facts read
## "—", and Send a spy must stand close by them — the FIRST order, with no
## empty section's spacing between the facts and the orders. At 2560x1600
## the spy button sat below the card's scroll fold, behind BUY and five
## empty sections' separations.
func test_a_foreign_manor_card_offers_its_spy_first_and_wastes_no_room() -> void:
	Game.start_campaign(42)
	Intel.dev_all = false
	var p := _panel()
	await wait_process_frames(1)
	var realm := Game.data.resolve_realm("player_realm")
	var cell := -1
	var ids := Game.data.manors.keys()
	ids.sort()
	for c: int in ids:
		var prov := MapManors.province_of(Game.data, c, Game.state)
		if prov != "" and MapOwnership.owner_of(Game.data, Game.state, prov) != realm \
				and String(MapManors.purchase_kind(Game.data, Game.state, c)["kind"]) != "":
			cell = c
			break
	assert_gt(cell, -1, "a foreign manor with an order besides the spy")
	p.show_entry({"title": "x", "lines": [], "ask": "?", "obj": {"kind": "manor", "cell": cell}})
	await wait_process_frames(1)
	var buttons := p.actions_box().get_children()
	assert_gt(buttons.size(), 1, "the spy and at least one other order")
	assert_true(String(buttons[0].name).begins_with("SPY_SEND"), "the spy is the first order on foreign land")
	for box: Control in [p.rates_box(), p.features_row(), p.production_box(), p.rows()]:
		assert_false(box.visible, "an empty section takes no room: " + String(box.name))
	# ...and a full card keeps its own sections and order.
	var home := MapManors.manors_of_province(Game.data, MapManors.home_province(Game.data, Game.state))
	p.show_entry({"title": "x", "lines": [], "ask": "?", "obj": {"kind": "manor", "cell": int(home[0])}})
	await wait_process_frames(1)
	assert_true(p.rates_box().visible, "a manor the crown controls shows its output")
	assert_false(String(p.actions_box().get_child(0).name).begins_with("SPY_SEND"))


## Fix round 1 finding 1: the BUY button's full label ("BUY — 1,234 gold
## from the crown's treasury") ran past two lines of the fixed 240 px left
## column (ScreenLayout.LEFT_WIDTH) and was cut off. It now reads short,
## like the BUILD button beside it, with the whole line as its tooltip.
func test_the_buy_button_fits_the_column_and_keeps_its_full_text_as_a_tooltip() -> void:
	Game.start_campaign(42)
	Game.state.metrics["treasury"] = 100000.0
	var p := _panel()
	await wait_process_frames(1)
	var realm := Game.data.resolve_realm("player_realm")
	var cell := -1
	var ids := Game.data.manors.keys()
	ids.sort()
	for c: int in ids:
		var prov := MapManors.province_of(Game.data, c, Game.state)
		if prov != "" and MapOwnership.owner_of(Game.data, Game.state, prov) != realm \
				and String(MapManors.purchase_kind(Game.data, Game.state, c)["kind"]) == "foreign":
			cell = c
			break
	assert_gt(cell, -1, "a manor the crown may buy across the border")
	p.show_entry({"title": "x", "lines": [], "ask": "?", "obj": {"kind": "manor", "cell": cell}})
	await wait_process_frames(1)
	var buy: Button = null
	for b in p.actions_box().get_children():
		if b is Button and String(b.name).begins_with("MANOR_BUY"):
			buy = b as Button
	assert_not_null(buy, "the card offers BUY")
	assert_false(buy.disabled, "the treasury can pay")
	assert_true(buy.text.begins_with("Buy"), "a command, in title case (ui_command_style)")
	assert_string_contains(buy.tooltip_text, "from the crown's treasury",
		"the full line survives as the button's tooltip")
	var font := buy.get_theme_font("font")
	var px := buy.get_theme_font_size("font_size")
	var width := font.get_string_size(buy.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	assert_lt(width, ScreenLayout.LEFT_WIDTH,
		"BUY's short text fits the fixed column on one line (%d of %d px)" % [width, ScreenLayout.LEFT_WIDTH])


## A report on the same spot as the card's subject, so Intel._latest's
## tier-3 "point" match hits a manor, province or burg query alike (distance
## 0, same province).
func _point_report(centre: Vector2) -> void:
	MissiveLog.add(Game.data, Game.state, MissiveLog.make("spy", "credible", Game.state.absolute_day(),
		MissiveLog.subject("point", "", -1, centre), "A spy report",
		[MissiveLog.span("people", "People", 9600, 18800)]))


## Fix round 1 finding 2: the fogged/reported cards' fact LABELS
## (_intel_rows' row["label"], e.g. "People"/"Tax"/"Wealth"/"Stance") are
## drawn with autowrap OFF ("only as wide as their words", Task 10's look
## check) — nothing catches a label that runs wide. This builds the
## longest-labelled cards the left column ever shows — a foreign manor,
## province and burg, each fogged and then with a spy report on top — and
## holds the whole card's minimum width under the fixed 240 px column
## (ScreenLayout.LEFT_WIDTH); the panel sits in the column with nothing
## between it and the column's own edge, so this is the real invariant, not
## an approximation of it.
func test_the_longest_fogged_and_reported_fact_labels_never_widen_the_left_column() -> void:
	Game.start_campaign(42)
	Intel.dev_all = false
	var realm := Game.data.resolve_realm("player_realm")
	var p := _panel()
	await wait_process_frames(1)

	# a foreign manor
	var manor_cell := -1
	var manor_ids := Game.data.manors.keys()
	manor_ids.sort()
	for c: int in manor_ids:
		var prov := MapManors.province_of(Game.data, c, Game.state)
		if prov != "" and MapOwnership.owner_of(Game.data, Game.state, prov) != realm:
			manor_cell = c
			break
	assert_gt(manor_cell, -1, "a foreign manor")
	p.show_entry({"title": "x", "lines": [], "ask": "?", "obj": {"kind": "manor", "cell": manor_cell}})
	await wait_process_frames(1)
	assert_lte(p.get_combined_minimum_size().x, ScreenLayout.LEFT_WIDTH,
		"a fogged foreign manor's card fits the column (%d of %d px)" %
		[p.get_combined_minimum_size().x, ScreenLayout.LEFT_WIDTH])
	_point_report(MapTerrain.cell_center(Game.data, Game.data.cells.get(manor_cell, {"vertex_ids": PackedInt32Array()})))
	p.show_entry({"title": "x", "lines": [], "ask": "?", "obj": {"kind": "manor", "cell": manor_cell}})
	await wait_process_frames(1)
	assert_lte(p.get_combined_minimum_size().x, ScreenLayout.LEFT_WIDTH,
		"a reported foreign manor's card fits the column (%d of %d px)" %
		[p.get_combined_minimum_size().x, ScreenLayout.LEFT_WIDTH])

	# a foreign province
	var foreign_prov := ""
	var prov_codes := Game.data.provinces.keys()
	prov_codes.sort()
	for code: String in prov_codes:
		if MapOwnership.owner_of(Game.data, Game.state, code) != realm:
			foreign_prov = code
			break
	assert_ne(foreign_prov, "", "a foreign province")
	var prov_row: Dictionary = Game.data.provinces[foreign_prov]
	var prov_centre := Vector2(float(prov_row.get("center_x", 0)), float(prov_row.get("center_y", 0)))
	p.show_province(foreign_prov)
	await wait_process_frames(1)
	assert_lte(p.get_combined_minimum_size().x, ScreenLayout.LEFT_WIDTH,
		"a fogged foreign province's card fits the column (%d of %d px)" %
		[p.get_combined_minimum_size().x, ScreenLayout.LEFT_WIDTH])
	_point_report(prov_centre)
	p.show_province(foreign_prov)
	await wait_process_frames(1)
	assert_lte(p.get_combined_minimum_size().x, ScreenLayout.LEFT_WIDTH,
		"a reported foreign province's card fits the column (%d of %d px)" %
		[p.get_combined_minimum_size().x, ScreenLayout.LEFT_WIDTH])

	# a foreign burg
	var foreign_burg := ""
	var burg_codes := Game.data.burgs.keys()
	burg_codes.sort()
	for code: String in burg_codes:
		var b: Dictionary = Game.data.burgs[code]
		if MapOwnership.owner_of(Game.data, Game.state, String(b["province_code"])) != realm:
			foreign_burg = code
			break
	assert_ne(foreign_burg, "", "a foreign town")
	var burg_row: Dictionary = Game.data.burgs[foreign_burg]
	var burg_centre := Vector2(float(burg_row["x"]), float(burg_row["y"]))
	p.show_entry({"title": "x", "lines": [], "ask": "?", "obj": {"kind": "burg", "code": foreign_burg}})
	await wait_process_frames(1)
	assert_lte(p.get_combined_minimum_size().x, ScreenLayout.LEFT_WIDTH,
		"a fogged foreign town's card fits the column (%d of %d px)" %
		[p.get_combined_minimum_size().x, ScreenLayout.LEFT_WIDTH])
	_point_report(burg_centre)
	p.show_entry({"title": "x", "lines": [], "ask": "?", "obj": {"kind": "burg", "code": foreign_burg}})
	await wait_process_frames(1)
	assert_lte(p.get_combined_minimum_size().x, ScreenLayout.LEFT_WIDTH,
		"a reported foreign town's card fits the column (%d of %d px)" %
		[p.get_combined_minimum_size().x, ScreenLayout.LEFT_WIDTH])

	# the kingdom card (CountryPanel), a foreign kingdom with the longest
	# words the fog ever shows ("many thousands", stance, court)
	var country := CountryPanel.create()
	add_child_autofree(country)
	var foreign_kingdom := ""
	var kingdom_codes := Game.data.kingdoms.keys()
	kingdom_codes.sort()
	for code: String in kingdom_codes:
		if code != realm:
			foreign_kingdom = code
			break
	assert_ne(foreign_kingdom, "", "a foreign kingdom")
	country.show_country(foreign_kingdom)
	await wait_process_frames(1)
	assert_lte(country.get_combined_minimum_size().x, ScreenLayout.LEFT_WIDTH,
		"the kingdom card fits the column (%d of %d px)" %
		[country.get_combined_minimum_size().x, ScreenLayout.LEFT_WIDTH])


## Ruling 18 N1: the fogged manor card's output row is named for its chief
## good ("<Good> a month"), and the row's label column never wraps — so the
## pack's LONGEST good, with a wide reported span under it, must still fit
## the fixed left column.
func test_the_longest_chief_good_row_fits_the_left_column() -> void:
	Game.start_campaign(42)
	Intel.dev_all = false
	var realm := Game.data.resolve_realm("player_realm")
	var longest := ""
	for g: Dictionary in Game.data.world_table("economy", "goods").values():
		if String(g.get("label", "")).length() > longest.length():
			longest = String(g["label"])
	var cell := -1
	var ids := Game.data.manors.keys()
	ids.sort()
	for c: int in ids:
		var prov := MapManors.province_of(Game.data, c, Game.state)
		if prov != "" and MapOwnership.owner_of(Game.data, Game.state, prov) != realm:
			cell = c
			break
	var card := MapObjects.manor_card(Game.data, Game.state, cell)
	var found := false
	for row: Dictionary in card["intel"]:
		if String(row["label"]).ends_with(" a month") or String(row["label"]) == "Output":
			row["label"] = "%s a month" % longest
			row["text"] = "≈ 10,000–20,000"
			row["tag"] = "spy · Spring 30, Year 1"
			row["column"] = "rumour"
			found = true
	assert_true(found, "the card has an output row")
	var p := _panel()
	await wait_process_frames(1)
	p.show_card(card)
	await wait_process_frames(1)
	assert_lte(p.get_combined_minimum_size().x, ScreenLayout.LEFT_WIDTH,
		"'%s a month' fits the column (%d of %d px)" % [longest, p.get_combined_minimum_size().x,
		ScreenLayout.LEFT_WIDTH])

## An idle building (LEDGER M5: its inputs went unpaid) says so in its slot:
## the art dimmed, an "idle" word under it, and why in the tooltip.
func test_an_idle_building_says_so_in_its_slot() -> void:
	Game.start_campaign(42)
	var p := _panel()
	await wait_process_frames(1)
	var cell := -1
	for c: int in MapManors.manors_of_house(Game.data, Game.state, MapManors.crown(Game.state),
			Game.data.resolve_realm("player_realm")):
		if not (ManorEconomy.line_of(Game.data, Game.state, c, Game.state.tick)["units"] as Dictionary).has("iron"):
			cell = c
			break
	assert_true(MapManors.build(Game.data, Game.state, cell, "smithy", "test: a forge"))
	p.show_manor(cell)
	await wait_process_frames(1)
	var working: Control = p.slots_row().find_child("Slot_smithy", true, false)
	assert_not_null(working)
	assert_null(p.slots_row().find_child("Idle", true, false), "a working forge is not idle")
	Game.state.idle_buildings[str(cell)] = ["smithy"]
	p.show_manor(cell)
	await wait_process_frames(1)
	var slot: Control = p.slots_row().find_child("Slot_smithy", true, false)
	assert_not_null(slot)
	assert_string_contains(slot.tooltip_text, "idle: no iron")
	var word: Label = p.slots_row().find_child("Idle", true, false)
	assert_not_null(word, "an idle word under the slot")
	var icon: ResourceIcon = null
	for n: Node in slot.find_children("*", "", true, false):
		if n is ResourceIcon:
			icon = n
	assert_not_null(icon)
	assert_almost_eq(icon.modulate.a, Game.data.bal("ui_slot_idle_alpha"), 0.001, "its art dimmed by the balance row")
