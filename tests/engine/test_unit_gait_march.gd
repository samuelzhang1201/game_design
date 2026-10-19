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
	var f := _fixture(1000)
	f.state.regiments[f.code]["disengaging"] = 1
	_begin(f)
	_substeps(f.repo, f.state, 0, 10)
	assert_eq(_walked(f), 917, "92 × 7 + 91 × 3")
	assert_eq(int(f.state.regiments[f.code]["supplies"]), 970, "3 a substep; the base 100 waits for eat_day")
	assert_eq(int(f.state.regiments[f.code].get("run_supply_rem", 0)), 0)
	assert_eq(f.state.regiments[f.code]["gait"],
		{"mode": "run", "reason": "withdrawal", "until": "march_end"})

func test_wounded_keep_only_their_base() -> void:
	var f := _fixture(1000)
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
	var straight := _fixture(1000)
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
	var f := _fixture(100)
	f.state.regiments[f.code]["disengaging"] = 1
	_begin(f)
	_substeps(f.repo, f.state, 0, 10)
	assert_eq(_walked(f), 767)
	assert_eq(int(f.state.regiments[f.code]["supplies"]), 100)
	assert_eq(String(f.state.regiments[f.code]["gait"]["mode"]), "run", "the reason holds; each substep walks")

func test_103_in_hand_runs_one_substep() -> void:
	var f := _fixture(103)
	f.state.regiments[f.code]["disengaging"] = 1
	_begin(f)
	_substeps(f.repo, f.state, 0, 10)
	# 92 + 77 × 6 + 76 × 3: the last substep's catch-up (767 − 706 = 61) stays below 76.
	assert_eq(_walked(f), 782)
	assert_eq(int(f.state.regiments[f.code]["supplies"]), 100)

func test_a_march_to_join_a_known_battle_runs_until_it_ends() -> void:
	var f := _fixture(1000)
	var dest := (f.start as Vector2i) + Vector2i(2300, 0)
	f.state.battles.append({"id": 7, "att": [f.other], "def": [], "place_x_m": dest.x, "place_y_m": dest.y})
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

func test_a_battle_beyond_reach_of_the_destination_gives_no_reason() -> void:
	var f := _fixture(1000)
	var far := (f.start as Vector2i) + Vector2i(2300 + int(f.repo.bal("battle_contact_km") * 1000) + 1, 0)
	f.state.battles.append({"id": 7, "att": [f.other], "def": [], "place_x_m": far.x, "place_y_m": far.y})
	_begin(f)
	_substeps(f.repo, f.state, 0, 10)
	assert_eq(_walked(f), 767)
	assert_false(f.state.regiments[f.code].has("gait"))

func test_packing_is_not_shortened() -> void:
	var f := _fixture(1000)
	var entry: Dictionary = f.state.regiments[f.code]
	entry["disengaging"] = 1
	entry["camp_state"] = {"phase": CampSystem.PACKING, "move_not_before_day": f.state.absolute_day() + 1}
	_begin(f)
	_substeps(f.repo, f.state, 0, 10)
	assert_eq(_walked(f), 0)
	assert_eq(int(entry["supplies"]), 1000)
