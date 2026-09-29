# tests/engine/test_ledger_cards.gd
extends GutTest
## A sphere's fact card, a thread's card and Show on map (spec §6.1).

var data: DataRepository
var s: GameState

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	s = GameState.new_campaign(data, 42)
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
	var e := LedgerCards.entry(data, s, "type:market", Ledger.snapshot(data, s, "economy", {}))
	assert_string_contains("\n".join(e["lines"]), "Not yet built (M6)")

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
	for l: Dictionary in Ledger.snapshot(data, s, "economy", {})["links"]:
		if String(l["type"]) == "trades":
			var e := LedgerCards.thread_entry(data, s, l)
			assert_has(e["lines"], "Not yet built (M6): lit by markets and trade routes")
			return
	fail_test("the economy lens draws the planned trades thread")

func test_show_on_map_has_a_place_for_places_only() -> void:
	var home := MapManors.home_province(data, s)
	var subj := LedgerCards.subject_of(data, s, "province:" + home)
	assert_eq(String(subj["kind"]), "province")
	assert_eq(float(subj["x"]), float(roundi(float(data.provinces[home]["center_x"]))))
	assert_true(LedgerCards.subject_of(data, s, "type:gold").is_empty())
	assert_true(LedgerCards.subject_of(data, s, "character:you").is_empty())
