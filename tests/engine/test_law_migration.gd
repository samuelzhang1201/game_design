extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The five old policy actions became laws (spec 2026-10-08-laws-tab-design
## §2.5, §3): no code or table names them any more; their drift signatures
## live on as LAW_SET variants; the council suggests, the model orders and the
## events move the laws through LAW_SET and the `law:` effect op.

const OLD_CODES := ["TAX_RATE_ADJUST", "TARIFF_ADJUST", "GRAIN_POLICY_SET", "JUSTICE_SEVERITY", "CHURCH_POLICY"]

## The old action_signatures.csv rows, as they stood: the law each became, the
## params that pick the variant, and centralism, militarism, orthodoxy,
## tax_incidence, expansionism.
const OLD_SIGNATURES := [
	["tax_rate", {"delta": 1}, [10, 0, 0, -30, 0]],
	["tax_rate", {"delta": -1}, [-5, 0, 0, 30, 0]],
	["tariff_rate", {"delta": 1}, [0, 0, 0, 15, -15]],
	["tariff_rate", {"delta": -1}, [0, 0, 0, -10, 15]],
	["grain_ration", {"value": "ration"}, [10, 0, 0, -15, 0]],
	["grain_ration", {"value": "release"}, [0, 0, 0, 20, 0]],
	["grain_ration", {"value": "market"}, [0, 0, 0, 0, 0]],
	["church_policy", {"value": "endow"}, [0, 0, 50, 0, 0]],
	["church_policy", {"value": "tithe"}, [10, 0, -50, 0, 0]],
	["justice_severity", {"delta": 1}, [30, 0, 10, -10, 0]],
	["justice_severity", {"delta": -1}, [-20, 0, -5, 10, 0]],
]

var repo: DataRepository
var s: GameState
var engine: TickEngine
var realm: String


func before_all() -> void:
	RoadGraph.forget()


func before_each() -> void:
	repo = SuiteData.repo()
	s = SuiteData.campaign(repo, 42)
	engine = TickEngine.new(repo)
	realm = repo.resolve_realm("player_realm")
	s.metrics["treasury"] = 5000.0
	Weather.forget()


func after_all() -> void:
	RoadGraph.forget()


func _law(law: String, value: Variant) -> ActionRequest:
	return ActionRequest.make("LAW_SET", {"law": law, "value": value})


func _scan(dir: String, ext: String, out: Array) -> void:
	for f: String in DirAccess.get_files_at(dir):
		var path := dir.path_join(f)
		if not f.ends_with(ext):
			continue
		var text := FileAccess.get_file_as_string(path)
		for code: String in OLD_CODES:
			if text.contains(code):
				out.append("%s names %s" % [path, code])
	for d: String in DirAccess.get_directories_at(dir):
		_scan(dir.path_join(d), ext, out)


func test_no_old_policy_code_remains() -> void:
	var out: Array = []
	_scan("res://scripts", ".gd", out)
	_scan("res://tools", ".gd", out)
	_scan("res://data", ".csv", out)
	assert_eq(out, [], "\n".join(out))
	for code: String in OLD_CODES:
		assert_false(repo.actions.has(code), code + " is no action")


func test_the_old_signatures_survive_as_law_variants() -> void:
	for row: Array in OLD_SIGNATURES:
		var params: Dictionary = {"law": row[0], "value": "x"}
		params.merge(row[1], true)
		var sig := OpinionDrift.signature_for(repo, "LAW_SET", params)
		var want: Array = row[2]
		for i in OpinionDrift.AXES.size():
			assert_eq(float(sig[OpinionDrift.AXES[i]]), float(want[i]),
				"%s %s %s" % [row[0], str(row[1]), OpinionDrift.AXES[i]])
	# Executed, a tax raised by one drifts the council as the old delta_pos
	# row did: the same ministers by the same amounts as applying that row
	# to a twin of the state.
	var twin := SuiteData.campaign(repo, 42)
	var now := int(LawSystem.decreed(repo, s, "tax_rate"))
	var up_sig := OpinionDrift.signature_for(repo, "LAW_SET", {"law": "tax_rate", "delta": 1})
	var expected := OpinionDrift.apply(repo, twin, up_sig, "x")
	var out := engine.actions.execute(_law("tax_rate", str(now + 1)), s)
	var got := {}
	for d: Dictionary in out["drift"]:
		got[String(d["character_id"])] = int(d["delta"])
	var want_drift := {}
	for d: Dictionary in expected:
		want_drift[String(d["character_id"])] = int(d["delta"])
	assert_gt(want_drift.size(), 0, "raising the tax moves someone")
	assert_eq(got, want_drift)
	assert_false((out["params"] as Dictionary).has("delta"), "the direction rides on a copy, not the order")


func test_a_suggestion_is_a_law_set() -> void:
	s.metrics["unrest"] = 55.0
	var concerns := ConcernScanner.scan(s, repo)
	var sugs := engine.suggestions.generate(s, concerns)
	var now := int(LawSystem.decreed(repo, s, "justice_severity"))
	var found := false
	for sug: Dictionary in sugs:
		if String(sug["pitch_key"]) != "harsh_justice":
			continue
		found = true
		var req: ActionRequest = sug["request"]
		assert_eq(req.action_code, "LAW_SET")
		assert_eq(String(req.params["law"]), "justice_severity")
		assert_eq(String(req.params["value"]), str(now + 1))
		assert_eq(engine.actions.validate(req, s), "")
	assert_true(found, "unrest raises the harsher-courts suggestion beside easing the tax")


func test_a_typed_order_for_an_unknown_law_is_rejected() -> void:
	var out := OrderPipeline.apply_order(repo, s, engine, [_law("nope", "1")], [], {}, "order")
	assert_eq(out["executed"].size(), 0)
	assert_eq(out["rejected"].size(), 1)
	assert_eq(String(out["rejected"][0]["error"]), "No such law: nope")


func test_the_tariff_event_moves_the_law() -> void:
	var was := int(LawSystem.decreed(repo, s, "tariff_rate"))
	var id_was := int(s.law_decree["tariff_rate"]["decree_id"])
	engine.events._fire("ev_07", s)
	var res := engine.events.apply_choice("tariff", s)
	assert_false(res.is_empty())
	assert_eq(int(LawSystem.decreed(repo, s, "tariff_rate")), was + 1)
	assert_eq(int(s.law_decree["tariff_rate"]["decree_id"]), id_was + 1, "a new decree: older couriers arrive stale")
	assert_eq(float(s.metrics["tariff_rate"]), float(was + 1), "the mirror follows the decree")
	var provinces := MapOwnership.provinces_of(repo, s, realm)
	assert_gt(provinces.size(), 0)
	for code: String in provinces:
		assert_eq(LawSystem.number(repo, s, "tariff_rate", code), was + 1, code + " follows at once")
	var line := {}
	for e: Dictionary in res["effects"]:
		if String(e.get("kind", "")) == "law":
			line = e
	assert_eq(String(line.get("law", "")), "tariff_rate")
	assert_ne(String(line.get("reason", "")), "", "an event's law change carries its reason")
	assert_true(s.couriers.filter(func(c: Dictionary) -> bool:
		return String(c.get("order", {}).get("action_code", "")) == "LAW_SET").is_empty(),
		"an event is not a courier")
	# Clamped to the law's range.
	var top := int(LawSystem.def(repo, "tariff_rate")["values"][1])
	EventEffects.apply("law:tariff_rate:%d" % top, s, repo, "test")
	EventEffects.apply("law:tariff_rate:+1", s, repo, "test")
	assert_eq(int(LawSystem.decreed(repo, s, "tariff_rate")), top)
	for code: String in provinces:
		assert_eq(LawSystem.number(repo, s, "tariff_rate", code), top)


func test_the_trigger_reads_the_law_stamp() -> void:
	assert_eq(String(repo.events_by_id["ev_07"]["trigger"]), "action_since=LAW_tariff_rate:24")
	s.tick = 40
	assert_false(TriggerDsl.evaluate("action_since=LAW_tariff_rate:24", s, repo))
	var now := int(LawSystem.decreed(repo, s, "tariff_rate"))
	var other := now + 1 if now < int(LawSystem.def(repo, "tariff_rate")["values"][1]) else now - 1
	engine.actions.execute(_law("tariff_rate", str(other)), s)
	assert_eq(int(s.event_state["last_action_tick"]["LAW_tariff_rate"]), 40)
	assert_true(TriggerDsl.evaluate("action_since=LAW_tariff_rate:24", s, repo))
	s.tick = 65
	assert_false(TriggerDsl.evaluate("action_since=LAW_tariff_rate:24", s, repo))


## An event's law change and a typed decree each print their ledger line
## (OrderPipeline.describe_effects), naming the law and its values, never
## a bare "law +0".
func test_an_event_law_change_prints_its_ledger_line() -> void:
	var was := int(LawSystem.decreed(repo, s, "tariff_rate"))
	engine.events._fire("ev_07", s)
	var res := engine.events.apply_choice("tariff", s)
	var line := OrderPipeline.describe_effects(res["effects"], s)
	assert_string_contains(line, "Tariff rate %d → %d" % [was, was + 1])
	assert_string_contains(line, String(res["label"]))


func test_a_typed_decree_prints_its_reason_not_a_zero() -> void:
	var out := OrderPipeline.apply_order(repo, s, engine, [_law("tax_rate", "7")], [], {}, "order")
	assert_eq(out["executed"].size(), 1)
	var ledger := "\n".join(out["ledger"])
	assert_string_contains(ledger, "Tax rate decreed 7: ")
	assert_false(ledger.contains("law +0"), ledger)
