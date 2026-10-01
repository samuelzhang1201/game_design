extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Terrain under a regiment (owner 2026-09-17, spec §4): height makes hills
## and mountains, else the cell's biome decides; walls or a citadel in the
## same cell fortify it; the modifier table is per mille and defaults to 1000.

var repo: DataRepository

func before_all() -> void:
	repo = SuiteData.repo()

## A regiment dict standing at a cell's centre (the pack is generated, so the
## test finds its cells by what they are, never by id).
func _at_cell(id: int, naval: bool = false) -> Dictionary:
	var c := MapTerrain.cell_center(repo, repo.cells[id])
	return {"regiment_code": "t", "kingdom_code": "t", "x": str(c.x), "y": str(c.y),
		"is_naval": "1" if naval else "0"}

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

func test_cell_at_finds_the_cell_it_stands_in() -> void:
	var id := _land_cell(func(_c: Dictionary) -> bool: return true)
	assert_eq(MapEconomy.cell_at(repo, MapTerrain.cell_center(repo, repo.cells[id])), id)

## The cached search (land cells' polygons and centres kept per repository,
## perf 2026-10-02) answers exactly what a search building them afresh does:
## the cell whose polygon holds the point, else the nearest centre in the
## neighbouring buckets — checked over a grid of points across the pack.
func test_cell_at_agrees_with_an_uncached_search_everywhere() -> void:
	var lg := MapEconomy._land_grid(repo)
	var bucket: float = lg["bucket"]
	var grid: Dictionary = lg["grid"]
	var w := float(repo.map_info.get("width", 2560))
	var h := float(repo.map_info.get("height", 929))
	var checked := 0
	for gy in 24:
		for gx in 64:
			var p := Vector2((gx + 0.37) * w / 64.0, (gy + 0.61) * h / 24.0)
			var home := Vector2i((p / bucket).floor())
			var want := -1
			var want_d := INF
			var found := false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					for id: int in grid.get(home + Vector2i(dx, dy), []):
						if found:
							continue
						var cell: Dictionary = repo.cells[id]
						var poly := PackedVector2Array()
						for v in (cell["vertex_ids"] as PackedInt32Array):
							poly.append(repo.vertices[v] as Vector2)
						if Geometry2D.is_point_in_polygon(p, poly):
							want = id
							found = true
							continue
						var d := p.distance_squared_to(MapTerrain.cell_center(repo, cell))
						if d < want_d:
							want_d = d
							want = id
			assert_eq(MapEconomy.cell_at(repo, p), want, "cell_at at %s" % p)
			checked += 1
	assert_eq(checked, 64 * 24)

func test_height_makes_mountains_and_hills() -> void:
	var peak := float(repo.army_height_supply.filter(func(r: Dictionary) -> bool: return r["tier"] == "mountains")[0]["min_height"])
	var high := float(repo.army_height_supply.filter(func(r: Dictionary) -> bool: return r["tier"] == "hills")[0]["min_height"])
	var m := _land_cell(func(c: Dictionary) -> bool: return float(c["height"]) >= peak)
	if m >= 0:
		assert_eq(ArmySystem.terrain_of(repo, _at_cell(m)), "mountains")
	var h := _land_cell(func(c: Dictionary) -> bool: return float(c["height"]) >= high and float(c["height"]) < peak)
	assert_gte(h, 0, "the pack has hills")
	assert_eq(ArmySystem.terrain_of(repo, _at_cell(h)), "hills")

func test_low_ground_takes_its_biomes_terrain() -> void:
	var high := float(repo.army_height_supply.filter(func(r: Dictionary) -> bool: return r["tier"] == "hills")[0]["min_height"])
	var f := _land_cell(func(c: Dictionary) -> bool: return float(c["height"]) < high and int(c["biome_id"]) == 6)
	assert_gte(f, 0, "the pack has low deciduous forest")
	assert_eq(ArmySystem.terrain_of(repo, _at_cell(f)), "forest")
	assert_eq(ArmySystem.terrain_label(repo, _at_cell(f)).begins_with("Forest"), true)

func test_a_fleet_is_at_sea() -> void:
	var id := _land_cell(func(_c: Dictionary) -> bool: return true)
	assert_eq(ArmySystem.terrain_of(repo, _at_cell(id, true)), "sea")

func test_walls_in_the_cell_fortify() -> void:
	var cells := MapEconomy.burg_cells(repo)
	var walled := ""
	var codes := repo.burgs.keys()
	codes.sort()
	for code: String in codes:
		var feats := String(repo.burgs[code].get("features", "")).split("|")
		if ("walls" in feats or "citadel" in feats) and cells.has(code):
			walled = code
			break
	assert_ne(walled, "", "the pack has a walled town")
	var reg := _at_cell(int(cells[walled]))
	assert_true(ArmySystem.is_fortified(repo, reg))
	assert_string_contains(ArmySystem.terrain_label(repo, reg), "(fortified)")

func _row(key: String, stance: String) -> int:
	return int((repo.army_terrain[key] as Dictionary)[stance])

func test_the_modifier_table() -> void:
	assert_eq(ArmySystem.terrain_factor(repo, "mountains", "cavalry", "defend", false), _row("mountains|cavalry", "defend"))
	assert_eq(ArmySystem.terrain_factor(repo, "mountains", "cavalry", "attack", false), _row("mountains|cavalry", "attack"))
	assert_false(repo.army_terrain.has("plains|cavalry"))
	assert_eq(ArmySystem.terrain_factor(repo, "plains", "cavalry", "attack", false), 1000, "a missing row is 1000")
	var walls := _row("fortified|infantry", "defend")
	assert_gt(walls, 1000, "walls help")
	assert_eq(ArmySystem.terrain_factor(repo, "plains", "infantry", "defend", true), walls, "walls on open ground")
	var jungle := _row("jungle|infantry", "defend")
	@warning_ignore("integer_division")  # the formula's own whole per-mille
	assert_eq(ArmySystem.terrain_factor(repo, "jungle", "infantry", "defend", true), jungle * walls / 1000)
	assert_eq(ArmySystem.terrain_factor(repo, "jungle", "infantry", "attack", true), _row("jungle|infantry", "attack"),
		"walls only help the defender")
