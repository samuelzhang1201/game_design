extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")

var data: DataRepository
var sys: ActionSystem
var s: GameState

func before_each() -> void:
	data = SuiteData.repo()
	sys = ActionSystem.new(data)
	s = SuiteData.campaign(data, 42)

func test_unknown_action_rejected() -> void:
	assert_string_contains(sys.validate(ActionRequest.make("FLY_TO_MOON"), s), "Unknown")

func test_unaffordable_rejected() -> void:
	s.metrics["treasury"] = 5.0
	assert_string_contains(sys.validate(ActionRequest.make("LEVY_RAISE"), s), "afford")

## A law's cooldown is its own (LawSystem): a second, different decree of
## the tax rate right after the first is refused for it.
func test_cooldown_enforced() -> void:
	var now := int(LawSystem.decreed(data, s, "tax_rate"))
	var req := ActionRequest.make("LAW_SET", {"law": "tax_rate", "value": str(now + 1)})
	assert_eq(sys.validate(req, s), "")
	sys.execute(req, s)
	assert_string_contains(sys.validate(ActionRequest.make("LAW_SET",
		{"law": "tax_rate", "value": str(now + 2)}), s), "cooldown")

## The tax is a law now: the decree moves the rate's mirror at once (spec
## 2026-10-08-laws-tab-design §2.5) and its law line says why.
func test_tax_adjust_moves_rate_with_reason() -> void:
	var out := sys.execute(ActionRequest.make("LAW_SET", {"law": "tax_rate", "value": "7"}), s)
	assert_true(out["ok"])
	assert_eq(s.metrics["tax_rate"], 7.0)
	assert_eq(LawSystem.decreed(data, s, "tax_rate"), "7")
	var found := false
	for e in out["effects"]:
		if String(e.get("metric", "")) == "law":
			found = true
			assert_string_contains(e["reason"], "Tax rate")
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
	assert_string_contains(sys.validate(ActionRequest.make("LAW_SET", {"law": "tax_rate", "value": 99}), s),
		"not a value")
	assert_string_contains(sys.validate(ActionRequest.make("LAW_SET", {"law": "grain_ration", "value": "feast"}), s),
		"not a value")
	assert_string_contains(
		sys.validate(ActionRequest.make("CHARACTER_REWARD", {"mode": "gold"}, "char_nobody"), s), "target")

## The tithe is the church law's value now: the drift is the old tithe's
## (-6 for Odo), and the law's own cost op (laws.csv cost_ops, charged on
## every decree) costs him one more.
func test_execute_applies_ideology_drift() -> void:
	var odo_before: int = s.characters["char_chaplain"].opinion
	var out := sys.execute(ActionRequest.make("LAW_SET", {"law": "church_policy", "value": "tithe"}), s)
	assert_eq(s.characters["char_chaplain"].opinion, odo_before - 6 - 1)
	assert_true(out.has("drift"))
	assert_gt(out["drift"].size(), 0)
	var odo_drift := 0
	for d in out["drift"]:
		if String(d["character_id"]) == "char_chaplain":
			odo_drift = int(d["delta"])
	assert_eq(odo_drift, -6)
	assert_string_contains(
		s.characters["char_chaplain"].opinion_log[-1]["reason"], "opposes, orthodoxy")

## --- Manors (MANOR_SYSTEM.md §5) ------------------------------------------

## A manor in the crown's realm held by another house, and one the crown
## holds (its demesne), from the real pack.
func _foreign_manor() -> int:
	var realm := data.resolve_realm("player_realm")
	for province: String in MapOwnership.provinces_of(data, s, realm):
		for cell: int in MapManors.manors_of_province(data, province):
			if not MapManors.is_crowns(data, s, cell) \
					and String(MapManors.purchase_kind(data, s, cell)["kind"]) == "domestic":
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
	s.metrics["lord_gold"] = price - 1.0
	assert_string_contains(sys.validate(ActionRequest.make("MANOR_BUY", {"manor": cell}), s),
		"afford")
	# Abroad, off the border: a manor of another kingdom touching nothing of the realm.
	var realm := data.resolve_realm("player_realm")
	s.metrics["treasury"] = 100000.0
	s.metrics["lord_gold"] = 100000.0
	var found := false
	for province: String in data.provinces:
		if MapOwnership.owner_of(data, s, province) == realm:
			continue
		for abroad: int in MapManors.manors_of_province(data, province):
			if String(MapManors.purchase_kind(data, s, abroad)["kind"]) == "":
				assert_string_contains(sys.validate(ActionRequest.make("MANOR_BUY", {"manor": abroad}), s),
					"does not touch the realm's border")
				found = true
				break
		if found:
			break
	assert_true(found, "most of the world lies off the realm's border")

