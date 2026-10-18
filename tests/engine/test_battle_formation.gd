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

func test_flanking_uses_the_armys_position_not_the_enemy_contact_point() -> void:
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
	assert_true(BattleFormation.context(repo, state, battle, "att")["flanked"], "enemy columns stand on opposite sides of this army")
