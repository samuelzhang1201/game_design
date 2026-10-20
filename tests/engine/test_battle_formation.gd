extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")

func test_tactical_formation_has_a_delivered_request() -> void:
	var formation: GDScript = load("res://scripts/engine/battle_formation.gd")
	assert_not_null(formation)
	if formation == null:
		return
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 91)
	var mine := state.regiments.keys()
	mine.sort()
	var foe := state.foes.keys()
	foe.sort()
	var battle := {"id": 987, "att": [mine[0]], "def": [foe[0]], "rounds": 0,
		"place_x_m": 0, "place_y_m": 0, "town": ""}
	state.battles.append(battle)
	var result: Dictionary = formation.request(repo, state, 987, "att", "line")
	assert_eq(result.get("status"), "preparing")
	var snapshot: Dictionary = battle["formations"]["att"].duplicate(true)
	formation.request(repo, state, 987, "att", "line")
	assert_eq(battle["formations"]["att"], snapshot, "repeated request cannot reset exposure")
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	formation.advance(repo, state, battle)
	formation.advance(repo, restored, restored.battles.back())
	assert_eq(restored.battles.back()["formations"], battle["formations"])
	var progressed: Dictionary = battle["formations"].duplicate(true)
	formation.advance(repo, state, battle)
	assert_eq(battle["formations"], progressed, "advance once per day")

func test_four_shapes_preserve_figures() -> void:
	var formation: GDScript = load("res://scripts/engine/battle_formation.gd")
	if formation == null:
		return
	for shape: String in ["line", "wedge", "diamond", "double_rank"]:
		var slots: Array = formation.slots(shape, 9)
		assert_eq(slots.size(), 9, shape)
		var unique := {}
		for slot: Vector2 in slots:
			unique[slot] = true
		assert_eq(unique.size(), 9, shape + " has no overlap")

func _apply(base: int, result: Dictionary) -> int:
	var seen := {}
	for factor: Dictionary in result["factors"]:
		assert_false(seen.has(factor["source"]), "each source occurs once")
		seen[factor["source"]] = true
		@warning_ignore("integer_division")
		base = base * int(factor["permille"]) / 1000
	return base

func test_terrain_flanks_and_real_centre_hand_values() -> void:
	var repo := SuiteData.repo()
	var line := BattleFormation.evaluate(repo, "line", {"width_m": 250}, false)
	assert_eq(line["frontage_m"], 250)
	assert_eq(_apply(630, line), 661, "630 × 1050 / 1000")
	assert_eq(_apply(630, BattleFormation.evaluate(repo, "wedge", {}, true)), 756)
	assert_eq(_apply(630, BattleFormation.evaluate(repo, "wedge", {"flanked": true}, true)), 642)
	assert_eq(_apply(630, BattleFormation.evaluate(repo, "double_rank", {}, false)), 724)
	assert_eq(_apply(630, BattleFormation.evaluate(repo, "double_rank", {"flanked": true}, false)), 615)
	assert_eq(_apply(630, BattleFormation.evaluate(repo, "diamond", {"centre": "king"}, false)), 724)
	assert_eq(_apply(630, BattleFormation.evaluate(repo, "diamond", {"centre": "king", "flanked": true}, false)), 796)
	var empty := BattleFormation.evaluate(repo, "diamond", {}, false)
	assert_eq(_apply(630, empty), 630)
	assert_true(String(empty["reason"]).contains("no king"))

