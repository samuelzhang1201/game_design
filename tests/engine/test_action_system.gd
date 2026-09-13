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

## --- Manors (MANOR_SYSTEM.md §5) ------------------------------------------

## A manor in the crown's realm held by another house, and one the crown
## holds (its demesne), from the real pack.
func _foreign_manor() -> int:
	var realm := data.resolve_realm("player_realm")
	for province: String in MapOwnership.provinces_of(data, s, realm):
		for cell: int in MapManors.manors_of_province(data, province):
			if not MapManors.is_crowns(data, s, cell):
				return cell
	return -1

func _crown_manor() -> int:
	var realm := data.resolve_realm("player_realm")
	for province: String in MapOwnership.provinces_of(data, s, realm):
		for cell: int in MapManors.manors_of_province(data, province):
			if MapManors.is_crowns(data, s, cell):
				return cell
	return -1

func test_the_pack_gives_the_crown_a_demesne_and_others_to_buy() -> void:
	assert_ne(MapManors.crown(s), "", "the player has a house")
	assert_gt(_crown_manor(), -1, "the crown holds manors")
	assert_gt(_foreign_manor(), -1, "other houses hold manors in the realm")

func test_buying_a_manor_needs_a_real_one_in_the_realm_and_the_gold() -> void:
	assert_string_contains(sys.validate(ActionRequest.make("MANOR_BUY", {"manor": "nowhere"}), s),
		"No such manor")
	var own := _crown_manor()
	assert_string_contains(sys.validate(ActionRequest.make("MANOR_BUY", {"manor": own}), s),
		"already holds")
	var cell := _foreign_manor()
	var price := MapManors.price_of(data, s, cell)
	s.metrics["treasury"] = price - 1.0
	assert_string_contains(sys.validate(ActionRequest.make("MANOR_BUY", {"manor": cell}), s),
		"afford")
	# Outside the realm: the first manor of a province another kingdom holds.
	var realm := data.resolve_realm("player_realm")
	for province: String in data.provinces:
		if MapOwnership.owner_of(data, s, province) != realm and not MapManors.manors_of_province(data, province).is_empty():
			var abroad: int = MapManors.manors_of_province(data, province)[0]
			s.metrics["treasury"] = 100000.0
			assert_string_contains(sys.validate(ActionRequest.make("MANOR_BUY", {"manor": abroad}), s),
				"outside the realm")
			break

func test_buying_moves_the_manor_pays_the_house_and_warms_it() -> void:
	var cell := _foreign_manor()
	var seller := MapManors.owner_of(data, s, cell)
	var price := MapManors.price_of(data, s, cell)
	s.metrics["treasury"] = price + 500.0
	var before: float = s.metrics["treasury"]
	var opinions: Dictionary = {}
	for id in s.characters:
		if (s.characters[id] as Character).family_name == seller:
			opinions[id] = (s.characters[id] as Character).opinion
	# By label, in any case: the way a typed order names it.
	var req := ActionRequest.make("MANOR_BUY", {"manor": MapManors.label_of(data, cell).to_upper()})
	assert_eq(sys.validate(req, s), "")
	var out := sys.execute(req, s)
	assert_true(MapManors.is_crowns(data, s, cell), "the crown holds it now")
	assert_almost_eq(s.metrics["treasury"], before - price - 2.0, 0.001,
		"the price and the notary's fee (order_costs.csv)")
	assert_eq(s.manor_log.size(), 1)
	assert_string_contains(String(s.manor_log[0]["reason"]), "bought from House " + seller)
	for id in opinions:
		assert_eq((s.characters[id] as Character).opinion,
			clampi(int(opinions[id]) + int(data.bal("manor_trade_goodwill")), -100, 100),
			"%s of House %s warms to the crown" % [id, seller])
	var manor_effects: Array = (out["effects"] as Array).filter(func(e: Dictionary) -> bool: return e["metric"] == "manor")
	assert_eq(manor_effects.size(), 1, "the ledger line names the manor")

func test_selling_and_building_need_a_crown_manor() -> void:
	var cell := _foreign_manor()
	assert_string_contains(sys.validate(ActionRequest.make("MANOR_SELL", {"manor": cell}), s),
		"does not hold")
	assert_string_contains(sys.validate(ActionRequest.make("MANOR_BUILD", {"manor": cell, "building": "mill"}), s),
		"does not hold")
	s.metrics["treasury"] = MapManors.price_of(data, s, cell) + 1000.0
	sys.execute(ActionRequest.make("MANOR_BUY", {"manor": cell}), s)
	var house := MapManors.default_owner(data, s, cell)
	# Build a mill: its cost and the surveyor's fee leave the chest.
	assert_string_contains(sys.validate(ActionRequest.make("MANOR_BUILD", {"manor": cell, "building": "castle"}), s),
		"No such building")
	var before: float = s.metrics["treasury"]
	var build := ActionRequest.make("MANOR_BUILD", {"manor": cell, "building": "mill"})
	assert_eq(sys.validate(build, s), "")
	sys.execute(build, s)
	assert_eq(MapManors.buildings_of(s, cell), ["mill"])
	assert_almost_eq(s.metrics["treasury"], before - float(data.manor_buildings["mill"]["cost_gold"]) - 1.0, 0.001)
	assert_string_contains(sys.validate(build, s), "already has")
	# Sell it back: the house takes it, the crown gets the sell-back price
	# less the notary's fee.
	var sell := ActionRequest.make("MANOR_SELL", {"manor": cell})
	assert_eq(sys.validate(sell, s), "")
	before = s.metrics["treasury"]
	var price := MapManors.sell_price_of(data, s, cell)
	sys.execute(sell, s)
	assert_eq(MapManors.owner_of(data, s, cell), house)
	assert_almost_eq(s.metrics["treasury"], before + price - 2.0, 0.001)
	assert_eq(MapManors.buildings_of(s, cell), ["mill"], "the mill goes with the land")

func test_seizing_is_gated_and_costs_legitimacy_unrest_and_the_houses_regard() -> void:
	var cell := _foreign_manor()
	var req := ActionRequest.make("MANOR_SEIZE", {"manor": cell})
	assert_string_contains(sys.validate(req, s), "not permitted", "off by default")
	data.balance["manor_seize_enabled"] = 1.0
	assert_eq(sys.validate(req, s), "")
	var victim := MapManors.owner_of(data, s, cell)
	var legitimacy: float = s.metrics["legitimacy"]
	var unrest: float = s.metrics["unrest"]
	var treasury: float = s.metrics["treasury"]
	var opinions: Dictionary = {}
	for id in s.characters:
		if (s.characters[id] as Character).family_name == victim:
			opinions[id] = (s.characters[id] as Character).opinion
	sys.execute(req, s)
	assert_true(MapManors.is_crowns(data, s, cell))
	assert_almost_eq(s.metrics["legitimacy"], legitimacy - data.bal("manor_seize_legitimacy"), 0.001)
	assert_almost_eq(s.metrics["unrest"], unrest + data.bal("manor_seize_unrest"), 0.001)
	assert_almost_eq(s.metrics["treasury"], treasury - 10.0, 0.001, "the men-at-arms are paid (always)")
	for id in opinions:
		assert_eq((s.characters[id] as Character).opinion,
			clampi(int(opinions[id]) - int(data.bal("manor_seize_outrage")), -100, 100))
	assert_string_contains(String(s.manor_log[0]["reason"]), "seized by force")
	assert_string_contains(sys.validate(req, s), "cooldown")
	data.balance["manor_seize_enabled"] = 0.0
