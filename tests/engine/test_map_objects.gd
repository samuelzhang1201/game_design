extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## MapObjects: what lies under a map point (pin > line > land > water), the
## zoom-based LOD rule for town pins, and the text each info card shows.
## Engine-pure: a hand-built repository and 4x4 bitmaps for the unit cases,
## the real Beria pack for the integration cases.

var real: DataRepository

func before_all() -> void:
	real = SuiteData.repo()
	assert_not_null(real, DataRepository.last_error)

## A 4x4 world: state 6 / province 72 / biome 6 on the left half, water right.
## Capital "cap" at (0.5, 0.5), village "vil" at (1.5, 2.5) with 300 people,
## road "rd" from cap to vil, trail "tr" starting ON the road at (1, 1.5),
## marker "inn" exactly on the village.
func _tiny() -> DataRepository:
	var repo := DataRepository.new()
	repo.balance = {"map_lod_town_scale": 0.5, "map_lod_village_scale": 1.0,
		"map_lod_marker_scale": 0.5, "map_lod_town_pop": 5000.0,
		"map_pick_radius_px": 6.0, "map_line_pick_px": 4.0,
		"map_show_markers": 0.0}
	repo.map_info = {"distance_unit": "km", "distance_scale": "2", "width": "4", "height": "4"}
	repo.kingdoms = {"k": {"kingdom_code": "k", "state_id": "6", "label": "Kingdom", "capital_burg": "cap",
		"neighbor_codes": "", "population": "9000", "center_x": "0", "center_y": "0"}}
	repo.provinces = {"p": {"province_code": "p", "label": "Province", "kingdom_code": "k",
		"capital_burg": "cap", "province_id": "72"}}
	repo.burgs = {
		"cap": {"burg_code": "cap", "label": "Capital", "province_code": "p", "kingdom_code": "k",
			"population": "8000", "is_capital": "1", "is_port": "1", "x": "0.5", "y": "0.5",
			"type": "Naval", "features": "walls|citadel"},
		"vil": {"burg_code": "vil", "label": "Village", "province_code": "p", "kingdom_code": "k",
			"population": "300", "is_capital": "0", "is_port": "0", "x": "1.5", "y": "2.5",
			"type": "Generic", "features": ""},
	}
	var road := {"route_code": "rd", "label": "Old Road", "group": "roads", "from_burg": "cap",
		"to_burg": "vil", "length": "2.2", "points": "0.5 0.5|1.5 2.5"}
	road["polyline"] = MapGeometry.parse_points(String(road["points"]))
	road["bbox"] = MapGeometry.bounds(road["polyline"])
	var trail := {"route_code": "tr", "label": "Trail to Village", "group": "trails", "from_burg": "",
		"to_burg": "", "length": "2", "points": "1 1.5|3 1.5"}
	trail["polyline"] = MapGeometry.parse_points(String(trail["points"]))
	trail["bbox"] = MapGeometry.bounds(trail["polyline"])
	repo.routes = {"rd": road, "tr": trail}
	var river := {"river_code": "rv", "label": "Silver", "type": "River", "length": "3",
		"kingdom_codes": "k", "points": "0 3.5|3 3.5"}
	river["polyline"] = MapGeometry.parse_points(String(river["points"]))
	river["bbox"] = MapGeometry.bounds(river["polyline"])
	repo.rivers = {"rv": river}
	repo.markers = {"inn": {"marker_code": "inn", "label": "The Inn", "type": "inns",
		"x": "1.5", "y": "2.5", "legend": "A warm hearth."}}
	repo.biomes = {6: {"biome_id": "6", "label": "Forest", "color": "", "habitability": "50"}}
	repo.realm_bindings = {"player_realm": "k"}
	return repo

func test_lod_rule_from_balance() -> void:
	var repo := _tiny()
	assert_eq(MapObjects.min_burg_pop_for_scale(repo, 0.3), MapObjects.CAPITALS_ONLY)
	assert_eq(MapObjects.min_burg_pop_for_scale(repo, 0.5), 5000)
	assert_eq(MapObjects.min_burg_pop_for_scale(repo, 1.0), 0)

