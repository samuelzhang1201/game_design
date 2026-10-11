extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Where the router really detours (owner 2026-10-12 item 5, R12): hand-built
## 9 x 5 grids of 1 km cells, a cell's slope 150 (past army_max_slope, closed),
## 20 (open) or 255 (water). Whole metres: cell (x, y) spans x*1000..x*1000+999.

var repo: DataRepository


func before_all() -> void:
	repo = SuiteData.flat_ground(SuiteData.repo())
	repo.balance["army_march_grid_px"] = 4


func after_each() -> void:
	MarchPath.forget()


func _use(walls: Array, wall: int) -> MarchPath:
	var bytes := PackedByteArray()
	bytes.resize(45)
	bytes.fill(20)
	for c: Vector2i in walls:
		bytes[c.y * 9 + c.x] = wall
	var g := MarchPath.build(repo, 9, 5, 1000, bytes)
	MarchPath.use(repo, g)
	return g


func _column(wall: int) -> MarchPath:
	return _use([Vector2i(4, 0), Vector2i(4, 1), Vector2i(4, 2), Vector2i(4, 3)], wall)


## The walk, corners included: (2500,3500) -> (5500,500) runs x + y = 6000, so it
## meets a corner at (3000,3000), (4000,2000) and (5000,1000). Past the second
## it leaves (3,2) for (4,1), the cells beside it (4,2) and (3,1) counted
## first; the third leaves (4,1) for (5,0) beside (5,1) and (4,0).
func test_cells_on_counts_the_cells_beside_a_corner() -> void:
	var g := _use([], 20)
	var cells := g.cells_on(Vector2i(2500, 3500), Vector2i(5500, 500))
	assert_eq(cells, [Vector2i(2, 3), Vector2i(3, 3), Vector2i(2, 2), Vector2i(3, 2),
		Vector2i(4, 2), Vector2i(3, 1), Vector2i(4, 1), Vector2i(5, 1), Vector2i(4, 0), Vector2i(5, 0)])
	assert_eq(g.cells_on(Vector2i(1500, 2500), Vector2i(4500, 2500)),
		[Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2)])


func test_a_line_grazing_a_closed_corner_has_the_graze_for_its_run() -> void:
	_use([Vector2i(4, 2)], 150)
	assert_eq(MarchPath.blocked_runs(repo, Vector2i(2500, 3500), [], Vector2i(5500, 500)),
		[[Vector2i(4, 2), Vector2i(4, 2)]])


func test_a_line_through_the_cell_has_it() -> void:
	_use([Vector2i(4, 2)], 150)
	assert_eq(MarchPath.blocked_runs(repo, Vector2i(1500, 2500), [], Vector2i(7500, 2500)),
		[[Vector2i(4, 2), Vector2i(4, 2)]])
	# through a waypoint on the same line: the same one run
	assert_eq(MarchPath.blocked_runs(repo, Vector2i(1500, 2500), [Vector2i(2500, 2500)], Vector2i(7500, 2500)),
		[[Vector2i(4, 2), Vector2i(4, 2)]])


func test_a_run_longer_than_one_cell_is_one_run() -> void:
	_use([Vector2i(4, 2), Vector2i(5, 2)], 150)
	assert_eq(MarchPath.blocked_runs(repo, Vector2i(1500, 2500), [], Vector2i(7500, 2500)),
		[[Vector2i(4, 2), Vector2i(5, 2)]])


func test_a_curved_leg_has_its_run_where_the_curve_crosses() -> void:
	_use([Vector2i(3, 3)], 150)
	var runs := MarchPath.blocked_runs(repo, Vector2i(1500, 2500), [Vector2i(4500, 3500)], Vector2i(7500, 2500))
	assert_eq(runs, [[Vector2i(3, 3), Vector2i(3, 3)]])


func test_adjacent_closed_cells_are_one_run() -> void:
	_use([Vector2i(4, 1), Vector2i(4, 2), Vector2i(4, 3)], 150)
	assert_eq(MarchPath.blocked_runs(repo, Vector2i(1500, 2500), [], Vector2i(7500, 2500)),
		[[Vector2i(4, 2), Vector2i(4, 2)]], "the line meets only the middle one")


func test_no_run_when_the_march_ends_on_the_wall() -> void:
	_column(150)
	assert_true(MarchPath.blocked_runs(repo, Vector2i(1500, 2500), [], Vector2i(4500, 2500)).is_empty())


func test_no_run_over_water() -> void:
	_column(MarchPath.WATER)
	assert_true(MarchPath.blocked_runs(repo, Vector2i(1500, 2500), [], Vector2i(7500, 2500)).is_empty(),
		"the router goes round water, but water is no scarp to bar")


func test_no_run_where_the_router_is_walled_in_and_walks_straight() -> void:
	_use([Vector2i(4, 0), Vector2i(4, 1), Vector2i(4, 2), Vector2i(4, 3), Vector2i(4, 4)], 150)
	assert_eq(ArmySystem.route_m_of(repo, Vector2i(1500, 2500), [], Vector2i(7500, 2500)), [Vector2i(7500, 2500)])
	assert_true(MarchPath.blocked_runs(repo, Vector2i(1500, 2500), [], Vector2i(7500, 2500)).is_empty())


func test_no_run_on_open_ground() -> void:
	_use([], 20)
	assert_true(MarchPath.blocked_runs(repo, Vector2i(1500, 2500), [], Vector2i(7500, 2500)).is_empty())
