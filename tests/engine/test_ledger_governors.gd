# tests/engine/test_ledger_governors.gd
extends GutTest
## The governor is the reporter (spec 2026-09-30-ledger-governors-design §4).

var data: DataRepository
var s: GameState
var sys: ActionSystem
var cell := -1

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	s = GameState.new_campaign(data, 42)
	sys = ActionSystem.new(data)
	RealmEconomy.forget()
	cell = int(MapManors.manors_of_province(data, MapManors.home_province(data, s), s)[0])
	MapManors.build(data, s, cell, WorkshopSystem.BUILDING, "a test workshop")
	s.metrics["lord_civil"] = 100.0
	s.metrics["strategic"] = 1000000.0
	for c in s.regiments.keys():
		s.regiments[c]["supplies"] = 0

func after_each() -> void:
	RealmEconomy.forget()

func _link(snap: Dictionary, type: String) -> Dictionary:
	for l: Dictionary in snap["links"]:
		if String(l["type"]) == type:
			return l
	return {}

func _marshal(traits: Array) -> Character:
	var m: Character = s.characters[String(s.council["marshal"])]
	m.skills["sk_admin"] = 16
	m.opinion = 50
	m.traits = traits
	m.attributes["integrity"] = 50
	return m

func test_the_ontology_stays_clean() -> void:
	assert_eq(Ledger.validate(data), [] as Array[String])

func test_an_honest_marshal_is_one_strand_with_both_sources() -> void:
	_marshal(["honest"])
	var code := String(SupplySystem.plan(data, s)[0]["code"])
	var out := _link(Ledger.snapshot(data, s, "war", {"id": "regiment:" + code}), "supplies_out")
	assert_eq(out["accounts"].size(), 1)
	assert_string_contains(String(out["accounts"][0]["source"]), "the regiment's own count")

func test_a_venal_marshal_splits_the_thread() -> void:
	var m := _marshal(["venal"])
	var row: Dictionary = SupplySystem.plan(data, s)[0]
	var out := _link(Ledger.snapshot(data, s, "war", {"id": "regiment:" + String(row["code"])}), "supplies_out")
	assert_eq(out["accounts"].size(), 2)
	assert_eq(int(out["accounts"][0]["value"]), int(row["claimed"]))
	assert_string_contains(String(out["accounts"][0]["source"]), m.display_name)
	assert_eq(int(out["accounts"][1]["value"]), int(row["delivered"]))
	assert_eq(int(out["flow"]), int(row["claimed"]), "the thread's flow is the first account's")

func test_a_fresh_audit_is_an_account_of_its_own() -> void:
	var st: Character = s.characters[String(s.council["steward"])]
	st.traits = ["venal"]
	sys.execute(ActionRequest.make("LEDGER_AUDIT", {"flow": "workshop"}), s)
	var out := _link(Ledger.snapshot(data, s, "economy", {"id": "workshop:%d" % cell}), "converts_out")
	assert_eq(out["accounts"].size(), 2, "the steward's word and the audit's figure")
	assert_string_contains(String(out["accounts"][1]["source"]), "audit")

## An audit older than gov_audit_fresh_days no longer stands as an account.
func test_a_stale_audit_is_dropped() -> void:
	var st: Character = s.characters[String(s.council["steward"])]
	st.traits = ["venal"]
	sys.execute(ActionRequest.make("LEDGER_AUDIT", {"flow": "workshop"}), s)
	var filed := s.absolute_day()
	s.tick = maxi(s.tick, 1) + 4  # 120 days on: past the 90 an audit stands
	assert_eq(s.absolute_day() - filed, 120)
	var out := _link(Ledger.snapshot(data, s, "economy", {"id": "workshop:%d" % cell}), "converts_out")
	assert_eq(out["accounts"].size(), 1, "only the steward's word")

