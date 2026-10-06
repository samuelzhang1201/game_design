# tests/engine/test_ledger_governors.gd
extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The governor is the reporter (spec 2026-09-30-ledger-governors-design §4).

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
	s.metrics["lord_civil"] = 100.0
	s.metrics["strategic"] = 1000000.0
	for c in s.regiments.keys():
		s.regiments[c]["supplies"] = 0
	# the supply lines are the regiments' own now: the first two land
	# regiments run one each (spec 2026-10-07-army-supply-lines)
	var codes: Array = s.regiments.keys()
	codes.sort()
	var given := 0
	for c in codes:
		if given < 2 and String(ArmySystem.regiment(data, String(c)).get("is_naval", "0")) != "1":
			s.supply_lines[c] = SupplyLines._new_record(TownStores.realm_towns(data, s)[0], 1000, 1)
			s.supply_lines[c]["state"] = SupplyLines.FLOWING
			given += 1

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


## An audit is a snapshot of ITS month (fix round 1 ruling): the next month
## it no longer stands as an account.
func test_an_audit_stands_only_for_its_own_month() -> void:
	var st: Character = s.characters[String(s.council["steward"])]
	st.traits = ["venal"]
	sys.execute(ActionRequest.make("LEDGER_AUDIT", {"flow": "workshop"}), s)
	s.tick += 1
	var out := _link(Ledger.snapshot(data, s, "economy", {"id": "workshop:%d" % cell}), "converts_out")
	assert_eq(out["accounts"].size(), 1, "only the steward's word")

## The audit day: the letter's figures are the live projection (the
## opinion changes land first), so a skimming marshal's audit equals the
## regiment's own count and merges with it; the month after, it is gone.
func test_a_same_day_audit_agrees_with_the_regiments_count() -> void:
	var m := _marshal(["venal"])
	m.opinion = 0  # at gov_opinion_cooperate: the audit's -3 then costs him efficiency
	sys.execute(ActionRequest.make("LEDGER_AUDIT", {"flow": "supply_line"}), s)
	var row: Dictionary = SupplySystem.plan(data, s)[0]
	var out := _link(Ledger.snapshot(data, s, "war", {"id": "regiment:" + String(row["code"])}), "supplies_out")
	assert_eq(out["accounts"].size(), 2, "his word, and the count the audit confirms")
	assert_eq(int(out["accounts"][1]["value"]), int(row["delivered"]))
	assert_string_contains(String(out["accounts"][1]["source"]), "the regiment's own count; the audit of ")
	s.tick += 1
	out = _link(Ledger.snapshot(data, s, "war", {"id": "regiment:" + String(row["code"])}), "supplies_out")
	assert_eq(out["accounts"].size(), 2)
	assert_false(String(out["accounts"][1]["source"]).contains("audit"), "last month's audit is gone")

## An honest successor's word and the regiment's count agree: one strand.
func test_an_honest_successor_merges_the_thread() -> void:
	_marshal(["venal"])
	var heir: Character = s.characters[String(s.council["chaplain"])]
	heir.traits = ["honest"]
	sys.execute(ActionRequest.make("GOVERNOR_SET", {"flow": "supply_line", "character": heir.id}), s)
	s.tick += 1
	var code := String(SupplySystem.plan(data, s)[0]["code"])
	var out := _link(Ledger.snapshot(data, s, "war", {"id": "regiment:" + code}), "supplies_out")
	assert_eq(out["accounts"].size(), 1, "one strand")
	assert_string_contains(String(out["accounts"][0]["source"]), heir.display_name)

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
	var snap := Ledger.snapshot(data, s, "all", ego)
	var skims := _link(snap, "skims")
	assert_eq(String(skims["to"]), "type:workshop", "one link to the flow, not one per workshop")
	assert_eq(int(skims["flow"]), int(s.caught[st.id][0]["amount"]))
	assert_eq((snap["links"] as Array).filter(
		func(l: Dictionary) -> bool: return String(l["type"]) == "skims").size(), 1)
	assert_true(_link(Ledger.snapshot(data, s, "economy", {"id": "workshop:%d" % cell}), "skims").is_empty(),
		"a workshop's own ego shows no skim")