func test_buying_moves_the_manor_pays_the_house_and_warms_it() -> void:
	var cell := _foreign_manor()
	var seller := MapManors.owner_of(data, s, cell)
	var price := MapManors.price_of(data, s, cell)
	s.metrics["lord_gold"] = price + 500.0
	var before: float = s.metrics["lord_gold"]
	var treasury_before: float = s.metrics["treasury"]
	var opinions: Dictionary = {}
	for id in s.characters:
		if (s.characters[id] as Character).family_name == seller:
			opinions[id] = (s.characters[id] as Character).opinion
	# By label, in any case: the way a typed order names it.
	var req := ActionRequest.make("MANOR_BUY", {"manor": MapManors.label_of(data, cell).to_upper()})
	assert_eq(sys.validate(req, s), "")
	var out := sys.execute(req, s)
	assert_true(MapManors.is_crowns(data, s, cell), "the crown holds it now")
	assert_almost_eq(s.metrics["lord_gold"], before - price, 0.001, "the lord's purse pays the price")
	assert_almost_eq(s.metrics["treasury"], treasury_before - 2.0, 0.001,
		"the notary's fee (order_costs.csv) is the crown's")
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
	s.metrics["lord_gold"] = MapManors.price_of(data, s, cell) + 1000.0
	s.metrics["lord_civil"] = 100000.0
	sys.execute(ActionRequest.make("MANOR_BUY", {"manor": cell}), s)
	var house := MapManors.default_owner(data, s, cell)
	# Building needs the province (2026-09-13): take the rest of it first.
	for other: int in MapManors.manors_of_province(data, MapManors.province_of(data, cell)):
		if not MapManors.is_crowns(data, s, other):
			MapManors.set_owner(data, s, other, MapManors.crown(s), "test: taken")
	# Build a mill: its cost and the surveyor's fee leave the chest.
	assert_string_contains(sys.validate(ActionRequest.make("MANOR_BUILD", {"manor": cell, "building": "moon_tower"}), s),
		"No such building")
	var before: float = s.metrics["treasury"]
	var grain_before: float = s.metrics["lord_civil"]
	var build := ActionRequest.make("MANOR_BUILD", {"manor": cell, "building": "mill"})
	assert_eq(sys.validate(build, s), "")
	sys.execute(build, s)
	# Begun, not standing (2026-09-13): the mill takes its build_days.
	assert_eq(MapManors.buildings_of(s, cell), [])
	assert_true(MapManors.is_building(s, cell, "mill"))
	# The lord's own civil goods pay for the work (owner 2026-09-14); only the
	# surveyor's fee leaves the crown's chest.
	assert_almost_eq(s.metrics["treasury"], before - 1.0, 0.001)
	assert_almost_eq(s.metrics["lord_civil"], grain_before - float(data.manor_buildings["mill"]["civil_cost"]), 0.001)
	assert_string_contains(sys.validate(build, s), "already being built")
	s.tick += int(ceili(float(data.manor_buildings["mill"]["build_days"]) / float(Calendar.DAYS_PER_TICK))) + 1
	assert_eq(MapManors.advance_works(data, s), [{"cell": cell, "building": "mill"}])
	assert_eq(MapManors.buildings_of(s, cell), ["mill"])
	assert_string_contains(sys.validate(build, s), "already has")
	# Sell it back: the house takes it, the crown gets the sell-back price
	# less the notary's fee.
	var sell := ActionRequest.make("MANOR_SELL", {"manor": cell})
	assert_eq(sys.validate(sell, s), "")
	before = s.metrics["treasury"]
	var purse: float = s.metrics["lord_gold"]
	var price := MapManors.sell_price_of(data, s, cell)
	sys.execute(sell, s)
	assert_eq(MapManors.owner_of(data, s, cell), house)
	assert_almost_eq(s.metrics["lord_gold"], purse + price, 0.001, "the sale goes to the lord's purse")
	assert_almost_eq(s.metrics["treasury"], before - 2.0, 0.001, "the notary's fee to the crown's")
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

