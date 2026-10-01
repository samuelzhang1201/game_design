# tests/engine/test_ledger_cards.gd
extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## A sphere's fact card, a thread's card and Show on map (spec §6.1).

var data: DataRepository
var s: GameState

func before_each() -> void:
	data = SuiteData.repo()
	s = SuiteData.campaign(data, 42)
	RealmEconomy.forget()

func after_each() -> void:
	RealmEconomy.forget()

func test_a_thing_the_map_knows_opens_the_maps_own_card() -> void:
	var home := MapManors.home_province(data, s)
	var cell := int(MapManors.manors_of_province(data, home, s)[0])
	var e := LedgerCards.entry(data, s, "manor:%d" % cell, {})
	assert_eq(e["obj"], {"kind": "manor", "cell": cell})
	var reg: Dictionary = MapObjects.regiments_of(data, data.resolve_realm("player_realm"))[0]
	assert_eq(LedgerCards.entry(data, s, "regiment:" + String(reg["regiment_code"]), {})["obj"]["kind"], "army")

func test_a_type_card_lists_its_threads_with_their_sources() -> void:
	var snap := Ledger.snapshot(data, s, "economy", {})
	var e := LedgerCards.entry(data, s, "type:civil_goods", snap)
	assert_eq(String(e["title"]), "Civil goods")
	var joined := "\n".join(e["lines"])
	assert_string_contains(joined, "own records")
	assert_false(joined.contains("%"), "no numeric credibility")

func test_a_type_not_yet_built_says_so() -> void:
	var e := LedgerCards.entry(data, s, "type:faction", Ledger.snapshot(data, s, "all", {}))
	assert_string_contains("\n".join(e["lines"]), "Not yet built (PRD Step 5)")

func test_a_thread_card_names_its_governor() -> void:
	var chancellor := String(s.council.get("chancellor", ""))
	assert_ne(chancellor, "", "a fresh reign fills the chancellor's seat")
	var snap := Ledger.snapshot(data, s, "economy", {})
	var taxed: Dictionary = {}
	for l: Dictionary in snap["links"]:
		if String(l["type"]) == "taxed":
			taxed = l
	assert_false(taxed.is_empty(), "the economy lens draws the tax thread")
	assert_eq(String(taxed["governor"]), chancellor)
	var e := LedgerCards.thread_entry(data, s, taxed)
	assert_eq(String(e["title"]), "Manors pays tax Gold")
	assert_has(e["lines"], "Governed by " + (s.characters[chancellor] as Character).display_name)

## Final fix I3: a thread not yet built names the milestone that lights it.
func test_a_planned_thread_names_its_milestone() -> void:
	for l: Dictionary in Ledger.snapshot(data, s, "all", {})["links"]:
		if String(l["type"]) == "faction_governs":
			var e := LedgerCards.thread_entry(data, s, l)
			assert_has(e["lines"], "Not yet built (PRD Step 5): lit when factions exist")
			return
	fail_test("the all lens draws the planned faction_governs thread")

func test_show_on_map_has_a_place_for_places_only() -> void:
	var home := MapManors.home_province(data, s)
	var subj := LedgerCards.subject_of(data, s, "province:" + home)
	assert_eq(String(subj["kind"]), "province")
	assert_eq(float(subj["x"]), float(roundi(float(data.provinces[home]["center_x"]))))
	assert_true(LedgerCards.subject_of(data, s, "type:gold").is_empty())
	assert_true(LedgerCards.subject_of(data, s, "character:you").is_empty())


## Final review I2: what a province folds reaches its card — counted in the
## types' own names, one or many — and a merged thread names how many it
## stands for, on the province's card and on its own.
func test_a_provinces_card_names_what_it_folds() -> void:
	var g := Ledger.galaxy(data, s, {})
	var home := MapManors.home_province(data, s)
	var folded := {}
	for n: Dictionary in g["nodes"]:
		if String(n["id"]) == "province:" + home:
			folded = n.get("folded", {})
	assert_gt(int(folded.get("manor", 0)), 1, "the home province folds its manors")
	var e := LedgerCards.entry(data, s, "province:" + home, g)
	var line := String((e["lines"] as Array).filter(func(t: String) -> bool: return t.begins_with("Folds "))[0])
	assert_string_contains(line, "%d manors" % int(folded["manor"]))
	var one := LedgerCards.entry(data, s, "province:x",
		{"nodes": [{"id": "province:x", "folded": {"town": 1, "manor": 3}}], "links": []})
	assert_has(one["lines"], "Folds 3 manors, 1 town", "in the types' order, one named as one")
	assert_false("\n".join(LedgerCards.entry(data, s, "province:" + home, {})["lines"]).contains("Folds"),
		"a snapshot with nothing folded says nothing of it")


func test_a_merged_thread_names_how_many_it_stands_for() -> void:
	var g := Ledger.galaxy(data, s, {})
	var home := "province:" + MapManors.home_province(data, s)
	var merged := {}
	for l: Dictionary in g["links"]:
		if int(l.get("count", 1)) > 1 and String(l["from"]) == home:
			merged = l
			break
	assert_false(merged.is_empty(), "the home province carries a merged thread")
	var row := Ledger.link_row(data, String(merged["type"]))
	var label := String(Ledger.type_row(data, String(row["from_type"]))["label"]).to_lower()
	var prefix := "%d %s: " % [int(merged["count"]), label]
	var lines: Array = LedgerCards.entry(data, s, home, g)["lines"]
	assert_true(lines.any(func(t: String) -> bool: return t.begins_with(prefix + String(merged["verb"]))),
		"the province's card: " + prefix)
	assert_true(String(LedgerCards.thread_entry(data, s, merged)["title"]).begins_with(prefix), "the thread's own card")
