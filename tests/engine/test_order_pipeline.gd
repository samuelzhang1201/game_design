extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## One order end to end (spec 2026-09-09 §4.3): actions, world impacts, the
## court reaction, the cost rule, and the ledger lines the screens print.

var data: DataRepository
var state: GameState
var engine: TickEngine

func before_each() -> void:
	data = SuiteData.repo()
	state = SuiteData.campaign(data, 42)
	engine = TickEngine.new(data)
	engine.advance(state)
	state.pending_event = {}

func _reaction() -> Dictionary:
	return {"addressed": [], "tone": "neutral", "promises": []}

func test_actions_and_impacts_apply_and_print() -> void:
	var grain: float = state.metrics["grain"]
	var out := OrderPipeline.apply_order(data, state, engine,
		[ActionRequest.make("SPY_MISSION")],
		[{"path": "metrics.grain", "delta": 10.0, "reason": "a gift of grain", "clamped": false}],
		_reaction(), "order")
	assert_eq(out["executed"].size(), 1)
	assert_eq(state.metrics["grain"], grain + 10.0)
	assert_eq(out["world_effects"].size(), 1)
	assert_true(out["cost_effects"].is_empty(), "the action's own gold was the cost")
	var joined := "\n".join(out["ledger"])
	assert_string_contains(joined, "grain +10")
	assert_string_contains(joined, "a gift of grain")
	assert_string_contains(joined, "treasury")

func test_a_pure_impact_order_without_a_cost_is_charged_the_generic_cost() -> void:
	var gold: float = state.metrics["treasury"]
	var out := OrderPipeline.apply_order(data, state, engine, [],
		[{"path": "metrics.peasant_contentment", "delta": 2.0, "reason": "a feast",
		"clamped": false}], _reaction(), "order")
	assert_eq(out["cost_effects"].size(), 1)
	assert_lt(state.metrics["treasury"], gold)
	assert_string_contains("\n".join(out["ledger"]), "clerks")

func test_a_pure_impact_order_with_a_cost_is_not_charged_twice() -> void:
	var gold: float = state.metrics["treasury"]
	OrderPipeline.apply_order(data, state, engine, [],
		[{"path": "metrics.treasury", "delta": -20.0, "reason": "alms", "clamped": false}],
		_reaction(), "order")
	assert_eq(state.metrics["treasury"], gold - 20.0)

func test_rejected_impacts_and_actions_are_reported() -> void:
	var out := OrderPipeline.apply_order(data, state, engine,
		[ActionRequest.make("LAW_SET", {"law": "tax_rate", "value": 99})],
		[{"path": "metrics.grain", "delta": 1.0, "reason": "", "clamped": false}],
		_reaction(), "order")
	assert_eq(out["rejected"].size(), 1, "the illegal value is rejected by validate")
	assert_eq(out["world_rejected"].size(), 1, "the ledger refuses an impact with no reason")
	assert_string_contains("\n".join(out["ledger"]), "struck")

func test_event_choice_rides_through_the_pipeline() -> void:
	engine.events._fire("ev_01", state)
	var choice: String = state.pending_event["choices"][0]["choice_id"]
	var out := OrderPipeline.apply_order(data, state, engine,
		[ActionRequest.make("EVENT_CHOICE", {"choice_id": choice})], [], _reaction(), "order")
	assert_eq(String(out["executed"][0]["action_code"]), "EVENT_CHOICE")
	assert_true(state.pending_event.is_empty())

func test_world_impacts_are_logged_with_their_source() -> void:
	OrderPipeline.apply_order(data, state, engine, [],
		[{"path": "military.kingdoms.player_realm.cavalry", "delta": -20.0,
		"reason": "horses sold", "clamped": false}], _reaction(), "order")
	assert_eq(String(state.world_log[-1]["source"]), "order")
	assert_eq(String(state.world_log[-1]["reason"]), "horses sold")
