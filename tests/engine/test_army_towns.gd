extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Where a regiment stands (owner 2026-10-06, spec 2026-10-06-army-location-
## and-town-defence): IN a town within its group's reach, the town's works
## defending the side that holds it, a garrison only inside a held town, and
## a march paced by the road or the ground under it each day.

var repo: DataRepository

func before_all() -> void:
	repo = SuiteData.repo()

func _xy(code: String) -> Vector2:
	var b: Dictionary = repo.burgs[code]
	return Vector2(float(b["x"]), float(b["y"]))

## A regiment dict of `kingdom` standing at a pack point (no state: the pack's
## own position).
func _reg_at(at: Vector2, kingdom: String) -> Dictionary:
	return {"regiment_code": "t", "kingdom_code": kingdom, "x": str(at.x), "y": str(at.y),
		"is_naval": "0", "infantry": "100", "cavalry": "100"}

func _works(code: String) -> String:
	var feats := String(repo.burgs[code].get("features", "")).split("|")
	return "citadel" if "citadel" in feats else ("walls" if "walls" in feats else "town")

## A town with no other burg within three of its reaches, by code.
func _lonely_town(pred: Callable) -> String:
	var codes := repo.burgs.keys()
	codes.sort()
	for code: String in codes:
		if not pred.call(code):
			continue
		var reach := ArmySystem.town_reach_px(repo, repo.burgs[code])
		if reach <= 0.0:
			continue
		var alone := true
		for other: String in codes:
			if other != code and _xy(other).distance_to(_xy(code)) < reach * 3.0:
				alone = false
				break
		if alone:
			return code
	return ""

func _land_at(at: Vector2) -> bool:
	return MapEconomy.cell_at(repo, at) >= 0

# --- the town a regiment is in ------------------------------------------------

func test_a_regiment_is_in_a_town_within_its_reach() -> void:
	var town := _lonely_town(func(c: String) -> bool: return String(repo.burgs[c]["group"]) == "town")
	assert_ne(town, "", "the pack has a town standing alone")
	var reach := ArmySystem.town_reach_px(repo, repo.burgs[town])
	var km := float(repo.army_town_reach["town"])
	assert_almost_eq(reach * float(ArmySystem.metres_per_pack_px(repo)), km * 1000.0, 0.01,
		"the reach is the table's km on the pack's measure")
	var k := String(repo.burgs[town]["kingdom_code"])
	assert_eq(ArmySystem.town_of(repo, _reg_at(_xy(town), k)), town, "at its point")
	assert_eq(ArmySystem.town_of(repo, _reg_at(_xy(town) + Vector2(reach * 0.9, 0.0), k)), town, "just inside")
	assert_eq(ArmySystem.town_of(repo, _reg_at(_xy(town) + Vector2(reach * 1.1, 0.0), k)), "", "just outside")

func test_a_capital_reaches_further_than_a_village() -> void:
	assert_gt(float(repo.army_town_reach["capital"]), float(repo.army_town_reach["village"]))

func test_the_nearer_town_wins_where_two_reaches_meet() -> void:
	# the pack's towns stand apart, so a copy gets a second town beside one
	var other := SuiteData.repo()
	var town := _lonely_town(func(c: String) -> bool: return String(repo.burgs[c]["group"]) == "town")
	var reach := ArmySystem.town_reach_px(other, other.burgs[town])
	var near := (other.burgs[town] as Dictionary).duplicate()
	near["x"] = str(_xy(town).x + reach)
	other.burgs["zz_test_town"] = near
	var at := _xy(town) + Vector2(reach * 0.4, 0.0)
	assert_eq(ArmySystem.town_at(other, at), town, "0.4 of a reach from it, 0.6 from the other")
	assert_eq(ArmySystem.town_at(other, at + Vector2(reach * 0.2, 0.0)), "zz_test_town", "and now the other is nearer")

func test_a_fleet_is_in_no_town() -> void:
	var town: String = repo.burgs.keys()[0]
	var reg := _reg_at(_xy(town), String(repo.burgs[town]["kingdom_code"]))
	reg["is_naval"] = "1"
	assert_eq(ArmySystem.town_of(repo, reg), "")

# --- the town's works -------------------------------------------------------

func test_the_works_are_the_best_the_town_has() -> void:
	var seen := {}
	var codes := repo.burgs.keys()
	codes.sort()
	for code: String in codes:
		var w := _works(code)
		if seen.has(w):
			continue
		var reg := _reg_at(_xy(code), String(repo.burgs[code]["kingdom_code"]))
		if ArmySystem.town_of(repo, reg) != code:
			continue   # another burg's point sits nearer
		assert_eq(ArmySystem.works_of(repo, reg), w, code)
		seen[w] = true
	assert_eq(seen.size(), 3, "the pack has towns of every works")

func test_only_the_side_that_holds_the_town_gets_its_works() -> void:
	var town := _lonely_town(func(c: String) -> bool: return _works(c) == "walls")
	assert_ne(town, "")
	var mine := String(repo.burgs[town]["kingdom_code"])
	var theirs := ""
	for k: String in repo.kingdoms:
		if k != mine:
			theirs = k
			break
	var foe := _reg_at(_xy(town), theirs)
	assert_eq(ArmySystem.town_of(repo, foe), town, "the foe stands in it")
	assert_eq(ArmySystem.held_town_of(repo, foe), "", "but does not hold it")
	assert_eq(ArmySystem.works_of(repo, foe), "", "so it fights in the field")
	assert_eq(ArmySystem.terrain_label(repo, foe), ArmySystem.terrain_of(repo, foe).capitalize())
	var own := _reg_at(_xy(town), mine)
	assert_eq(ArmySystem.works_of(repo, own), "walls")
	assert_eq(ArmySystem.terrain_label(repo, own), "%s — behind the walls of %s" % [
		ArmySystem.terrain_of(repo, own).capitalize(), String(repo.burgs[town]["label"])])

func test_a_town_follows_its_province_when_it_changes_hands() -> void:
	var town := _lonely_town(func(c: String) -> bool: return _works(c) == "walls")
	var mine := String(repo.burgs[town]["kingdom_code"])
	var theirs := ""
	for k: String in repo.kingdoms:
		if k != mine:
			theirs = k
			break
	var s := SuiteData.campaign(repo, 7)
	MapOwnership.set_owner(repo, s, String(repo.burgs[town]["province_code"]), theirs, "test: taken")
	assert_eq(ArmySystem.works_of(repo, _reg_at(_xy(town), theirs), s), "walls", "the new holder's")
	assert_eq(ArmySystem.works_of(repo, _reg_at(_xy(town), mine), s), "", "no longer the old one's")

func test_town_defence_by_works_and_arm() -> void:
	var d := func(works: String, arm: String) -> int:
		return ArmySystem.terrain_factor(repo, "plains", arm, "defend", works)
	assert_eq(d.call("", "infantry"), 1000, "the open plain")
	assert_gt(d.call("town", "infantry"), 1000, "a town without walls still helps foot")
	assert_lt(d.call("town", "cavalry"), 1000, "horse is worse in streets")
	assert_gt(d.call("walls", "infantry"), d.call("town", "infantry"))
	assert_gt(d.call("citadel", "infantry"), d.call("walls", "infantry"))
	for works: String in ["town", "walls", "citadel"]:
		assert_eq(ArmySystem.terrain_factor(repo, "plains", "infantry", "attack", works), 1000,
			"%s only helps the defender" % works)

## The works follow a regiment from a walled town to an unwalled one.
func test_the_works_follow_the_regiment() -> void:
	var s := SuiteData.campaign(repo, 7)
	var realm := repo.resolve_realm("player_realm")
	var code := ""
	for r: Dictionary in MapObjects.regiments_of(repo, realm):
		if String(r.get("is_naval", "0")) != "1":
			code = String(r["regiment_code"])
			break
	var reg := ArmySystem.regiment(repo, code)
	var put := func(at: Vector2) -> void:
		var m := ArmySystem.pack_to_metres(repo, at)
		s.regiments[code]["x_m"] = m.x
		s.regiments[code]["y_m"] = m.y
	var walled := ""
	var open := ""
	for b: String in repo.burgs:
		if String(repo.burgs[b]["kingdom_code"]) != realm:
			continue
		if walled == "" and _works(b) == "walls":
			walled = b
		if open == "" and _works(b) == "town":
			open = b
	put.call(_xy(walled))
	assert_eq(ArmySystem.works_of(repo, reg, s), "walls")
	put.call(_xy(open))
	assert_eq(ArmySystem.works_of(repo, reg, s), "town")
	assert_string_contains(ArmySystem.terrain_label(repo, reg, s), " — in " + String(repo.burgs[open]["label"]))

# --- the garrison -------------------------------------------------------------

func _player_land(s: GameState) -> String:
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) != "1":
			return String(r["regiment_code"])
	return ""

