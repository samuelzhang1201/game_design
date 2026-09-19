extends GutTest
## Elevation (owner 2026-09-19, spec 2026-09-19-map3d-heights-design §1):
## cell height into metres and supply tiers.

var repo: DataRepository

func before_all() -> void:
	repo = DataRepository.load_all("res://data")

func test_metres_from_the_cell_height() -> void:
	assert_eq(Elevation.metres_of_height(repo, 20.0), 0, "the waterline")
	assert_eq(Elevation.metres_of_height(repo, 45.0), 750)
	assert_eq(Elevation.metres_of_height(repo, 100.0), 2400)
	assert_eq(Elevation.metres_of_height(repo, 17.0), -90, "below the waterline")

func test_metres_of_a_cell_reads_its_height() -> void:
	var ids := repo.cells.keys()
	ids.sort()
	var id: int = ids[0]
	assert_eq(Elevation.metres_of_cell(repo, id),
		Elevation.metres_of_height(repo, float(repo.cells[id]["height"])))
	assert_eq(Elevation.metres_of_cell(repo, -1), 0, "no cell is the waterline")

func test_tier_edges() -> void:
	assert_eq(Elevation.tier_of(repo, 44.0)["tier"], "plains")
	assert_eq(Elevation.tier_of(repo, 45.0)["tier"], "hills")
	assert_eq(Elevation.tier_of(repo, 61.0)["tier"], "hills")
	assert_eq(Elevation.tier_of(repo, 62.0)["tier"], "mountains")
	assert_eq(Elevation.tier_of(repo, 71.0)["tier"], "mountains")
	assert_eq(Elevation.tier_of(repo, 72.0)["tier"], "peak")
	assert_eq(int(Elevation.tier_of(repo, 10.0)["supply_permille"]), 1000)
	assert_eq(int(Elevation.tier_of(repo, 50.0)["supply_permille"]), 1300)
	assert_eq(int(Elevation.tier_of(repo, 65.0)["supply_permille"]), 1700)
	assert_eq(int(Elevation.tier_of(repo, 90.0)["supply_permille"]), 2200)

func test_the_table_is_read_highest_first() -> void:
	var mins: Array = repo.army_height_supply.map(func(r: Dictionary) -> int: return int(r["min_height"]))
	assert_eq(mins, [72, 62, 45, 0])
