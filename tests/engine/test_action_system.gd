extends GutTest

var data: DataRepository
var sys: ActionSystem
var s: GameState

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	sys = ActionSystem.new(data)
	s = GameState.new_campaign(data, 42)

func test_unknown_action_rejected() -> void:
	assert_string_contains(sys.validate(ActionRequest.make("FLY_TO_MOON"), s), "Unknown")

func test_unaffordable_rejected() -> void:
	s.metrics["treasury"] = 5.0
	assert_string_contains(sys.validate(ActionRequest.make("LEVY_RAISE"), s), "afford")

func test_cooldown_enforced() -> void:
	var req := ActionRequest.make("TAX_RATE_ADJUST", {"delta": 1})
	assert_eq(sys.validate(req, s), "")
	sys.execute(req, s)
	assert_string_contains(sys.validate(req, s), "cooldown")

func test_tax_adjust_moves_rate_with_reason() -> void:
	var out := sys.execute(ActionRequest.make("TAX_RATE_ADJUST", {"delta": 2}), s)
	assert_true(out["ok"])
	assert_eq(s.metrics["tax_rate"], 7.0)
	var found := false
	for e in out["effects"]:
		if String(e.get("metric", "")) == "tax_rate":
			found = true
			assert_string_contains(e["reason"], "tax")
	assert_true(found)

func test_reward_changes_opinion_with_reason() -> void:
	var target: String = s.council["marshal"]
	var gold_before: float = s.metrics["treasury"]
	sys.execute(ActionRequest.make("CHARACTER_REWARD", {"mode": "gold"}, target), s)
	var c: Character = s.characters[target]
	assert_gt(c.opinion, 10)
	assert_string_contains(c.opinion_log[-1]["reason"], "reward")
	assert_lt(s.metrics["treasury"], gold_before)

func test_bad_params_rejected() -> void:
	assert_string_contains(sys.validate(ActionRequest.make("TAX_RATE_ADJUST", {"delta": 9}), s), "delta")
	assert_string_contains(sys.validate(ActionRequest.make("GRAIN_POLICY_SET", {"mode": "feast"}), s), "mode")
	assert_string_contains(
		sys.validate(ActionRequest.make("CHARACTER_REWARD", {"mode": "gold"}, "char_nobody"), s), "target")

func test_execute_applies_ideology_drift() -> void:
	var odo_before: int = s.characters["char_chaplain"].opinion
	var out := sys.execute(ActionRequest.make("CHURCH_POLICY", {"mode": "tithe"}), s)
	assert_eq(s.characters["char_chaplain"].opinion, odo_before - 6)
	assert_true(out.has("drift"))
	assert_gt(out["drift"].size(), 0)
	assert_string_contains(
		s.characters["char_chaplain"].opinion_log[-1]["reason"], "opposes, orthodoxy")