## A skim caught stays his after the flow is given away.
func test_a_caught_skim_survives_a_handover() -> void:
	var st: Character = s.characters[String(s.council["steward"])]
	st.traits = ["venal"]
	WorkshopSystem.settle_month(data, s)
	sys.execute(ActionRequest.make("LEDGER_AUDIT", {"flow": "workshop"}), s)
	sys.execute(ActionRequest.make("GOVERNOR_SET", {"flow": "workshop", "character": String(s.council["marshal"])}), s)
	var skims := _link(Ledger.snapshot(data, s, "all", {"id": "character:" + st.id}), "skims")
	assert_eq(String(skims["from"]), "character:" + st.id)
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

## Fix round 1: a governed flow's thread names the man who governs it now,
## not the seat holder; his word is under HIS OWN seat, "(given …)".
func test_a_given_flows_thread_names_its_new_governor() -> void:
	var odo: Character = s.characters[String(s.council["chaplain"])]
	sys.execute(ActionRequest.make("GOVERNOR_SET", {"flow": "supply_line", "character": odo.id}), s)
	var code := String(SupplySystem.plan(data, s)[0]["code"])
	var out := _link(Ledger.snapshot(data, s, "war", {"id": "regiment:" + code}), "supplies_out")
	assert_eq(String(out["governor"]), odo.id)
	assert_has(LedgerCards.thread_entry(data, s, out)["lines"], "Governed by " + odo.display_name)
	var chaplain := String(data.seats["chaplain"]["label"])
	assert_string_contains(String(out["accounts"][0]["source"]),
		"%s: %s (given the supply lines)" % [chaplain, odo.display_name])

func test_the_type_level_counts_the_regiments_in_the_plural() -> void:
	_marshal(["venal"])
	var out := _link(Ledger.snapshot(data, s, "war", {}), "supplies_out")
	assert_eq(String(out["accounts"][1]["source"]), "the regiments' own count")

func test_cards_say_the_accounts_differ() -> void:
	_marshal(["venal"])
	var code := String(SupplySystem.plan(data, s)[0]["code"])
	var snap := Ledger.snapshot(data, s, "war", {"id": "regiment:" + code})
	var out := _link(snap, "supplies_out")
	var lines: Array = LedgerCards.thread_entry(data, s, out)["lines"]
	assert_has(lines, "Accounts differ:")
	var card: Array = LedgerCards.entry(data, s, "supply_line:" + code, snap)["lines"]
	var line: String = card.filter(func(t: String) -> bool: return t.contains("accounts differ"))[0]
	assert_string_contains(line, Intel.num(int(out["accounts"][0]["value"])))
	assert_string_contains(line, Intel.num(int(out["accounts"][1]["value"])))

func test_the_governs_card_reads_a_percentage() -> void:
	var st: Character = s.characters[String(s.council["steward"])]
	st.skills["sk_steward"] = 8
	st.opinion = 50
	var gov := _link(Ledger.snapshot(data, s, "economy", {"id": "workshop:%d" % cell}), "governs")
	var lines: Array = LedgerCards.thread_entry(data, s, gov)["lines"]
	assert_eq(lines.filter(func(t: String) -> bool: return t.begins_with("Runs it at 85%")).size(), 1)
	for t: String in lines:
		assert_false(t.contains("‰"), "no per-mille on the card: " + t)

## The plans are memoised for ONE snapshot only (fix round 1).
func test_a_snapshot_leaves_no_plan_memo_behind() -> void:
	var code := String(SupplySystem.plan(data, s)[0]["code"])
	var a := Ledger.snapshot(data, s, "war", {"id": "supply_line:" + code})
	assert_false(LedgerResolvers.memo_active())
	s.supply_lines[code]["rate"] = 1200   # the line's month moves with its rate
	var b := Ledger.snapshot(data, s, "war", {"id": "supply_line:" + code})
	assert_ne(int(_link(a, "supplies_out")["flow"]), int(_link(b, "supplies_out")["flow"]), "read afresh")

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


# --- final review fixes ---------------------------------------------------------

