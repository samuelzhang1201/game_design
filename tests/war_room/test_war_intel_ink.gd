extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## What we KNOW, inked over the laid sheet once a day (spec 2026-10-02-war-room-v2
## §2.4): our supply lines, our couriers, the weather, spy reports that came in.

var repo: DataRepository
var state: GameState


func before_each() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 42)
	WarSheets.forget()


func _sheet_of_first_regiment() -> Dictionary:
	var p: Dictionary = WarRoom.pieces(repo, state)[0]
	return WarSheets.series(repo)[int(p["sheet"])]


func test_only_our_own_supply_lines_are_inked() -> void:
	var ours: Array = MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), state).map(
		func(r: Dictionary) -> String: return String(r["regiment_code"]))
	# every land regiment of ours runs a supply line (spec 2026-10-07-army-supply-lines)
	for c in state.regiments.keys():
		if String(ArmySystem.regiment(repo, String(c)).get("is_naval", "0")) != "1":
			state.supply_lines[c] = SupplyLines._new_record(TownStores.realm_towns(repo, state)[0], 1000, 1)
			state.supply_lines[c]["state"] = SupplyLines.FLOWING
	var inked := 0
	for s: Dictionary in WarSheets.series(repo):
		for line: Dictionary in WarIntelInk.strokes(repo, state, s, 1024)["supply"]:
			assert_true(String(line["code"]) in ours, "a foreign regiment's supply line is not ours to know")
			assert_gte((line["poly"] as PackedVector2Array).size(), 2)
			inked += 1
	assert_gt(inked, 0, "our lines are inked")


## Final review 7: only a FLOWING line is a road the wagons roll on (as the
## 3D map draws them): ordered, riding and cut lines are not inked.
func test_only_flowing_lines_are_inked() -> void:
	var codes: Array = []
	for c in state.regiments.keys():
		if String(ArmySystem.regiment(repo, String(c)).get("is_naval", "0")) != "1":
			codes.append(String(c))
	codes.sort()
	for st: String in [SupplyLines.ORDERED, SupplyLines.RIDING, SupplyLines.CUT, SupplyLines.FLOWING]:
		for c: String in codes:
			state.supply_lines[c] = SupplyLines._new_record(TownStores.realm_towns(repo, state)[0], 1000, 1)
			state.supply_lines[c]["state"] = st
		var inked := 0
		for s: Dictionary in WarSheets.series(repo):
			inked += (WarIntelInk.strokes(repo, state, s, 1024)["supply"] as Array).size()
		if st == SupplyLines.FLOWING:
			assert_gt(inked, 0, "a flowing line is inked")
		else:
			assert_eq(inked, 0, "a %s line is not inked" % st)


func test_a_spy_still_riding_is_a_courier_and_files_no_report_yet() -> void:
	var s := _sheet_of_first_regiment()
	var at: Vector2 = (s["cell"] as Rect2).get_center()
	CourierSystem.dispatch_spy(repo, state, at)
	var ink := WarIntelInk.strokes(repo, state, s, 1024)
	assert_eq((ink["spies"] as Array).size(), 0, "no report until it has come in")
	var riding: Array = (ink["couriers"] as Array).filter(func(x: Dictionary) -> bool: return bool(x["spy"]))
	assert_lte(riding.size(), 1, "the spy rides as a courier, once")


func test_an_arrived_spy_report_is_a_ring_with_its_estimate() -> void:
	var s := _sheet_of_first_regiment()
	var at: Vector2 = (s["cell"] as Rect2).get_center()
	MissiveLog.add(repo, state, MissiveLog.make("spy", "credible", state.absolute_day(),
		MissiveLog.subject("point", "", -1, at), "A report", [MissiveLog.span("people", "People", 2800, 3200)]))
	var ink := WarIntelInk.strokes(repo, state, s, 1024)
	assert_eq((ink["spies"] as Array).size(), 1)
	assert_string_contains(String(ink["spies"][0]["text"]), "2,800")
	assert_gt(float(ink["spies"][0]["radius"]), repo.bal("war_intel_spy_ring_px"), "a spread estimate rings wider")


func test_fair_weather_is_not_news() -> void:
	for s: Dictionary in WarSheets.series(repo):
		for w: Dictionary in WarIntelInk.strokes(repo, state, s, 1024)["weather"]:
			assert_true(float(w["rain"]) > 0.0 or float(w["snow"]) > 0.0 or float(w["overcast"]) >= 0.5)


func test_the_key_turns_with_the_day() -> void:
	var a := WarIntelInk.cache_key(state, 0)
	state.day += 1
	assert_ne(WarIntelInk.cache_key(state, 0), a)


func test_the_key_turns_with_land_and_letters_too() -> void:
	var a := WarIntelInk.cache_key(state, 0)
	state.manor_owner["1"] = "someone"
	var b := WarIntelInk.cache_key(state, 0)
	assert_ne(b, a, "a manor changing hands can move a supply road")
	state.next_missive_id += 1
	assert_ne(WarIntelInk.cache_key(state, 0), b, "a letter replaced at the column's cap")


