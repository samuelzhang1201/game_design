extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Brigands and pirates on a supply line (spec 2026-10-07-war-room-p2-tactical-layer §1.2).

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()


func _mark_of(type: String) -> Dictionary:
	var codes: Array = repo.markers.keys()
	codes.sort()
	for code: String in codes:
		if String(repo.markers[code]["type"]) == type:
			var m: Dictionary = repo.markers[code]
			return {"code": code, "label": String(m["label"]), "at": Vector2(float(m["x"]), float(m["y"]))}
	return {}


func test_a_route_through_a_brigand_mark_pays_its_share_once() -> void:
	var m := _mark_of("brigands")
	var at: Vector2 = m["at"]
	var hz: Dictionary = repo.war_mark_hazards["brigands"]
	# past it and back again: one mark, counted once
	var route := PackedVector2Array([at + Vector2(-20, 0.5), at + Vector2(20, 0.5), at + Vector2(-20, 1.0)])
	var got := SupplySystem.mark_loss(repo, route)
	var mine: Array = (got["hazards"] as Array).filter(func(h: Dictionary) -> bool: return String(h["code"]) == String(m["code"]))
	assert_eq(mine.size(), 1)
	assert_eq(int(mine[0]["permille"]), int(hz["permille"]))
	assert_eq(String(mine[0]["label"]), String(m["label"]))


func test_a_route_out_of_reach_pays_nothing() -> void:
	var m := _mark_of("brigands")
	var reach_px := float(repo.war_mark_hazards["brigands"]["reach_km"]) / WarMarks.km_per_px(repo)
	var at: Vector2 = m["at"]
	var route := PackedVector2Array([at + Vector2(-20, reach_px * 1.5), at + Vector2(20, reach_px * 1.5)])
	var got := SupplySystem.mark_loss(repo, route)
	assert_false((got["hazards"] as Array).any(func(h: Dictionary) -> bool: return String(h["code"]) == String(m["code"])))


func test_a_mark_that_is_no_hazard_takes_nothing() -> void:
	var m := _mark_of("mines")
	if m.is_empty():
		pass_test("no mine on this pack")
		return
	var at: Vector2 = m["at"]
	var got := SupplySystem.mark_loss(repo, PackedVector2Array([at + Vector2(-1, 0), at + Vector2(1, 0)]))
	assert_false((got["hazards"] as Array).any(func(h: Dictionary) -> bool: return String(h["code"]) == String(m["code"])))


func test_the_total_never_passes_the_cap() -> void:
	var cap := int(repo.bal("army_supply_loss_cap_permille"))
	assert_eq(SupplySystem.total_loss(repo, 100000, 500), cap)
	assert_eq(SupplySystem.total_loss(repo, 0, 40), mini(40, cap))
	assert_eq(SupplySystem.total_loss(repo, 100, 0), SupplySystem.loss_of(repo, 100))