## I2: an honest steward's audit, then the lord's civil goods move the same
## month — his claim moves with them, the audit no longer speaks to it and
## is dropped: one account, never a false split.
func test_an_audit_of_an_honest_man_drops_once_his_claim_moves() -> void:
	var st: Character = s.characters[String(s.council["steward"])]
	st.traits = ["honest"]
	s.metrics["lord_civil"] = 20.0
	sys.execute(ActionRequest.make("LEDGER_AUDIT", {"flow": "workshop"}), s)
	var id := {"id": "workshop:%d" % cell}
	var out := _link(Ledger.snapshot(data, s, "economy", id), "converts_out")
	assert_eq(out["accounts"].size(), 1)
	assert_string_contains(String(out["accounts"][0]["source"]), "; the audit of ")
	for civil: float in [500.0, 5.0]:
		s.metrics["lord_civil"] = civil
		out = _link(Ledger.snapshot(data, s, "economy", id), "converts_out")
		assert_eq(out["accounts"].size(), 1, "one account at %d civil goods" % int(civil))
		assert_false(String(out["accounts"][0]["source"]).contains("audit"), "the audit is dropped")

## I2: an honest marshal's audit, then the line's rate moves — one account.
func test_an_audit_of_an_honest_marshal_drops_once_the_line_moves() -> void:
	_marshal(["honest"])
	var code := String(SupplySystem.plan(data, s)[0]["code"])
	sys.execute(ActionRequest.make("LEDGER_AUDIT", {"flow": "supply_line"}), s)
	s.supply_lines[code]["rate"] = 1200
	var out := _link(Ledger.snapshot(data, s, "war", {"id": "regiment:" + code}), "supplies_out")
	assert_eq(out["accounts"].size(), 1, "his word and the count, one account")
	assert_false(String(out["accounts"][0]["source"]).contains("audit"))

## I2: a venal steward's audit stands beside his word while his word stands.
func test_an_audit_of_a_venal_man_stands_beside_his_word() -> void:
	var st: Character = s.characters[String(s.council["steward"])]
	st.traits = ["venal"]
	sys.execute(ActionRequest.make("LEDGER_AUDIT", {"flow": "workshop"}), s)
	var row: Dictionary = WorkshopSystem.plan(data, s)[0]
	var out := _link(Ledger.snapshot(data, s, "economy", {"id": "workshop:%d" % cell}), "converts_out")
	assert_eq(out["accounts"].size(), 2, "the steward's word and the audit's figure")
	assert_eq(int(out["accounts"][0]["value"]), int(row["claimed"]))
	assert_eq(int(out["accounts"][1]["value"]), int(row["make"]))
	assert_string_contains(String(out["accounts"][1]["source"]), "audit")
	var m: Dictionary = s.missives[-1]
	var fact: Dictionary = (m["facts"] as Array).filter(
		func(f: Dictionary) -> bool: return String(f["key"]) == "workshop:%d" % cell)[0]
	assert_eq(int(fact["claimed"]), int(row["claimed"]), "the letter keeps his word beside the truth")
	assert_eq(Intel.text_of(fact), "%s (he reported %s)" % [Intel.num(int(row["make"])), Intel.num(int(row["claimed"]))])

## M5: the type level carries the audit's total under the same rule.
func test_the_type_level_carries_the_audits_total() -> void:
	var st: Character = s.characters[String(s.council["steward"])]
	st.traits = ["venal"]
	sys.execute(ActionRequest.make("LEDGER_AUDIT", {"flow": "workshop"}), s)
	var row: Dictionary = WorkshopSystem.plan(data, s)[0]
	var out := _link(Ledger.snapshot(data, s, "economy", {}), "converts_out")
	assert_eq(out["accounts"].size(), 2, "his word, and the audit's total")
	assert_eq(int(out["accounts"][1]["value"]), int(row["make"]))
	assert_string_contains(String(out["accounts"][1]["source"]), "the audit of ")
	s.metrics["lord_civil"] = 5.0
	out = _link(Ledger.snapshot(data, s, "economy", {}), "converts_out")
	assert_eq(out["accounts"].size(), 1, "his word moved: the audit's total is dropped")

