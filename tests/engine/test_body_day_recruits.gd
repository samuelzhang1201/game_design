extends GutTest
## ACT-DRIVER part B2c: recruit orders and completions in the body day.
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

## B2c: the garrisoned crown unit of 100 on the point of a town it holds, a
## treasury, 1000 eligible civilians and a two-day infantry contract at 2 gold a commoner, 10 a noble.
func _recruit_world() -> Dictionary:
	var f := _helper("res://tests/engine/test_body_marches.gd", "_fixture", [[100]])
	var state: GameState = f.state
	var realm: String = f.repo.resolve_realm("player_realm")
	assert_eq(String(state.army_roster[f.code].kingdom_code), realm)
	var towns: Array = f.repo.burgs.keys()
	towns.sort()
	for key: String in towns:
		if ArmyGround.holds(f.repo, state, realm, key) and MapOwnership.owner_of(f.repo, state, String(f.repo.burgs[key].province_code)) == realm:
			f.town = key
			break
	f.province = String(f.repo.burgs[f.town].province_code)
	# The town stands where the pack has it (a new unit camps on real ground), so the open test
	# grid is stretched over the whole map (10 km cells) and the unit stands on the town's point.
	var size := Vector2i(ceili(float(f.repo.map_info.width) / 10.0), ceili(float(f.repo.map_info.height) / 10.0))
	var slopes := PackedByteArray()
	slopes.resize(size.x * size.y)
	MarchPath.use(f.repo, MarchPath.build(f.repo, size.x, size.y, 10000, slopes))
	f.at = ArmyGround.town_point_m(f.repo, f.town)
	var entry: Dictionary = state.regiments[f.code]
	for row: Dictionary in [entry, entry.body_groups[0]]:
		row.x_m = f.at.x
		row.y_m = f.at.y
	entry.order = ArmySystem.ORDER_GARRISON
	entry.dest_x_m = f.at.x
	entry.dest_y_m = f.at.y
	entry.erase("route_m")
	assert_eq(BodyDayDriver._seat_day(f.repo, state, [f.code]), "")
	assert_eq(ArmyGround.garrison_town(f.repo, state, f.code), f.town)
	state.metrics.treasury = 5000
	f.repo.balance.recruitment_eligible_permille = 1000
	state.world[MilitaryPopulation.path(f.province, "rural_population")] = 1000
	for arm: String in ["infantry", MapObjects.regiment_arm(f.repo, state.army_roster[f.code])]: f.repo.recruitment[arm] = {"arm": arm, "commoner_gold": "2", "noble_gold": "10",
		"commander_gold": "0", "equipment_gold_per_element": "0", "build_days": "2", "requires_port": "0"}
	var ids: Array = f.repo.commanders.keys()
	ids.sort()
	f.officers = ids.filter(func(id: String) -> bool:
		return (state.characters[id] as Character).kingdom == realm and MilitaryCommanders.candidate_error(f.repo, state, id) == "" \
			and "infantry" in String(f.repo.commanders[id].unit_kinds).split("|"))
	return f

func _recruit_order(f: Dictionary, mode: String, id: String, total: int, officer: String) -> Dictionary:
	return {"request_id": id, "mode": mode, "arm": "infantry" if mode == "new" else "", "unit_code": f.code if mode == "reinforce" else "",
		"total": total, "source_province": f.province, "source_population_field": "rural_population", "assembly_town": f.town,
		"noble_permille": 0, "commander_id": officer}

func _row_facts(repo: DataRepository, state: GameState, code: String) -> Array:
	return UnitBodies.rows(repo, state, code).map(func(row: Dictionary) -> Array: return [row.slot, row.count])