## A land regiment out in the field (a step out of its town onto dry land, as
## test_supply_day marches one out: out of its camp, never a seated one) fed
## by a FLOWING line from the first
## eligible realm town, its marshal able and honest (efficiency 1000, no skim)
## and every other regiment too full to draw — [code, town], or [] when the
## pack offers none.
func _flowing_line(state: GameState) -> Array:
	var m: Character = state.characters[String(state.council["marshal"])]
	m.skills["sk_admin"] = 16
	m.opinion = 50
	m.traits = []
	m.attributes["integrity"] = 50
	var codes: Array = state.regiments.keys()
	codes.sort()
	for c in codes:
		var reg := ArmySystem.regiment(repo, String(c))
		if String(reg.get("is_naval", "0")) == "1" or ArmyGround.seated_in(repo, state, String(c)) != "":
			continue
		var camp := String(state.regiments[c].get("camp_town", ""))
		var home := ArmySystem.position_of(repo, state, reg)
		for step: Vector2 in [Vector2.ZERO, Vector2(40.0, 0.0), Vector2(-40.0, 0.0), Vector2(0.0, 40.0), Vector2(0.0, -40.0)]:
			var cell := MapEconomy.cell_at(repo, home + step)
			if cell < 0 or MapTerrain.is_water(repo.cells[cell]):
				continue
			var mm := ArmySystem.pack_to_metres(repo, home + step)
			state.regiments[c]["x_m"] = mm.x
			state.regiments[c]["y_m"] = mm.y
			state.regiments[c]["camp_town"] = ""
			var town := _eligible_town(state, String(c)) if ArmySystem.held_town_of(repo, reg, state) == "" else ""
			if town != "":
				state.supply_lines[String(c)] = SupplyLines._new_record(town, 1000, 1)
				state.supply_lines[String(c)]["state"] = SupplyLines.FLOWING
				for o in codes:
					if o != c:
						var use := ArmySystem.supply_use(repo, ArmySystem.regiment(repo, String(o)), state)
						state.regiments[o]["supplies"] = ArmySystem.max_units(repo, use) + use
				return [String(c), town]
		var back := ArmySystem.pack_to_metres(repo, home)
		state.regiments[c]["x_m"] = back.x
		state.regiments[c]["y_m"] = back.y
		state.regiments[c]["camp_town"] = camp
	return []


func _eligible_town(state: GameState, code: String) -> String:
	var e := SupplyLines.eligibility(repo, state, code)
	var towns: Array = e.keys()
	towns.sort()
	for t: String in towns:
		if String(e[t]) == "" and SupplyLines.road_px(repo, state, code, t).size() >= 2:
			return t
	return ""


func test_every_line_names_its_hazards_and_no_line_has_none() -> void:
	var state := SuiteData.campaign(repo, 42)
	var fed := _flowing_line(state)
	for code: String in state.regiments:
		var line := SupplySystem.line_of(repo, state, code)
		assert_true(line.has("hazards"), code)
		if String(line["town"]) == "":
			assert_eq(line["hazards"], [])
			assert_eq(int(line["loss_permille"]), 0)
	assert_false(fed.is_empty(), "a regiment in the field with a town in reach")
	if not fed.is_empty():
		var line := SupplySystem.line_of(repo, state, String(fed[0]))
		var route := SupplySystem.route_px(repo, state, String(fed[0]))
		assert_eq(int(line["loss_permille"]), SupplySystem.total_loss(repo, int(line["length_km"]),
			int(SupplySystem.road_loss(repo, state, String(fed[0]), route)["permille"])))


func test_a_brigand_on_a_regiments_road_shows_in_its_line_and_robs_its_day() -> void:
	RealmEconomy.forget()
	var state := SuiteData.campaign(repo, 42)
	var fed := _flowing_line(state)
	assert_false(fed.is_empty(), "a regiment in the field with a town in reach")
	if fed.is_empty():
		return
	var target := String(fed[0])
	var town := String(fed[1])
	var route := SupplySystem.route_px(repo, state, target)
	var mid := route[route.size() / 2]
	var m := _mark_of("brigands")
	repo.markers[m["code"]]["x"] = str(mid.x)
	repo.markers[m["code"]]["y"] = str(mid.y)
	var line := SupplySystem.line_of(repo, state, target)
	var labels: Array = (line["hazards"] as Array).map(func(h: Dictionary) -> String: return String(h["label"]))
	assert_true(labels.has(String(m["label"])))
	var robbed := SupplySystem.road_loss(repo, state, target, route)
	assert_true(int(robbed["permille"]) >= int(repo.war_mark_hazards["brigands"]["permille"]))
	assert_eq(int(line["loss_permille"]), SupplySystem.total_loss(repo, int(line["length_km"]), int(robbed["permille"])))
	# one day's delivery is thinned by the whole loss, the brigands' share included
	state.day = 5
	state.regiments[target]["supplies"] = 0
	state.town_stock[town] = {"crown": 100000, "lord": 0, "house": 0}
	TownStores.sync_metrics(repo, state)
	var send := ArmySystem.day_bite(ArmySystem.supply_use(repo, ArmySystem.regiment(repo, target), state), 5)
	SupplyLines.day_step(repo, state)
	@warning_ignore("integer_division")
	assert_eq(int(state.regiments[target]["supplies"]), send * (1000 - int(line["loss_permille"])) / 1000)
	# in thousandths, exact: the carried remainder holds the rest of send × keep
	assert_eq(int(state.supply_lines[target]["arrive_milli"]), send * (1000 - int(line["loss_permille"])) % 1000)
	assert_true(int(line["loss_permille"]) > SupplySystem.loss_of(repo, int(line["length_km"])),
		"the brigands' share is on top of the road's")
	RealmEconomy.forget()


