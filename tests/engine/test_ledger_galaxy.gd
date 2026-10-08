# tests/engine/test_ledger_galaxy.gd
extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The realm as one galaxy (spec 2026-09-30-ledger-galaxy-design §3): every
## instance once, in its cluster; the economy counted by province.

var data: DataRepository
var s: GameState


func before_each() -> void:
	data = SuiteData.repo()
	s = SuiteData.campaign(data, 42)
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


## Fix round 1, M4: the regiment→province index built per memo answers the
## same as the scan (LedgerResolvers._province_now) it replaces.
func test_the_regiment_province_index_matches_the_scan() -> void:
	LedgerResolvers.begin_memo()
	var idx := LedgerResolvers._regiment_provinces(data, s)
	LedgerResolvers.end_memo()
	for reg: Dictionary in MapObjects.regiments_of(data, data.resolve_realm("player_realm"), s):
		var code := String(reg["regiment_code"])
		assert_eq(String((idx[code] as Dictionary)["province"]), LedgerResolvers._province_now(data, s, reg), code)


## Fix round 1, M4: a manor's cached Intel subject, read within a memo,
## matches the same build made outside one.
func test_the_manor_subject_cache_matches_the_build() -> void:
	var home := MapManors.home_province(data, s)
	var cell: int = MapManors.manors_of_province(data, home, s)[0]
	LedgerResolvers.begin_memo()
	var cached := LedgerResolvers._manor_subj(data, cell)
	LedgerResolvers.end_memo()
	assert_eq(cached, LedgerResolvers._manor_subj(data, cell))


## Fix round 1, M4: Intel.level, cached within a memo, matches the same
## call made outside one.
func test_the_intel_level_cache_matches_the_call() -> void:
	var home := MapManors.home_province(data, s)
	var cell: int = MapManors.manors_of_province(data, home, s)[0]
	var subj := LedgerResolvers._manor_subj(data, cell)
	LedgerResolvers.begin_memo()
	var cached := LedgerResolvers.intel_level(data, s, subj)
	LedgerResolvers.end_memo()
	assert_eq(cached, LedgerResolvers.intel_level(data, s, subj))


## Fix round 1, IMPORTANT 2 (owner ruling): a planned row is drawn only
## when at least one of its ends is a ghost (planned) type — its own type
## sphere — and the other end is that type's pool sphere if one stands,
## else its busiest instance. `commands` and `contradicts` touch no ghost
## type and are never drawn.
func test_planned_links_touch_a_ghost_end() -> void:
	var g := Ledger.galaxy(data, s, {})
	var nodes := _nodes(g)
	var by_type := {}
	for l: Dictionary in g["links"]:
		if String(l["status"]) != "planned":
			continue
		(by_type.get_or_add(String(l["type"]), []) as Array).append(l)
		var from_ghost := String(nodes[String(l["from"])]["status"]) == "planned"
		var to_ghost := String(nodes[String(l["to"])]["status"]) == "planned"
		assert_true(from_ghost or to_ghost, "%s has a ghost end" % l["id"])
	assert_true((by_type.get("commands", []) as Array).is_empty(), "commands touches no ghost type")
	assert_true((by_type.get("contradicts", []) as Array).is_empty(), "contradicts touches no ghost type")
	var attacks: Array = by_type.get("attacks", [])
	assert_eq(attacks.size(), 1, "enemy_host has exactly one planned link")
	assert_eq(String(attacks[0]["to"]), "type:enemy_host")
	assert_true(String(attacks[0]["from"]).begins_with("regiment:"), String(attacks[0]["from"]))
	var has_workshop := false
	for id: String in nodes:
		if id.begins_with("workshop:"):
			has_workshop = true
			break
	if has_workshop:
		var governs: Array = by_type.get("faction_governs", [])
		assert_eq(governs.size(), 1, "faction governs a workshop when one stands")
		assert_eq(String(governs[0]["from"]), "type:faction")
		assert_true(String(governs[0]["to"]).begins_with("workshop:"), String(governs[0]["to"]))


