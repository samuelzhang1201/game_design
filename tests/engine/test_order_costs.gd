extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Every order carries a cost (owner rule 2026-09-09, spec §3): explicit
## (gold, grain, population) or hidden (opinion, relationship, attribute).

var data: DataRepository
var state: GameState
var sys: ActionSystem

func before_each() -> void:
	data = SuiteData.repo()
	state = SuiteData.campaign(data, 42)
	sys = ActionSystem.new(data)

func test_every_catalog_action_has_a_cost_row() -> void:
	for code: String in data.actions:
		assert_true(data.order_costs.has(code), "%s has an order_costs.csv row" % code)
	assert_true(data.order_costs.has("generic_order"))
	assert_true(data.order_costs.has("EVENT_CHOICE"))

func test_polarity_covers_every_metric() -> void:
	for m: String in state.metrics:
		assert_true(data.metric_polarity.has(m), "metric_polarity.csv lists %s" % m)

func test_cost_detection_reads_polarity() -> void:
	assert_true(OrderCosts.has_cost(data, state,
		[{"metric": "treasury", "delta": -5.0, "reason": "x"}], [], {}))
	assert_true(OrderCosts.has_cost(data, state,
		[{"metric": "unrest", "delta": 2.0, "reason": "x"}], [], {}))
	assert_false(OrderCosts.has_cost(data, state,
		[{"metric": "grain", "delta": 20.0, "reason": "x"}], [], {}))
	assert_false(OrderCosts.has_cost(data, state,
		[{"metric": "tax_rate", "delta": -1.0, "reason": "x"}], [], {}),
		"a rate change is neutral in itself")
	assert_true(OrderCosts.has_cost(data, state, [],
		[{"character_id": "char_marshal", "delta": -3, "reason": "x"}], {}))
	assert_true(OrderCosts.has_cost(data, state,
		[{"kind": "world", "path": "economy.kingdoms.player_realm.rural_population",
		"delta": -100.0}], [], {}))
	assert_false(OrderCosts.has_cost(data, state,
		[{"kind": "world", "path": "economy.kingdoms.player_realm.rural_population",
		"delta": 100.0}], [], {}))

func test_direct_opinion_losses_count_through_the_snapshot() -> void:
	var before := OrderCosts.snapshot_opinions(state)
	state.characters["char_marshal"].change_opinion(-4, "test", 0)
	assert_true(OrderCosts.has_cost(data, state, [], [], before))

func test_charge_applies_the_row_with_its_reason() -> void:
	var p: int = state.characters["you"].attributes["prestige"]
	var charged := OrderCosts.charge(data, state, "CHARACTER_CONFIDE", "")
	assert_eq(charged.size(), 1)
	assert_eq(int(state.characters["you"].attributes["prestige"]), p - 1)
	assert_string_contains(String(charged[0]["reason"]), "confides")
	assert_true(OrderCosts.charge(data, state, "COUNCIL_CONSULT", "").is_empty(), "exempt")

func test_charge_resolves_target_for_punishments() -> void:
	var before: int = state.characters["char_marshal"].opinion
	OrderCosts.charge(data, state, "CHARACTER_PUNISH", "char_marshal")
	assert_eq(state.characters["char_marshal"].opinion, before - 2)

func test_ensure_charges_only_when_nothing_else_did() -> void:
	var effects: Array = [{"metric": "treasury", "delta": -30.0, "reason": "paid"}]
	var charged := OrderCosts.ensure(data, state, effects, [],
		OrderCosts.snapshot_opinions(state), "CHARACTER_CONFIDE", "")
	assert_true(charged.is_empty(), "the gold already was the cost")
	var free: Array = []
	charged = OrderCosts.ensure(data, state, free, [], OrderCosts.snapshot_opinions(state),
		"CHARACTER_CONFIDE", "")
	assert_eq(charged.size(), 1)
	assert_eq(free.size(), 1, "the charge rides on the outcome's effects")

func test_training_keeps_a_real_cost_without_mobilizing_fictitious_people() -> void:
	var pop_before := int(WorldLedger.value_of(data, state,
		"economy.kingdoms.player_realm.rural_population"))
	var out := sys.execute(ActionRequest.make("LEVY_RAISE"), state)
	assert_eq(int(WorldLedger.value_of(data, state,
		"economy.kingdoms.player_realm.rural_population")), pop_before,
		"training is not a second personnel recruitment path")
	var seen := false
	for e in out["effects"]:
		if String(e.get("metric", "")) == "strategic" and float(e.get("delta", 0)) < 0:
			seen = true
	assert_true(seen, "training materials remain an explicit cost beside gold")

## The guarantee itself: every handled action, executed from a fresh
## campaign, leaves a cost on the record.
func test_every_handled_action_leaves_a_cost() -> void:
	var cases := [
		ActionRequest.make("LAW_SET", {"law": "tax_rate", "value": "6"}),
		ActionRequest.make("LAW_SET", {"law": "tariff_rate", "value": "2"}),
		ActionRequest.make("LEVY_RAISE"),
		ActionRequest.make("LAW_SET", {"law": "grain_ration", "value": "release"}),
		ActionRequest.make("LAW_SET", {"law": "church_policy", "value": "endow"}),
		ActionRequest.make("LAW_SET", {"law": "justice_severity", "value": "2"}),
		ActionRequest.make("BUILD_ECONOMIC", {"project": "road"}),
		ActionRequest.make("SPY_MISSION"),
		ActionRequest.make("CHARACTER_REWARD", {"mode": "gold"}, "char_marshal"),
		ActionRequest.make("CHARACTER_PUNISH", {}, "char_marshal"),
		ActionRequest.make("CHARACTER_CONFIDE", {}, "char_marshal"),
		ActionRequest.make("RECRUIT_COURTIER", {}, "char_bard_corvin"),
		ActionRequest.make("GUARD_ADJUST"),
		ActionRequest.make("LAW_SET", {"law": "plunder", "value": "allow"}),
	]
	for req in cases:
		var s := SuiteData.campaign(data, 42)
		var before := OrderCosts.snapshot_opinions(s)
		assert_eq(sys.validate(req, s), "", req.action_code + " is legal on a fresh campaign")
		var out := sys.execute(req, s)
		assert_true(OrderCosts.has_cost(data, s, out["effects"], out["drift"], before),
			"%s left a cost" % req.action_code)

func test_affordability_counts_the_cost_rows_gold() -> void:
	state.metrics["treasury"] = 20.0
	assert_string_contains(
		sys.validate(ActionRequest.make("RECRUIT_COURTIER", {}, "char_bard_corvin"), state),
		"afford")
