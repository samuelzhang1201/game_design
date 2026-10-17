extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Roster := preload("res://scripts/engine/military_roster.gd")
var repo: DataRepository
var state: GameState
var original: String

func before_each() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 42)
	SuiteData.open_country(repo)
	var codes := state.army_roster.keys()
	codes.sort()
	for code: String in codes:
		if int(state.army_roster[code].get("cavalry", 0)) > 0 and state.regiments.has(code):
			original = code
			break
	var unit: Dictionary = state.army_roster[original].duplicate(true)
	var commander := String(state.military_rosters[original]["commander_id"])
	var family := (state.characters[commander] as Character).family_name
	var origin := String(unit["source_parts"][0]["province_code"])
	state.army_roster = {original: unit}
	state.regiments = {original: state.regiments[original].duplicate(true)}
	state.foes.clear()
	state.military_cohorts.clear()
	state.military_rosters = {original: {"commander_id": commander, "commander_cohort_id": "officer", "cohort_ids": []}}
	state.military_migration = {"version": 1, "organization_pending": true}
	state.town_seat.clear()
	repo.balance["army_split_cap_men"] = 600
	repo.world_table("military", "unit_types")["cavalry"]["crew"] = "2"
	unit["cavalry"] = "600"
	unit["source_parts"] = [{"regiment_code": "saved_source", "province_code": origin, "arm": "cavalry", "equipment_count": 600, "crew_per_element": 2}]
	_add("officer", "noble", family, 1, 0, 0, 0, origin, commander)
	_add("nobles", "noble", family, 54, 0, 0, 0, origin)
	_add("common", "commoner", "", 1045, 50, 40, 10, origin)
	state.regiments[original]["supplies"] = 101
	state.supply_lines = {original: {"rate": 1200, "fee_milli": 101, "m_drawn": 103, "m_bought": {"house": 101}}}
	state.ai_hosts = {"host": {"plunder": 501}}

func _add(id: String, identity: String, family: String, fit: int, wounded: int, dead: int, released: int, origin: String, person := "") -> void:
	var cohort := {"id": id, "unit_code": original, "identity": identity, "family_name": family,
		"stage": "active", "source_province": origin, "source_population_field": "rural_population",
		"initial": fit + wounded + dead + released, "fit": fit, "wounded": wounded, "dead": dead,
		"released": released, "captured_current": 0}
	if person != "":
		cohort["person_id"] = person
	state.military_cohorts[id] = cohort
	state.military_rosters[original]["cohort_ids"].append(id)

func _reconcile() -> Dictionary:
	var path := "res://scripts/engine/military_reorganization.gd"
	assert_true(FileAccess.file_exists(path), "saved organizations need a safe reconciliation")
	if not FileAccess.file_exists(path):
		return {"status": "error"}
	return load(path).call("reconcile", repo, state)

func test_live_custody_defers_legacy_cohort_splitting() -> void:
	state.military_cohorts.common.fit -= 10
	state.military_cohorts.common.captured_current = 10
	var before: Dictionary = state.military_cohorts.duplicate(true)
	assert_eq(_reconcile().status, "deferred")
	assert_eq(state.military_cohorts, before, "Custody source IDs must survive pending organization")

func test_conserves_equipment_people_stores_and_rates_and_repeats_stably() -> void:
	assert_eq(_reconcile().get("status"), "complete")
	if state.army_roster.size() != 2:
		assert_eq(state.army_roster.size(), 2)
		return
	var children: Array = state.military_migration["unit_mapping"][original]
	assert_eq(children[0], original)
	var initial := 0
	var noble := 0
	for i: int in children.size():
		var code: String = children[i]
		assert_eq(int(state.army_roster[code]["cavalry"]), 300)
		assert_eq(state.regiments[code]["supplies"], 51 if i == 0 else 50)
		assert_eq(state.supply_lines[code]["rate"], 1200)
		assert_eq(state.supply_lines[code]["fee_milli"], 51 if i == 0 else 50)
		assert_eq(Roster.fit(state, code), 550)
		assert_eq(Roster.living(state, code) - Roster.fit(state, code), 25)
		var dead := 0
		var released := 0
		for id: String in state.military_rosters[code]["cohort_ids"]:
			dead += int(state.military_cohorts[id]["dead"])
			released += int(state.military_cohorts[id]["released"])
		assert_eq(dead, 20)
		assert_eq(released, 5)
	for cohort: Dictionary in state.military_cohorts.values():
		initial += int(cohort["initial"])
		if cohort["identity"] == "noble":
			noble += int(cohort["initial"])
	assert_eq(initial, 1200)
	assert_eq(noble, 55)
	assert_eq(state.ai_hosts["host"]["plunder"], 501)
	assert_eq(state.military_cohorts["officer"]["unit_code"], original)
	var saved := state.to_dict()
	state = GameState.from_dict(JSON.parse_string(JSON.stringify(saved)), false)
	assert_eq(_reconcile().get("status"), "complete")
	assert_eq(state.to_dict(), saved)

