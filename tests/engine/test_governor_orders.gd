extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## GOVERNOR_SET and LEDGER_AUDIT (spec 2026-09-30-ledger-governors-design §3).

var data: DataRepository
var s: GameState
var sys: ActionSystem
var cell := -1

func before_each() -> void:
	data = SuiteData.repo()
	s = SuiteData.campaign(data, 42)
	sys = ActionSystem.new(data)
	RealmEconomy.forget()
	cell = int(MapManors.manors_of_province(data, MapManors.home_province(data, s), s)[0])
	MapManors.build(data, s, cell, WorkshopSystem.BUILDING, "a test workshop")

func after_each() -> void:
	RealmEconomy.forget()

func _steward() -> Character:
	return s.characters[String(s.council["steward"])]

## A month of the supply lines banked as the marshal's month banks it: the
## first land regiment ran a line (spec 2026-10-07-army-supply-lines) that
## skimmed some units, and SupplyLines.settle_month banks the gold to its
## governor.
func _bank_a_supply_month() -> void:
	var codes: Array = s.regiments.keys()
	codes.sort()
	for c in codes:
		if String(ArmySystem.regiment(data, String(c)).get("is_naval", "0")) != "1":
			s.supply_lines[c] = SupplyLines._new_record(TownStores.realm_towns(data, s)[0], 1000, 1)
			s.supply_lines[c]["state"] = SupplyLines.FLOWING
			s.supply_lines[c]["m_skim"] = 100000
			break
	SupplyLines.settle_month(data, s)

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
	var skimmed := Governance.skimmed_on(s, st.id, "workshop")
	assert_gt(skimmed, 0)
	var n := s.missives.size()
	var op := st.opinion
	sys.execute(ActionRequest.make("LEDGER_AUDIT", {"flow": "workshop"}), s)
	assert_eq(s.missives.size(), n + 1)
	var m: Dictionary = s.missives[-1]
	assert_eq(String(m["kind"]), "audit")
	assert_eq(String(m["column"]), "truth", "the crown's own audit is ground truth (owner 2026-10-10)")
	assert_eq(int(s.caught[st.id][0]["amount"]), skimmed)
	assert_eq(Governance.skimmed_on(s, st.id, "workshop"), 0, "the count starts again")
	assert_string_contains(String(s.records[st.id][0]), "Caught skimming the war workshops")
	assert_string_contains(String(s.records[st.id][0]), "(%d gold)" % skimmed)
	assert_has(st.opinion_log, {"tick": s.tick, "delta": int(data.bal("gov_caught_opinion")),
		"reason": "caught skimming the war workshops"})
	assert_eq(st.opinion, op + int(data.bal("gov_audited_opinion")) + int(data.bal("gov_caught_opinion")))

func test_an_audit_of_an_honest_man_finds_nothing() -> void:
	var st := _steward()
	st.traits = ["honest"]
	var op := st.opinion
	var out := sys.execute(ActionRequest.make("LEDGER_AUDIT", {"flow": "workshop"}), s)
	assert_false(s.caught.has(st.id))
	assert_eq(st.opinion, op + int(data.bal("gov_audited_opinion")))
	var reasons: Array = (out["effects"] as Array).map(func(e: Dictionary) -> String: return String(e["reason"]))
	assert_has(reasons, "The books on the war workshops are in order", "M2: the audit says it found nothing")

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


# --- final review I1: the books are the FLOW's -----------------------------