## An audit of the other flow never lends its figures to this one.
func test_an_audit_speaks_only_for_its_own_flow() -> void:
	var st: Character = s.characters[String(s.council["steward"])]
	st.traits = ["venal"]
	sys.execute(ActionRequest.make("LEDGER_AUDIT", {"flow": "supply_line"}), s)
	var out := _link(Ledger.snapshot(data, s, "economy", {}), "converts_out")
	assert_eq(out["accounts"].size(), 1, "the supply lines' total is not the workshops'")

## M4: a governor's card folds his ties into one line per flow, with his factors.
func test_a_governors_card_has_one_line_per_flow() -> void:
	var st: Character = s.characters[String(s.council["steward"])]
	st.skills["sk_steward"] = 8
	st.opinion = 50
	sys.execute(ActionRequest.make("GOVERNOR_SET", {"flow": "supply_line", "character": st.id}), s)
	var snap := Ledger.snapshot(data, s, "all", {"id": "character:" + st.id})
	var n := (snap["links"] as Array).filter(func(l: Dictionary) -> bool:
		return String(l["type"]) == "governs_supply").size()
	assert_gt(n, 1, "a tie per supply line on the ego")
	var lines: Array = LedgerCards.entry(data, s, "character:" + st.id, snap)["lines"]
	var gov: Array = lines.filter(func(t: String) -> bool: return t.begins_with("governs "))
	# the steward governs the war workshops and (M6) the trade tolls too
	assert_eq(gov.size(), 3, "one line per flow: " + str(gov))
	assert_has(lines, "governs the trade tolls (%d) — %s" % [MarketSystem.routes(data, s).size(),
		LedgerCards._factors_text(data, s, "trade_route")])
	assert_has(lines, "governs the supply lines (%d) — %s" % [n,
		LedgerCards._factors_text(data, s, "supply_line")])
	assert_has(lines, "governs the war workshops (1) — runs it at 85% of what it could — skill 8")

## M6: the governs tie carries the flow's audit and give orders.
func test_the_governs_tie_offers_audit_and_give() -> void:
	for pair: Array in [["governs", "workshop:%d" % cell, "workshop"], ["governs_supply", "", "supply_line"]]:
		var rows := Ledger.actions_for(data, "%s|character:%s|%s" % [pair[0], String(s.council["steward"]), pair[1]], s)
		var audit: Array = rows.filter(func(a: Dictionary) -> bool: return String(a["code"]) == "LEDGER_AUDIT")
		assert_eq(audit.size(), 1)
		assert_eq(String(Ledger.params_of(audit[0], "x")["flow"]), String(pair[2]))
		assert_gt(rows.filter(func(a: Dictionary) -> bool: return String(a["code"]) == "GOVERNOR_SET").size(), 0)

## M8: an empty seat's flow is still tied at the type level — greyed, "no
## one governs it" — and its card says so.
func test_an_empty_seat_draws_a_vacant_tie() -> void:
	s.council["steward"] = ""
	var gov := _link(Ledger.snapshot(data, s, "economy", {}), "governs")
	assert_false(gov.is_empty(), "the tie is drawn")
	assert_true(bool(gov["vacant"]))
	assert_eq(String(gov["accounts"][0]["source"]), "no one governs it")
	assert_eq(String(gov["governor"]), "")
	assert_has(LedgerCards.thread_entry(data, s, gov)["lines"], "No one governs it: it runs at 60% of what it could")
	assert_true(_link(Ledger.snapshot(data, s, "economy", {"id": "workshop:%d" % cell}), "governs").is_empty(),
		"no man to draw it from on the instance")

## I3: an unknown flow has no instances and no books, and says so.
func test_an_unknown_flow_has_no_instances_and_no_books() -> void:
	assert_eq(LedgerResolvers._instances_of_flow(data, s, "moat"), [])
	assert_eq(AuditWriter.facts(data, s, "moat"), [])

## M7: a fresh snapshot never reads a plan memoised before it began.
func test_begin_memo_clears_a_stale_memo() -> void:
	LedgerResolvers.begin_memo()
	var stale := LedgerResolvers._workshop_plan(data, s)
	s.metrics["lord_civil"] = 5.0
	LedgerResolvers.begin_memo()
	assert_ne(LedgerResolvers._workshop_plan(data, s), stale, "begin threw the stale plan away")
	LedgerResolvers.end_memo()
