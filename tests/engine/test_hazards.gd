extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Hazards as state (spec 2026-10-07-war-room-p2-tactical-layer §2).

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()


func test_every_zone_lists_its_cells() -> void:
	var rows: Dictionary = repo.world_table("society", "zones")
	assert_gt(rows.size(), 0)
	for code: String in rows:
		var ids := String(rows[code]["cells"]).split("|", false)
		assert_gt(ids.size(), 1, "%s lists cells, not a count" % code)
		var seen: Dictionary = {}
		var last := -1
		for s: String in ids:
			assert_true(s.is_valid_int(), code)
			var id := int(s)
			assert_true(repo.cells.has(id), "%s: cell %d" % [code, id])
			assert_false(seen.has(id), "%s repeats %d" % [code, id])
			assert_gt(id, last, "%s ascending" % code)
			seen[id] = true
			last = id


func test_every_zone_type_has_a_kind() -> void:
	for code: String in repo.world_table("society", "zones"):
		var kind := String(repo.world_table("society", "zones")[code]["type"])
		assert_true(repo.hazard_kinds.has(kind), "kind %s" % kind)
	for kind: String in repo.hazard_kinds:
		var k: Dictionary = repo.hazard_kinds[kind]
		assert_true(["plague", "unrest", "water", "rock", "none"].has(String(k["ink"])), kind)
		assert_gte(int(k["months"]), 0, kind)