func test_burg_visible_respects_capitals_and_population() -> void:
	var repo := _tiny()
	assert_true(MapObjects.burg_visible(repo.burgs["cap"], MapObjects.CAPITALS_ONLY))
	assert_false(MapObjects.burg_visible(repo.burgs["vil"], MapObjects.CAPITALS_ONLY))
	assert_false(MapObjects.burg_visible(repo.burgs["vil"], 5000))
	assert_true(MapObjects.burg_visible(repo.burgs["vil"], 0))

func test_label_of_each_kind() -> void:
	var repo := _tiny()
	assert_eq(MapObjects.label_of(repo, {"kind": "burg", "code": "vil"}), "Village")
	assert_eq(MapObjects.label_of(repo, {"kind": "route", "code": "rd"}), "Old Road")
	assert_eq(MapObjects.label_of(repo, {"kind": "marker", "code": "inn"}), "The Inn")
	assert_eq(MapObjects.label_of(repo, {"kind": "water"}), "")

# --- the province panel (user request 2026-09-09) ----------------------------

func _player_realm() -> String:
	return Game.data.resolve_realm("player_realm")

func _own_province() -> String:
	return MapOwnership.provinces_of(Game.data, Game.state, _player_realm())[0]

func _foreign_province() -> String:
	for code: String in Game.data.provinces:
		if String(Game.data.provinces[code]["kingdom_code"]) != _player_realm():
			return code
	return ""

func test_house_of_uses_the_binding_then_the_capital_town() -> void:
	Game.start_campaign(42)
	assert_false(Game.data.house_bindings.is_empty(), "the pack binds houses to land")
	var bound: String = Game.data.house_bindings.keys()[0]
	assert_eq(MapObjects.house_of(Game.data, bound),
		"House " + String(Game.data.house_bindings[bound]))
	var unbound := _foreign_province()
	var cap: Dictionary = Game.data.burgs[String(Game.data.provinces[unbound]["capital_burg"])]
	assert_eq(MapObjects.house_of(Game.data, unbound), "House " + String(cap["label"]),
		"an unbound province is held by the house of its seat")

# --- info cards after Azgaar's burg editor (user request 2026-09-09) --------

func test_burg_card_carries_the_towns_facts_and_goods() -> void:
	Game.start_campaign(42)
	var realm: Dictionary = Game.data.kingdoms[_player_realm()]
	var code := String(realm["capital_burg"])
	var card := MapObjects.burg_card(Game.data, Game.state, code)
	assert_eq(String(card["kind"]), "burg")
	assert_eq(String(card["title"]), String(Game.data.burgs[code]["label"]))
	assert_string_contains(String(card["subtitle"]), String(realm["label"]))
	var labels: Array = []
	for f in card["fields"]:
		labels.append(String(f[0]))
	for want in ["Group", "Type", "Culture", "Population"]:
		assert_has(labels, want)
	assert_true(card["features"].size() > 0, "a capital has walls or a citadel")
	for f in card["features"]:
		assert_true(Game.data.resource_icons.has(String(f)), "%s has a glyph" % f)
	assert_true(card["production"].size() > 0, "the capital makes something")
	assert_gt(float(card["treasury"]), 0.0)
	assert_eq(card["center"], Vector2(float(Game.data.burgs[code]["x"]), float(Game.data.burgs[code]["y"])))

## A town card offers a spy too (owner 2026-09-28), aimed at the town's own
## point — burg_card's SPY_SEND wiring, untested until fix round 1.
func test_burg_card_offers_a_spy_at_its_point() -> void:
	Game.start_campaign(42)
	var realm: Dictionary = Game.data.kingdoms[_player_realm()]
	var code := String(realm["capital_burg"])
	var card := MapObjects.burg_card(Game.data, Game.state, code)
	var spy: Dictionary = {}
	for a: Dictionary in card["actions"]:
		if String(a["action_code"]) == "SPY_SEND":
			spy = a
	assert_false(spy.is_empty(), "the town card offers SPY_SEND")
	var p: Dictionary = spy["params"]
	assert_eq(Vector2(float(p["x"]), float(p["y"])), card["center"], "aimed at the town's own point")