func test_a_spy_ring_names_its_source() -> void:
	var s := _sheet_of_first_regiment()
	var at: Vector2 = (s["cell"] as Rect2).get_center()
	MissiveLog.add(repo, state, MissiveLog.make("spy", "rumour", state.absolute_day(),
		MissiveLog.subject("point", "", -1, at), "A report", [MissiveLog.span("people", "People", 2800, 3200)]))
	var ink := WarIntelInk.strokes(repo, state, s, 1024)
	assert_string_contains(String(ink["spies"][0]["text"]).to_lower(), "rumour")


func test_a_known_hazard_is_hatched_and_named_and_an_unknown_is_not() -> void:
	var codes: Array = state.regiments.keys()
	codes.sort()
	var home := ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, String(codes[0])))
	var s: Dictionary = WarSheets.series(repo)[WarSheets.sheet_of(repo, home)]
	var r: Rect2 = s["rect"]
	var cells: Array = []
	for c: int in repo.cells:
		if not MapTerrain.is_water(repo.cells[c]) and r.has_point(MapTerrain.cell_center(repo, repo.cells[c])):
			cells.append(c)
		if cells.size() >= 3:
			break
	Hazards.add(state, "hz", "Flood", "Sheet Flood", cells, state.tick, state.tick + 2, "test")
	var ink := WarIntelInk.strokes(repo, state, s, int(repo.bal("war_intel_texture_px")))
	var mine: Array = (ink["hazards"] as Array).filter(func(h: Dictionary) -> bool: return String(h["text"]).begins_with("Sheet Flood"))
	assert_eq(mine.size(), 1)
	assert_gt((mine[0]["lines"] as Array).size(), 0, "hatched")
	assert_gt((mine[0]["edges"] as Array).size(), 0, "outlined")
	assert_eq(String(mine[0]["ink"]), "water")
	var before := WarIntelInk.cache_key(state, int(s["index"]))
	Hazards.end_now(state, "hz")
	assert_ne(WarIntelInk.cache_key(state, int(s["index"])), before, "an ending redraws the layer")


func test_a_hazards_name_sits_inside_one_of_its_cells_and_on_the_sheet() -> void:
	var codes: Array = state.regiments.keys()
	codes.sort()
	var home := ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, String(codes[0])))
	var s: Dictionary = WarSheets.series(repo)[WarSheets.sheet_of(repo, home)]
	var r: Rect2 = s["rect"]
	# two land cells at opposite corners of the sheet: their mean lies between them, in neither
	var land: Array = []
	for c: int in repo.cells:
		if not MapTerrain.is_water(repo.cells[c]) and r.has_point(MapTerrain.cell_center(repo, repo.cells[c])):
			land.append(c)
	land.sort_custom(func(a: int, b: int) -> bool:
		var pa := MapTerrain.cell_center(repo, repo.cells[a])
		var pb := MapTerrain.cell_center(repo, repo.cells[b])
		return pa.x + pa.y < pb.x + pb.y)
	var cells: Array = [land[0], land[land.size() - 1]]
	Hazards.add(state, "hz", "Rebels", "Split Rebels", cells, state.tick, state.tick + 2, "test")
	Intel.dev_all = true
	var w := int(repo.bal("war_intel_texture_px"))
	var ink := WarIntelInk.strokes(repo, state, s, w)
	Intel.dev_all = false
	var mine: Array = (ink["hazards"] as Array).filter(func(h: Dictionary) -> bool: return String(h["text"]).begins_with("Split Rebels"))
	var at: Vector2 = mine[0]["at"]
	var k := float(w) / r.size.x
	var inside := false
	for c: int in cells:
		var poly := PackedVector2Array()
		for v in (repo.cells[c]["vertex_ids"] as PackedInt32Array):
			poly.append(((repo.vertices[v] as Vector2) - r.position) * k)
		inside = inside or Geometry2D.is_point_in_polygon(at, poly)
	assert_true(inside, "the name sits in one of the hazard's own cells")
	var px := repo.bal("war_intel_hazard_label_px")
	assert_true(at.x >= px * 4.0 - 0.01 and at.x <= r.size.x * k - px * 4.0 + 0.01, "the name stays on the sheet across")
	assert_true(at.y >= px * 1.5 - 0.01 and at.y <= r.size.y * k - px * 1.5 + 0.01, "and down")


func test_plague_dots_are_staggered_row_by_row() -> void:
	var sq := PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)])
	var dots := WarIntelInk.hatch_dots([sq], "plague", 10.0)
	var rows: Dictionary = {}
	for p: Vector2 in dots:
		rows[int(roundf(p.y))] = fposmod(p.x, 10.0)
	var ys: Array = rows.keys()
	ys.sort()
	assert_gt(ys.size(), 3)
	assert_almost_eq(absf(float(rows[ys[0]]) - float(rows[ys[1]])), 5.0, 0.01, "each row sits half a step over from the last")