## B2c: two paid assemblies ordered between days (150 reinforcements for the unit of 100, and a new
## unit of 200) are sealed as ordinary writers: people reserved, no body. Both complete at the
## second day's end, and the close gives them bodies through the placement protocol.
## Hand-computed: neither unit has a commander, so each order is its commoners at 2 gold and one
## noble officer at 10: 149 * 2 + 10 = 308 and 199 * 2 + 10 = 408. Rows hold 100 men: 250 fit is
## [100, 100, 50], the survivor keeping slot 0 and its point, growth taking slots 10 and 11 (the
## counter stood at 10); the new unit's 200 are slots 0 and 1, camped one slot spacing off the town.
func test_recruit_orders_reserve_people_and_completion_places_their_bodies() -> void:
	var f := _recruit_world()
	var repo: DataRepository = f.repo
	var state: GameState = f.state
	var raised := "recruited:raise"
	var before_rows := UnitBodies.rows(repo, state, f.code)
	assert_eq([state.military_rosters[f.code].commander_id, _row_facts(repo, state, f.code), state.regiments[f.code].group_next_slot], ["", [[0, 100]], 10])
	var gold := [308, 408]
	var orders := [_recruit_order(f, "reinforce", "grow", 150, f.officers[0]), _recruit_order(f, "new", "raise", 200, f.officers[1])]
	for i: int in orders.size():
		var sequence := int(state.military_migration.get("body_battle", {}).get("sequence", -1))
		var order := func(r: DataRepository, s: GameState) -> void: assert_eq(RecruitmentSystem.recruit(r, s, orders[i]).get("gold"), gold[i])
		var published := BodyDayDriver.publish(repo, state, {"kind": "recruit", "id": orders[i].request_id}, order)
		assert_eq(published.status, "complete", published.reason)
		if published.candidate == null: return
		state = published.candidate
		assert_eq(int(state.military_migration.body_battle.sequence), sequence + 1, "each order is one outer operation")
	assert_eq(int(state.metrics.treasury), 5000 - 308 - 408)
	assert_eq([MilitaryRoster.fit(state, f.code), MilitaryRoster.fit(state, raised), UnitBodies.rows(repo, state, f.code)], [100, 0, before_rows], "reserved people have no body")
	assert_eq(state.recruitment_projects.grow.cohort_ids.map(func(id: String) -> Array: return [state.military_cohorts[id].stage, state.military_cohorts[id].fit]),
		[["assembling", 149], ["assembling", 1]])
	assert_false(state.regiments.has(raised))
	# People cannot become soldiers but through a completion: a writer that activates them is refused.
	var enlist := func(_r: DataRepository, s: GameState) -> void: s.military_cohorts["recruit:grow:commoners"].stage = "active"
	assert_string_contains(BodyDayDriver.publish(repo, state, {"kind": "enlist"}, enlist).reason, "personnel")
	# Day one: a day's work each, still assembling; the body world carries them through its whole day.
	var first := BodyDayDriver.day(repo, state)
	assert_eq(first.status, "complete", first.reason)
	if first.candidate == null: return
	state = first.candidate
	assert_eq(state.recruitment_projects.values().map(func(p: Dictionary) -> Array: return [p.status, p.worked_days]), [["assembling", 1], ["assembling", 1]])
	assert_eq([_row_facts(repo, state, f.code), state.regiments.has(raised), state.military_migration.has("body_placement")], [[[0, 100]], false, false])
	# The held row now carries its own point as its path; the point itself has not moved.
	assert_eq([before_rows[0].x_m, before_rows[0].y_m], [f.at.x, f.at.y])
	before_rows = UnitBodies.rows(repo, state, f.code)
	assert_eq([before_rows[0].x_m, before_rows[0].y_m], [f.at.x, f.at.y])
	# Day two: both complete in the close, and each gets its bodies as one placement operation.
	var source_hash := _hash(state)
	var second := BodyDayDriver.day(repo, state)
	assert_eq(_hash(state), source_hash, "the driver never touches its source")
	assert_eq(second.status, "complete", second.reason)
	if second.candidate == null: return
	assert_eq(_hash(BodyDayDriver.day(repo, _json(state)).candidate), _hash(second.candidate), "the JSON save drives to the same day")
	var done: GameState = second.candidate
	assert_eq(done.recruitment_projects.values().map(func(p: Dictionary) -> Array: return [p.status, p.completed_day]),
		[["complete", state.absolute_day()], ["complete", state.absolute_day()]])
	assert_eq([MilitaryRoster.fit(done, f.code), _row_facts(repo, done, f.code), done.regiments[f.code].group_next_slot], [250, [[0, 100], [10, 100], [11, 50]], 12])
	assert_eq(UnitBodies.rows(repo, done, f.code)[0], before_rows[0], "the survivor keeps its row")
	assert_eq([done.military_rosters[f.code].commander_id, done.military_rosters[raised].commander_id], [f.officers[0], f.officers[1]])
	assert_eq([MilitaryRoster.fit(done, raised), _row_facts(repo, done, raised), done.regiments[raised].group_next_slot], [200, [[0, 100], [1, 100]], 2])
	var camp := Vector2i(done.regiments[raised].x_m, done.regiments[raised].y_m)
	assert_eq([done.regiments[raised].camp_town, MarchClearance.dist2(camp, f.at)], [f.town, 4400 * 4400], "camped on the town's first ring")
	assert_eq(int(repo.bal("army_slot_spacing_m")), 4400)
	assert_eq([done.military_migration.body_placement.sequence, done.military_migration.body_placement.operation_id], ["1", "placement:recruit:raise:" + raised],
		"two placement operations, in project order")
	assert_eq(UnitBodies.validate_battle_candidate(repo, done, BodyBattle.safe_boundary(done)).status, "complete")
	# The close's guard lets through exactly the recruits: nothing else may gain a body or change.
	var cohorts: Array = done.recruitment_projects.grow.cohort_ids + done.recruitment_projects.raise.cohort_ids
	assert_eq(BodyDayDriver._body_change(state, done, "X", [f.code, raised], cohorts), "")
	assert_string_contains(BodyDayDriver._body_change(state, done, "X"), "X moved, added or removed a body")
	assert_string_contains(BodyDayDriver._body_change(state, done, "X", [f.code, raised]), "X changed personnel")
	var hungry := UnitBodies._copy(done)
	var veteran: String = hungry.military_rosters[f.code].cohort_ids.filter(func(id: String) -> bool: return id not in cohorts and int(hungry.military_cohorts[id].fit) > 0)[0]
	hungry.military_cohorts[veteran].fit -= 1
	assert_string_contains(BodyDayDriver._body_change(state, hungry, "X", [f.code, raised], cohorts), "X changed personnel", "a recruited unit's veterans stay guarded")
	# Day three is admitted and leaves both units' bodies where they stand.
	var third := BodyDayDriver.day(repo, done)
	assert_eq(third.status, "complete", third.reason)
	if third.candidate == null: return
	for code: String in [f.code, raised]: assert_eq(UnitBodies.rows(repo, third.candidate, code), UnitBodies.rows(repo, done, code))