func test_day_transaction_defers_without_any_state_write() -> void:
	state.day_resolution = {"phase": "battles", "battle_index": 1}
	var before := state.to_dict()
	assert_eq(_reconcile().get("status"), "deferred")
	assert_eq(state.to_dict(), before)
	state.day_resolution.clear()
	assert_eq(_reconcile().get("status"), "complete")

func test_unknown_cohort_origin_rejects_atomically() -> void:
	state.military_cohorts["common"]["source_province"] = "unknown"
	var before := state.to_dict()
	assert_eq(_reconcile().get("status"), "error")
	assert_eq(state.to_dict(), before)

func test_active_battle_defers_then_completes() -> void:
	state.battles = [{"id": 1, "att": [original], "def": []}]
	var before := state.to_dict()
	assert_eq(_reconcile().get("status"), "deferred")
	assert_eq(state.to_dict(), before)
	state.battles.clear()
	assert_eq(_reconcile().get("status"), "complete")

func test_derived_id_collision_rejects_atomically() -> void:
	state.army_roster[original + ":organization:v1:2"] = state.army_roster[original].duplicate(true)
	var before := state.to_dict()
	assert_eq(_reconcile().get("status"), "error")
	assert_eq(state.to_dict(), before)

func test_live_references_expand_but_historical_records_and_attributes_stay() -> void:
	state.regiments[original]["morale"] = 71
	state.regiments[original]["training"] = 63
	state.regiments[original]["desert_rem"] = 101
	state.scout_log = {original: {"contact": 7, "scout": 8}}
	state.sightings = {"history": {"unit": original, "x_m": 99}}
	state.war_drafts = {original: {"order": "garrison", "tick": 1}}
	state.law_in_force = {"unit:" + original: {"test": {"value": "on", "decree_id": 4}}}
	var historical := {"unit_code": original, "cohort_ids": ["common"]}
	state.recruitment_projects = {"recruit": {"unit_code": original, "cohort_ids": ["common"], "equipment": {"cavalry": 9},
		"request": historical.duplicate(true), "result": historical.duplicate(true), "action_outcome": historical.duplicate(true)}}
	var before_sightings := state.sightings.duplicate(true)
	assert_eq(_reconcile().get("status"), "complete")
	var children: Array = state.military_migration["unit_mapping"][original]
	var project: Dictionary = state.recruitment_projects["recruit"]
	assert_eq(project["unit_codes"], children)
	assert_eq(children.size(), 3)
	for child: String in children:
		assert_eq(project["equipment_by_unit"][child]["cavalry"], 3)
	assert_eq(project["equipment"], {"cavalry": 9})
	for field: String in ["request", "result", "action_outcome"]:
		assert_eq(project[field], historical)
	assert_eq(project["cohort_ids"], state.military_migration["cohort_mapping"]["common"])
	for i: int in children.size():
		var child: String = children[i]
		assert_eq(state.regiments[child]["morale"], 71)
		assert_eq(state.regiments[child]["training"], 63)
		assert_eq(state.regiments[child]["desert_rem"], 34 if i < 2 else 33)
		assert_eq(state.scout_log[child], {"contact": 7, "scout": 8})
		assert_eq(state.law_in_force["unit:" + child], state.law_in_force["unit:" + original])
		assert_eq(state.war_drafts[child], {"order": "garrison", "tick": 1})
	assert_eq(state.sightings, before_sightings)

