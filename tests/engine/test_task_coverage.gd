extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## P6.1a (spec 2026-10-16-battle-system-design §13): the four area-task kinds are
## data and the search coverage is an integer grid of cells (data/army/
## balance.csv task_cell_m = 2 000 m) with the newest day each was searched.

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()


func test_coverage_counts_unique_cells() -> void:
	var coverage: Dictionary = {}
	TaskCoverage.mark(coverage, [Vector2i(1, 2), Vector2i(1, 3)], 10)
	TaskCoverage.mark(coverage, [Vector2i(1, 2)], 11)
	assert_eq(TaskCoverage.searched_cells(coverage), 2)
	assert_eq(coverage["1:2"], 11)
	TaskCoverage.mark(coverage, [Vector2i(1, 2)], 9)
	assert_eq(coverage["1:2"], 11, "a later mark never lowers the newest day")
	assert_eq(TaskCoverage.last_searched(coverage, Vector2i(1, 3)), 10)
	assert_eq(TaskCoverage.last_searched(coverage, Vector2i(5, 5)), -1)


func test_cell_of_floors_negatives() -> void:
	assert_eq(int(repo.bal("task_cell_m")), 2000)
	assert_eq(TaskCoverage.cell_of(repo, Vector2i(0, 0)), Vector2i(0, 0))
	assert_eq(TaskCoverage.cell_of(repo, Vector2i(1999, 2000)), Vector2i(0, 1))
	assert_eq(TaskCoverage.cell_of(repo, Vector2i(-1, -2000)), Vector2i(-1, -1))


## Cell (cx, cy) has its centre at (2000 cx + 1000, 2000 cy + 1000).
func test_cells_in_circle_by_cell_centre() -> void:
	# (3000,3000) is the centre of cell (1,1); the neighbours' centres are 2000 away.
	assert_eq(TaskCoverage.cells_in_circle(repo, Vector2i(3000, 3000), 1500),
			[Vector2i(1, 1)] as Array[Vector2i])
	assert_eq(TaskCoverage.cells_in_circle(repo, Vector2i(3000, 3000), 2000),
			[Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2)] as Array[Vector2i],
			"inclusive at exactly 2000, sorted by (y, x); diagonals (2828 m) stay out")
	# Negative side: centre (-1000,-1000) is cell (-1,-1).
	assert_eq(TaskCoverage.cells_in_circle(repo, Vector2i(-1000, -1000), 0),
			[Vector2i(-1, -1)] as Array[Vector2i])


func test_task_kinds_table() -> void:
	for kind in ["search", "raid", "destroy", "siege"]:
		assert_true(repo.task_kinds.has(kind), kind)
		var row: Dictionary = repo.task_kinds[kind]
		assert_true(row["allowed_encounters"].has(row["default_encounter"]), kind)
	assert_eq(repo.task_kinds.size(), 4)
	assert_eq(repo.task_kinds["search"]["default_encounter"], "keep_distance")
	assert_true(repo.task_kinds["siege"]["needs_target"])
	assert_false(repo.task_kinds["search"]["needs_target"])
