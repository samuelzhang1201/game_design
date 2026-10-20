extends GutTest
## P4.4c2: the saved gait and the running march (spec 2026-10-17-unit-behavior-
## and-battlefield-design §5). Hand-computed on flat open ground at 1 000 m a
## day: a 2 300 m march is three days, today's budget ceil(2300 / 3) = 767 over
## ten substeps, 77 × 7 + 76 × 3. Running: 92 × 7 + 91 × 3 = 917 (1200‰,
## whole metres). 30 000 commoners on the plains use 30 000 × 1000‰ × 100‰ ×
## 1000‰ = 3 000 a month; day 10's bite is 1 000 − 900 = 100, and a running
## substep of all of them pays 100 × 300 / 10 000 = 3.
const Personnel := preload("res://tests/engine/personnel_helpers.gd")
const SuiteData := preload("res://tests/suite_data.gd")
const BattleScenario := preload("res://tests/fixtures/battle_scenario.gd")

func _fixture(supplies: int) -> Dictionary:
	var repo := SuiteData.flat_ground(SuiteData.repo())
	var state := SuiteData.campaign(repo, 24601)
	state.tick = 1
	state.day = 10
	state.foes.clear()
	state.ai_hosts.clear()
	state.battles.clear()
	for arm: String in repo.army_speed:
		repo.army_speed[arm] = 1
	repo.balance["army_clearance_on"] = 0.0
	var codes: Array = state.regiments.keys()
	codes.sort()
	var code := String(codes[0])
	assert_false(Personnel.replace(repo, state, code, 30000).has("error"))
	var entry: Dictionary = state.regiments[code]
	entry["morale"] = 100
	entry["training"] = 100
	entry["carry_days"] = 10
	entry["supplies"] = supplies
	var start := Vector2i(1000000, 1000000)
	entry["x_m"] = start.x
	entry["y_m"] = start.y
	entry["dest_x_m"] = start.x
	entry["dest_y_m"] = start.y
	ArmySystem.set_march_m(repo, state, code, start + Vector2i(2300, 0))
	return {"repo": repo, "state": state, "code": code, "start": start, "other": String(codes[1])}

func _begin(f: Dictionary) -> void:
	var repo: DataRepository = f.repo
	var state: GameState = f.state
	var tx := DayResolution.begin(state.day, false, state.absolute_day(), int(repo.bal("battle_substeps")))
	tx["march_entries"] = {f.code: state.regiments[f.code].duplicate(true)}
	tx["march_budgets"] = {f.code: ArmySystem.day_walk_budget(repo, state, f.code)}
	state.day_resolution = tx

func _substeps(repo: DataRepository, state: GameState, from: int, to: int) -> void:
	for i in range(from, to):
		ArmySystem.march_day_saved(repo, state, int(repo.bal("battle_substeps")), i,
			state.day_resolution["march_entries"], state.day_resolution["march_budgets"])

func _walked(f: Dictionary, state: GameState = null) -> int:
	var s: GameState = f.state if state == null else state
	return int(s.regiments[f.code]["x_m"]) - (f.start as Vector2i).x

func _join_fixture(martial: int, boldness: int) -> Dictionary:
	var f := _fixture(1000)
	var roster: Dictionary = f.state.military_rosters[f.code]
	var officer: Dictionary = {}
	for id: String in roster["cohort_ids"]:
		var cohort: Dictionary = f.state.military_cohorts[id]
		if not String(cohort.get("person_id", "")).is_empty():
			officer = cohort
			break
	assert_false(officer.is_empty(), "opening unit had a named officer before replacement")
	var person := String(officer["person_id"])
	assert_false(Personnel.move(f.repo, f.state, f.code, "fit", "released", 1).has("error"))
	var raised := MilitaryRoster.mobilize(f.repo, f.state, "gait:officer", [{
		"id": "gait:officer", "unit_code": f.code,
		"source_province": officer["source_province"],
		"source_population_field": officer["source_population_field"],
		"identity": "noble", "family_name": officer["family_name"],
		"person_id": person, "stage": "active", "count": 1}], "Gait fixture officer")
	assert_false(raised.has("error"), str(raised))
	var assigned := MilitaryCommanders.assign(f.repo, f.state, f.code, person, "Gait fixture appointment")
	assert_false(assigned.has("error"), str(assigned))
	f.state.characters[person].skills["sk_martial"] = martial
	f.state.characters[person].attributes["boldness"] = boldness
	f["person"] = person
	f.repo.balance["army_run_martial_weight"] = 5
	f.repo.balance["army_run_min_score"] = 100
	var dest := (f.start as Vector2i) + Vector2i(2300, 0)
	f.state.battles.append({"id": 7, "att": [f.other], "def": [], "place_x_m": dest.x, "place_y_m": dest.y})
	return f