## A venal marshal skims the supply gold, the lines are given to the
## chancellor, and the audit of the supply lines still catches the marshal
## — the books are the lines', whoever kept them.
func test_an_audit_catches_a_skimmer_the_flow_was_taken_from() -> void:
	var ma: Character = s.characters[String(s.council["marshal"])]
	ma.traits = ["venal"]
	var ch: Character = s.characters[String(s.council["chancellor"])]
	ch.traits = ["honest"]
	s.metrics["strategic"] = 1000000.0
	for c in s.regiments.keys():
		s.regiments[c]["supplies"] = 0
	_bank_a_supply_month()
	var skimmed := Governance.skimmed_on(s, ma.id, "supply_line")
	assert_gt(skimmed, 0)
	sys.execute(ActionRequest.make("GOVERNOR_SET", {"flow": "supply_line", "character": ch.id}), s)
	var ma_log := ma.opinion_log.size()
	var ch_log := ch.opinion_log.size()
	sys.execute(ActionRequest.make("LEDGER_AUDIT", {"flow": "supply_line"}), s)
	assert_eq(s.caught[ma.id], [{"flow": "supply_line", "day": s.absolute_day(), "amount": skimmed}])
	var caught_entry := {"tick": s.tick, "delta": int(data.bal("gov_caught_opinion")),
		"reason": "caught skimming the supply lines"}
	var audited_entry := {"tick": s.tick, "delta": int(data.bal("gov_audited_opinion")),
		"reason": "the crown's clerks went through his books on the supply lines"}
	var ma_new := ma.opinion_log.slice(ma_log)
	assert_has(ma_new, caught_entry, "caught, with its reason")
	assert_does_not_have(ma_new, audited_entry, "not audited: he no longer keeps the books")
	assert_string_contains(String(s.records[ma.id][0]), "Caught skimming the supply lines")
	assert_string_contains(String(s.records[ma.id][0]), "(%d gold)" % skimmed)
	assert_false(s.skims.has(ma.id), "his count starts again")
	assert_false(s.caught.has(ch.id), "the honest chancellor is not caught")
	var ch_new := ch.opinion_log.slice(ch_log)
	assert_has(ch_new, audited_entry, "the governor now is the one audited")
	assert_does_not_have(ch_new, {"tick": s.tick, "delta": int(data.bal("gov_caught_opinion")),
		"reason": "caught skimming the supply lines"})

## The steward holding both flows is caught per flow, each audit for its own
## flow's amount only.
func test_a_man_holding_two_flows_is_caught_per_flow() -> void:
	var st := _steward()
	st.traits = ["venal"]
	sys.execute(ActionRequest.make("GOVERNOR_SET", {"flow": "supply_line", "character": st.id}), s)
	s.metrics["lord_civil"] = 100.0
	s.metrics["strategic"] = 1000000.0
	for c in s.regiments.keys():
		s.regiments[c]["supplies"] = 0
	WorkshopSystem.settle_month(data, s)
	_bank_a_supply_month()
	var goods := Governance.skimmed_on(s, st.id, "workshop")
	var gold := Governance.skimmed_on(s, st.id, "supply_line")
	assert_gt(goods, 0)
	assert_gt(gold, 0)
	sys.execute(ActionRequest.make("LEDGER_AUDIT", {"flow": "workshop"}), s)
	assert_eq((s.caught[st.id] as Array).size(), 1)
	assert_eq(int(s.caught[st.id][0]["amount"]), goods)
	assert_eq(Governance.skimmed_on(s, st.id, "supply_line"), gold, "the supply books were not opened")
	assert_eq(Governance.skimmed_on(s, st.id, "workshop"), 0)
	sys.execute(ActionRequest.make("LEDGER_AUDIT", {"flow": "supply_line"}), s)
	assert_eq(s.caught[st.id][1], {"flow": "supply_line", "day": s.absolute_day(), "amount": gold})
	assert_false(s.skims.has(st.id))
	assert_eq((s.records[st.id] as Array).size(), 2)
	assert_string_contains(String(s.records[st.id][1]), "the supply lines")
	assert_string_contains(String(s.records[st.id][1]), "(%d gold)" % gold)

## Every skimmer on the flow is caught, in id order.
func test_an_audit_catches_every_skimmer_of_the_flow() -> void:
	var st := _steward()
	var other := String(s.council["marshal"])
	s.skims[st.id] = {"workshop": 4}
	s.skims[other] = {"workshop": 7, "supply_line": 3}
	sys.execute(ActionRequest.make("LEDGER_AUDIT", {"flow": "workshop"}), s)
	assert_eq(int(s.caught[st.id][0]["amount"]), 4)
	assert_eq(int(s.caught[other][0]["amount"]), 7)
	assert_eq(s.skims, {other: {"supply_line": 3}})

## M3: a governor id missing from the characters is refused.
func test_a_missing_character_cannot_govern_or_be_audited() -> void:
	s.council["chancellor"] = "ghost"
	assert_ne(sys.validate(ActionRequest.make("GOVERNOR_SET", {"flow": "workshop", "character": "ghost"}), s), "",
		"a seat naming no living character")
	s.council["steward"] = "ghost"
	assert_eq(Governance.governor_of(data, s, "workshop"), "", "no one governs through a ghost")
	assert_ne(sys.validate(ActionRequest.make("LEDGER_AUDIT", {"flow": "workshop"}), s), "")