func test_province_card_is_full_at_home_and_basic_abroad() -> void:
	Game.start_campaign(42)
	var mine := MapObjects.province_card(Game.data, Game.state, _own_province())
	assert_eq(String(mine["known"]), "full")
	var labels: Array = []
	for f in mine["fields"]:
		labels.append(String(f[0]))
	for want in ["Held by", "Seat", "Population", "Area", "Terrain", "Towns"]:
		assert_has(labels, want)
	assert_true(mine["production"].size() > 0, "the province's towns make goods")
	var theirs := MapObjects.province_card(Game.data, Game.state, _foreign_province())
	assert_eq(String(theirs["known"]), "basic")
	assert_eq(theirs["fields"].size(), 3, "house, seat and weather, nothing more")
	assert_true(theirs["production"].is_empty())

func test_goods_are_shown_under_a_tag_with_a_glyph() -> void:
	Game.start_campaign(42)
	var goods := Game.data.world_table("economy", "goods")
	assert_eq(MapObjects.good_tag(Game.data, "grain"), "tag_food")
	var tagged := 0
	for g: String in goods:
		if MapObjects.good_tag(Game.data, g) != "":
			tagged += 1
	assert_gt(float(tagged), goods.size() / 2.0, "most goods fall under a tagged glyph")

## Settlement art (user request 2026-09-09): every burg group in the pack has
## a drawing, walled towns draw behind walls, and every drawing exists.
## A regiment's card (owner 2026-09-15): the painting of its piece, its arms
## as icons with their counts, the host under arms, where it is quartered.
func test_a_regiment_card_paints_its_piece_and_lists_its_arms() -> void:
	var mine := Game.data.resolve_realm("player_realm")
	var royal := MapObjects.royal_regiment(Game.data, mine)
	var checked := 0
	for r: Dictionary in MapObjects.regiments_of(Game.data, mine):
		var code := String(r["regiment_code"])
		var card := MapObjects.army_card(Game.data, code)
		assert_eq(String(card["kind"]), "army")
		assert_eq(String(card["title"]), String(r["label"]))
		var piece := MapObjects.army_piece(Game.data, r)
		if String(r.get("is_naval", "0")) == "1":
			assert_eq(piece, "fleet")
		elif code == royal:
			assert_eq(piece, "royal")
		else:
			assert_eq(piece, MapObjects.regiment_arm(Game.data, r))
		assert_true(Game.data.army_art.has(piece), "%s has art" % piece)
		assert_eq(String(card["painting"]), GameArt.path(GameArt.ARMY_PAINTINGS, piece))
		var keys: Dictionary = {}
		for st: Dictionary in card["stats"]:
			keys[String(st["key"])] = String(st["text"])
		for unit: String in Game.data.world_table("military", "unit_types"):
			var n := int(float(r.get(unit, 0)))
			assert_eq(keys.has(unit), n > 0, "%s: %s shown only when mustered" % [code, unit])
			if n > 0:
				assert_eq(keys[unit], str(n))
		assert_eq(keys["army"], str(int(MapObjects.regiment_size(Game.data, r))), "the host under arms")
		checked += 1
	assert_gt(checked, 0)
	assert_true(MapObjects.army_card(Game.data, "no_such_regiment").is_empty())
	for piece: String in Game.data.army_art:
		assert_true(GameArt.table(GameArt.ARMY_PAINTINGS).of(piece) is Texture2D, "%s's card painting is installed" % piece)