func test_courier_delivers_children_physically_in_sequence_with_one_id() -> void:
	var commander := String(state.military_rosters[original]["commander_id"])
	var c := CourierSystem.dispatch(repo, state, CourierSystem.ORDINARY, original,
		{"action_code": "ARMY_STANCE", "stance": "evade"})
	var id := int(c["id"])
	var path: Array = c["path"].duplicate(true)
	var treasury := int(state.metrics.treasury)
	assert_eq(_reconcile().get("status"), "complete")
	var children: Array = state.military_migration["unit_mapping"][original]
	assert_eq(state.couriers.size(), 1)
	assert_eq(state.couriers[0]["id"], id)
	assert_eq(state.couriers[0]["path"], path)
	assert_eq(state.couriers[0]["recipient_queue"].size(), 1)
	assert_eq(state.military_rosters[original]["commander_id"], commander)
	var first := ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, state, state.army_roster[original]))
	state.couriers[0]["x_m"] = first.x
	state.couriers[0]["y_m"] = first.y
	state.couriers[0]["path"] = []
	CourierSystem.ride_day(repo, state)
	assert_eq(state.regiments[original]["stance_next"], "evade")
	assert_false(state.regiments[children[1]].has("stance_next"))
	assert_eq(state.couriers.size(), 1)
	assert_eq(state.couriers[0]["target"], children[1])
	assert_eq(state.couriers[0]["id"], id)
	assert_false(state.couriers[0]["path"].is_empty())
	for day: int in 100:
		if state.couriers.is_empty():
			break
		CourierSystem.ride_day(repo, state)
	assert_eq(state.couriers.size(), 0)
	assert_eq(state.regiments[children[1]]["stance_next"], "evade")
	assert_eq(int(state.metrics.treasury), treasury)

func test_pending_march_and_law_scopes_follow_recipient_queue_and_seat_is_first_only() -> void:
	CourierSystem.dispatch(repo, state, CourierSystem.ORDINARY, original,
		{"action_code": "ARMY_MARCH", "dest_x_m": 100, "dest_y_m": 200})
	CourierSystem.dispatch(repo, state, CourierSystem.ORDINARY, original, {"action_code": "ARMY_SEAT"})
	var law := CourierSystem.dispatch(repo, state, CourierSystem.ORDINARY, original,
		{"action_code": "LAW_SET", "law": "forage", "scope_key": "unit:" + original, "value": "on", "decree_id": 9})
	assert_eq(_reconcile().get("status"), "complete")
	var child: String = state.military_migration["unit_mapping"][original][1]
	assert_eq(CourierSystem.pending_for(state, child)["id"], state.couriers[0]["id"])
	assert_eq(state.couriers[0]["recipient_queue"][0]["orders"].size(), 1)
	assert_eq(state.couriers[0]["recipient_queue"][0]["orders"][0]["action_code"], "ARMY_MARCH")
	var queued: Dictionary = state.couriers[1]["recipient_queue"][0]
	assert_eq(queued["orders"][0]["scope_key"], "unit:" + child)
	assert_eq(state.couriers[1]["id"], law["id"])

func test_no_eligible_replacement_records_vacancy_without_inventing_people() -> void:
	repo.commanders.clear()
	assert_eq(_reconcile().get("status"), "complete")
	var child: String = state.military_migration["unit_mapping"][original][1]
	assert_eq(state.military_rosters[child]["commander_id"], "")
	assert_string_contains(state.military_rosters[child]["vacancy_reason"], "existing noble")
	var people := 0
	var named := 0
	for cohort: Dictionary in state.military_cohorts.values():
		people += int(cohort["initial"])
		if cohort.has("person_id"):
			named += 1
	assert_eq(people, 1200)
	assert_eq(named, 1)

func test_illegal_camp_placement_refuses_whole_upgrade() -> void:
	repo.balance["army_slot_max_rings"] = 0
	var before := state.to_dict()
	assert_eq(_reconcile().get("status"), "error")
	assert_eq(state.to_dict(), before)

func test_new_campaign_organization_is_never_resplit() -> void:
	state.military_migration = {"version": 1, "status": "initialized"}
	var before := state.to_dict()
	assert_eq(_reconcile().get("status"), "complete")
	assert_eq(state.to_dict(), before)

