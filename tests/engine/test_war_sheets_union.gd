extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Up to four held cells laid as ONE sheet (owner 2026-10-12, item 7; R11
## owner-approved): WarSheets.union, and the pieces split by it.

var repo: DataRepository
var state: GameState


func before_each() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 42)
	WarSheets.forget()


## Sheet index at (col, row), -1 none.
func _at(col: int, row: int) -> int:
	for s: Dictionary in WarSheets.series(repo):
		if int(s["col"]) == col and int(s["row"]) == row:
			return int(s["index"])
	return -1


## Two sheets side by side, west first ([] when the pack has none).
func _pair() -> Array:
	if _at(3, 4) >= 0 and _at(4, 4) >= 0:
		return [_at(3, 4), _at(4, 4)]
	for s: Dictionary in WarSheets.series(repo):
		var e := _at(int(s["col"]) + 1, int(s["row"]))
		if e >= 0:
			return [int(s["index"]), e]
	return []


func test_one_cell_union_is_todays_sheet() -> void:
	var all := WarSheets.series(repo)
	for i in [0, int(all.size() / 2.0), all.size() - 1]:
		var s: Dictionary = all[i]
		var u := WarSheets.union(repo, [i])
		assert_eq(u["rect"], s["rect"], "the same rect")
		assert_eq(u["cell"], s["cell"], "the same neat line")
		assert_eq(u["id"], s["id"])
		assert_eq(u["name"], s["name"])
		assert_eq(int(u["index"]), i)
		assert_eq([int(u["cols"]), int(u["rows"])], [1, 1])
		assert_eq(u["key"], str(i), "keyed on the sheet alone")
		assert_eq(u["indices"], [i])


## (3,4) + (4,4): the neat lines merged (two cells across, one down), grown by
## war_sheet_collar_km x px_per_unit on every side.
func test_union_rect() -> void:
	var p := _pair()
	assert_eq(p.size(), 2, "the pack has two sheets side by side")
	var all := WarSheets.series(repo)
	var a: Dictionary = all[p[0]]
	var b: Dictionary = all[p[1]]
	var u := WarSheets.union(repo, [p[1], p[0]])
	var s := MapCoords.px_per_deg(repo) * repo.bal("war_sheet_deg")   # one cell, pack px
	var collar := repo.bal("war_sheet_collar_km") * WarSheets.px_per_unit(repo)
	var want_cell := Rect2(Vector2(float(a["col"]) * s.x, float(a["row"]) * s.y), Vector2(2.0 * s.x, s.y))
	assert_almost_eq((u["cell"] as Rect2).position.x, want_cell.position.x, 0.01)
	assert_almost_eq((u["cell"] as Rect2).size.x, want_cell.size.x, 0.01)
	assert_almost_eq((u["cell"] as Rect2).size.y, want_cell.size.y, 0.01)
	assert_eq(u["cell"], (a["cell"] as Rect2).merge(b["cell"]))
	assert_almost_eq((u["rect"] as Rect2).size.x, 2.0 * s.x + 2.0 * collar, 0.01)
	assert_almost_eq((u["rect"] as Rect2).size.y, s.y + 2.0 * collar, 0.01)
	assert_eq([int(u["col"]), int(u["row"]), int(u["cols"]), int(u["rows"])], [int(a["col"]), int(a["row"]), 2, 1])
	assert_eq(u["key"], "%d+%d" % [p[0], p[1]], "sorted, whatever order the markers went out")
	assert_eq(u["id"], "%s–%s" % [a["id"], b["id"]])
	assert_eq(u["name"], b["name"], "named after the first index given")


func test_a_diagonal_pair_spans_its_whole_box() -> void:
	for s: Dictionary in WarSheets.series(repo):
		var d := _at(int(s["col"]) + 1, int(s["row"]) + 1)
		if d < 0:
			continue
		var u := WarSheets.union(repo, [int(s["index"]), d])
		assert_eq([int(u["cols"]), int(u["rows"])], [2, 2], "four cells of box, sea or land")
		return
	pass_test("no diagonal pair in this pack")


func test_no_sheet_no_union() -> void:
	assert_eq(WarSheets.union(repo, []), {})
	assert_eq(WarSheets.union(repo, [-1, 99999]), {})


## The pieces split by a one-cell union as by its index; a union holds what
## either cell holds.
func test_the_pieces_split_by_a_union() -> void:
	var p := _pair()
	for i: int in p:
		assert_eq(WarRoom.partition(repo, state, WarSheets.union(repo, [i])), WarRoom.partition(repo, state, i))
	var both := WarRoom.on_sheet(repo, state, WarSheets.union(repo, p)).map(func(q: Dictionary) -> String: return String(q["code"]))
	for i: int in p:
		for q: Dictionary in WarRoom.on_sheet(repo, state, i):
			assert_true(String(q["code"]) in both, "%s stands on the union" % q["code"])
