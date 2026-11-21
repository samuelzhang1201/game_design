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
		assert_eq(state.military_migration.body_placement.operation_id, "placement:refit:%d:%s" % [day, f.code])
		assert_eq(UnitBodies.validate_battle_candidate(repo, state, BodyBattle.safe_boundary(state)).status, "complete")
	assert_eq(int(state.military_migration.body_placement.sequence), 1, "one placement a day")

## Hand-computed month's end on the field unit (tick 1, day 30): 219 men, 20 of them wounded, so
## 199 fit in rows [100, 99]. The month first heals max(1, 20 * 200 / 1000) = 4
## (`army_wound_recovery_permille` 200): 203 fit, 16 wounded. Then 29 days off the land (the most a
## unit home on day 30 can have) harass 203 * 10 * 29 / 30000 = 1 (`forage_harass_permille` 10):
## 202 fit, 17 wounded. Rows [100, 100, 2]: the survivors keep slots 0 and 1 and their points, the
## second row fills to 100, growth takes slot 10 (the counter stood at 10). No desertion (morale and
## training high).
func test_month_heals_and_harasses_and_the_rows_follow() -> void:
	var f := _home_world(219, 100, 100)
	var repo: DataRepository = f.repo
	var state: GameState = f.state
	assert_false(MilitaryRoster.transfer_units(repo, state, "test:wound", [{"unit_code": f.code, "from": "fit", "to": "wounded", "count": 20}], "Test wounds").has("error"))
	var entry: Dictionary = state.regiments[f.code]
	entry.body_groups.resize(2)
	entry.body_groups[1].count = 99
	entry.forage_days = 29
	state.tick = 1
	state.day = 30
	assert_eq([int(repo.bal("army_wound_recovery_permille")), int(repo.bal("forage_harass_permille")), ArmySystem.wounded_count(repo, state, f.code)], [200, 10, 20])
	var kept: Array = entry.body_groups.duplicate(true)
	var result := BodyDayDriver.day(repo, state)
	assert_eq(result.status, "complete", result.reason)
	if result.candidate == null: return
	assert_eq(_hash(BodyDayDriver.day(repo, _json(state)).candidate), _hash(result.candidate), "the JSON save drives to the same day")
	var done: GameState = result.candidate
	assert_eq([result.ticked, done.tick, done.day], [true, 2, 1])
	assert_eq([MilitaryRoster.fit(done, f.code), ArmySystem.wounded_count(repo, done, f.code), _row_facts(repo, done, f.code), done.regiments[f.code].group_next_slot],
		[202, 17, [[0, 100], [1, 100], [10, 2]], 11])
	for i: int in 2:
		var row := UnitBodies.rows(repo, done, f.code)[i]
		assert_eq([row.x_m, row.y_m, row.home_slot], [kept[i].x_m, kept[i].y_m, kept[i].home_slot])
	assert_eq(UnitBodies.validate_battle_candidate(repo, done, BodyBattle.safe_boundary(done)).status, "complete")
	# The next day is admitted and changes no one: the rows stand.
	var next := BodyDayDriver.day(repo, done)
	assert_eq(next.status, "complete", next.reason)
	if next.candidate != null: assert_eq(UnitBodies.rows(repo, next.candidate, f.code), UnitBodies.rows(repo, done, f.code))