func test_queued_law_recipient_is_riding_with_a_physical_later_eta() -> void:
	state.town_seat.clear()
	state.regiments[original]["camp_town"] = ""
	state.army_roster[original]["camp_town"] = ""
	state.law_decree = {"wear_badges": {"value": "on", "decree_id": 9, "day": 1, "sent": ["unit:" + original]}}
	CourierSystem.dispatch(repo, state, CourierSystem.ORDINARY, original,
		{"action_code": "LAW_SET", "law": "wear_badges", "scope_key": "unit:" + original, "value": "on", "decree_id": 9})
	assert_eq(_reconcile().get("status"), "complete")
	var child: String = state.military_migration["unit_mapping"][original][1]
	var untold := LawSystem.untold(repo, state, "wear_badges")
	var first_days := -1
	var child_days := -1
	for item: Dictionary in untold:
		if item["scope_key"] == "unit:" + original:
			first_days = int(item["days"])
		if item["scope_key"] == "unit:" + child:
			child_days = int(item["days"])
			assert_false(item["lost"])
	assert_gt(first_days, 0)
	assert_gt(child_days, first_days)
	assert_eq(LawSystem.delivery(repo, state, "wear_badges")["riding"], 2)
	assert_eq(LawSystem.delivery(repo, state, "wear_badges")["last_days"], child_days)

func test_active_battle_defers_only_its_unit_and_retries_without_resplitting_others() -> void:
	var other := original + ":other"
	state.army_roster[other] = state.army_roster[original].duplicate(true)
	state.army_roster[other]["regiment_code"] = other
	state.regiments[other] = state.regiments[original].duplicate(true)
	state.military_rosters[other] = {"cohort_ids": [], "commander_id": "", "commander_cohort_id": ""}
	for id: String in state.military_rosters[original]["cohort_ids"]:
		var clone: Dictionary = state.military_cohorts[id].duplicate(true)
		clone["id"] = id + ":other"
		clone["unit_code"] = other
		clone.erase("person_id")
		state.military_cohorts[clone["id"]] = clone
		state.military_rosters[other]["cohort_ids"].append(clone["id"])
	state.battles = [{"id": 1, "att": [original], "def": []}]
	assert_eq(_reconcile().get("status"), "deferred")
	assert_eq(state.army_roster.size(), 3)
	assert_true(state.military_migration["organization_pending"])
	assert_false(state.military_migration["unit_mapping"].has(original))
	assert_eq(state.military_migration["unit_mapping"][other].size(), 2)
	var saved := state.to_dict()
	assert_eq(_reconcile().get("status"), "deferred")
	assert_eq(state.to_dict(), saved)
	state.battles.clear()
	assert_eq(_reconcile().get("status"), "complete")
	assert_eq(state.army_roster.size(), 4)

func test_named_cohorts_remain_indivisible_and_existing_noble_pays_for_new_commander() -> void:
	var original_officer := String(state.military_rosters[original]["commander_id"])
	var candidate := Character.from_dict((state.characters[original_officer] as Character).to_dict())
	candidate.id = "migration_officer"
	candidate.seat = ""
	candidate.category = "commander"
	candidate.attributes["health"] = 100
	state.characters[candidate.id] = candidate
	var eligibility: Dictionary = repo.commanders[original_officer].duplicate(true)
	repo.commanders.clear()
	repo.commanders[candidate.id] = eligibility
	assert_eq(_reconcile().get("status"), "complete")
	var named := 0
	for cohort: Dictionary in state.military_cohorts.values():
		if cohort.has("person_id"):
			named += 1
			assert_eq(cohort["initial"], 1)
			assert_eq(cohort["identity"], "noble")
	var child: String = state.military_migration["unit_mapping"][original][1]
	var commander := String(state.military_rosters[child]["commander_id"])
	assert_eq(named, 2)
	assert_eq(commander, candidate.id)
	if commander != "":
		assert_eq(named, 2)
		var officer: Dictionary = state.military_cohorts[state.military_rosters[child]["commander_cohort_id"]]
		assert_eq(officer["person_id"], commander)
		assert_eq(officer["fit"], 1)
		assert_eq(officer["family_name"], state.military_cohorts["officer"]["family_name"])
	var noble := 0
	for cohort: Dictionary in state.military_cohorts.values():
		if cohort["identity"] == "noble":
			noble += int(cohort["initial"])
	assert_eq(noble, 55)