## A land point of the realm with no town within reach, by cell.
func _field_of(s: GameState, realm: String) -> Vector2:
	var ids := repo.cells.keys()
	ids.sort()
	for id: int in ids:
		var cell: Dictionary = repo.cells[id]
		if MapTerrain.is_water(cell) or (cell["vertex_ids"] as PackedInt32Array).size() < 3:
			continue
		var at := MapTerrain.cell_center(repo, cell)
		if MapEconomy.cell_at(repo, at) != id or ArmySystem.town_at(repo, at) != "":
			continue
		var prov := MapManors.province_of(repo, id, s)
		if prov != "" and MapOwnership.owner_of(repo, s, prov) == realm \
				and MapManors.crown_controls(repo, s, prov):
			return at
	return Vector2(-1, -1)

func test_a_garrison_is_the_held_town_it_stands_in() -> void:
	var s := SuiteData.campaign(repo, 7)
	var code := _player_land(s)
	var town := ""
	for b: String in repo.burgs:
		if String(repo.burgs[b]["kingdom_code"]) == repo.resolve_realm("player_realm") \
				and ArmySystem.town_at(repo, _xy(b)) == b:
			town = b
			break
	var m := ArmySystem.pack_to_metres(repo, _xy(town))
	s.regiments[code]["x_m"] = m.x
	s.regiments[code]["y_m"] = m.y
	ArmySystem.set_garrison(repo, s, code)
	assert_eq(SupplySystem.garrisoned_in(repo, s, code), town, "it garrisons THAT town")

