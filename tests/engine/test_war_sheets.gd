extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The WAR ROOM's series cut by the pack's graticule (spec 2026-10-02-war-room-v2
## §2.2): a sheet per war_sheet_deg cell with land, id "D4", a neat line and a
## collar, places written "D4 · c7 · 24°N 51°E".

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()
	WarSheets.forget()


func test_every_sheet_is_a_graticule_cell_grown_by_the_collar() -> void:
	var deg := repo.bal("war_sheet_deg")
	var collar := repo.bal("war_sheet_collar_km") * WarSheets.px_per_unit(repo)
	var all := WarSheets.series(repo)
	assert_gt(all.size(), 0)
	for s: Dictionary in all:
		var cell: Rect2 = s["cell"]
		assert_eq(cell, MapCoords.cell_rect(repo, Vector2i(int(s["col"]), int(s["row"])), deg))
		assert_eq(s["rect"], cell.grow(collar))
		assert_eq(String(s["id"]), WarSheets.id_of(int(s["col"]), int(s["row"])))


func test_ids_are_column_letters_and_row_numbers_from_the_north_west() -> void:
	assert_eq(WarSheets.id_of(0, 0), "A1")
	assert_eq(WarSheets.id_of(3, 3), "D4")
	assert_eq(WarSheets.id_of(17, 8), "R9")


func test_columns_past_z_are_lettered_like_a_ledger() -> void:
	assert_eq(WarSheets.column_letters(0), "A")
	assert_eq(WarSheets.column_letters(25), "Z")
	assert_eq(WarSheets.column_letters(26), "AA")
	assert_eq(WarSheets.column_letters(35), "AJ")
	assert_eq(WarSheets.column_letters(51), "AZ")
	assert_eq(WarSheets.column_letters(52), "BA")
	assert_eq(WarSheets.id_of(26, 0), "AA1")
	assert_eq(WarSheets.id_of(35, 17), "AJ18")


func test_only_cells_with_land_are_sheets_and_every_land_cell_is_on_one() -> void:
	var all := WarSheets.series(repo)
	var ids: Dictionary = {}
	for s: Dictionary in all:
		ids[s["id"]] = true
	assert_eq(ids.size(), all.size(), "ids are unique")
	for id: int in repo.cells:
		var cell: Dictionary = repo.cells[id]
		if MapTerrain.is_water(cell) or (cell["vertex_ids"] as PackedInt32Array).size() < 3:
			continue
		var at := MapTerrain.cell_center(repo, cell)
		var si := WarSheets.sheet_of(repo, at)
		assert_gte(si, 0, "land cell %d has a sheet" % id)
		assert_true((all[si]["rect"] as Rect2).has_point(at), "land cell %d lies on the table of its sheet" % id)


func test_a_point_belongs_to_the_cell_it_lies_in_not_a_neighbours_collar() -> void:
	for s: Dictionary in WarSheets.series(repo):
		var c: Rect2 = s["cell"]
		assert_eq(WarSheets.sheet_of(repo, c.position + Vector2(1, 1)), int(s["index"]), String(s["id"]))


func test_the_place_names_sheet_square_and_degrees() -> void:
	var s: Dictionary = WarSheets.series(repo)[0]
	var c: Rect2 = s["cell"]
	var g := MapCoords.px_per_deg(repo) * repo.bal("war_grid_deg")
	var at := c.position + Vector2(g.x * 2.5, g.y * 6.5)   # the third column, the seventh row
	var ll := MapCoords.lon_lat(repo, at)
	assert_eq(WarSheets.grid_ref(repo, s, at), "%s · c7 · %s" % [s["id"], MapCoords.format(ll)])


func test_neighbours_are_the_grid_cells_beside_it() -> void:
	var cells := {Vector2i(1, 1): 0, Vector2i(2, 1): 1, Vector2i(1, 0): 2}
	assert_eq(WarSheets.grid_neighbours(cells, Vector2i(1, 1)), {"e": 1, "n": 2})


func test_the_series_is_cut_at_ten_degrees_and_its_ids_are_unique() -> void:
	assert_eq(repo.bal("war_sheet_deg"), 10.0)
	var g := MapCoords.grid_size(repo, repo.bal("war_sheet_deg"))
	var seen: Dictionary = {}
	for s: Dictionary in WarSheets.series(repo):
		assert_lt(int(s["col"]), g.x)
		assert_lt(int(s["row"]), g.y)
		assert_false(seen.has(s["id"]), "id %s is unique" % s["id"])
		seen[s["id"]] = true
	assert_gt(g.x, 26, "the series runs past Z")