func test_fleet_organization_exception_keeps_its_equipment_and_people() -> void:
	state.army_roster[original]["is_naval"] = "1"
	var cohorts := state.military_cohorts.duplicate(true)
	assert_eq(_reconcile().get("status"), "complete")
	assert_eq(state.army_roster.size(), 1)
	assert_eq(int(state.army_roster[original]["cavalry"]), 600)
	assert_eq(state.military_cohorts, cohorts)

func test_cohort_fragment_collision_rejects_whole_upgrade() -> void:
	var id := "common:organization:v1:2"
	state.military_cohorts[id] = state.military_cohorts["common"].duplicate(true)
	state.military_cohorts[id]["id"] = id
	var before := state.to_dict()
	assert_eq(_reconcile().get("status"), "error")
	assert_eq(state.to_dict(), before)

func test_original_seat_is_inherited_once_and_child_camps_outside_it() -> void:
	var realm := String(state.army_roster[original]["kingdom_code"])
	var town := String(repo.kingdoms[realm]["capital_burg"])
	var point := ArmyGround.town_point_m(repo, town)
	ArmySplit._put(repo, state.army_roster[original], point)
	state.army_roster[original]["camp_town"] = town
	state.regiments[original]["camp_town"] = town
	state.regiments[original]["x_m"] = point.x
	state.regiments[original]["y_m"] = point.y
	state.town_seat = {town: original}
	assert_eq(_reconcile().get("status"), "complete")
	assert_eq(state.town_seat, {town: original})
	var child: String = state.military_migration["unit_mapping"][original][1]
	var at := ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, state, state.army_roster[child]))
	assert_false(ArmyGround.in_reach(repo, town, at))
	assert_eq(ArmyGround.camped_by(repo, state, child), town)
	assert_eq(ArmyGround.seated_in(repo, state, child), "")

func _replacement_candidate() -> String:
	var serving := String(state.military_rosters[original]["commander_id"])
	var candidate := Character.from_dict((state.characters[serving] as Character).to_dict())
	candidate.id = "migration_last_noble"
	candidate.seat = ""
	candidate.category = "commander"
	candidate.attributes["health"] = 100
	state.characters[candidate.id] = candidate
	var eligibility: Dictionary = repo.commanders[serving].duplicate(true)
	repo.commanders = {serving: repo.commanders[serving], candidate.id: eligibility}
	return candidate.id

func test_last_anonymous_noble_is_replaced_without_zero_cohort_and_loads_again() -> void:
	var candidate := _replacement_candidate()
	state.military_cohorts["nobles"]["initial"] = 2
	state.military_cohorts["nobles"]["fit"] = 2
	state.military_cohorts["common"]["initial"] += 52
	state.military_cohorts["common"]["fit"] += 52
	assert_eq(_reconcile().get("status"), "complete")
	var child: String = state.military_migration["unit_mapping"][original][1]
	assert_eq(state.military_rosters[child]["commander_id"], candidate)
	for id: String in state.military_cohorts:
		assert_gt(int(state.military_cohorts[id]["initial"]), 0, id)
	for ids: Array in state.military_migration["cohort_mapping"].values():
		for id: String in ids:
			assert_true(state.military_cohorts.has(id), id)
	var officer := String(state.military_rosters[child]["commander_cohort_id"])
	assert_has(state.military_migration["cohort_mapping"]["nobles"], officer)
	state = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)
	var migrated := MilitaryBootstrap.migrate(repo, state)
	assert_false(migrated.has("error"), str(migrated))

func _town_warrant(action: String) -> Dictionary:
	var realm := String(state.army_roster[original]["kingdom_code"])
	var town := String(repo.kingdoms[realm]["capital_burg"])
	var at := Vector2(float(repo.burgs[town]["x"]), float(repo.burgs[town]["y"]))
	var order := {"action_code": action, "to_town": town, "town": town, "rate": 1200}
	var courier := CourierSystem.dispatch_to(repo, state, CourierSystem.ORDINARY, original, order, at)
	state.supply_lines[original] = SupplyLines._new_record(town, 1200, int(courier["id"]) if action == "SUPPLY_POINT_SET" else int(courier["id"]) - 1)
	return courier