func test_a_halt_in_the_open_is_a_field_camp() -> void:
	var s := SuiteData.campaign(repo, 7)
	var code := _player_land(s)
	var field := _field_of(s, repo.resolve_realm("player_realm"))
	assert_true(field.x >= 0.0, "the crown's province has open country")
	var m := ArmySystem.pack_to_metres(repo, field)
	s.regiments[code]["x_m"] = m.x
	s.regiments[code]["y_m"] = m.y
	ArmySystem.set_garrison(repo, s, code)
	assert_eq(SupplySystem.garrisoned_in(repo, s, code), "", "no garrison in the open")
	assert_eq(SupplySystem.stronghold_of(repo, s, code) != "", true,
		"still supplied through the province's capital (the supply rule is unchanged)")
	assert_false(bool(SupplySystem.line_of(repo, s, code)["garrison"]))
	var rows: Array = []
	for sec: Dictionary in WarFolio.sections(repo, s, code):
		rows.append_array(sec.get("rows", []))
	var order := ""
	for row in rows:
		if String((row as Dictionary).get("label", "")) == "Order":
			order = String((row as Dictionary).get("text", ""))
	assert_eq(order, WarFolio.order_word(repo, "camp"), "the folio says it is encamped")
	# the morale mark: no garrison bonus in a field camp
	var reg := ArmySystem.regiment(repo, code)
	var use := ArmySystem.supply_use(repo, reg, s)
	var score := ArmySystem.supply_score(repo, int(s.regiments[code]["supplies"]), use)
	assert_eq(ArmySystem.morale_mark(repo, score, SupplySystem.garrisoned_in(repo, s, code) != ""),
		ArmySystem.morale_mark(repo, score, false))

# --- the ground's pace ------------------------------------------------------

func _a_road_point() -> Vector2:
	var codes := repo.routes.keys()
	codes.sort()
	for code in codes:
		var r: Dictionary = repo.routes[code]
		if String(r.get("group", "")) != "roads":
			continue
		for p: Vector2 in r["polyline"]:
			if _land_at(p) and ArmySystem.town_at(repo, p) == "":
				return p
	return Vector2(-1, -1)

func test_a_road_is_found_within_its_reach_and_not_beyond() -> void:
	var p := _a_road_point()
	assert_true(p.x >= 0.0, "the pack has roads")
	assert_eq(ArmySystem.road_at(repo, p), "road")
	var reach := repo.bal("army_road_reach_m") / float(ArmySystem.metres_per_pack_px(repo))
	# straight off the road, far past the reach, until no route is near
	var far := Vector2(-1, -1)
	for i in range(1, 200):
		var q := p + Vector2(reach * float(i), 0.0)
		if _land_at(q) and ArmySystem.road_at(repo, q) == "":
			far = q
			break
	assert_true(far.x >= 0.0, "open country beside the road")