## The card of a player's regiment reads its state (owner 2026-09-17): the
## ground, morale, the wounded beside the headcount, the month's recovery
## and supply use, and the training and strength only as words.
func test_a_regiment_card_shows_its_state() -> void:
	var s := SuiteData.campaign(Game.data, 7)
	var mine := Game.data.resolve_realm("player_realm")
	var r: Dictionary = MapObjects.regiments_of(Game.data, mine)[0]
	var code := String(r["regiment_code"])
	var heads := int(MapObjects.regiment_size(Game.data, r))
	s.regiments[code]["wounded"] = 120
	var card := MapObjects.army_card(Game.data, code, s)
	var order: Array = []
	var text: Dictionary = {}
	for st: Dictionary in card["stats"]:
		order.append(String(st["key"]))
		text[String(st["key"])] = String(st["text"])
		assert_ne(String(st["tooltip"]), "", "%s explains itself" % st["key"])
	for key in ["army_terrain", "army_height", "army_morale", "army_wounded", "army_supply", "army_training", "army_strength"]:
		assert_true(text.has(key), key)
	assert_true(text.has("army_height"))
	assert_true(order.find("army_terrain") < order.find("army_strength"), "the state reads in order")
	assert_eq(text["army"], "%d (120 wounded)" % heads)
	assert_eq(text["army_morale"], str(int(s.regiments[code]["morale"])))
	assert_eq(text["army_wounded"], "+%d / mo" % ArmySystem.wound_recovery(Game.data, 120))
	var use := ArmySystem.supply_use(Game.data, r)
	assert_eq(text["army_supply"], "%d (−%d / mo)" % [int(s.regiments[code]["supplies"]), use])
	assert_eq(text["army_training"], ArmySystem.training_grade(Game.data, int(s.regiments[code]["training"])))
	assert_true(text["army_strength"] in ["Strong", "Average", "Weak"])
	assert_eq(text["army_terrain"], ArmySystem.terrain_label(Game.data, r))
	# No number leaks for the hidden values.
	assert_false(text["army_training"].is_valid_int())

## --- Manors (MANOR_SYSTEM.md §3, §6) ----------------------------------------

func _campaign() -> GameState:
	return SuiteData.campaign(real, 42)

func _manor_where(state: GameState, crowns: bool, in_realm: bool = true) -> int:
	var realm := real.resolve_realm("player_realm")
	for province: String in real.provinces:
		if (MapOwnership.owner_of(real, state, province) == realm) != in_realm:
			continue
		for cell: int in MapManors.manors_of_province(real, province):
			if MapManors.is_crowns(real, state, cell) == crowns:
				return cell
	return -1