func _arrive_at_town() -> Array:
	state = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)
	state.couriers[0]["x_m"] = state.couriers[0]["aim_x_m"]
	state.couriers[0]["y_m"] = state.couriers[0]["aim_y_m"]
	state.couriers[0]["path"] = []
	return CourierSystem.ride_day(repo, state)

func test_town_supply_warrant_reaches_every_child_on_one_physical_arrival() -> void:
	var courier := _town_warrant("SUPPLY_POINT_SET")
	var old_path: Array = courier["path"].duplicate(true)
	var id := int(courier["id"])
	var gold := int(state.metrics["treasury"])
	assert_eq(_reconcile().get("status"), "complete")
	var children: Array = state.military_migration["unit_mapping"][original]
	assert_eq(state.couriers.size(), 1)
	assert_eq(state.couriers[0]["path"], old_path)
	assert_eq(state.couriers[0].get("delivery_targets", []), children)
	assert_true(CourierSystem.has_recipient(state.couriers[0], children[1]))
	assert_true((state.couriers[0].get("recipient_queue", []) as Array).is_empty())
	var events := _arrive_at_town()
	assert_eq(state.couriers.size(), 0)
	for child: String in children:
		assert_eq(state.supply_lines[child]["state"], SupplyLines.RIDING)
		assert_eq(state.supply_lines[child]["order_id"], id)
		assert_gt(int(state.supply_lines[child]["ready_day"]), state.absolute_day())
	assert_eq(SupplyLines.set_out_events(events).size(), children.size())
	assert_eq(int(state.metrics["treasury"]), gold)

func test_town_supply_warrant_staleness_is_per_child_for_set_and_clear() -> void:
	for action: String in ["SUPPLY_POINT_SET", "SUPPLY_POINT_CLEAR"]:
		before_each()
		var courier := _town_warrant(action)
		var id := int(courier["id"])
		assert_eq(_reconcile().get("status"), "complete")
		var children: Array = state.military_migration["unit_mapping"][original]
		var child: String = children[1]
		state.supply_lines[child]["order_id"] = id + 1
		var newer: Dictionary = state.supply_lines[child].duplicate(true)
		_arrive_at_town()
		assert_eq(state.couriers.size(), 0)
		assert_eq(state.supply_lines[child], newer)
		if action == "SUPPLY_POINT_SET":
			assert_eq(state.supply_lines[original]["state"], SupplyLines.RIDING)
		else:
			assert_false(state.supply_lines.has(original))

func _paid_legacy_reinforcement(equipment: int, living: int, added: int, noble_permille: int,
		new_commander := "") -> Dictionary:
	var serving := String(state.military_rosters[original]["commander_id"])
	var family := (state.characters[serving] as Character).family_name
	var realm := String(state.army_roster[original]["kingdom_code"])
	var town := String(repo.kingdoms[realm]["capital_burg"])
	var origin := String(repo.burgs[town]["province_code"])
	var at := ArmyGround.town_point_m(repo, town)
	ArmySplit._put(repo, state.army_roster[original], at)
	state.army_roster[original]["camp_town"] = town
	state.army_roster[original]["cavalry"] = str(equipment)
	state.army_roster[original]["source_parts"] = [{"regiment_code": "saved_source", "province_code": origin, "arm": "cavalry", "equipment_count": equipment, "crew_per_element": 2}]
	state.regiments[original]["x_m"] = at.x
	state.regiments[original]["y_m"] = at.y
	state.regiments[original]["camp_town"] = town
	state.regiments[original]["order"] = ArmySystem.ORDER_GARRISON
	state.military_cohorts.clear()
	state.military_rosters[original]["cohort_ids"] = []
	var recruited_commander := serving if new_commander.is_empty() else new_commander
	if new_commander.is_empty():
		_add("officer", "noble", family, 1, 0, 0, 0, origin, serving)
		_add("nobles", "noble", family, 54, 0, 0, 0, origin)
		_add("common", "commoner", "", living - 55, 0, 0, 0, origin)
	else:
		state.military_rosters[original]["commander_id"] = ""
		state.military_rosters[original]["commander_cohort_id"] = ""
		_add("nobles", "noble", family, 54, 0, 0, 0, origin)
		_add("common", "commoner", "", living - 54, 0, 0, 0, origin)
	state.metrics["treasury"] = 1_000_000
	repo.balance["army_split_cap_men"] = 1800
	repo.balance["recruitment_eligible_permille"] = 1000
	state.world[MilitaryPopulation.path(origin, "rural_population")] = 100_000
	repo.recruitment["cavalry"] = {"commoner_gold": "2", "noble_gold": "10", "commander_gold": "0", "equipment_gold_per_element": "3", "build_days": "2", "requires_port": "0"}
	state.military_migration = {"version": 1, "status": "initialized"}
	var req := {"request_id": "headroom", "mode": "reinforce", "arm": "", "unit_code": original,
		"total": added, "noble_permille": noble_permille, "source_province": origin,
		"source_population_field": "rural_population", "assembly_town": town, "commander_id": recruited_commander}
	var receipt := RecruitmentSystem.recruit(repo, state, req)
	assert_false(receipt.has("error"), str(receipt))
	repo.balance["army_split_cap_men"] = 600
	state.military_migration["organization_pending"] = true
	return receipt