func test_fixture_numbers() -> void:
	var f := _fixture(1000)
	var repo: DataRepository = f.repo
	var reg := ArmySystem.regiment(repo, f.code, f.state)
	assert_eq(ArmySystem.supply_use(repo, reg, f.state), 3000)
	assert_eq(ArmySystem.day_bite(3000, 10), 100)
	assert_eq(ArmySystem.day_walk_budget(repo, f.state, f.code), 767)

func test_an_ordinary_march_walks_and_saves_no_gait() -> void:
	var f := _fixture(1000)
	_begin(f)
	_substeps(f.repo, f.state, 0, 10)
	assert_eq(_walked(f), 767)
	assert_eq(int(f.state.regiments[f.code]["supplies"]), 1000, "the base is eaten by eat_day, not the march")
	assert_false(f.state.regiments[f.code].has("gait"))

func test_a_withdrawal_march_runs_and_pays_the_increment() -> void:
	var f := _context_fixture("withdrawal")
	f.state.regiments[f.code]["disengaging"] = 1
	_begin(f)
	_substeps(f.repo, f.state, 0, 10)
	assert_eq(_walked(f), 917, "92 × 7 + 91 × 3")
	assert_eq(int(f.state.regiments[f.code]["supplies"]), 970, "3 a substep; the base 100 waits for eat_day")
	assert_eq(int(f.state.regiments[f.code].get("run_supply_rem", 0)), 0)
	assert_eq(f.state.regiments[f.code]["gait"],
		{"mode": "run", "reason": "withdrawal", "until": "march_end"})

func test_wounded_keep_only_their_base() -> void:
	var f := _context_fixture("withdrawal")
	assert_false(Personnel.move(f.repo, f.state, f.code, "fit", "wounded", 15000).has("error"))
	f.state.regiments[f.code]["disengaging"] = 1
	_begin(f)
	_substeps(f.repo, f.state, 0, 10)
	# runners' bite 100 × 15 000 / 30 000 = 50: 15 000 / 10 000 a substep,
	# 1, 2, 1, 2 … = 15 over the day, remainder 0.
	assert_eq(_walked(f), 917)
	assert_eq(int(f.state.regiments[f.code]["supplies"]), 985)
	assert_eq(int(f.state.regiments[f.code].get("run_supply_rem", 0)), 0)

func test_json_mid_day_equals_straight_through() -> void:
	var straight := _context_fixture("withdrawal")
	assert_false(Personnel.move(straight.repo, straight.state, straight.code, "fit", "wounded", 15000).has("error"))
	straight.state.regiments[straight.code]["disengaging"] = 1
	_begin(straight)
	_substeps(straight.repo, straight.state, 0, 3)
	assert_eq(int(straight.state.regiments[straight.code]["run_supply_rem"]), 5000, "1, 2, 1 paid; half carried")
	var restored := BattleScenario.roundtrip(straight.state)
	_substeps(straight.repo, straight.state, 3, 10)
	_substeps(straight.repo, restored, 3, 10)
	for key: String in ["x_m", "supplies", "run_supply_rem", "gait"]:
		assert_eq(restored.regiments[straight.code].get(key), straight.state.regiments[straight.code].get(key), key)