## Building needs the province, not just the manor (owner 2026-09-13): a
## manor bought in another house's province cannot be built on until the
## crown controls the province.
func test_building_needs_a_province_the_crown_controls() -> void:
	var cell := _foreign_manor()
	s.metrics["lord_gold"] = 100000.0
	sys.execute(ActionRequest.make("MANOR_BUY", {"manor": cell}), s)
	assert_true(MapManors.is_crowns(data, s, cell))
	var province := MapManors.province_of(data, cell)
	if MapManors.crown_controls(data, s, province):
		pass_test("a one-manor province: buying it took it")
		return
	assert_string_contains(sys.validate(ActionRequest.make("MANOR_BUILD", {"manor": cell, "building": "mill"}), s),
		"does not control")
	# Take the province manor by manor; then the mill may rise.
	for other: int in MapManors.manors_of_province(data, province):
		if not MapManors.is_crowns(data, s, other):
			MapManors.set_owner(data, s, other, MapManors.crown(s), "test: taken")
	assert_true(MapManors.crown_controls(data, s, province))
	assert_eq(sys.validate(ActionRequest.make("MANOR_BUILD", {"manor": cell, "building": "mill"}), s), "")

## The chief good (owner 2026-09-13): a crown manor in a province the crown
## controls may be turned to any good its land allows, for the focus's
## switch cost and the reeve's fee; the same focus twice, or a manor in a
## province the crown does not control, is refused.
func test_turning_a_manor_to_a_chief_good() -> void:
	var cell := _crown_manor()
	assert_true(MapManors.crown_controls(data, s, MapManors.province_of(data, cell)))
	var allowed := MapManors.focuses_for(data, cell)
	assert_gt(allowed.size(), 1, "the capital's land allows a choice")
	var working := MapManors.focus_of(data, s, cell)
	assert_eq(working, MapManors.default_focus(data, cell), "the default follows the terrain")
	assert_string_contains(sys.validate(ActionRequest.make("MANOR_FOCUS", {"manor": cell, "focus": working}), s),
		"already works")
	assert_string_contains(sys.validate(ActionRequest.make("MANOR_FOCUS", {"manor": cell, "focus": "moon_dust"}), s),
		"No such focus")
	var target := String(allowed[1])
	var req := ActionRequest.make("MANOR_FOCUS", {"manor": cell, "focus": target})
	s.metrics["lord_gold"] = 0.0
	assert_string_contains(sys.validate(req, s), "afford")
	s.metrics["lord_gold"] = 1000.0
	var chest: float = s.metrics["treasury"]
	assert_eq(sys.validate(req, s), "")
	var out := sys.execute(req, s)
	assert_true(out["ok"])
	assert_eq(MapManors.focus_of(data, s, cell), target)
	assert_almost_eq(s.metrics["lord_gold"],
		1000.0 - float(data.manor_focus[target]["switch_cost_gold"]), 0.001,
		"the switch cost from the lord's purse")
	assert_almost_eq(s.metrics["treasury"], chest - 1.0, 0.001, "the reeve's fee (order_costs.csv)")
	assert_eq(int(s.manor_focus[str(cell)]["since"]), s.tick)
	assert_string_contains(String(s.manor_log[0]["reason"]), "turned from")
	assert_string_contains(sys.validate(req, s), "already works")
	# Elsewhere in the realm the crown holds nothing it controls.
	var foreign := _foreign_manor()
	s.metrics["lord_gold"] = 100000.0
	sys.execute(ActionRequest.make("MANOR_BUY", {"manor": foreign}), s)
	if not MapManors.crown_controls(data, s, MapManors.province_of(data, foreign)):
		var f_allowed := MapManors.focuses_for(data, foreign)
		if f_allowed.size() > 1:
			assert_string_contains(sys.validate(ActionRequest.make("MANOR_FOCUS",
				{"manor": foreign, "focus": String(f_allowed[1])}), s), "does not control")

