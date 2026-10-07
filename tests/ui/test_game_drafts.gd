extends GutTest
## Game's drafts (spec 2026-10-02-war-room-v2 §3): planted, reviewed, sealed —
## each draft runs as the real order, in code order; what the chest cannot pay
## stays a draft with its reason.

var codes: Array = []


func before_each() -> void:
	Game.start_campaign(44)
	codes.clear()
	for r: Dictionary in MapObjects.regiments_of(Game.data, Game.data.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) != "1" and ArmySystem.base_pace_km(Game.data, r) > 0:
			codes.append(String(r["regiment_code"]))
	codes.sort()


func _near(code: String) -> Vector2:
	return ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, code)) + Vector2(15, 0)


func test_there_are_two_land_regiments_to_draft() -> void:
	assert_gte(codes.size(), 2)


func test_review_lists_each_draft_with_its_cost_and_the_total() -> void:
	Game.plant_draft(codes[0], "march", _near(codes[0]))
	Game.plant_draft(codes[1], "garrison", Vector2.ZERO)
	var r := Game.review_drafts()
	assert_eq((r["lines"] as Array).size(), 2)
	assert_eq(String(r["lines"][0]["code"]), codes[0], "in code order")
	assert_gt(int(r["lines"][0]["days"]), 0, "a march reads its days")
	var want := 0
	for l: Dictionary in r["lines"]:
		assert_gt(int(l["gold"]), 0)
		assert_eq(String(l["refusal"]), "")
		want += int(l["gold"])
	assert_eq(int(r["total"]), want)


func test_the_review_spends_nothing() -> void:
	Game.plant_draft(codes[0], "march", _near(codes[0]))
	var chest: float = Game.state.metrics["treasury"]
	var riders := Game.state.couriers.size()
	Game.review_drafts()
	assert_eq(Game.state.metrics["treasury"], chest)
	assert_eq(Game.state.couriers.size(), riders)


func test_deploy_runs_every_draft_once_as_its_real_order() -> void:
	Game.plant_draft(codes[0], "march", _near(codes[0]))
	Game.plant_draft(codes[1], "garrison", Vector2.ZERO)
	var total := int(Game.review_drafts()["total"])
	var chest: float = Game.state.metrics["treasury"]
	var riders := Game.state.couriers.size()
	var out := Game.deploy_drafts()
	assert_eq(out["sent"], [codes[0], codes[1]])
	assert_eq(Game.state.couriers.size(), riders + 2, "a courier each")
	assert_almost_eq(chest - float(Game.state.metrics["treasury"]), float(total), 0.5, "the seal costs what the review said")
	assert_false(WarDrafts.any(Game.state))
	assert_eq(Game.deploy_drafts()["sent"], [], "nothing runs twice")


func test_a_deployed_draft_does_not_say_it_was_set_aside() -> void:
	Game.plant_draft(codes[0], "march", _near(codes[0]))
	var heard: Array = []
	var listen := func(t: String) -> void: heard.append(t)
	Game.news_published.connect(listen)
	Game.deploy_drafts()
	Game.news_published.disconnect(listen)
	var effects: Array = Game.state.recent_outcomes.back()["effects"]
	assert_true(effects.all(func(e: Dictionary) -> bool: return String(e.get("metric", "")) != "war_draft"))


func test_what_the_chest_cannot_pay_stays_a_draft_with_its_reason() -> void:
	Game.plant_draft(codes[0], "march", _near(codes[0]))
	Game.plant_draft(codes[1], "march", _near(codes[1]))
	var one := int(Game.review_drafts()["lines"][0]["gold"])
	Game.state.metrics["treasury"] = float(one)   # enough for the first only
	var r := Game.review_drafts()
	assert_eq(String(r["lines"][0]["refusal"]), "")
	assert_ne(String(r["lines"][1]["refusal"]), "", "the review says so before the seal")
	assert_eq(int(r["total"]), one, "a refused line spends nothing")
	var out := Game.deploy_drafts()
	assert_eq(out["sent"], [codes[0]])
	assert_true((out["refused"] as Dictionary).has(codes[1]))
	assert_eq(WarDrafts.codes(Game.state), [codes[1]])
	assert_ne(String(WarDrafts.of(Game.state, codes[1])["refused"]), "")


func test_discard_and_strike() -> void:
	Game.plant_draft(codes[0], "march", _near(codes[0]))
	Game.plant_draft(codes[1], "garrison", Vector2.ZERO)
	Game.strike_draft(codes[0])
	assert_eq(WarDrafts.codes(Game.state), [codes[1]])
	Game.discard_drafts()
	assert_false(WarDrafts.any(Game.state))


func test_every_writer_tells_the_screens() -> void:
	watch_signals(Game)
	Game.plant_draft(codes[0], "march", _near(codes[0]))
	Game.strike_draft(codes[0])
	Game.plant_draft(codes[0], "march", _near(codes[0]))
	Game.discard_drafts()
	assert_signal_emit_count(Game, "state_changed", 4)


## Spec 2026-10-07-march-waypoints ruling 8: a march draft's new load rides as
## its own order before the march when sealed, and the line counts both.
func test_a_draft_with_a_new_load_seals_the_load_then_the_march() -> void:
	var code := String(codes[0])
	var carry := ArmySystem.carry_of(Game.data, Game.state.regiments[code])
	var other := 30 if carry != 30 else 10
	Game.plant_draft(code, "march", _near(code))
	var plain := int(Game.review_drafts()["lines"][0]["gold"])
	var wp := ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, code)) + Vector2(8, 4)
	if MapEconomy.cell_at(Game.data, wp) < 0:
		wp = _near(code)
	Game.plant_draft(code, "march", _near(code), [wp], other)
	var line: Dictionary = Game.review_drafts()["lines"][0]
	assert_eq(String(line["refusal"]), "")
	assert_gt(int(line["gold"]), plain, "the load's courier and order are counted too")
	var riders := Game.state.couriers.size()
	var out := Game.deploy_drafts()
	assert_eq(out["sent"], [code])
	assert_eq(Game.state.couriers.size(), riders + 2, "a courier for the load, one for the march")
	var kinds: Array = []
	for c: Dictionary in Game.state.couriers:
		kinds.append(String(c["order"]["action_code"]))
	assert_eq(kinds.slice(kinds.size() - 2), ["SUPPLY_CARRY_SET", "ARMY_MARCH"], "the load first")
	assert_eq((Game.state.couriers.back()["order"] as Dictionary)["waypoints_m"].size(), 1, "the march keeps its route")