func test_supplies_at_the_base_walk_and_pay_nothing() -> void:
	var f := _context_fixture("withdrawal", 10, 50, 100)
	f.state.regiments[f.code]["disengaging"] = 1
	_begin(f)
	_substeps(f.repo, f.state, 0, 10)
	assert_eq(_walked(f), 767)
	assert_eq(int(f.state.regiments[f.code]["supplies"]), 100)
	assert_eq(String(f.state.regiments[f.code]["gait"]["mode"]), "run", "the reason holds; each substep walks")

func test_103_in_hand_runs_one_substep() -> void:
	var f := _context_fixture("withdrawal", 10, 50, 103)
	f.state.regiments[f.code]["disengaging"] = 1
	_begin(f)
	_substeps(f.repo, f.state, 0, 10)
	# 92 + 77 × 6 + 76 × 3: the last substep's catch-up (767 − 706 = 61) stays below 76.
	assert_eq(_walked(f), 782)
	assert_eq(int(f.state.regiments[f.code]["supplies"]), 100)

func test_a_march_to_join_a_known_battle_runs_until_it_ends() -> void:
	var f := _join_fixture(10, 50)
	_begin(f)
	_substeps(f.repo, f.state, 0, 5)
	assert_eq(_walked(f), 460, "92 × 5")
	assert_eq(f.state.regiments[f.code]["gait"],
		{"mode": "run", "reason": "join_battle", "until": "battle_over", "battle_id": 7})
	f.state.battles.clear()
	_substeps(f.repo, f.state, 5, 10)
	# 77 × 2 + 76 × 3 walked once the battle is over.
	assert_eq(_walked(f), 842)
	assert_false(f.state.regiments[f.code].has("gait"))
	assert_eq(int(f.state.regiments[f.code]["supplies"]), 985)

func test_voluntary_run_needs_both_the_ability_and_personality_score() -> void:
	# 10*5+49=99 walks; +1 boldness reaches 100. At boldness 45,
	# martial 10 scores 95; martial 11 reaches the same inclusive threshold.
	for row: Array in [[10, 49, 767, 1000], [10, 50, 917, 970],
			[10, 45, 767, 1000], [11, 45, 917, 970]]:
		var f := _join_fixture(row[0], row[1])
		_begin(f)
		_substeps(f.repo, f.state, 0, 10)
		assert_eq(_walked(f), row[2], str(row))
		assert_eq(int(f.state.regiments[f.code]["supplies"]), row[3], str(row))
		assert_eq(f.state.regiments[f.code]["order"], ArmySystem.ORDER_MARCH,
			"choosing walk never vetoes the march")

func test_voluntary_run_rechecks_changed_commander_and_survives_json() -> void:
	var f := _join_fixture(10, 50)
	_begin(f)
	_substeps(f.repo, f.state, 0, 3)
	var restored := BattleScenario.roundtrip(f.state)
	f.state.characters[f.person].attributes["boldness"] = 49
	restored.characters[f.person].attributes["boldness"] = 49
	_substeps(f.repo, f.state, 3, 10)
	_substeps(f.repo, restored, 3, 10)
	assert_eq(_walked(f), 812, "92*3 + 77*4 + 76*3; the next substep walks")
	assert_eq(int(f.state.regiments[f.code]["supplies"]), 991)
	assert_false(f.state.regiments[f.code].has("gait"))
	assert_eq(SaveLoad.state_hash(restored), SaveLoad.state_hash(f.state))

func test_unavailable_commander_cannot_choose_a_voluntary_run() -> void:
	var f := _join_fixture(20, 100)
	_begin(f)
	_substeps(f.repo, f.state, 0, 1)
	f.state.characters[f.person].attributes["health"] = 0
	_substeps(f.repo, f.state, 1, 10)
	assert_eq(_walked(f), 782)
	assert_false(f.state.regiments[f.code].has("gait"))
	assert_eq(int(f.state.regiments[f.code]["supplies"]), 997)

func test_missing_commander_walks_to_the_known_battle() -> void:
	var f := _join_fixture(20, 100)
	f.state.military_rosters[f.code]["commander_id"] = ""
	_begin(f)
	_substeps(f.repo, f.state, 0, 10)
	assert_eq(_walked(f), 767)
	assert_false(f.state.regiments[f.code].has("gait"))

