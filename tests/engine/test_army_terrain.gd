extends GutTest
## Terrain under a regiment (owner 2026-09-17, spec §4): height makes hills
## and mountains, else the cell's biome decides; walls or a citadel in the
## same cell fortify it; the modifier table is per mille and defaults to 1000.

var repo: DataRepository

func before_all() -> void:
	repo = DataRepository.load_all("res://data")

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

func test_height_makes_mountains_and_hills() -> void:
	var peak := repo.bal("manor_focus_peak_height")
	var high := repo.bal("manor_focus_high_height")
	var m := _land_cell(func(c: Dictionary) -> bool: return float(c["height"]) >= peak)
	if m >= 0:
		assert_eq(ArmySystem.terrain_of(repo, _at_cell(m)), "mountains")
	var h := _land_cell(func(c: Dictionary) -> bool: return float(c["height"]) >= high and float(c["height"]) < peak)
	assert_gte(h, 0, "the pack has hills")
	assert_eq(ArmySystem.terrain_of(repo, _at_cell(h)), "hills")

func test_low_ground_takes_its_biomes_terrain() -> void:
	var high := repo.bal("manor_focus_high_height")
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

func test_the_modifier_table() -> void:
	assert_eq(ArmySystem.terrain_factor(repo, "mountains", "cavalry", "defend", false), 700)
	assert_eq(ArmySystem.terrain_factor(repo, "mountains", "cavalry", "attack", false), 650)
	assert_eq(ArmySystem.terrain_factor(repo, "plains", "cavalry", "attack", false), 1000, "a missing row is 1000")
	assert_eq(ArmySystem.terrain_factor(repo, "plains", "infantry", "defend", true), 1300, "walls on open ground")
	assert_eq(ArmySystem.terrain_factor(repo, "jungle", "infantry", "defend", true), 800 * 1300 / 1000)
	assert_eq(ArmySystem.terrain_factor(repo, "jungle", "infantry", "attack", true), 800, "walls only help the defender")
