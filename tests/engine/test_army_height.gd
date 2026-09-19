extends GutTest
## Height in war (owner 2026-09-19, spec 2026-09-19-map3d-heights-design §2):
## the higher side of a fight gains, the lower loses by as much; a regiment
## uses supplies by its cell's height tier.

var repo: DataRepository

func before_all() -> void:
	repo = DataRepository.load_all("res://data")

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
	var base := ArmySystem.headcount(repo, _at_cell(low)) * 100 / 1000
	assert_eq(ArmySystem.supply_use(repo, _at_cell(low)), base)
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
	# Two copies of one regiment on different ground: the odds of A on B
	# and of B on A sum to 1 when their powers are equal, and the higher
	# one's odds are above one half.
	var s := GameState.new_campaign(repo, 7)
	var mine := MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"))
	var land: Array = mine.filter(func(r: Dictionary) -> bool: return String(r.get("is_naval", "0")) != "1")
	assert_gte(land.size(), 2)
	var a := String(land[0]["regiment_code"])
	var b := String(land[1]["regiment_code"])
	var ea := ArmySystem.elevation_of(repo, ArmySystem.regiment(repo, a))
	var eb := ArmySystem.elevation_of(repo, ArmySystem.regiment(repo, b))
	var pa := ArmySystem.power(repo, s, a, "attack")
	var pd := ArmySystem.power(repo, s, b, "defend")
	var fa := ArmySystem.height_factor(repo, ea - eb)
	var fd := ArmySystem.height_factor(repo, eb - ea)
	var expected := float(pa * fa / 1000) / float(pa * fa / 1000 + pd * fd / 1000)
	assert_almost_eq(ArmySystem.battle_odds(repo, s, a, b), expected, 0.0001)
