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


func test_a_new_reign_seeds_every_zone_with_its_end() -> void:
	var state := SuiteData.campaign(repo, 42)
	assert_true(state.hazards_seeded)
	for code: String in repo.world_table("society", "zones"):
		var row: Dictionary = repo.world_table("society", "zones")[code]
		var k := Hazards.kind_of(repo, String(row["type"]))
		assert_true(state.hazards.has(code), code)
		var h: Dictionary = state.hazards[code]
		assert_eq(int(h["start"]), 0)
		assert_eq(int(h["end"]), int(k["months"]) if int(k["months"]) > 0 else -1, code)
		assert_eq(h["cells"].size(), String(row["cells"]).split("|", false).size())


func test_the_hazards_survive_the_save() -> void:
	var state := SuiteData.campaign(repo, 42)
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	assert_eq(back.hazards, state.hazards)
	assert_true(back.hazards_seeded)


func test_an_old_save_is_seeded_once_at_its_own_tick() -> void:
	var state := SuiteData.campaign(repo, 42)
	var d := state.to_dict()
	d.erase("hazards")
	d.erase("hazards_seeded")
	var old := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	assert_false(old.hazards_seeded)
	assert_eq(old.hazards, {})
	old.tick = 7
	Hazards.ensure(repo, old)
	assert_true(old.hazards_seeded)
	for id: String in old.hazards:
		assert_eq(int(old.hazards[id]["start"]), 7)
	# all ended and the save re-loaded: never seeded again
	for id: String in old.hazards.keys():
		old.hazards.erase(id)
	Hazards.ensure(repo, old)
	assert_eq(old.hazards, {})


func test_a_hazard_is_active_until_its_end_and_its_ending_is_news_once() -> void:
	var state := SuiteData.campaign(repo, 42)
	Hazards.add(state, "t", "Flood", "Test Flood", [repo.cells.keys()[0]], state.tick, state.tick + 2, "test")
	assert_true(Hazards.is_active(state, "t"))
	assert_eq(Hazards.months_left(state, "t"), 2)
	state.tick += 1
	assert_eq(Hazards.settle_month(repo, state).filter(func(n: String) -> bool: return n.contains("Test Flood")), [])
	state.tick += 1
	assert_false(Hazards.is_active(state, "t"))
	var news := Hazards.settle_month(repo, state).filter(func(n: String) -> bool: return n.contains("Test Flood"))
	assert_eq(news.size(), 1)
	state.tick += 1
	assert_eq(Hazards.settle_month(repo, state).filter(func(n: String) -> bool: return n.contains("Test Flood")), [])


func test_at_cell_finds_only_the_active() -> void:
	var state := SuiteData.campaign(repo, 42)
	var cell: int = repo.cells.keys()[3]
	Hazards.add(state, "a", "Flood", "A", [cell], state.tick, -1, "test")
	Hazards.add(state, "b", "Flood", "B", [cell], state.tick, state.tick, "test")   # already over
	assert_true(Hazards.at_cell(state, cell).has("a"))
	assert_false(Hazards.at_cell(state, cell).has("b"))


func test_known_abroad_only_if_public() -> void:
	var state := SuiteData.campaign(repo, 42)
	var mine := repo.resolve_realm("player_realm")
	var foreign_cell := -1
	var home_cell := -1
	var ids: Array = repo.cells.keys()
	ids.sort()
	for c: int in ids:
		var prov := MapManors.province_of(repo, c, state)
		if prov == "":
			continue
		var owner := MapOwnership.owner_of(repo, state, prov)
		if owner == mine and home_cell < 0:
			home_cell = c
		elif owner != mine and owner != "" and foreign_cell < 0:
			foreign_cell = c
	Hazards.add(state, "r_abroad", "Rebels", "Far rebels", [foreign_cell], state.tick, -1, "test")
	Hazards.add(state, "p_abroad", "Disease", "Far plague", [foreign_cell], state.tick, -1, "test")
	Hazards.add(state, "r_home", "Rebels", "Home rebels", [home_cell], state.tick, -1, "test")
	assert_false(Hazards.known(repo, state, "r_abroad"))
	assert_true(Hazards.known(repo, state, "p_abroad"))
	assert_true(Hazards.known(repo, state, "r_home"))