## Controller ruling, fix round 1, IMPORTANT 1a: the min of three WARM
## calls (after the warm-up), so a shared machine's noise on any one call
## cannot fail the budget — it measures the code, not the machine.
func test_the_galaxy_is_read_within_its_budget() -> void:
	var engine := TickEngine.new(data)
	for d in 29:  # one played month: reports, couriers and settled stores to read
		engine.advance_day(s)
	engine.advance(s)
	Ledger.galaxy(data, s, {})  # warm the economy's caches
	var times: Array[float] = []
	var stars := 0
	var links := 0
	for i in 3:
		var t0 := Time.get_ticks_usec()
		var g := Ledger.galaxy(data, s, {})
		times.append((Time.get_ticks_usec() - t0) / 1000.0)
		stars = (g["nodes"] as Array).size()
		links = (g["links"] as Array).size()
	gut.p("galaxy: %d stars, %d links, %.1f/%.1f/%.1f ms" % [stars, links, times[0], times[1], times[2]])
	var ms: float = minf(minf(times[0], times[1]), times[2])
	# A regression tripwire at twice spec §3's 60 ms budget; the true budget
	# is measured on a quiet machine (Task 11).
	assert_lt(ms, 2.0 * 60.0, "a regression tripwire at twice spec §3's 60 ms budget; " +
		"the true budget is measured on a quiet machine (Task 11)")


## Task 11 fix round 1 (F7): the readers remembered within one read give what
## the unremembered ones give — a governor per link row, Intel's level and
## fact per subject — and two different subjects never share an answer.
func test_the_read_memos_give_what_the_readers_give() -> void:
	var truth := {}
	for r: Dictionary in data.ledger_links:
		truth[String(r["link_id"])] = Ledger._governor(data, s, r)
	var subj_a := {"kind": "province", "code": MapManors.home_province(data, s)}
	var subj_b := {"kind": "regiment", "code": String(s.regiments.keys()[0])}
	var lvl_a := Intel.level(data, s, subj_a)
	var lvl_b := Intel.level(data, s, subj_b)
	var fact_a := Intel.fact(data, s, subj_a, "people", 1234)
	LedgerResolvers.begin_memo()
	for r: Dictionary in data.ledger_links:
		assert_eq(Ledger._governor(data, s, r), truth[String(r["link_id"])], String(r["link_id"]))
		assert_eq(Ledger._governor(data, s, r), truth[String(r["link_id"])], "remembered: " + String(r["link_id"]))
	for i in 2:
		assert_eq(LedgerResolvers.intel_level(data, s, subj_a), lvl_a)
		assert_eq(LedgerResolvers.intel_level(data, s, subj_b), lvl_b)
		assert_eq(Ledger._fact(data, s, subj_a, "people", 1234), fact_a)
	LedgerResolvers.memo_subject_put("probe", subj_a, "a")
	assert_eq(LedgerResolvers.memo_subject("probe", subj_a), [true, "a"])
	assert_eq(LedgerResolvers.memo_subject("probe", subj_b), [false, null], "another subject is not found")
	LedgerResolvers.end_memo()


## Task 11 fix round 1 (F7): the opened galaxy's links carry the governor
## the unremembered reader names, row by row.
func test_the_opened_galaxys_governors_are_the_readers() -> void:
	var opened := {MapManors.home_province(data, s): true}
	var g := Ledger.galaxy(data, s, opened)
	var n := 0
	for l: Dictionary in g["links"]:
		if String(l["status"]) != "live":
			continue
		assert_eq(String(l["governor"]), Ledger._governor(data, s, Ledger.link_row(data, String(l["type"]))), String(l["id"]))
		n += 1
	assert_gt(n, 0)


## Final review minors: _merge_into on its own — a worse-level account
## brings its own words, source and level; a better one merged into words
## keeps the words and their source; two figures at one level sum.
func test_a_merge_takes_the_worse_accounts_words_and_source() -> void:
	var full := {"value": 120, "text": "120", "source": "own records", "day": 10, "level": "full"}
	var general := {"value": null, "text": "hundreds", "source": "common knowledge", "day": 7, "level": "general"}
	var m := {"count": 1, "flow": 120, "accounts": [full.duplicate()]}
	Ledger._merge_into(m, {"flow": null, "accounts": [general.duplicate()]})
	assert_eq(int(m["count"]), 2)
	assert_null(m["flow"], "words and a figure make words")
	assert_eq(m["accounts"], [{"value": null, "text": "hundreds", "source": "common knowledge", "day": 7,
		"level": "general"}], "the worse account's words travel with its source")
	var w := {"count": 1, "flow": null, "accounts": [general.duplicate()]}
	Ledger._merge_into(w, {"flow": 120, "accounts": [full.duplicate()]})
	assert_eq(w["accounts"], [{"value": null, "text": "hundreds", "source": "common knowledge", "day": 7,
		"level": "general"}], "a better account adds nothing to the words")
	var f := {"count": 1, "flow": 120, "accounts": [full.duplicate()]}
	var other := full.duplicate()
	other["source"] = "steward's report"
	other["value"] = 30
	Ledger._merge_into(f, {"flow": 30, "accounts": [other]})
	assert_eq(int(f["flow"]), 150)
	assert_eq(String(f["accounts"][0]["source"]), "own records", "a tie keeps the first source")