func test_tuning_changes_voluntary_choice_but_never_creates_a_reason() -> void:
	var f := _join_fixture(10, 50)
	f.repo.balance["army_run_min_score"] = 101
	_begin(f)
	_substeps(f.repo, f.state, 0, 1)
	assert_eq(_walked(f), 77)
	f.repo.balance["army_run_martial_weight"] = 6
	_substeps(f.repo, f.state, 1, 2)
	assert_eq(_walked(f), 169, "60+50 reaches 101")
	f.state.battles.clear()
	_substeps(f.repo, f.state, 2, 3)
	assert_eq(_walked(f), 246, "even a willing commander walks without a known reason")

func test_a_battle_beyond_reach_of_the_destination_gives_no_reason() -> void:
	var f := _fixture(1000)
	var far := (f.start as Vector2i) + Vector2i(2300 + int(f.repo.bal("battle_contact_km") * 1000) + 1, 0)
	f.state.battles.append({"id": 7, "att": [f.other], "def": [], "place_x_m": far.x, "place_y_m": far.y})
	_begin(f)
	_substeps(f.repo, f.state, 0, 10)
	assert_eq(_walked(f), 767)
	assert_false(f.state.regiments[f.code].has("gait"))

func test_packing_is_not_shortened() -> void:
	var f := _context_fixture("withdrawal")
	var entry: Dictionary = f.state.regiments[f.code]
	entry["disengaging"] = 1
	entry["camp_state"] = {"phase": CampSystem.PACKING, "move_not_before_day": f.state.absolute_day() + 1}
	_begin(f)
	_substeps(f.repo, f.state, 0, 10)
	assert_eq(_walked(f), 0)
	assert_eq(int(entry["supplies"]), 1000)

func _context_fixture(reason: String, martial := 10, boldness := 50, supplies := 1000) -> Dictionary:
	var f := _join_fixture(martial, boldness)
	f.state.battles.clear()
	f.state.regiments[f.code]["supplies"] = supplies
	if reason == "withdrawal":
		f.state.regiments[f.code]["disengaging"] = 1
	else:
		# A received, authorized pursuit's known-target phase; no hidden target lookup.
		f.state.unit_tasks[f.code] = {"current_id": "gait:pursue", "orders": {
			"gait:pursue": {"status": "received", "request": {"task": "pursue", "target_unit": "unseen"},
				"track": {"phase": "follow"}}}}
	return f

func test_pursuit_and_withdrawal_use_the_live_commander_score() -> void:
	for reason: String in ["pursuit", "withdrawal"]:
		for row: Array in [[10, 49, 767, 1000], [10, 50, 917, 970], [11, 45, 917, 970]]:
			var f := _context_fixture(reason, row[0], row[1])
			_begin(f)
			_substeps(f.repo, f.state, 0, 10)
			assert_eq(_walked(f), row[2], reason + str(row))
			assert_eq(int(f.state.regiments[f.code]["supplies"]), row[3])
			assert_eq(f.state.regiments[f.code]["order"], ArmySystem.ORDER_MARCH)
			assert_eq(String(f.state.regiments[f.code].get("gait", {}).get("reason", "")),
				reason if row[2] == 917 else "")

func test_context_choice_rechecks_after_json_and_stops_with_context() -> void:
	for reason: String in ["pursuit", "withdrawal"]:
		var f := _context_fixture(reason)
		_begin(f)
		_substeps(f.repo, f.state, 0, 3)
		var restored := BattleScenario.roundtrip(f.state)
		for state: GameState in [f.state, restored]:
			state.characters[f.person].attributes["boldness"] = 49
			_substeps(f.repo, state, 3, 10)
			assert_eq(_walked(f, state), 812)
			assert_eq(int(state.regiments[f.code]["supplies"]), 991)
			assert_false(state.regiments[f.code].has("gait"))
		assert_eq(SaveLoad.state_hash(restored), SaveLoad.state_hash(f.state))
		f.state.characters[f.person].attributes["boldness"] = 50
		var entry: Dictionary = f.state.regiments[f.code]
		UnitGait.refresh(f.repo, f.state, f.code, entry)
		assert_eq(String(entry.gait.reason), reason)
		entry.erase("disengaging")
		f.state.unit_tasks.clear()
		UnitGait.refresh(f.repo, f.state, f.code, entry)
		assert_false(entry.has("gait"))

