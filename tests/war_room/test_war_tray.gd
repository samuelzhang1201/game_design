extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The war markers' tray and the covered area (owner 2026-10-12, items 5-7): up
## to war_tray_max markers (4), one per cell, put back at will; the map covers
## the markers' cells and its zoom is the widest side of their bounding box in
## cells. Plus the barrier bars across a march where the ground is too steep.

var repo: DataRepository


func before_all() -> void:
	repo = SuiteData.repo()


func after_each() -> void:
	MarchPath.forget()


func test_the_tray_holds_the_balance_keys_count_and_a_fifth_is_refused() -> void:
	assert_eq(int(repo.bal("war_tray_max")), 4)
	var t := WarTray.of(repo)
	assert_eq(t.max_slots, 4)
	for i in 4:
		assert_eq(t.take(10 + i), i, "slot %d" % i)
	assert_true(t.full())
	assert_eq(t.take(99), -1, "a fifth cannot be taken")
	assert_eq(t.count(), 4)
	assert_eq(t.held(), [10, 11, 12, 13], "oldest first")


func test_one_cell_holds_one_marker_and_a_put_back_frees_its_slot() -> void:
	var t := WarTray.new(4)
	t.take(5)
	t.take(6)
	assert_eq(t.take(5), -1, "the cell already holds one")
	assert_true(t.put_back(5))
	assert_eq(t.slot_of(5), -1)
	assert_eq(t.take(7), 0, "the freed slot is the next taken")
	assert_eq(t.newest(), 7)
	assert_false(t.put_back(99), "no marker there")


func test_the_last_marker_out_cannot_be_put_back() -> void:
	var t := WarTray.new(4)
	t.take(3)
	assert_false(t.put_back(3))
	assert_eq(t.count(), 1)


func test_hold_takes_a_free_marker_else_moves_the_newest() -> void:
	var t := WarTray.new(2)
	assert_eq(t.hold(1), 0)
	assert_eq(t.hold(1), 0, "already held")
	assert_eq(t.hold(2), 1)
	assert_eq(t.hold(3), 1, "the tray is empty of markers: the newest moves")
	assert_eq(t.held(), [1, 3])


## A bounding box in cells; the zoom is its widest side (hand-computed).
func test_the_covered_extent_and_zoom_for_one_to_four_markers() -> void:
	var one := [Vector2i(4, 4)]
	assert_eq(WarTray.extent_cells(one), Vector2i(1, 1))
	assert_eq(WarTray.area_cells(one), 1)
	assert_eq(WarTray.zoom_factor(one), 1.0)
	var two := [Vector2i(4, 4), Vector2i(5, 4)]
	assert_eq(WarTray.extent_cells(two), Vector2i(2, 1))
	assert_eq(WarTray.area_cells(two), 2)
	assert_eq(WarTray.zoom_factor(two), 2.0)
	var three := [Vector2i(3, 5), Vector2i(1, 2), Vector2i(2, 4)]   # cols 1..3, rows 2..5
	assert_eq(WarTray.extent_cells(three), Vector2i(3, 4))
	assert_eq(WarTray.area_cells(three), 12)
	assert_eq(WarTray.zoom_factor(three), 4.0)
	var square := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
	assert_eq(WarTray.extent_cells(square), Vector2i(2, 2))
	assert_eq(WarTray.area_cells(square), 4)
	assert_eq(WarTray.zoom_factor(square), 2.0)
	var row := [Vector2i(2, 7), Vector2i(3, 7), Vector2i(4, 7), Vector2i(5, 7)]
	assert_eq(WarTray.extent_cells(row), Vector2i(4, 1))
	assert_eq(WarTray.zoom_factor(row), 4.0)
	assert_eq(WarTray.zoom_factor([]), 0.0)


func test_the_span_rect_unites_the_cells_neat_lines() -> void:
	var all := WarSheets.series(repo)
	assert_gte(all.size(), 2)
	var r := WarTray.span_rect(repo, [0, 1])
	assert_eq(r, (all[0]["cell"] as Rect2).merge(all[1]["cell"]))
	assert_eq(WarTray.span_rect(repo, [0]), all[0]["cell"])
	assert_eq(WarTray.cells_of(repo, [0]), [Vector2i(int(all[0]["col"]), int(all[0]["row"]))])


## A hand-built grid, cells of 1 km: a scarp (1.5 rise per run, past army_max_slope)
## down column 4, rows 0..3 of 9 x 5.
func _grid(wall: int) -> MarchPath:
	var bytes := PackedByteArray()
	bytes.resize(45)
	bytes.fill(20)
	for y in 4:
		bytes[y * 9 + 4] = wall
	return MarchPath.build(repo, 9, 5, 1000, bytes)


func test_one_barrier_bar_lies_across_a_march_over_a_scarp() -> void:
	repo.balance["army_march_grid_px"] = 4
	MarchPath.use(repo, _grid(150))
	var from := ArmySystem.metres_to_pack(repo, Vector2i(1500, 2500))
	var to := ArmySystem.metres_to_pack(repo, Vector2i(7500, 2500))
	var bars := WarSlopeBars.bars(repo, [from, to])
	assert_eq(bars.size(), 1, "one run of steep ground, one bar")
	# the run is cell (4, 2) alone: centre (4500, 2500) m; the march runs east, so the
	# bar runs north-south, (0.75 + 0.5) cells = 1250 m either side
	var a := ArmySystem.pack_to_metres(repo, bars[0]["a"])
	var b := ArmySystem.pack_to_metres(repo, bars[0]["b"])
	assert_almost_eq(float(a.x), 4500.0, 2.0)
	assert_almost_eq(float(b.x), 4500.0, 2.0)
	assert_almost_eq(absf(float(b.y - a.y)), 2500.0, 3.0)
	assert_eq(bars[0]["cells"], 1)
	repo.balance["army_march_grid_px"] = 0


func test_no_bar_on_open_ground_water_or_a_gentle_slope() -> void:
	repo.balance["army_march_grid_px"] = 4
	var from := ArmySystem.metres_to_pack(repo, Vector2i(1500, 2500))
	var to := ArmySystem.metres_to_pack(repo, Vector2i(7500, 2500))
	MarchPath.use(repo, _grid(MarchPath.WATER))
	assert_true(WarSlopeBars.bars(repo, [from, to]).is_empty(), "water is not a scarp")
	MarchPath.use(repo, _grid(50))
	assert_true(WarSlopeBars.bars(repo, [from, to]).is_empty(), "a gentle slope is climbed")
	repo.balance["army_march_grid_px"] = 0


func test_a_march_ending_on_the_scarp_has_no_bar_at_its_own_cell() -> void:
	repo.balance["army_march_grid_px"] = 4
	MarchPath.use(repo, _grid(150))
	var from := ArmySystem.metres_to_pack(repo, Vector2i(1500, 2500))
	var to := ArmySystem.metres_to_pack(repo, Vector2i(4500, 2500))
	assert_true(WarSlopeBars.bars(repo, [from, to]).is_empty(), "the end's own cell never blocks")
	repo.balance["army_march_grid_px"] = 0