## An honest steward's word and the audit agree: one account naming both.
func test_an_audit_that_agrees_merges_into_the_claim() -> void:
	var st: Character = s.characters[String(s.council["steward"])]
	st.traits = ["honest"]
	sys.execute(ActionRequest.make("LEDGER_AUDIT", {"flow": "workshop"}), s)
	var out := _link(Ledger.snapshot(data, s, "economy", {"id": "workshop:%d" % cell}), "converts_out")
	assert_eq(out["accounts"].size(), 1)
	assert_string_contains(String(out["accounts"][0]["source"]), st.display_name)
	assert_string_contains(String(out["accounts"][0]["source"]), "; the audit of ")

func test_skims_are_drawn_only_once_caught() -> void:
	var st: Character = s.characters[String(s.council["steward"])]
	st.traits = ["venal"]
	WorkshopSystem.settle_month(data, s)
	var ego := {"id": "character:" + st.id}
	assert_true(_link(Ledger.snapshot(data, s, "all", ego), "skims").is_empty())
	sys.execute(ActionRequest.make("LEDGER_AUDIT", {"flow": "workshop"}), s)
	var skims := _link(Ledger.snapshot(data, s, "all", ego), "skims")
	assert_eq(int(skims["flow"]), int(s.caught[st.id][0]["amount"]))

func test_the_governor_is_drawn() -> void:
	var st := String(s.council["steward"])
	var gov := _link(Ledger.snapshot(data, s, "economy", {"id": "workshop:%d" % cell}), "governs")
	assert_eq(String(gov["from"]), "character:" + st)

func test_a_given_flow_draws_its_new_governor() -> void:
	var m := String(s.council["marshal"])
	sys.execute(ActionRequest.make("GOVERNOR_SET", {"flow": "workshop", "character": m}), s)
	var gov := _link(Ledger.snapshot(data, s, "economy", {"id": "workshop:%d" % cell}), "governs")
	assert_eq(String(gov["from"]), "character:" + m)

func test_the_thread_offers_the_audit_and_every_other_councillor() -> void:
	var rows := Ledger.actions_for(data, "converts_out|workshop:%d|type:strategic_goods" % cell, s)
	var codes: Array = rows.map(func(a: Dictionary) -> String: return String(a["code"]))
	assert_has(codes, "LEDGER_AUDIT")
	var gives: Array = rows.filter(func(a: Dictionary) -> bool: return String(a["code"]) == "GOVERNOR_SET")
	assert_eq(gives.size(), s.council.size() - 1, "every councillor but the steward")
	assert_string_contains(String(gives[0]["label"]), "Give it to ")

func test_a_give_row_reads_and_runs() -> void:
	var id := "converts_out|workshop:%d|type:strategic_goods" % cell
	var give: Dictionary = Ledger.actions_for(data, id, s).filter(
		func(a: Dictionary) -> bool: return String(a["code"]) == "GOVERNOR_SET")[0]
	var params := Ledger.params_of(give, id)
	var who: Character = s.characters[String(params["character"])]
	assert_eq(Ledger.order_text(data, give, id), "Give it to %s  (2 gold)" % who.display_name)
	assert_eq(String(params["flow"]), "workshop")
	assert_true(bool(sys.execute(ActionRequest.make("GOVERNOR_SET", params), s)["ok"]))
	assert_eq(Governance.governor_of(data, s, "workshop"), who.id)

func test_without_a_state_no_give_row_is_offered() -> void:
	var rows := Ledger.actions_for(data, "converts_out|workshop:%d|type:strategic_goods" % cell)
	for a: Dictionary in rows:
		assert_ne(String(a["code"]), "GOVERNOR_SET")

func test_a_characters_card_carries_his_record() -> void:
	var st: Character = s.characters[String(s.council["steward"])]
	s.records[st.id] = ["Caught skimming the war workshops, spring of year 1 (5 gold)"]
	var e := LedgerCards.entry(data, s, "character:" + st.id, Ledger.snapshot(data, s, "court", {}))
	assert_has(e["lines"], "Caught skimming the war workshops, spring of year 1 (5 gold)")