func test_context_without_commander_or_incremental_supply_still_walks() -> void:
	for reason: String in ["pursuit", "withdrawal"]:
		for missing: bool in [true, false]:
			var f := _context_fixture(reason, 10, 50, 100 if not missing else 1000)
			if missing:
				f.state.military_rosters[f.code]["commander_id"] = ""
			_begin(f)
			_substeps(f.repo, f.state, 0, 10)
			assert_eq(_walked(f), 767)
			assert_eq(int(f.state.regiments[f.code]["supplies"]), 1000 if missing else 100)
			assert_eq(f.state.regiments[f.code]["order"], ArmySystem.ORDER_MARCH)

func test_context_eligibility_and_known_phase_exclude_hidden_truth() -> void:
	for reason: String in ["pursuit", "withdrawal"]:
		var f := _context_fixture(reason)
		var entry: Dictionary = f.state.regiments[f.code]
		UnitGait.refresh(f.repo, f.state, f.code, entry)
		assert_eq(String(entry.gait.reason), reason)
		f.state.characters[f.person].attributes["health"] = 0
		UnitGait.refresh(f.repo, f.state, f.code, entry)
		assert_false(entry.has("gait"))
	var f := _context_fixture("pursuit")
	var entry: Dictionary = f.state.regiments[f.code]
	# Hidden real position, strength and supplies cannot change an already known follow phase.
	f.state.foes["unseen"] = {"x_m": -999999, "y_m": -999999, "supplies": 0}
	UnitGait.refresh(f.repo, f.state, f.code, entry)
	assert_eq(String(entry.gait.reason), "pursuit")
	f.state.unit_tasks[f.code]["orders"]["gait:pursue"]["track"]["phase"] = "search"
	UnitGait.refresh(f.repo, f.state, f.code, entry)
	assert_false(entry.has("gait"), "a hidden target does not create a new run reason")


func _key_point_fixture() -> Dictionary:
	var f := _join_fixture(10, 50)
	f.state.battles.clear()
	f.state.sightings.clear()
	var town := String(TownStores.realm_towns(f.repo, f.state)[0])
	for weather: Dictionary in f.repo.weather_kinds.values():
		weather["speed_permille"] = 1000
	for tier: Dictionary in f.repo.army_height_supply:
		tier["supply_permille"] = 1000
	var burg: Dictionary = f.repo.burgs[town]
	var dest := ArmySystem.pack_to_metres(f.repo, Vector2(float(burg.x), float(burg.y)))
	f.start = dest - Vector2i(2300, 0)
	f.state.regiments[f.code]["x_m"] = f.start.x
	f.state.regiments[f.code]["y_m"] = f.start.y
	ArmySystem.set_march_m(f.repo, f.state, f.code, dest)
	f.state.sightings["known"] = {"kind": "unit", "code": "known", "x_m": dest.x,
		"y_m": dest.y, "day": f.state.absolute_day(), "source": "spy", "men": 100}
	f["town"] = ArmySystem.town_at(f.repo, ArmySystem.metres_to_pack(f.repo, dest))
	return f

func test_known_contested_town_runs_with_actual_march_and_food() -> void:
	var f := _key_point_fixture()
	_begin(f)
	_substeps(f.repo, f.state, 0, 10)
	assert_eq(_walked(f), 917)
	assert_eq(int(f.state.regiments[f.code]["supplies"]), 970)
	assert_eq(f.state.regiments[f.code].get("gait", {}),
		{"mode": "run", "reason": "key_point", "until": "town_clear", "town": f.town})

func test_known_key_point_stops_and_json_preserves_real_march() -> void:
	var f := _key_point_fixture()
	_begin(f)
	_substeps(f.repo, f.state, 0, 3)
	var restored := BattleScenario.roundtrip(f.state)
	for state: GameState in [f.state, restored]:
		state.sightings.clear()
		_substeps(f.repo, state, 3, 10)
		assert_eq(_walked(f, state), 812)
		assert_eq(int(state.regiments[f.code]["supplies"]), 991)
		assert_false(state.regiments[f.code].has("gait"))
	assert_eq(SaveLoad.state_hash(restored), SaveLoad.state_hash(f.state))

