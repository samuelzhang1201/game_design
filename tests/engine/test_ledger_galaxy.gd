# tests/engine/test_ledger_galaxy.gd
extends GutTest
## The realm as one galaxy (spec 2026-09-30-ledger-galaxy-design §3): every
## instance once, in its cluster; the economy counted by province.

var data: DataRepository
var s: GameState


func before_each() -> void:
	data = DataRepository.load_all("res://data")
	s = GameState.new_campaign(data, 42)
	RealmEconomy.forget()


func after_each() -> void:
	Intel.dev_all = false
	RealmEconomy.forget()


func _nodes(g: Dictionary) -> Dictionary:
	var out := {}
	for n: Dictionary in g["nodes"]:
		out[String(n["id"])] = n
	return out


func _links_of_type(g: Dictionary, t: String) -> Array:
	return (g["links"] as Array).filter(func(l: Dictionary) -> bool: return String(l["type"]) == t)


func test_every_listed_instance_stands_once_in_its_cluster() -> void:
	var g := Ledger.galaxy(data, s, {})
	var nodes := _nodes(g)
	assert_eq(nodes.size(), (g["nodes"] as Array).size(), "no star twice")
	for cid: String in s.characters:
		assert_eq(String(nodes["character:" + cid]["cluster"]), "court")
	for code: String in s.regiments:
		if nodes.has("regiment:" + code):
			assert_eq(String(nodes["regiment:" + code]["cluster"]), "war")
	assert_true(nodes.has("type:gold") and nodes.has("type:civil_goods"), "the pools stand as one star each")
	assert_eq(String(nodes["type:enemy_host"]["status"]), "planned", "a planned type is a ghost")


func test_no_manor_town_or_building_stands_unless_its_province_is_opened() -> void:
	var g := Ledger.galaxy(data, s, {})
	for n: Dictionary in g["nodes"]:
		assert_false(String(n["type"]) in ["manor", "town", "building"], String(n["id"]))
	var home := MapManors.home_province(data, s)
	var folded: Dictionary = _nodes(g)["province:" + home].get("folded", {})
	assert_eq(int(folded.get("manor", 0)), MapManors.manors_of_province(data, home, s).size(),
		"the home province folds every one of its manors")


func test_opening_a_province_shows_exactly_its_manors() -> void:
	var home := MapManors.home_province(data, s)
	var g := Ledger.galaxy(data, s, {home: true})
	var manors: Array = (g["nodes"] as Array).filter(func(n: Dictionary) -> bool:
		return String(n["type"]) == "manor")
	assert_eq(manors.size(), MapManors.manors_of_province(data, home, s).size())
	for n: Dictionary in manors:
		var cell := int(String(n["id"]).get_slice(":", 1))
		assert_eq(MapManors.province_of(data, cell, s), home)
		assert_eq(String(n["home_id"]), "province:" + home, "it settles round its province")


func test_a_merged_link_counts_what_it_stands_for() -> void:
	var g := Ledger.galaxy(data, s, {})
	var holds := _links_of_type(g, "holds")
	assert_false(holds.is_empty())
	for l: Dictionary in holds:
		var family := String(l["from"]).substr(6)
		var province := String(l["to"]).substr(9)
		var want := 0
		for cell: int in MapManors.manors_of_house(data, s, family):
			if MapManors.province_of(data, cell, s) == province:
				want += 1
		assert_eq(int(l["count"]), want, String(l["id"]))


func test_no_link_joins_a_star_to_itself() -> void:
	var g := Ledger.galaxy(data, s, {})
	for l: Dictionary in g["links"]:
		assert_ne(String(l["from"]), String(l["to"]), String(l["id"]))


func test_flows_merge_only_within_one_level() -> void:
	var g := Ledger.galaxy(data, s, {})
	var home := MapManors.home_province(data, s)
	for l: Dictionary in _links_of_type(g, "yields_civil"):
		var code := String(l["from"]).substr(9)
		if code == home:
			var want := 0
			for cell: int in MapManors.manors_of_province(data, home, s):
				want += int(RealmEconomy.line_of(data, s, cell)["civil"])
			assert_eq(int(l["flow"]), want, "the controlled province's civil yield is the sum of its manors'")
			assert_eq(String((l["accounts"] as Array)[0]["level"]), "full")
		elif String((l["accounts"] as Array)[0]["level"]) != "full":
			assert_null(l["flow"], "a province known in words sums to words, never a number")


func test_an_annexed_manor_folds_into_its_new_province() -> void:
	var home := MapManors.home_province(data, s)
	var cell := -1
	var to := ""
	for c: int in data.manors.keys():
		var t := MapManors.annex_target(data, s, c)
		if t != "" and MapManors.province_of(data, c, s) != t:
			cell = c
			to = t
			break
	assert_ne(cell, -1, "the pack has a manor that can be annexed")
	assert_true(MapManors.annex(data, s, cell, to, "test: annexed"))
	var g := Ledger.galaxy(data, s, {to: true})
	assert_true(_nodes(g).has("manor:%d" % cell), "opened, the annexed manor stands in its new province")
	assert_eq(String(_nodes(g)["manor:%d" % cell]["home_id"]), "province:" + to)


func test_every_unfolded_ego_link_is_in_the_galaxy() -> void:
	var g := Ledger.galaxy(data, s, {})
	var ids := {}
	for l: Dictionary in g["links"]:
		ids[String(l["id"])] = true
	var nodes := _nodes(g)
	for id: String in ["regiment:" + String(s.regiments.keys()[0]), "character:you",
			"province:" + MapManors.home_province(data, s)]:
		for lens: String in ["economy", "war", "court", "intelligence"]:
			var ego := Ledger.snapshot(data, s, lens, {"id": id})
			for l: Dictionary in ego["links"]:
				if nodes.has(String(l["from"])) and nodes.has(String(l["to"])) \
						and String(l["status"]) == "live":
					assert_true(ids.has(String(l["id"])), "%s in the galaxy" % l["id"])


func test_the_house_index_gives_the_scans_manors() -> void:
	LedgerResolvers.begin_memo()
	for fam: String in [(s.characters["you"] as Character).family_name,
			MapObjects.house_name_of(data, MapManors.home_province(data, s))]:
		assert_eq(LedgerResolvers._manors_of_house(data, s, fam), MapManors.manors_of_house(data, s, fam), fam)
	LedgerResolvers.end_memo()


func test_the_galaxy_is_read_within_its_budget() -> void:
	var engine := TickEngine.new(data)
	for m in 6:
		for d in 29:
			engine.advance_day(s)
		engine.advance(s)
	Ledger.galaxy(data, s, {})  # warm the economy's caches
	var t0 := Time.get_ticks_usec()
	var g := Ledger.galaxy(data, s, {})
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	gut.p("galaxy: %d stars, %d links, %.1f ms" % [(g["nodes"] as Array).size(), (g["links"] as Array).size(), ms])
	assert_lt(ms, 60.0, "spec §3 budget")