## Room and demolition (owner 2026-09-13): a manor takes manor_slots_base
## works, no more; a building or a work can be pulled down for
## manor_demolish_refund of its cost, less the wreckers' fee.
func test_building_needs_a_free_slot_and_can_be_pulled_down() -> void:
	var cell := _crown_manor()
	s.metrics["treasury"] = 100000.0
	s.metrics["lord_civil"] = 100000.0
	var slots := MapManors.slots_of(data, cell)
	# Only what this ground takes with nothing yet standing: a building
	# whose prerequisite is missing (the abbey before its chapel) is refused,
	# and ActionSystem.execute asserts on a refused request.
	var codes: Array = []
	for code: String in data.manor_buildings.keys():
		if MapManors.building_blocked(data, s, cell, code) == "":
			codes.append(code)
	codes.sort()
	assert_gt(codes.size(), slots, "more kinds of building the ground takes than room")
	for i in slots:
		var built := sys.execute(ActionRequest.make("MANOR_BUILD", {"manor": cell, "building": codes[i]}), s)
		assert_true(built["ok"])
	assert_eq(MapManors.free_slots(data, s, cell), 0)
	assert_string_contains(sys.validate(ActionRequest.make("MANOR_BUILD", {"manor": cell, "building": codes[slots]}), s),
		"no room")
	assert_string_contains(sys.validate(ActionRequest.make("MANOR_DEMOLISH", {"manor": cell, "building": codes[slots]}), s),
		"There is no")
	# A build is paid for in civil goods, so its timber and stone come back
	# to the stores — never to the chest (2026-09-14).
	var before: float = s.metrics["treasury"]
	var stores: float = s.metrics["lord_civil"]
	var stop := ActionRequest.make("MANOR_DEMOLISH", {"manor": cell, "building": codes[0]})
	assert_eq(sys.validate(stop, s), "")
	var out := sys.execute(stop, s)
	assert_true(out["ok"])
	var refund := roundf(float(data.manor_buildings[codes[0]]["civil_cost"])
		* data.bal("manor_demolish_refund"))
	assert_gt(refund, 0.0, "the fixture's building is worth pulling down")
	assert_almost_eq(s.metrics["lord_civil"], stores + refund, 0.001, "the lord's stores take it back")
	assert_almost_eq(s.metrics["treasury"], before - 1.0, 0.001, "the chest pays the wreckers' ale")
	var said := ""
	for e in out["effects"]:
		if String(e.get("metric", "")) == "lord_civil":
			said = String(e.get("reason", ""))
	assert_string_contains(said, "the timber and stone of the")
	assert_false(MapManors.is_building(s, cell, codes[0]))
	assert_eq(MapManors.free_slots(data, s, cell), 1)
	assert_eq(sys.validate(ActionRequest.make("MANOR_BUILD", {"manor": cell, "building": codes[slots]}), s), "")
	# A standing building comes down the same way.
	assert_true(MapManors.build(data, s, cell, codes[0], "test: stood"))
	assert_eq(MapManors.free_slots(data, s, cell), 0)
	assert_true(sys.execute(ActionRequest.make("MANOR_DEMOLISH", {"manor": cell, "building": codes[0]}), s)["ok"])
	assert_false(MapManors.has_building(s, cell, codes[0]))
	assert_string_contains(String(s.manor_log[-1]["reason"]), "pulled down")

## GOODS_BUY / GOODS_SELL (spec §5): the treasury buys a pool's goods at
## the spread and sells them under it, whole gold both ways.
func test_buying_goods_costs_the_spread_and_selling_pays_under_it() -> void:
	var spread := data.bal("goods_trade_spread")
	s.metrics["treasury"] = 1000.0
	s.metrics["strategic"] = 50.0
	s.metrics["grain"] = 50.0
	var out := sys.execute(ActionRequest.make("GOODS_BUY", {"pool": "strategic", "gold": 100}), s)
	assert_true(out["ok"])
	assert_eq(int(s.metrics["strategic"]), 150)
	# The price at the spread, and the factor's fee (order_costs.csv), same as MANOR_BUY's notary.
	assert_eq(int(s.metrics["treasury"]), 1000 - int(roundf(100.0 * (1.0 + spread))) - 1)
	var t := int(s.metrics["treasury"])
	out = sys.execute(ActionRequest.make("GOODS_SELL", {"pool": "civil", "gold": 40}), s)
	assert_true(out["ok"])
	assert_eq(int(s.metrics["grain"]), 10)
	assert_eq(int(s.metrics["treasury"]), t + int(roundf(40.0 * (1.0 - spread))) - 1)