func test_key_point_requires_known_evidence_and_live_willing_commander() -> void:
	for mode: String in ["safe", "rumour", "expired", "empty", "unwilling", "missing", "base_only", "elsewhere"]:
		var f := _key_point_fixture()
		match mode:
			"safe": f.state.sightings.clear()
			"rumour": f.state.sightings.known.source = "rumour"
			"expired": f.state.sightings.known.day -= int(f.repo.bal("ghost_keep_days")) + 1
			"empty": f.state.sightings.known.men = 0
			"unwilling": f.state.characters[f.person].attributes.boldness = 49
			"missing": f.state.military_rosters[f.code].commander_id = ""
			"base_only": f.state.regiments[f.code].supplies = 100
			"elsewhere": f.state.sightings.known.x_m += 1000000
		_begin(f)
		_substeps(f.repo, f.state, 0, 10)
		assert_eq(_walked(f), 767, mode)
		assert_eq(int(f.state.regiments[f.code].supplies), 100 if mode == "base_only" else 1000, mode)

func test_key_point_never_uses_hidden_enemy_truth() -> void:
	var f := _key_point_fixture()
	UnitGait.refresh(f.repo, f.state, f.code, f.state.regiments[f.code])
	var gait: Dictionary = f.state.regiments[f.code].get("gait", {}).duplicate(true)
	assert_false(gait.is_empty())
	f.state.foes["known"] = {"x_m": -999999, "y_m": -999999, "supplies": 0}
	UnitGait.refresh(f.repo, f.state, f.code, f.state.regiments[f.code])
	assert_eq(f.state.regiments[f.code].get("gait", {}), gait)
	f.state.sightings.clear()
	UnitGait.refresh(f.repo, f.state, f.code, f.state.regiments[f.code])
	assert_false(f.state.regiments[f.code].has("gait"))

func test_key_point_running_fraction_and_food_survive_json() -> void:
	var f := _key_point_fixture()
	assert_false(Personnel.move(f.repo, f.state, f.code, "fit", "wounded", 15000).has("error"))
	_begin(f)
	_substeps(f.repo, f.state, 0, 3)
	assert_eq(int(f.state.regiments[f.code].get("run_supply_rem", 0)), 5000)
	var restored := BattleScenario.roundtrip(f.state)
	for state: GameState in [f.state, restored]:
		_substeps(f.repo, state, 3, 10)
		assert_eq(_walked(f, state), 917)
		assert_eq(int(state.regiments[f.code].supplies), 985, "half the men run: 15 extra, not 30")
	assert_eq(SaveLoad.state_hash(restored), SaveLoad.state_hash(f.state))

func test_key_point_cannot_shorten_packing_or_start_an_undelivered_march() -> void:
	for packing: bool in [true, false]:
		var f := _key_point_fixture()
		var entry: Dictionary = f.state.regiments[f.code]
		if packing:
			entry["camp_state"] = {"phase": CampSystem.PACKING, "move_not_before_day": f.state.absolute_day() + 1}
		else:
			entry["order"] = ArmySystem.ORDER_GARRISON
		_begin(f)
		_substeps(f.repo, f.state, 0, 10)
		assert_eq(_walked(f), 0)
		assert_eq(int(entry.supplies), 1000)

func test_key_point_stops_on_new_destination_or_lost_commander() -> void:
	for changed: String in ["destination", "commander", "arrival"]:
		var f := _key_point_fixture()
		var entry: Dictionary = f.state.regiments[f.code]
		UnitGait.refresh(f.repo, f.state, f.code, entry)
		assert_true(entry.has("gait"))
		match changed:
			"destination": entry.dest_x_m += 1000000
			"commander": f.state.characters[f.person].attributes.health = 0
			"arrival": entry.order = ArmySystem.ORDER_GARRISON
		UnitGait.refresh(f.repo, f.state, f.code, entry)
		assert_false(entry.has("gait"), changed)