func _complete_paid_project_after_json() -> void:
	state = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)
	RecruitmentSystem.step_day(repo, state)
	state.day += 1
	RecruitmentSystem.step_day(repo, state)
	assert_eq(state.recruitment_projects["headroom"]["status"], "complete", str(state.recruitment_projects["headroom"].get("pause_reason", "")))
	for code: String in state.recruitment_projects["headroom"]["unit_codes"]:
		assert_lte(Roster.personnel_capacity(repo, state.army_roster[code]), 600)
		assert_lte(Roster.living(state, code), Roster.personnel_capacity(repo, state.army_roster[code]))
		assert_false(ArmySplit.saved_sources(repo, state.army_roster[code]).has("error"))
	assert_false(MilitaryBootstrap.migrate(repo, state).has("error"))

func test_paid_gear_reserves_rounding_headroom_before_splitting() -> void:
	var receipt := _paid_legacy_reinforcement(599, 1198, 2, 46)
	if receipt.has("error"): return
	assert_eq(_reconcile().get("status"), "complete")
	var project: Dictionary = state.recruitment_projects["headroom"]
	var children: Array = project.get("unit_codes", [])
	assert_eq(children.size(), 2)
	if children.size() != 2: return
	for i: int in children.size():
		assert_eq(int(state.army_roster[children[i]]["cavalry"]), 300 if i == 0 else 299)
		assert_eq(project["equipment_by_unit"][children[i]]["cavalry"], 0 if i == 0 else 1)
		assert_eq(Roster.living(state, children[i]), 600 if i == 0 else 598)
		var assembling := 0
		for id: String in project["cohort_ids"]:
			var cohort: Dictionary = state.military_cohorts[id]
			if cohort["unit_code"] == children[i]: assembling += int(cohort["fit"])
		assert_eq(assembling, 0 if i == 0 else 2)
	assert_eq(project["result"], receipt)
	_complete_paid_project_after_json()

func test_outstanding_paid_gear_can_require_a_third_child() -> void:
	var receipt := _paid_legacy_reinforcement(600, 1200, 18, 50)
	if receipt.has("error"): return
	assert_eq(_reconcile().get("status"), "complete")
	var project: Dictionary = state.recruitment_projects["headroom"]
	var children: Array = project.get("unit_codes", [])
	assert_eq(children.size(), 3)
	if children.size() != 3: return
	for child: String in children:
		assert_eq(int(state.army_roster[child]["cavalry"]), 200)
		assert_eq(project["equipment_by_unit"][child]["cavalry"], 3)
		assert_eq(Roster.living(state, child), 400)
	assert_eq(project["result"], receipt)
	_complete_paid_project_after_json()

func test_current_equipment_within_cap_still_splits_for_paid_final_capacity() -> void:
	var receipt := _paid_legacy_reinforcement(300, 600, 2, 92)
	if receipt.has("error"): return
	assert_eq(_reconcile().get("status"), "complete")
	var project: Dictionary = state.recruitment_projects["headroom"]
	assert_eq(project.get("unit_codes", []).size(), 2)
	if project.get("unit_codes", []).size() != 2: return
	_complete_paid_project_after_json()

