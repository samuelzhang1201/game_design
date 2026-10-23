extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Height in war (owner 2026-09-19, spec 2026-09-19-map3d-heights-design §2):
## the higher side of a fight gains, the lower loses by as much; a regiment
## uses supplies by its cell's height tier.

var repo: DataRepository

func before_all() -> void:
	repo = SuiteData.repo()

func _at_cell(id: int, naval := false) -> Dictionary:
	var c := MapTerrain.cell_center(repo, repo.cells[id])
	return {"regiment_code": "t", "kingdom_code": "t", "x": str(c.x), "y": str(c.y),
		"is_naval": "1" if naval else "0", "infantry": "1000"}

func _land_cell(pred: Callable) -> int:
	var ids := repo.cells.keys()
	ids.sort()
	for id: int in ids:
		var cell: Dictionary = repo.cells[id]
		if MapTerrain.is_water(cell) or (cell["vertex_ids"] as PackedInt32Array).size() < 3:
			continue
		if pred.call(cell):
			return id
	return -1

func test_height_factor() -> void:
	assert_eq(ArmySystem.height_factor(repo, 0), 1000)
	assert_eq(ArmySystem.height_factor(repo, 500), 1200, "40 per 100 m")
	assert_eq(ArmySystem.height_factor(repo, -500), 800)
	assert_eq(ArmySystem.height_factor(repo, 1000), 1300, "capped")
	assert_eq(ArmySystem.height_factor(repo, -1000), 700, "capped")

func test_elevation_of_reads_the_cell_and_a_fleet_is_at_zero() -> void:
	var id := _land_cell(func(c: Dictionary) -> bool: return float(c["height"]) >= 50.0)
	assert_gte(id, 0)
	assert_eq(ArmySystem.elevation_of(repo, _at_cell(id)), Elevation.metres_of_cell(repo, id))
	assert_eq(ArmySystem.elevation_of(repo, _at_cell(id, true)), 0)

func test_supply_use_goes_up_by_tier() -> void:
	var low := _land_cell(func(c: Dictionary) -> bool: return float(c["height"]) < 45.0)
	var high := _land_cell(func(c: Dictionary) -> bool: return float(c["height"]) >= 62.0 and float(c["height"]) < 72.0)
	assert_gte(low, 0)
	assert_gte(high, 0, "the pack has mountains")
	@warning_ignore("integer_division")  # the formula's own whole per-mille
	var base := ArmySystem.headcount(repo, _at_cell(low)) * 100 / 1000
	assert_eq(ArmySystem.supply_use(repo, _at_cell(low)), base)
	@warning_ignore("integer_division")  # the formula's own whole per-mille
	assert_eq(ArmySystem.supply_use(repo, _at_cell(high)), base * 1700 / 1000)
	assert_eq(ArmySystem.supply_use(repo, _at_cell(high, true)), base, "a fleet is not scaled")

func test_terrain_follows_the_tier_lines() -> void:
	var h := _land_cell(func(c: Dictionary) -> bool: return float(c["height"]) >= 45.0 and float(c["height"]) < 52.0)
	assert_gte(h, 0, "the pack has ground between the old and new hill lines")
	assert_eq(ArmySystem.terrain_of(repo, _at_cell(h)), "hills")
	var p := _land_cell(func(c: Dictionary) -> bool: return float(c["height"]) >= 72.0)
	if p >= 0:
		assert_eq(ArmySystem.terrain_of(repo, _at_cell(p)), "mountains", "a peak fights as a mountain")

func test_battle_odds_swap_symmetrically_with_the_ground() -> void:
	# Two of the player's land regiments standing at DIFFERENT elevations:
	# the higher side's odds beat what they would be on equal ground (height
	# factor 1000 both ways, power alone), and the formula matches a
	# hand-checked value.
	var s := SuiteData.campaign(repo, 7)
	var mine := MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), s)
	var land: Array = mine.filter(func(r: Dictionary) -> bool: return String(r.get("is_naval", "0")) != "1")
	assert_gte(land.size(), 2)
	var a := ""
	var b := ""
	for i in land.size():
		for j in land.size():
			if i == j:
				continue
			var ca := String(land[i]["regiment_code"])
			var cb := String(land[j]["regiment_code"])
			if ArmySystem.elevation_of(repo, ArmySystem.regiment(repo, ca, s), s) \
					!= ArmySystem.elevation_of(repo, ArmySystem.regiment(repo, cb, s), s):
				a = ca
				b = cb
				break
		if a != "":
			break
	if a == "":
		pending("the pack has no two land regiments at different elevations")
		return
	var ea := ArmySystem.elevation_of(repo, ArmySystem.regiment(repo, a, s), s)
	var eb := ArmySystem.elevation_of(repo, ArmySystem.regiment(repo, b, s), s)
	assert_ne(ea, eb, "the two stand at different heights")
	var pa := ArmySystem.power(repo, s, a, "attack")
	var pd := ArmySystem.power(repo, s, b, "defend")
	var fa := ArmySystem.height_factor(repo, ea - eb)
	var fd := ArmySystem.height_factor(repo, eb - ea)
	@warning_ignore("integer_division")  # the formula's own whole per-mille
	var expected := float(pa * fa / 1000) / float(pa * fa / 1000 + pd * fd / 1000)
	var odds := ArmySystem.battle_odds(repo, s, a, b)
	assert_almost_eq(odds, expected, 0.0001, "hand-checked against the formula")
	# The spec's property: the higher side's odds beat the equal-ground
	# expectation (height_factor 1000 both ways, power only).
	var equal_ground := float(pa) / float(pa + pd) if pa + pd > 0 else 0.5
	if ea > eb:
		assert_gt(odds, equal_ground, "the higher attacker does better than on level ground")
	else:
		assert_lt(odds, equal_ground, "the lower attacker does worse than on level ground")