func test_the_ground_sets_the_pace() -> void:
	var reg := {"regiment_code": "t", "kingdom_code": "t", "is_naval": "0"}
	var p := _a_road_point()
	var id := MapEconomy.cell_at(repo, p)
	var tier := String(Elevation.tier_of(repo, float(repo.cells[id]["height"]))["tier"])
	@warning_ignore("integer_division")
	assert_eq(ArmySystem.ground_permille(repo, reg, p),
		int(repo.army_ground_speed["road"]) * int(repo.army_ground_speed["tier_" + tier]) / 1000,
		"on a road: the road's row times its height tier's")
	# off every road: the terrain's row
	var ids := repo.cells.keys()
	ids.sort()
	var checked := {}
	for cid: int in ids:
		var cell: Dictionary = repo.cells[cid]
		if MapTerrain.is_water(cell) or (cell["vertex_ids"] as PackedInt32Array).size() < 3:
			continue
		var at := MapTerrain.cell_center(repo, cell)
		if MapEconomy.cell_at(repo, at) != cid or ArmySystem.road_at(repo, at) != "":
			continue
		var t := ArmySystem.terrain_at(repo, at)
		if checked.has(t):
			continue
		checked[t] = true
		assert_eq(ArmySystem.ground_permille(repo, reg, at), int(repo.army_ground_speed.get(t, 1000)), t)
	assert_true(checked.has("plains") or checked.size() > 1, "several grounds checked: %s" % [checked.keys()])
	assert_gt(int(repo.army_ground_speed["road"]), int(repo.army_ground_speed["plains"]), "a road is faster")
	assert_lt(int(repo.army_ground_speed["forest"]), int(repo.army_ground_speed["plains"]), "a forest is slower")
	assert_lt(int(repo.army_ground_speed["mountains"]), int(repo.army_ground_speed["hills"]))

func test_a_column_on_a_road_marches_faster_than_one_off_it() -> void:
	var s := SuiteData.campaign(repo, 7)
	var code := _player_land(s)
	var step := ArmySystem.day_step_m(repo, s, code)
	var p := _a_road_point()
	var day := s.absolute_day()
	var on := ArmySystem.day_march_at(repo, s, code, p, day)
	var wx := Weather.speed_permille(repo, Weather.at(repo, s, p, day))
	@warning_ignore("integer_division")
	assert_eq(on, maxi(1, step * wx / 1000 * ArmySystem.ground_permille(repo, ArmySystem.regiment(repo, code), p) / 1000),
		"the day's metres: base x weather x ground")

## The arrival the ruler and the card promise is the day the column arrives,
## over a road and the open country and every day's weather on the way (a
## march short enough that its stores, which also set its pace, stay full).
func test_the_days_out_are_the_days_it_takes() -> void:
	var s := SuiteData.campaign(repo, 7)
	var engine := TickEngine.new(repo)
	var code := _player_land(s)
	var reg := ArmySystem.regiment(repo, code)
	var home := ArmySystem.position_of(repo, s, reg)
	# a town of the realm some five days' clear march away
	var want := 5.0 * float(ArmySystem.day_step_m(repo, s, code)) / float(ArmySystem.metres_per_pack_px(repo))
	var dest := home
	for b: String in repo.burgs:
		if String(repo.burgs[b]["kingdom_code"]) == String(reg["kingdom_code"]) \
				and absf(_xy(b).distance_to(home) - want) < absf(dest.distance_to(home) - want):
			dest = _xy(b)
	ArmySystem.set_march(repo, s, code, dest)
	var n := ArmySystem.days_out(repo, s, code)
	assert_gt(n, 3, "a march of days")
	assert_eq(n, ArmySystem.march_days_between(repo, s, code, home, dest), "one figure")
	for day in n:
		engine.advance_day(s)
		if day < n - 1:
			assert_eq(engine.day_arrivals, [], "still on the road at the end of day %d" % (day + 1))
			assert_eq(ArmySystem.days_out(repo, s, code), n - day - 1, "one day fewer each day")
	assert_eq(engine.day_arrivals, [code], "it arrives as day %d ends" % n)

# --- the pack's quarters ------------------------------------------------------

## Owner 2026-10-06 (开局部队挪进城里): every land regiment opens the game
## inside a town its kingdom holds, on land in its own province.
func test_every_land_regiment_starts_in_a_town_its_kingdom_holds() -> void:
	var rows: Dictionary = repo.world_table("military", "regiments")
	var codes := rows.keys()
	codes.sort()
	for code: String in codes:
		var reg: Dictionary = rows[code]
		if String(reg.get("is_naval", "0")) == "1":
			continue
		var town := ArmySystem.held_town_of(repo, reg)
		assert_ne(town, "", code + " stands in a town of its own")
		assert_true(_land_at(ArmySystem.position_of(repo, null, reg)), code + " stands on land")
		assert_eq(ArmySystem.province_of(repo, null, reg), String(reg["province_code"]), code + " in its province")

## The crown's banner still flies over the regiment the capital is named for:
## where two stand in the capital, the first by the pack's order stands nearest.
func test_the_royal_regiment_stands_in_the_capital() -> void:
	var realm := repo.resolve_realm("player_realm")
	var royal := MapObjects.royal_regiment(repo, realm)
	var capital := String(repo.kingdoms[realm]["capital_burg"])
	assert_eq(ArmySystem.town_of(repo, ArmySystem.regiment(repo, royal)), capital)