func test_goods_orders_are_validated() -> void:
	s.metrics["treasury"] = 10.0
	s.metrics["grain"] = 5.0
	assert_string_contains(sys.validate(ActionRequest.make("GOODS_BUY", {"pool": "wine", "gold": 10}), s), "pool")
	assert_string_contains(sys.validate(ActionRequest.make("GOODS_BUY", {"pool": "civil", "gold": 0}), s), "gold")
	assert_string_contains(sys.validate(ActionRequest.make("GOODS_BUY", {"pool": "civil", "gold": 100}), s), "afford")
	assert_string_contains(sys.validate(ActionRequest.make("GOODS_SELL", {"pool": "civil", "gold": 100}), s), "only 5")
	assert_eq(sys.validate(ActionRequest.make("GOODS_SELL", {"pool": "civil", "gold": 5}), s), "")

## MANOR_BUILD pays civil goods, not gold (spec §5); MANOR_RUSH pays gold a day.
func test_building_spends_civil_goods_and_rushing_spends_gold() -> void:
	var cell := _crown_manor()
	var civil := int(float(data.manor_buildings["palisade"]["civil_cost"]))
	assert_gt(civil, 0)
	# The lord's own stores and purse pay for his manors (owner 2026-09-14);
	# the crown's treasury pays only the orders' fees.
	s.metrics["lord_civil"] = float(civil - 1)
	s.metrics["grain"] = 100000.0
	s.metrics["treasury"] = 1000.0
	s.metrics["lord_gold"] = 1000.0
	assert_string_contains(sys.validate(ActionRequest.make("MANOR_BUILD", {"manor": cell, "building": "palisade"}), s), "civil goods")
	s.metrics["lord_civil"] = float(civil + 10)
	var t := int(s.metrics["treasury"])
	assert_true(sys.execute(ActionRequest.make("MANOR_BUILD", {"manor": cell, "building": "palisade"}), s)["ok"])
	assert_eq(int(s.metrics["lord_civil"]), 10)
	assert_eq(int(s.metrics["grain"]), 100000, "the crown's stores are not touched")
	assert_eq(int(s.metrics["treasury"]), t - int(OrderCosts.gold_of(data, "MANOR_BUILD")), "only the surveyor")
	var per_day := int(data.bal("build_rush_gold_per_day"))
	t = int(s.metrics["treasury"])
	var purse := int(s.metrics["lord_gold"])
	var left := MapManors.work_days_left(data, s, cell, "palisade")
	assert_true(sys.execute(ActionRequest.make("MANOR_RUSH", {"manor": cell, "building": "palisade", "days": 5}), s)["ok"])
	assert_eq(MapManors.work_days_left(data, s, cell, "palisade"), left - 5)
	assert_eq(int(s.metrics["lord_gold"]), purse - 5 * per_day, "the lord pays the masons")
	assert_eq(int(s.metrics["treasury"]), t - int(OrderCosts.gold_of(data, "MANOR_RUSH")))
	assert_string_contains(sys.validate(ActionRequest.make("MANOR_RUSH", {"manor": cell, "building": "chapel", "days": 1}), s), "no work")

## The levy marches on strategic goods (spec §5): its cost row charges them.
func test_raising_levies_spends_strategic_goods() -> void:
	s.metrics["treasury"] = 1000.0
	s.metrics["strategic"] = 100.0
	var out := sys.execute(ActionRequest.make("LEVY_RAISE"), s)
	assert_true(out["ok"])
	assert_eq(int(s.metrics["strategic"]), 80, "the baggage train took its twenty")
	var reasons: Array[String] = []
	for e in out["effects"]:
		if String(e.get("metric", "")) == "strategic":
			reasons.append(String(e.get("reason", "")))
	assert_true("supplies for training the standing ranks" in reasons,
		"the charge names itself: %s" % str(reasons))