func test_formation_order_uses_existing_local_and_courier_paths() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 92)
	var mine := state.regiments.keys()
	mine.sort()
	var code := String(mine[0])
	var battle := {"id": 986, "att": [code], "def": [state.foes.keys()[0]], "rounds": 0,
		"place_x_m": 0, "place_y_m": 0, "town": ""}
	state.battles.append(battle)
	var at := ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, code, state)))
	state.king_state["x_m"] = at.x
	state.king_state["y_m"] = at.y
	state.metrics["treasury"] = 10000.0
	var actions := ActionSystem.new(repo)
	var req := ActionRequest.make("BATTLE_FORMATION", {"regiment": code, "battle_id": 986, "formation": "line"})
	assert_eq(actions.validate(req, state), "")
	actions.execute(req, state)
	assert_eq(battle.get("formations", {}).get("att", {}).get("target", ""), "line")
	assert_eq(state.couriers.size(), 0)
	var local: Dictionary = battle["formations"]["att"].duplicate(true)
	state.king_state["x_m"] = at.x + 1000000
	state.king_state["y_m"] = at.y + 1000000
	req.params["formation"] = "double_rank"
	assert_eq(actions.validate(req, state), "")
	actions.execute(req, state)
	assert_eq(battle["formations"]["att"], local, "issuing remote order does not start changing")
	assert_eq(state.couriers.size(), 1)
	var courier: Dictionary = state.couriers.back()
	var order: Dictionary = CourierSystem.first_order(courier)
	CourierSystem._deliver_one(repo, state, courier, order)
	assert_eq(battle["formations"]["att"]["target"], "double_rank")
	var delivered: Dictionary = battle["formations"]["att"].duplicate(true)
	CourierSystem._deliver_one(repo, state, courier, order)
	assert_eq(battle["formations"]["att"], delivered, "duplicate arrival is idempotent")
	state.battles.clear()
	assert_eq(CourierSystem._deliver_one(repo, state, courier, order)["type"], "lapsed")

func test_fit_nobles_organize_once_per_day_hand_values() -> void:
	var repo := SuiteData.repo()
	var state := GameState.new()
	state.military_rosters["fixture"] = {"cohort_ids": ["common", "noble"]}
	state.military_cohorts = {
		"common": {"unit_code": "fixture", "identity": "commoner", "stage": "active", "fit": 570, "wounded": 0},
		"noble": {"unit_code": "fixture", "identity": "noble", "stage": "active", "fit": 30, "wounded": 0}}
	repo.noble_quality["noble"]["discipline_permille"] = 2000
	var battle := {"id": 98, "att": ["fixture"], "def": []}
	BattleFormation.ensure(battle)
	var change: Dictionary = battle["formations"]["att"]
	change["target"] = "line"
	change["required_progress"] = 2000
	BattleFormation.advance(repo, state, battle)
	assert_eq(change["progress"], 1050, "(570×1000 + 30×2000)/600")
	BattleFormation.advance(repo, state, battle)
	assert_eq(change["progress"], 1050)
	state.day += 1
	BattleFormation.advance(repo, state, battle)
	assert_eq(change["progress"], 2000)
	assert_eq(change["current"], "line")
	state.military_cohorts["noble"]["fit"] = 15
	state.military_cohorts["noble"]["wounded"] = 15
	assert_eq(MilitaryQuality.profile(repo, state, "fixture")["discipline_permille"], 1025)

func test_retarget_preserves_disorder_and_never_stacks_new_benefits() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 94)
	var mine := state.regiments.keys()
	mine.sort()
	var code := String(mine[0])
	var battle := {"id": 984, "att": [code], "def": [state.foes.keys()[0]], "place_x_m": 0, "place_y_m": 0, "town": ""}
	state.battles.append(battle)
	BattleFormation.ensure(battle)
	var change: Dictionary = battle["formations"]["att"]
	change["current"] = "line"
	change["target"] = "line"
	change["disorder_until"] = state.absolute_day() + 10
	var deadline := int(change["disorder_until"])
	BattleFormation.request(repo, state, 984, "att", "diamond")
	assert_eq(change["disorder_until"], deadline)
	repo.battle_formations["line"]["narrow_terrains"] = ""
	var factors: Array = BattleFormation.effects(repo, state, battle, "att", false)["factors"]
	assert_eq(factors[0]["reason"], "Extended line")
	assert_eq(factors.back()["source"], "formation:disorder")
	assert_eq(factors.back()["permille"], 800)
	assert_eq(_apply(630, {"factors": factors}), 554, "old line 1100 then disorder 800; target diamond is absent")