func test_a_fleet_pays_no_mark_toll() -> void:
	var state := SuiteData.campaign(repo, 42)
	var codes: Array = state.regiments.keys()
	codes.sort()
	for code: String in codes:
		var reg := ArmySystem.regiment(repo, code)
		if String(reg.get("is_naval", "0")) != "1":
			continue
		var at := ArmySystem.position_of(repo, state, reg)
		var m := _mark_of("pirates")
		repo.markers[m["code"]]["x"] = str(at.x + 2.0)
		repo.markers[m["code"]]["y"] = str(at.y)
		assert_eq(SupplySystem.road_loss(repo, state, code, PackedVector2Array([at + Vector2(-5, 0), at])),
			{"permille": 0, "hazards": []}, code)
		return
	pass_test("no fleet")


func test_a_line_through_rebels_pays_and_names_them_when_known() -> void:
	var state := SuiteData.campaign(repo, 42)
	var fed := _flowing_line(state)
	assert_false(fed.is_empty(), "a regiment in the field with a town in reach")
	if fed.is_empty():
		return
	var code := String(fed[0])
	var route := SupplySystem.route_px(repo, state, code)
	var cell := MapEconomy.cell_at(repo, route[route.size() / 2])
	Hazards.add(state, "rb", "Rebels", "Road Rebels", [cell], state.tick, -1, "test")
	var line := SupplySystem.line_of(repo, state, code)
	var hz: Array = (line["hazards"] as Array).filter(func(h: Dictionary) -> bool: return String(h["code"]) == "rb")
	assert_eq(hz.size(), 1)
	assert_eq(int(hz[0]["permille"]), int(Hazards.kind_of(repo, "Rebels")["supply_loss_permille"]))
	var label := "Road Rebels" if Hazards.known(repo, state, "rb") else "trouble on the road"
	assert_eq(String(hz[0]["label"]), label)


func test_an_unknown_hazard_is_never_named() -> void:
	var state := SuiteData.campaign(repo, 42)
	var route := PackedVector2Array()
	var mine := repo.resolve_realm("player_realm")
	var foreign := -1
	var ids: Array = repo.cells.keys()
	ids.sort()
	for c: int in ids:
		var owner := MapOwnership.owner_of(repo, state, MapManors.province_of(repo, c, state))
		if owner != "" and owner != mine and not MapTerrain.is_water(repo.cells[c]):
			foreign = c
			break
	var at := MapTerrain.cell_center(repo, repo.cells[foreign])
	route.append(at + Vector2(-0.2, 0))
	route.append(at + Vector2(0.2, 0))
	Hazards.add(state, "far", "Rebels", "Secret Rebels", [foreign], state.tick, -1, "test")
	var got := SupplySystem.hazard_loss(repo, state, route)
	assert_eq(int(got["permille"]), int(Hazards.kind_of(repo, "Rebels")["supply_loss_permille"]))
	assert_eq(String(got["hazards"][0]["label"]), "trouble on the road")
