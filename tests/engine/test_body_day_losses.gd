extends GutTest
## ACT-DRIVER part B2d: non-battle losses and recoveries in the body day.
## Its own file: each body-day suite fills much of a CI runner's per-phase deadline.

func after_each() -> void:
	MarchPath.forget()
	RoadGraph.forget()
	ArmySystem.forget_grids()

func _helper(path: String, method: String, args: Array = []) -> Dictionary:
	var helper: GutTest = load(path).new()
	var f: Dictionary = helper.callv(method, args)
	assert_eq(helper.get_fail_count(), 0, path)
	helper.free()
	return f

func _json(state: GameState) -> GameState:
	return GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)

func _hash(state: GameState) -> String:
	return BodyMotion._hash(state.to_dict())

func _row_facts(repo: DataRepository, state: GameState, code: String) -> Array:
	return UnitBodies.rows(repo, state, code).map(func(row: Dictionary) -> Array: return [row.slot, row.count])

## The B2c recruit fixture (a crown unit of `men` garrisoned at a town it holds, at home, so it
## deserts), with the given morale and training and plenty in hand.
func _home_world(men: int, morale: int, training: int) -> Dictionary:
	var f := _helper("res://tests/engine/test_body_day_recruits.gd", "_recruit_world", [men])
	var entry: Dictionary = f.state.regiments[f.code]
	entry.morale = morale
	entry.training = training
	entry.supplies = 100000
	assert_eq(Forage.land_kind(f.repo, f.state, ArmySystem.province_of(f.repo, f.state, ArmySystem.regiment(f.repo, f.code, f.state))), Forage.HOME)
	return f

## Hand-computed desertion (`Desertion.daily_loss`): morale 0 < `desert_morale` 20 and training
## 0 < `desert_training` 3 are two conditions (the stores are full), and the default "fine" law is
## x1000 per mille, so the daily rate is 3 * 100 * 2 = 600 per 100000 a man. Day one: 201 * 600 =
## 120600, one man leaves and 20600 carries. Day two: 200 * 600 + 20600 = 140600, one more, 40600
## carries. Rows hold 100: 201 is [100, 100, 1], 200 retires slot 2, 199 is [100, 99]; the survivors
## keep their points, the counter stays 10 (never reused).
func test_deserters_leave_the_last_row() -> void:
	var f := _home_world(201, 0, 0)
	var repo: DataRepository = f.repo
	var state: GameState = f.state
	assert_eq([int(repo.bal("desert_morale")), int(repo.bal("desert_training")), int(repo.bal("desert_permille_per_day")), Desertion.conditions(repo, state, f.code)], [20, 3, 3, 2])
	assert_eq(Desertion.multiplier_permille(repo, state, f.code), 1000)
	assert_eq(_row_facts(repo, state, f.code), [[0, 100], [1, 100], [2, 1]])
	var kept := UnitBodies.rows(repo, state, f.code)
	var expect := [[200, 20600, [[0, 100], [1, 100]]], [199, 40600, [[0, 100], [1, 99]]]]
	for day: int in expect.size():
		var source_hash := _hash(state)
		var result := BodyDayDriver.day(repo, state)
		assert_eq(_hash(state), source_hash, "the driver never touches its source")
		assert_eq(result.status, "complete", result.reason)
		if result.candidate == null: return
		assert_eq(_hash(BodyDayDriver.day(repo, _json(state)).candidate), _hash(result.candidate), "the JSON save drives to the same day")
		state = result.candidate
		var entry: Dictionary = state.regiments[f.code]
		assert_eq([MilitaryRoster.fit(state, f.code), int(entry.desert_rem), _row_facts(repo, state, f.code), entry.group_next_slot], expect[day].slice(0, 3) + [10])
		var rows := UnitBodies.rows(repo, state, f.code)
		for i: int in rows.size(): assert_eq([rows[i].x_m, rows[i].y_m], [kept[i].x_m, kept[i].y_m], "a survivor keeps its point")
		assert_eq(state.military_migration.body_placement.operation_id, "placement:day:%d:%s" % [state.absolute_day(), f.code])
		assert_eq(UnitBodies.validate_battle_candidate(repo, state, BodyBattle.safe_boundary(state)).status, "complete")
	assert_eq(int(state.military_migration.body_placement.sequence), 1, "one placement a day")