## The battle fixture on the month's last day, its 1000-man unit with `wounded` of them wounded
## and its rows cut to the fit, driven through its encounter to the close's source.
func _battle_month(wounded: int) -> Dictionary:
	var f := _helper("res://tests/engine/test_body_battle_motion.gd", "_world", [1000])
	var state: GameState = f.state
	state.tick = 1
	state.day = 30
	for code: String in state.army_roster:
		if MilitaryRoster.fit(state, code) == 1000: f.big = code
	assert_false(MilitaryRoster.transfer_units(f.repo, state, "test:wound", [{"unit_code": f.big, "from": "fit", "to": "wounded", "count": wounded}], "Test wounds").has("error"))
	var entry := UnitBodies._entry(state, f.big)
	entry.body_groups = entry.body_groups.slice(0, BattleGroups.counts(1000 - wounded, 100).size())
	entry.body_groups[-1].count = BattleGroups.counts(1000 - wounded, 100)[-1]
	var blocked := BodyDayDriver.day(f.repo, state)
	assert_eq(blocked.status, "blocked", blocked.reason)
	if blocked.candidate == null: return f
	var answered := BodyDayDriver.acknowledge(f.repo, blocked.candidate, blocked.candidate.day_resolution.pending_decision.token, "continue")
	assert_eq(answered.status, "complete", answered.reason)
	f.answered = answered.candidate
	if f.answered != null: f.tactical = BodyDayDriver.tactical_day(f.repo, f.answered).candidate
	return f

## A unit in a battle at the month's end heals in its battle rows, whatever the legacy recovery's
## own geometry makes of it (its `BattleGroups.refresh` rewrites the whole battle, and drops the heal
## when it cannot lay the legacy rows; the body day puts the battle back, heals any unit it dropped
## and lets the placement protocol lay the rows). Hand-computed on 1000 men:
## - 50 wounded: 950 fit, row 9 at 50; 50 * 200 / 1000 = 10 heal, so 960 fit and row 9 is 60.
## - 100 wounded: 900 fit in 9 full rows; 20 heal, so 920 fit and a new row of 20 at the next slot.
## Every other row, the battle's facings and anchors, and the other units stand as the day left them.
func test_month_heals_a_unit_in_battle_in_its_battle_rows() -> void:
	for wounded: int in [50, 100]:
		var f := _battle_month(wounded)
		if not f.has("tactical"): return
		var repo: DataRepository = f.repo
		var tactical: GameState = f.tactical
		var big: String = f.big
		var battle_id := int(BattleSystem.battle_of(tactical, big).get("id", -1))
		assert_gt(battle_id, 0, "the unit ends the tactical day in its battle")
		assert_eq([MilitaryRoster.fit(tactical, big), ArmySystem.wounded_count(repo, tactical, big)], [1000 - wounded, wounded])
		var closed := BodyDayDriver.day(repo, f.answered)
		assert_eq(closed.status, "complete", closed.reason)
		if closed.candidate == null: return
		var done: GameState = closed.candidate
		@warning_ignore("integer_division")
		var healed := wounded * 200 / 1000
		assert_eq([MilitaryRoster.fit(done, big), ArmySystem.wounded_count(repo, done, big), int(BattleSystem.battle_of(done, big).get("id", -1))],
			[1000 - wounded + healed, wounded - healed, battle_id])
		var was := UnitBodies.rows(repo, tactical, big)
		var now := UnitBodies.rows(repo, done, big)
		if wounded == 50:
			assert_eq(now.slice(0, 9), was.slice(0, 9), "the full rows stand as they were")
			var grown: Dictionary = was[9].duplicate(true)
			grown.count = 60
			assert_eq(now[9], grown, "only the last row's count grows")
		else:
			var slot := int(UnitBodies._entry(tactical, big).group_next_slot)
			assert_eq(now.slice(0, 9), was, "the full rows stand as they were")
			assert_eq([now.size(), now[9].slot, now[9].count, UnitBodies._entry(done, big).group_next_slot], [10, slot, 20, slot + 1], "a new row at the next slot")
		var then := BattleSystem.battle_of(tactical, big)
		var battle := BattleSystem.battle_of(done, big)
		for field: String in ["group_facing", "group_anchor_m", "geometry_version"]: assert_eq(battle.get(field), then.get(field), field)
		for code: String in f.state.army_roster:
			if code != big: assert_eq(UnitBodies.rows(repo, done, code), UnitBodies.rows(repo, tactical, code), code)
		assert_eq(UnitBodies.validate_battle_candidate(repo, done, BodyBattle.safe_boundary(done)).status, "complete")
		assert_eq(BodyDayDriver.day(repo, done).status, "complete", "the next day is admitted")