func test_batched_formation_orders_apply_in_order_and_replay_once() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 96)
	var codes := state.regiments.keys()
	codes.sort()
	var code := String(codes[0])
	var battle := {"id": 983, "att": [code], "def": [state.foes.keys()[0]], "place_x_m": 0, "place_y_m": 0, "town": ""}
	state.battles.append(battle)
	var courier := CourierSystem.dispatch(repo, state, CourierSystem.ORDINARY, code,
		{"action_code": "BATTLE_FORMATION", "battle_id": 983, "formation": "line"})
	CourierSystem.dispatch(repo, state, CourierSystem.ORDINARY, code,
		{"action_code": "BATTLE_FORMATION", "battle_id": 983, "formation": "diamond"})
	assert_eq(state.couriers.size(), 1)
	assert_eq(CourierSystem.orders_of(courier).size(), 2)
	CourierSystem._deliver(repo, state, courier)
	assert_eq(battle["formations"]["att"]["target"], "diamond", "last warrant in a shared courier takes effect")
	var saved: Dictionary = battle["formations"].duplicate(true)
	CourierSystem._deliver(repo, state, courier)
	assert_eq(battle["formations"], saved, "replaying the entire courier does not restart an older formation")
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	CourierSystem._deliver(repo, restored, restored.couriers.back())
	assert_eq(restored.battles.back()["formations"], saved, "save and replay preserve the applied sequence")

func test_distant_opposite_columns_do_not_flank_without_group_contact() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 97)
	var ours := state.regiments.keys()
	ours.sort()
	var foes := state.foes.keys()
	foes.sort()
	var code := String(ours[0])
	state.regiments[code]["x_m"] = 1000
	state.regiments[code]["y_m"] = 0
	state.foes[foes[0]]["x_m"] = 0
	state.foes[foes[0]]["y_m"] = 0
	state.foes[foes[1]]["x_m"] = 2000
	state.foes[foes[1]]["y_m"] = 0
	var battle := {"att": [code], "def": [foes[0], foes[1]], "place_x_m": 0, "place_y_m": 0}
	BattleGroups.refresh(repo, state, battle)
	assert_false(BattleFormation.context(repo, state, battle, "att")["flanked"], "opposite distant columns have no actual group contact")

func _unit_fixture() -> Dictionary:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 981)
	var codes := state.regiments.keys()
	codes.sort()
	var battle := {"id": 981, "att": [codes[0], codes[1]], "def": [state.foes.keys()[0]],
		"place_x_m": 0, "place_y_m": 0, "town": ""}
	state.battles = [battle]
	BattleFormation.ensure(battle)
	return {"repo": repo, "state": state, "battle": battle, "a": String(codes[0]), "b": String(codes[1])}

func test_unit_deployment_is_isolated_from_side_requests_and_combat_reads_it() -> void:
	var f := _unit_fixture()
	var side: Dictionary = f.battle.formations.att.duplicate(true)
	var before: Dictionary = BattleSystem.unit_strength(f.repo, f.state, f.b, Callable(), false)
	assert_eq(BattleFormation.request(f.repo, f.state, 981, "att", "line", f.a).status, "preparing")
	assert_eq(f.battle.formations.att, side)
	assert_eq(BattleSystem.unit_strength(f.repo, f.state, f.b, Callable(), false), before)
	var unit: Dictionary = f.battle.unit_formations[f.a]
	assert_eq(unit.current, "double_rank", "new benefits wait for actual preparation")
	assert_eq(unit.target, "line")
	var saved := unit.duplicate(true)
	assert_eq(BattleFormation.request(f.repo, f.state, 981, "att", "line", f.a).status, "unchanged")
	assert_eq(unit, saved, "replay preserves progress and exposure")
	BattleFormation.request(f.repo, f.state, 981, "att", "diamond")
	assert_eq(unit, saved, "legacy side deployment does not rewrite an explicit unit deployment")
	unit.current = "line"
	unit.disorder_until = -1
	f.repo.battle_formations.line.narrow_terrains = ""
	assert_eq(BattleFormation.of_unit(f.state, f.a), "line")
	assert_eq(BattleFormation.of_unit(f.state, f.b), "double_rank")
	var strength := BattleSystem.unit_strength(f.repo, f.state, f.a, Callable(), false)
	var factors: Array = strength["factors"]
	assert_true(factors.any(func(factor: Dictionary) -> bool:
		return factor.source == "formation:deployment" and factor.permille == 1100), "combat uses recipient line")

