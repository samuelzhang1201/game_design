extends GutTest
## GOVERNOR_SET and LEDGER_AUDIT (spec 2026-09-30-ledger-governors-design §3).

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

func after_each() -> void:
	RealmEconomy.forget()

func _steward() -> Character:
	return s.characters[String(s.council["steward"])]

func test_giving_a_flow_to_another_councillor() -> void:
	var other := String(s.council["chancellor"])
	var was := _steward()
	var was_opinion := was.opinion
	var req := ActionRequest.make("GOVERNOR_SET", {"flow": "workshop", "character": other})
	assert_eq(sys.validate(req, s), "")
	sys.execute(req, s)
	assert_eq(Governance.governor_of(data, s, "workshop"), other)
	assert_eq(was.opinion, was_opinion + int(data.bal("gov_passed_over_opinion")))
	assert_string_contains(String(was.opinion_log[-1]["reason"]), "war workshops")

func test_giving_it_refusals() -> void:
	assert_ne(sys.validate(ActionRequest.make("GOVERNOR_SET", {"flow": "workshop",
		"character": String(s.council["steward"])}), s), "", "he already holds it")
	assert_ne(sys.validate(ActionRequest.make("GOVERNOR_SET", {"flow": "workshop",
		"character": "you"}), s), "", "only a councillor")
	assert_ne(sys.validate(ActionRequest.make("GOVERNOR_SET", {"flow": "moat",
		"character": String(s.council["chancellor"])}), s), "", "no such flow")

func test_an_audit_catches_a_skimmer() -> void:
	var st := _steward()
	st.traits = ["venal"]
	s.metrics["lord_civil"] = 100.0
	WorkshopSystem.settle_month(data, s)
	var skimmed := int(s.skims[st.id])
	assert_gt(skimmed, 0)
	var n := s.missives.size()
	var op := st.opinion
	sys.execute(ActionRequest.make("LEDGER_AUDIT", {"flow": "workshop"}), s)
	assert_eq(s.missives.size(), n + 1)
	var m: Dictionary = s.missives[-1]
	assert_eq(String(m["kind"]), "audit")
	assert_eq(String(m["column"]), "credible")
	assert_eq(int(s.caught[st.id][0]["amount"]), skimmed)
	assert_eq(int(s.skims.get(st.id, 0)), 0, "the count starts again")
	assert_string_contains(String(s.records[st.id][0]), "Caught skimming the war workshops")
	assert_eq(st.opinion, op + int(data.bal("gov_audited_opinion")) + int(data.bal("gov_caught_opinion")))

func test_an_audit_of_an_honest_man_finds_nothing() -> void:
	var st := _steward()
	st.traits = ["honest"]
	var op := st.opinion
	sys.execute(ActionRequest.make("LEDGER_AUDIT", {"flow": "workshop"}), s)
	assert_false(s.caught.has(st.id))
	assert_eq(st.opinion, op + int(data.bal("gov_audited_opinion")))

func test_no_governor_no_audit() -> void:
	s.council.erase("steward")
	assert_ne(sys.validate(ActionRequest.make("LEDGER_AUDIT", {"flow": "workshop"}), s), "")

func test_an_audit_letter_is_no_estimate_of_a_place() -> void:
	var home := MapManors.home_province(data, s)
	var p: Dictionary = data.provinces[home]
	var subj := MissiveLog.subject("province", home, -1, Vector2(float(p["center_x"]), float(p["center_y"])))
	var before := Intel.fact(data, s, subj, "people", 1234)
	sys.execute(ActionRequest.make("LEDGER_AUDIT", {"flow": "workshop"}), s)
	assert_eq(Intel.fact(data, s, subj, "people", 1234), before)

func test_both_orders_are_catalogued_with_costs() -> void:
	for code in ["GOVERNOR_SET", "LEDGER_AUDIT"]:
		assert_true(data.actions.has(code))
		assert_true(data.order_costs.has(code))
