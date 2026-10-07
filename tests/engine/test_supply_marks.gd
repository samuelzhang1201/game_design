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


func test_every_line_names_its_hazards_and_a_stronghold_line_has_none() -> void:
	var state := SuiteData.campaign(repo, 42)
	for code: String in state.regiments:
		var line := SupplySystem.line_of(repo, state, code)
		assert_true(line.has("hazards"), code)
		if String(line["stronghold"]) != "":
			assert_eq(line["hazards"], [])
			assert_eq(int(line["loss_permille"]), 0)


func test_a_brigand_on_a_regiments_road_shows_in_its_line() -> void:
	var state := SuiteData.campaign(repo, 42)
	var target := ""
	for code: String in state.regiments:
		if SupplySystem.route_px(repo, state, code).size() >= 2:
			target = code
			break
	if target == "":
		pass_test("no regiment on a road at the campaign's start")
		return
	var route := SupplySystem.route_px(repo, state, target)
	var mid := route[route.size() / 2]
	var m := _mark_of("brigands")
	repo.markers[m["code"]]["x"] = str(mid.x)
	repo.markers[m["code"]]["y"] = str(mid.y)
	var line := SupplySystem.line_of(repo, state, target)
	var labels: Array = (line["hazards"] as Array).map(func(h: Dictionary) -> String: return String(h["label"]))
	assert_true(labels.has(String(m["label"])))
	assert_eq(int(line["loss_permille"]),
		SupplySystem.total_loss(repo, int(line["length_km"]), int(repo.war_mark_hazards["brigands"]["permille"])))


func test_a_fleet_pays_no_mark_toll() -> void:
	var state := SuiteData.campaign(repo, 42)
	for code: String in state.regiments:
		var reg := ArmySystem.regiment(repo, code)
		if String(reg.get("is_naval", "0")) != "1" or String(SupplySystem.line_of(repo, state, code)["stronghold"]) != "":
			continue
		var at := ArmySystem.position_of(repo, state, reg)
		var m := _mark_of("pirates")
		repo.markers[m["code"]]["x"] = str(at.x + 2.0)
		repo.markers[m["code"]]["y"] = str(at.y)
		assert_eq(SupplySystem.line_of(repo, state, code)["hazards"], [], code)
		return
	pass_test("no fleet")


func _road_regiment(state: GameState) -> String:
	for code: String in state.regiments:
		if SupplySystem.route_px(repo, state, code).size() >= 2:
			return code
	return ""


func test_a_line_through_rebels_pays_and_names_them_when_known() -> void:
	var state := SuiteData.campaign(repo, 42)
	var code := _road_regiment(state)
	if code == "":
		pass_test("no regiment on a road")
		return
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