func test_the_manor_card_offers_the_orders_the_crown_can_give() -> void:
	var state := _campaign()
	state.metrics["treasury"] = 100000.0
	var own := _manor_where(state, true)
	var card := MapObjects.manor_card(real, state, own)
	assert_eq(String(card["kind"]), "manor")
	assert_eq(int(card["cell"]), own)
	assert_eq(String(card["known"]), "full")
	var fields: Dictionary = {}
	for f in card["fields"]:
		fields[String(f[0])] = String(f[1])
	assert_eq(fields["Held by"], "The crown")
	for key in ["Province", "Land", "Area", "People", "Tax", "Chief good", "Defence", "Buildings", "Slots", "Value", "Sells for"]:
		assert_true(fields.has(key), key + " is on the card")
	# One economy on the card (2026-09-14): every figure is ManorEconomy's
	# integer month, and the month is the unit of time.
	var line := ManorEconomy.line_of(real, state, own, state.tick)
	assert_string_contains(fields["People"], str(int(line["people"])))
	assert_eq(fields["Tax"], "%d gold a month" % int(line["tax"]))
	assert_string_contains(fields["Chief good"], " a month", "the focus and its yield")
	var good := String(ManorEconomy.focus_units(real, state, own, int(line["people"]), state.tick)["good"])
	if good != "":
		assert_string_contains(fields["Chief good"],
			"%d " % int((line["units"] as Dictionary).get(good, 0)))
	var codes: Array = []
	for a: Dictionary in card["actions"]:
		codes.append(String(a["action_code"]))
		# The demesne has no house to sell back to; every other order stands —
		# except a building whose prerequisites are not up yet, which says so
		# (owner 2026-09-14).
		if String(a["action_code"]) == "MANOR_BUILD" and not MapManors.building_prereqs(real,
				String((a["params"] as Dictionary)["building"])).is_empty():
			assert_string_contains(String(a["error"]), "standing first", String(a["label"]))
		elif String(a["action_code"]) != "MANOR_SELL":
			assert_eq(String(a["error"]), "", "%s can be given: %s" % [a["label"], a["error"]])
	assert_has(codes, "MANOR_SELL")
	assert_has(codes, "MANOR_BUILD")
	assert_does_not_have(codes, "MANOR_BUY")
	var takes := 0
	for b: String in real.manor_buildings:
		if MapManors.building_land_ok(real, state, own, b):
			takes += 1
	assert_eq(codes.count("MANOR_BUILD"), takes, "one BUILD per building the manor's ground takes")
	assert_lt(takes, real.manor_buildings.size(), "and not every building: the land decides")
	assert_eq(int(card["slots"]), MapManors.slots_of(real, own))
	assert_true((card["slot_actions"] as Array).is_empty(), "nothing to pull down yet")
	for a: Dictionary in card["actions"]:
		if String(a["action_code"]) == "MANOR_BUILD":
			assert_true(String(a["label"]).ends_with("d"), "a building says how long it takes: " + String(a["label"]))
	# A work begun (2026-09-13): the card carries it with its days, and a
	# cross to stop it.
	assert_true(MapManors.start_work(real, state, own, "mill", "test"))
	var begun := MapObjects.manor_card(real, state, own)
	assert_eq((begun["works"] as Array).size(), 1)
	assert_eq(String(begun["works"][0]["building"]), "mill")
	assert_eq(int(begun["works"][0]["days_left"]), int(float(real.manor_buildings["mill"]["build_days"])))
	assert_eq((begun["slot_actions"] as Array).size(), 1)
	assert_eq(String(begun["slot_actions"][0]["action_code"]), "MANOR_DEMOLISH")
	assert_eq(String(begun["slot_actions"][0]["error"]), "")
	var begun_fields: Dictionary = {}
	for f in begun["fields"]:
		begun_fields[String(f[0])] = String(f[1])
	assert_string_contains(begun_fields["Buildings"], "days to go")
	assert_string_contains(begun_fields["Slots"], "1 of")
	assert_eq(codes.count("MANOR_FOCUS"), MapManors.focuses_for(real, own).size() - 1,
		"one WORK per chief good the land allows, less the one it works")
	# Another house's manor in the realm: buy, no seize while the flag is off.
	# Fog (spec 2026-09-28-missive-board-and-spies §1): a manor of the realm
	# the crown does not itself control reads "general", not "full" — its
	# BUY order still stands (the button's own label and error carry the
	# real price; that mechanism was never fogged, before this task or
	# after), but the detailed fields (Asking price among them) are the
	# full branch's alone, so the card falls back to the intel rows instead.
	var theirs := _manor_where(state, false)
	var other := MapObjects.manor_card(real, state, theirs)
	assert_eq(String(other["known"]), "general")
	var other_codes: Array = []
	for a: Dictionary in other["actions"]:
		other_codes.append(String(a["action_code"]))
	# Every land card offers a spy too (owner 2026-09-28), after its own orders.
	assert_eq(other_codes, ["MANOR_BUY", "SPY_SEND"])
	assert_true(String(other["actions"][0]["label"]).begins_with("BUY — "))
	var of: Dictionary = {}
	for f in other["fields"]:
		of[String(f[0])] = String(f[1])
	assert_true(of["Held by"].begins_with("House "))
	assert_false(of.has("Asking price"), "the exact price is a full-card field; general land is fogged")
	assert_true(other.has("intel"), "the fogged card carries what is known instead")
	# Poor: the button stays but carries its reason.
	state.metrics["treasury"] = 0.0
	var poor := MapObjects.manor_card(real, state, theirs)
	assert_string_contains(String(poor["actions"][0]["error"]), "afford")
	# A spy the treasury cannot afford is disabled too (fix round 1,
	# owner 2026-09-28): SPY_SEND's "error" is ActionSystem's own answer,
	# exactly like every other card action, not a fixed "".
	assert_eq(String((poor["actions"][1] as Dictionary)["action_code"]), "SPY_SEND")
	assert_string_contains(String((poor["actions"][1] as Dictionary)["error"]), "afford")
	# Abroad: basic, no orders.
	var abroad := _manor_where(state, false, false)
	var far := MapObjects.manor_card(real, state, abroad)
	assert_eq(String(far["known"]), "basic")
	# No BUY out of the border's reach, but a spy still may be sent anywhere
	# (owner 2026-09-28).
	var far_codes: Array = []
	for a: Dictionary in far["actions"]:
		far_codes.append(String(a["action_code"]))
	assert_eq(far_codes, ["SPY_SEND"])

