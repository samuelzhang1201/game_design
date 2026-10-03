extends GutTest
## ManorBars (owner 2026-10-04: 玩家自己省内的每个manor以柱状图显示人口和财富。
## 除非玩家探查清楚非自己掌控的地区，否则不显示): what the MANORS bars show.
const SuiteData := preload("res://tests/suite_data.gd")

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()
	Intel.dev_all = false


func after_each() -> void:
	Intel.dev_all = false


## A manor of a province the crown does not control.
func _foreign_manor(s: GameState) -> int:
	var mine: Array = MapManors.controlled_provinces(repo, s)
	for prov: String in repo.world_table("political", "provinces"):
		if prov in mine:
			continue
		var cells := MapManors.manors_of_province(repo, prov, s)
		if not cells.is_empty():
			return int(cells[0])
	return -1


func test_every_manor_of_a_controlled_province_shows_exactly() -> void:
	var s := SuiteData.campaign(repo, 7)
	var rows := ManorBars.rows(repo, s)
	var want: Array = []
	for prov: String in MapManors.controlled_provinces(repo, s):
		want.append_array(MapManors.manors_of_province(repo, prov, s))
	assert_eq(rows.size(), want.size(), "one row a manor of the crown's own land, no other")
	for r: Dictionary in rows:
		assert_has(want, int(r["cell"]))
		assert_false(bool(r["estimate"]))
		var line := RealmEconomy.line_of(repo, s, int(r["cell"]))
		assert_eq(int(r["people"]), int(line["people"]))
		assert_eq(int(r["worth"]), int(line["tax"]) + int(line["strategic"]) + int(line["civil"]),
			"wealth is the month's tax and goods in gold")


func test_a_foreign_manor_shows_only_after_a_credible_report_on_it() -> void:
	var s := SuiteData.campaign(repo, 7)
	var cell := _foreign_manor(s)
	assert_gt(cell, -1)
	var cells_of := func() -> Array:
		return ManorBars.rows(repo, s).map(func(r: Dictionary) -> int: return int(r["cell"]))
	assert_does_not_have(cells_of.call(), cell, "unscouted: nothing")
	var at := Vector2.ZERO
	var subj := MissiveLog.subject("manor", MapManors.code_of(repo, cell), cell, at)
	MissiveLog.add(repo, s, MissiveLog.make("spy", "rumour", 1, subj, "rumour",
		[MissiveLog.span("people", "People", 900, 1500)]))
	assert_does_not_have(cells_of.call(), cell, "a rumour is not scouting it clearly")
	MissiveLog.add(repo, s, MissiveLog.make("spy", "credible", 2, subj, "report",
		[MissiveLog.span("people", "People", 1000, 1400), MissiveLog.span("worth", "Worth", 40, 60)]))
	var row: Dictionary = {}
	for r: Dictionary in ManorBars.rows(repo, s):
		if int(r["cell"]) == cell:
			row = r
	assert_false(row.is_empty(), "a credible report shows it")
	assert_true(bool(row["estimate"]), "as an estimate")
	assert_eq(int(row["people"]), 1200, "its middle")
	assert_eq([int(row["people_lo"]), int(row["people_hi"])], [1000, 1400])
	assert_eq(int(row["worth"]), 50)
	assert_eq(ManorBars.scale_of([row])["people"], 1400, "the scale counts an estimate's high end")


func test_a_spy_report_on_a_manor_carries_its_worth() -> void:
	var s := SuiteData.campaign(repo, 7)
	var cell := _foreign_manor(s)
	var at := MapTerrain.cell_center(repo, repo.cells[cell])
	var rep := SpySystem.report(repo, s, at, 1000, 0)
	var keys: Array = (rep["facts"] as Array).map(func(f: Dictionary) -> String: return String(f["key"]))
	assert_has(keys, "worth")