func test_unit_suitability_and_invalid_membership_are_atomic() -> void:
	var f := _unit_fixture()
	f.repo.battle_formations.line.min_morale = 50
	f.state.regiments[f.a].morale = 100
	f.state.regiments[f.b].morale = 1
	assert_ne(BattleFormation.refusal(f.repo, f.state, 981, "att", "line"), "")
	assert_eq(BattleFormation.refusal(f.repo, f.state, 981, "att", "line", f.a), "")
	var saved: Dictionary = f.state.to_dict()
	assert_eq(BattleFormation.request(f.repo, f.state, 981, "att", "line", "absent").status, "invalid")
	assert_eq(BattleFormation.request(f.repo, f.state, 981, "def", "line", f.a).status, "invalid")
	assert_eq(BattleFormation.request(f.repo, f.state, 981, "att", "unknown", f.a).status, "invalid")
	assert_eq(f.state.to_dict(), saved)
	assert_eq(BattleFormation.request(f.repo, f.state, 981, "att", "line", f.a).status, "preparing")

func test_unit_progress_inherits_side_state_then_uses_only_recipient_and_json_replays() -> void:
	var f := _unit_fixture()
	var side: Dictionary = f.battle.formations.att
	side.current = "line"
	side.target = "line"
	side.disorder_until = f.state.absolute_day() + 20
	f.state.military_rosters[f.a] = {"cohort_ids": ["unit-common", "unit-noble"]}
	f.state.military_cohorts["unit-common"] = {"unit_code": f.a, "identity": "commoner", "stage": "active", "fit": 570, "wounded": 0}
	f.state.military_cohorts["unit-noble"] = {"unit_code": f.a, "identity": "noble", "stage": "active", "fit": 30, "wounded": 0}
	f.repo.noble_quality.noble.discipline_permille = 2000
	f.repo.battle_formations.diamond.change_progress = 2000
	assert_eq(BattleFormation.request(f.repo, f.state, 981, "att", "diamond", f.a).status, "preparing")
	var unit: Dictionary = f.battle.unit_formations[f.a]
	assert_eq(unit.current, "line")
	assert_eq(unit.disorder_until, side.disorder_until, "cannot shorten inherited exposure")
	f.repo.battle_formations.line.narrow_terrains = ""
	var effects := BattleFormation.effects(f.repo, f.state, f.battle, "att", false, f.a)
	assert_eq(effects.factors[0].reason, "Extended line", "only the current deployment grants benefits")
	assert_eq(effects.factors.back().source, "formation:disorder")
	assert_eq(effects.factors.back().permille, 800)
	var deadline := int(unit.disorder_until)
	BattleFormation.request(f.repo, f.state, 981, "att", "double_rank", f.a)
	assert_eq(unit.disorder_until, deadline, "unit retargeting cannot shorten exposure")
	BattleFormation.request(f.repo, f.state, 981, "att", "diamond", f.a)
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
	BattleFormation.advance(f.repo, f.state, f.battle)
	BattleFormation.advance(f.repo, restored, restored.battles[0])
	assert_eq(unit.progress, 1050, "recipient only: (570×1000 + 30×2000)/600")
	assert_eq(restored.battles, f.state.battles)
	BattleFormation.advance(f.repo, f.state, f.battle)
	assert_eq(unit.progress, 1050, "only once each completed day")
	f.state.day += 1
	BattleFormation.advance(f.repo, f.state, f.battle)
	assert_eq(unit.current, "diamond")
	assert_eq(unit.progress, 2000)
	f.battle.att.erase(f.a)
	f.state.day += 1
	var departed := unit.duplicate(true)
	BattleFormation.advance(f.repo, f.state, f.battle)
	assert_eq(unit, departed, "departed recipients do not continue preparing")