func test_new_paid_officer_stays_with_first_child_when_second_has_assembly_headroom() -> void:
	var realm := repo.resolve_realm("player_realm")
	var candidates := repo.commanders.keys()
	candidates.sort()
	var new_officer := ""
	for person: String in candidates:
		if (state.characters[person] as Character).kingdom == realm \
				and MilitaryCommanders.candidate_error(repo, state, person) == "":
			new_officer = person
			break
	assert_ne(new_officer, "")
	if new_officer == "": return
	var receipt := _paid_legacy_reinforcement(599, 1197, 3, 46, new_officer)
	if receipt.has("error"): return
	var project: Dictionary = state.recruitment_projects["headroom"]
	var named_cohort := String(project["cohort_ids"].filter(
		func(id: String) -> bool: return state.military_cohorts[id].has("person_id")).front())
	assert_true(bool(project["quote"]["needs_commander"]))
	var organization := _reconcile()
	assert_eq(organization.get("status"), "complete", str(organization))
	project = state.recruitment_projects["headroom"]
	var children: Array = project.get("unit_codes", [])
	assert_eq(children.size(), 2)
	assert_eq(project["equipment_by_unit"][children[0]]["cavalry"], 0)
	assert_eq(project["equipment_by_unit"][children[1]]["cavalry"], 1)
	assert_eq(Roster.living(state, children[0]), 599)
	assert_eq(Roster.living(state, children[1]), 598)
	var mapping: Array = state.military_migration["cohort_mapping"][named_cohort]
	assert_eq(mapping.size(), 1)
	assert_eq(state.military_cohorts[mapping[0]]["unit_code"], original,
		"named paid commander must reserve the first child's place")
	state = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)
	assert_false(MilitaryBootstrap.migrate(repo, state).has("error"))
	RecruitmentSystem.step_day(repo, state)
	state.day += 1
	RecruitmentSystem.step_day(repo, state)
	assert_eq(state.recruitment_projects["headroom"]["status"], "complete",
		str(state.recruitment_projects["headroom"].get("pause_reason", "")))
	assert_eq(state.military_rosters[original]["commander_id"], new_officer)
	assert_eq(int(state.army_roster[children[0]]["cavalry"]), 300)
	assert_eq(int(state.army_roster[children[1]]["cavalry"]), 300)
	assert_eq(state.recruitment_projects["headroom"]["result"], receipt)

func test_reorganization_conserves_released_promise_slices_without_binding_new_officers() -> void:
	var origin := String(state.military_cohorts.common.source_province)
	for id: String in ["common", "nobles"]:
		var cohort: Dictionary = state.military_cohorts[id]
		if id == "nobles":
			cohort.initial += 10
			cohort.released += 10
		cohort.civilian_promises = [
			{"count": 6, "until_day": 0, "proposal_id": "promise1", "reason": "Released under an indefinite pledge"},
			{"count": 4, "until_day": state.absolute_day() + 1, "proposal_id": "promise2", "reason": "Released under a brief pledge"}]
	var available := MilitaryPopulation.available(repo, state, origin, "rural_population")
	assert_eq(MilitaryPopulation.restricted(state, origin, "rural_population"), 20)
	assert_eq(_reconcile().get("status"), "complete")
	assert_eq(MilitaryPopulation.restricted(state, origin, "rural_population"), 20)
	assert_eq(MilitaryPopulation.available(repo, state, origin, "rural_population"), available)
	var slices := {}
	for cohort: Dictionary in state.military_cohorts.values():
		var promised := 0
		for promise: Dictionary in cohort.get("civilian_promises", []):
			promised += int(promise.count)
			slices[promise.proposal_id] = int(slices.get(promise.proposal_id, 0)) + int(promise.count)
		assert_lte(promised, int(cohort.released), "A serving named officer must not inherit civilians' pledges")
	assert_eq(slices, {"promise1": 12, "promise2": 8})
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)
	assert_eq(MilitaryPopulation.restricted(restored, origin, "rural_population"), 20)