## The card's BUILD button spends CIVIL GOODS (spec 2026-09-14 §5), and a
## work in progress gets a HURRY button that buys days with gold.
func test_the_manor_card_prices_a_build_in_civil_goods_and_offers_to_hurry_it() -> void:
	var state := _campaign()
	state.metrics["treasury"] = 100000.0
	state.metrics["grain"] = 100000.0
	var own := _manor_where(state, true)
	var card := MapObjects.manor_card(real, state, own)
	var build := {}
	for a: Dictionary in card["actions"]:
		if String(a["action_code"]) == "MANOR_BUILD" and String(a["params"]["building"]) == "mill":
			build = a
	assert_false(build.is_empty(), "a mill is offered")
	assert_string_contains(String(build["label"]), "%d civil" % int(float(real.manor_buildings["mill"]["civil_cost"])),
		"the BUILD button prices the work in civil goods")
	assert_does_not_have(card["actions"].map(func(a: Dictionary) -> String: return String(a["action_code"])),
		"MANOR_RUSH", "nothing to hurry before a work is begun")
	assert_true(MapManors.start_work(real, state, own, "mill", "test"))
	var hurry := {}
	for a: Dictionary in MapObjects.manor_actions(real, state, own):
		if String(a["action_code"]) == "MANOR_RUSH":
			hurry = a
	assert_false(hurry.is_empty(), "a work in progress can be hurried")
	var per_click := int(real.bal("manor_rush_days_per_click"))
	assert_eq(String(hurry["params"]["building"]), "mill")
	assert_eq(int(hurry["params"]["days"]), per_click, "one press buys manor_rush_days_per_click days")
	assert_eq(String(hurry["label"]), "HURRY MILL — %dg" % (per_click * int(real.bal("build_rush_gold_per_day"))))
	assert_eq(String(hurry["error"]), "", "the order can be given: " + String(hurry["error"]))
	# The order it carries is the one that runs.
	var before := MapManors.work_days_left(real, state, own, "mill")
	var outcome := ActionSystem.new(real).execute(
		ActionRequest.make("MANOR_RUSH", (hurry["params"] as Dictionary).duplicate()), state)
	assert_true(bool(outcome["ok"]), "the order the button carries runs")
	assert_eq(MapManors.work_days_left(real, state, own, "mill"), before - per_click, "the days came off")

func test_the_province_card_counts_its_manors_by_house() -> void:
	var state := _campaign()
	var realm := real.resolve_realm("player_realm")
	var province: String = MapOwnership.provinces_of(real, state, realm)[0]
	var card := MapObjects.province_card(real, state, province)
	var fields: Dictionary = {}
	for f in card["fields"]:
		fields[String(f[0])] = String(f[1])
	assert_true(fields.has("Manors"))
	assert_true(String(fields["Manors"]).begins_with(str(MapManors.manors_of_province(real, province).size())))