## Hand-computed month's end on the field unit (tick 1, day 30): 119 men, 20 of them wounded, so
## 99 fit in one row. The month first heals max(1, 20 * 200 / 1000) = 4 (`army_wound_recovery_permille`
## 200): 103 fit, 16 wounded. Then 30 days off the land harass 103 * 10 * 30 / 30000 = 1
## (`forage_harass_permille` 10): 102 fit, 17 wounded. Rows [100, 2]: the survivor keeps slot 0 and
## its point, growth takes slot 10 (the counter stood at 10). No desertion (morale and training high).
func test_month_heals_and_harasses_and_the_rows_follow() -> void:
	var f := _home_world(119, 100, 100)
	var repo: DataRepository = f.repo
	var state: GameState = f.state
	assert_false(MilitaryRoster.transfer_units(repo, state, "test:wound", [{"unit_code": f.code, "from": "fit", "to": "wounded", "count": 20}], "Test wounds").has("error"))
	var entry: Dictionary = state.regiments[f.code]
	entry.body_groups.resize(1)
	entry.body_groups[0].count = 99
	entry.forage_days = 30
	state.tick = 1
	state.day = 30
	assert_eq([int(repo.bal("army_wound_recovery_permille")), int(repo.bal("forage_harass_permille")), ArmySystem.wounded_count(repo, state, f.code)], [200, 10, 20])
	var kept: Dictionary = entry.body_groups[0].duplicate(true)
	var result := BodyDayDriver.day(repo, state)
	assert_eq(result.status, "complete", result.reason)
	if result.candidate == null: return
	assert_eq(_hash(BodyDayDriver.day(repo, _json(state)).candidate), _hash(result.candidate), "the JSON save drives to the same day")
	var done: GameState = result.candidate
	assert_eq([result.ticked, done.tick, done.day], [true, 2, 1])
	assert_eq([MilitaryRoster.fit(done, f.code), ArmySystem.wounded_count(repo, done, f.code), _row_facts(repo, done, f.code), done.regiments[f.code].group_next_slot],
		[102, 17, [[0, 100], [10, 2]], 11])
	var first := UnitBodies.rows(repo, done, f.code)[0]
	assert_eq([first.x_m, first.y_m, first.home_slot], [kept.x_m, kept.y_m, kept.home_slot])
	assert_eq(UnitBodies.validate_battle_candidate(repo, done, BodyBattle.safe_boundary(done)).status, "complete")
	# The next day is admitted and changes no one: the rows stand.
	var next := BodyDayDriver.day(repo, done)
	assert_eq(next.status, "complete", next.reason)
	if next.candidate != null: assert_eq(UnitBodies.rows(repo, next.candidate, f.code), UnitBodies.rows(repo, done, f.code))

## A unit in a battle at the month's end: the legacy recovery rewrites the battle's rows itself
## (`BattleGroups.refresh`); the body day puts them back and lets the placement protocol grow them.
## Hand-computed: 1000 men, 50 wounded, so 950 fit with row 9 at 50; 50 * 200 / 1000 = 10 heal, so
## 960 fit and row 9 is 60. Every other row, the battle and the other units are as the day left them.
func test_month_heals_a_unit_in_battle_in_its_battle_rows() -> void:
	var f := _helper("res://tests/engine/test_body_battle_motion.gd", "_world", [1000])
	var repo: DataRepository = f.repo
	var state: GameState = f.state
	state.tick = 1
	state.day = 30
	var big := ""
	for code: String in state.army_roster:
		if MilitaryRoster.fit(state, code) == 1000: big = code
	assert_false(MilitaryRoster.transfer_units(repo, state, "test:wound", [{"unit_code": big, "from": "fit", "to": "wounded", "count": 50}], "Test wounds").has("error"))
	UnitBodies._entry(state, big).body_groups[9].count = 50
	var blocked := BodyDayDriver.day(repo, state)
	assert_eq(blocked.status, "blocked", blocked.reason)
	if blocked.candidate == null: return
	var answered := BodyDayDriver.acknowledge(repo, blocked.candidate, blocked.candidate.day_resolution.pending_decision.token, "continue")
	assert_eq(answered.status, "complete", answered.reason)
	if answered.candidate == null: return
	var tactical: GameState = BodyDayDriver.tactical_day(repo, answered.candidate).candidate
	var battle_id := int(BattleSystem.battle_of(tactical, big).get("id", -1))
	assert_gt(battle_id, 0, "the unit ends the tactical day in its battle")
	assert_eq([MilitaryRoster.fit(tactical, big), ArmySystem.wounded_count(repo, tactical, big)], [950, 50])
	var closed := BodyDayDriver.day(repo, answered.candidate)
	assert_eq(closed.status, "complete", closed.reason)
	if closed.candidate == null: return
	var done: GameState = closed.candidate
	assert_eq([MilitaryRoster.fit(done, big), ArmySystem.wounded_count(repo, done, big), int(BattleSystem.battle_of(done, big).get("id", -1))], [960, 40, battle_id])
	var was := UnitBodies.rows(repo, tactical, big)
	var now := UnitBodies.rows(repo, done, big)
	assert_eq(now.slice(0, 9), was.slice(0, 9), "the full rows stand as they were")
	var grown: Dictionary = was[9].duplicate(true)
	grown.count = 60
	assert_eq(now[9], grown, "only the last row's count grows")
	for code: String in f.state.army_roster:
		if code != big: assert_eq(UnitBodies.rows(repo, done, code), UnitBodies.rows(repo, tactical, code), code)
	assert_eq(UnitBodies.validate_battle_candidate(repo, done, BodyBattle.safe_boundary(done)).status, "complete")
	assert_eq(BodyDayDriver.day(repo, done).status, "complete", "the next day is admitted")