## A pool a cost row draws on cannot go below empty: the order is refused
## before it is charged, never settled into a negative stock.
func test_a_levy_on_an_empty_strategic_stock_is_refused() -> void:
	s.metrics["treasury"] = 1000.0
	s.metrics["strategic"] = 10.0
	var why := sys.validate(ActionRequest.make("LEVY_RAISE"), s)
	assert_string_contains(why, "strategic goods")
	assert_eq(float(s.metrics["strategic"]), 10.0, "a refused order charges nothing")

func test_metric_cost_of_reads_the_rows_pool_charge() -> void:
	assert_eq(OrderCosts.metric_cost_of(data, "LEVY_RAISE", "strategic"), 20.0)
	assert_eq(OrderCosts.metric_cost_of(data, "LEVY_RAISE", "grain"), 0.0)
	assert_eq(OrderCosts.metric_cost_of(data, "COUNCIL_CONSULT", "strategic"), 0.0)

## Where a building may stand (owner 2026-09-14): its `land` must hold on the
## manor, the buildings in its `prereq` must already stand, and every
## building yields something once it does.
func test_buildings_need_their_land_and_their_prerequisites() -> void:
	var cell := _crown_manor()
	s.metrics["lord_civil"] = 100000.0
	s.metrics["lord_gold"] = 100000.0
	# A quay needs the coast: find the crown's inland manor, or skip the check.
	var inland := -1
	for c: int in MapManors.manors_of_house(data, s, MapManors.crown(s), data.resolve_realm("player_realm")):
		if not MapManors.is_coastal(data, c):
			inland = c
			break
	if inland >= 0:
		assert_string_contains(MapManors.building_blocked(data, s, inland, "fishing_quay"), "the coast")
		assert_string_contains(sys.validate(ActionRequest.make("MANOR_BUILD",
			{"manor": inland, "building": "fishing_quay"}), s), "the coast", "the order refuses it too")
	# A market needs a manor house standing.
	assert_string_contains(MapManors.building_blocked(data, s, cell, "market"), "needs a manor house standing first")
	assert_string_contains(sys.validate(ActionRequest.make("MANOR_BUILD",
		{"manor": cell, "building": "market"}), s), "standing first")
	assert_true(MapManors.build(data, s, cell, "manor_house", "test: stood"))
	assert_eq(MapManors.building_blocked(data, s, cell, "market"), "", "with the hall up, the market may rise")
	assert_eq(sys.validate(ActionRequest.make("MANOR_BUILD", {"manor": cell, "building": "market"}), s), "")
	# The land's words read right, and every token kind is understood.
	assert_true(MapManors.land_allows(data, s, cell, "any"))
	assert_true(MapManors.land_allows(data, s, cell, "focus:" + MapManors.focus_of(data, s, cell)))
	assert_false(MapManors.land_allows(data, s, cell, "focus:moon_dust"))
	assert_eq(MapManors.describe_land(data, "coast|town"), "the coast or a town")
	# Every building yields something: goods, or a bonus or a monthly effect.
	for code: String in data.manor_buildings:
		var row: Dictionary = data.manor_buildings[code]
		var yields := float(row.get("produce_units", 0)) > 0.0
		for col in ["tax_bonus", "output_bonus", "defence_bonus", "church_bonus", "gold_per_tick",
				"grain_per_tick", "contentment_per_tick", "unrest_per_tick"]:
			yields = yields or absf(float(row.get(col, 0))) > 0.0
		# The war workshop yields nothing in these columns: it turns the
		# lord's civil goods into strategic goods through WorkshopSystem
		# instead (spec 2026-09-30-ledger-supply-design §2).
		yields = yields or code == WorkshopSystem.BUILDING
		assert_true(yields, "%s yields something" % code)
		for p in MapManors.building_prereqs(data, code):
			assert_true(data.manor_buildings.has(p), "%s needs %s, a real building" % [code, p])
