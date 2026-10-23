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
	var codes := state.regiments.keys()
	codes.sort()
	for code: String in codes:
		if MapObjects.regiment_arm(repo, state.army_roster[code]) == "cavalry":
			original = code
			break
	var unit: Dictionary = state.army_roster[original].duplicate(true)
	var officer: String = state.military_rosters[original].commander_id
	var family: String = state.characters[officer].family_name
	var origin: String = unit.source_parts[0].province_code
	state.army_roster = {original: unit}
	state.regiments = {original: state.regiments[original].duplicate(true)}
	state.foes.clear()
	state.battles.clear()
	state.ai_hosts.clear()
	state.town_seat.clear()
	state.military_cohorts.clear()
	state.military_rosters = {original: {"commander_id": officer, "commander_cohort_id": "officer", "cohort_ids": []}}
	state.military_migration = {"version": 1, "organization_version": 1, "organization_pending": false,
		"unit_mapping": {"historical": [original]}}
	for arm: String in repo.world_table("military", "unit_types"):
		unit[arm] = "0"
	unit.cavalry = "1001"
	unit.source_parts = [{"regiment_code": "saved_source", "province_code": origin, "arm": "cavalry", "equipment_count": 1001,
		"crew_per_element": int(repo.world_row("military", "unit_types", "cavalry").crew)}]
	_add("officer", 1, 0, 0, 0, 0, officer, family)
	_add("common", 0, 1000, 77, 31, 12)
	state.regiments[original].supplies = 101
	state.unit_prize_gold = {original: 101}

func _add(id: String, fit: int, wounded: int, captured := 0, dead := 0, released := 0, person := "", family := "") -> void:
	var cohort := {"id": id, "unit_code": original, "identity": "noble" if person != "" else "commoner", "family_name": family,
		"stage": "active", "source_province": state.army_roster[original].source_parts[0].province_code,
		"source_population_field": "rural_population", "initial": fit + wounded + captured + dead + released,
		"fit": fit, "wounded": wounded, "captured_current": captured, "dead": dead, "released": released,
		"origin_reason": "Saved paid people"}
	if person != "": cohort.person_id = person
	state.military_cohorts[id] = cohort
	state.military_rosters[original].cohort_ids.append(id)

func _reconcile() -> Dictionary:
	return MilitaryReorganization.reconcile(repo, state)

func _children() -> Array:
	return state.military_migration.get("living_unit_mapping", {}).get(original, [])

func test_v1_complete_splits_living_not_equipment_and_anchors_history() -> void:
	state.military_cohorts.common.civilian_promises = [{"count": 12, "until_day": 99, "reason": "saved release"}]
	var history := state.military_events.duplicate(true)
	var world := state.world.duplicate(true)
	var metrics := state.metrics.duplicate(true)
	var rng_state := state.rng.to_dict()
	assert_eq(_reconcile().status, "complete")
	var children := _children()
	assert_eq(children, [original, original + ":living:v2:1"])
	if children.size() != 2: return
	assert_eq(state.military_migration.living_cap_version, 2)
	assert_eq(state.military_migration.unit_mapping, {"historical": [original]})
	assert_eq(Roster.living(state, children[0]), 501)
	assert_eq(Roster.living(state, children[1]), 500)
	assert_eq(Roster.fit(state, children[0]), 1)
	assert_eq(Roster.fit(state, children[1]), 0)
	assert_eq(state.military_cohorts.officer.unit_code, original)
	assert_eq(state.military_rosters[children[1]].commander_id, "")
	assert_eq(state.military_cohorts.common.captured_current, 77)
	assert_eq(state.military_cohorts.common.dead, 31)
	assert_eq(state.military_cohorts.common.released, 12)
	assert_eq(state.military_cohorts.common.civilian_promises.size(), 1)
	var initial := 0
	for cohort: Dictionary in state.military_cohorts.values():
		initial += int(cohort.initial)
		if cohort.id != "common":
			assert_eq(int(cohort.captured_current) + int(cohort.dead) + int(cohort.released), 0)
	assert_eq(initial, 1121)
	for i: int in children.size():
		assert_eq(state.regiments[children[i]].supplies, 51 if i == 0 else 50)
		assert_eq(state.unit_prize_gold[children[i]], 51 if i == 0 else 50)
	assert_eq(state.military_events, history)
	assert_eq(state.world, world)
	assert_eq(state.metrics, metrics)
	assert_eq(state.rng.to_dict(), rng_state)
	var hash_before := SaveLoad.state_hash(state)
	state = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)
	assert_eq(_reconcile().status, "complete")
	assert_eq(SaveLoad.state_hash(state), hash_before)
	assert_false(MilitaryBootstrap.migrate(repo, state).has("error"))
	assert_eq(SaveLoad.state_hash(state), hash_before)

func test_captives_do_not_consume_living_cap() -> void:
	state.military_cohorts.common.wounded = 999
	state.military_cohorts.common.initial -= 1
	var cohorts := state.military_cohorts.duplicate(true)
	assert_eq(_reconcile().status, "complete")
	assert_eq(state.army_roster.size(), 1)
	assert_eq(state.military_cohorts, cohorts)

func test_recursive_2500_and_2001_have_binary_path_ids() -> void:
	for example: Array in [[2500, [625, 625, 625, 625], ["", "01", "10", "11"]], [2001, [501, 500, 1000], ["", "01", "1"]]]:
		before_each()
		state.military_cohorts.common.wounded = example[0] - 1
		state.military_cohorts.common.initial = example[0] - 1 + 120
		assert_eq(_reconcile().status, "complete")
		var children := _children()
		assert_eq(children.size(), example[1].size())
		for i: int in children.size():
			assert_eq(Roster.living(state, children[i]), example[1][i])
			assert_eq(children[i], original if i == 0 else original + ":living:v2:" + example[2][i])

func test_frozen_day_or_round_is_byte_unchanged_then_completes() -> void:
	for day: bool in [true, false]:
		before_each()
		state.military_migration.organization_pending = true
		if day: state.day_resolution = {"phase": "battles", "battle_index": 1}
		else: state.battles = [{"id": 1, "att": [original], "def": [], "pending_round": {"att": [original], "roll": 99}}]
		var before := SaveLoad.state_hash(state)
		assert_eq(_reconcile().status, "deferred")
		assert_eq(SaveLoad.state_hash(state), before)
		state.day_resolution.clear()
		state.battles.clear()
		assert_eq(_reconcile().status, "complete")

func test_id_and_cohort_collision_and_bad_origin_are_atomic() -> void:
	for kind: String in ["unit", "cohort", "origin", "camp", "cap"]:
		before_each()
		match kind:
			"unit": state.army_roster[original + ":living:v2:1"] = state.army_roster[original].duplicate(true)
			"cohort": state.military_cohorts["common:living:v2:1"] = state.military_cohorts.common.duplicate(true)
			"origin": state.military_cohorts.common.source_province = "unknown"
			"camp": repo.balance.army_slot_max_rings = 0
			"cap": repo.balance.army_living_cap_men = 0
		var before := SaveLoad.state_hash(state)
		assert_eq(_reconcile().status, "error", kind)
		assert_eq(SaveLoad.state_hash(state), before, kind)

func test_live_intent_and_sighting_stay_on_original_laws_and_host_expand() -> void:
	state.scout_log = {original: {"contact": 7}}
	state.sightings = {"old": {"unit": original, "x_m": 99}}
	state.war_drafts = {original: {"order": "march"}}
	state.regiments[original].charge = {"phase": "impact", "target": "foe"}
	state.regiments[original].carry_order_id = 88
	state.regiments[original].dest_x_m = 123
	state.regiments[original].dest_y_m = 456
	state.ai_hosts = {"host": {"unit_codes": [original]}}
	state.war_plans = {"strokes": {"stroke": {"codes": [original]}}}
	state.law_in_force = {"unit:" + original: {"test": {"value": "on", "decree_id": 4}}}
	var courier := {"id": 99, "target": original, "orders": [{"action_code": "ARMY_MARCH", "regiment": original}], "recipient_queue": []}
	state.couriers = [courier.duplicate(true)]
	var sightings := state.sightings.duplicate(true)
	assert_eq(_reconcile().status, "complete")
	var children := _children()
	if children.size() != 2: return
	var child: String = children[1]
	assert_eq(state.ai_hosts.host.unit_codes, children)
	assert_eq(state.war_plans.strokes.stroke.codes, children)
	assert_eq(state.law_in_force["unit:" + child], state.law_in_force["unit:" + original])
	assert_false(state.scout_log.has(child))
	assert_false(state.war_drafts.has(child))
	assert_false(state.regiments[child].has("charge"))
	assert_eq(state.regiments[original].carry_order_id, 88)
	assert_false(state.regiments[child].has("carry_order_id"), "a received supply-load receipt stays singular")
	assert_false(state.regiments[child].has("dest_x_m"))
	assert_eq(state.couriers, [courier])
	assert_eq(state.sightings, sightings)

func test_two_small_units_are_not_consolidated_and_wounded_only_is_valid() -> void:
	state.military_cohorts.common.wounded = 399
	state.military_cohorts.common.initial -= 601
	var unit: Dictionary = state.army_roster[original].duplicate(true)
	unit.regiment_code = "second"
	state.army_roster.second = unit
	state.military_rosters.second = {"commander_id": "", "cohort_ids": ["second"]}
	var cohort: Dictionary = state.military_cohorts.common.duplicate(true)
	cohort.id = "second"
	cohort.unit_code = "second"
	cohort.initial = 400
	cohort.wounded = 400
	cohort.captured_current = 0
	cohort.dead = 0
	cohort.released = 0
	state.military_cohorts.second = cohort
	assert_eq(_reconcile().status, "complete")
	assert_eq(state.army_roster.size(), 2)
	assert_eq(Roster.living(state, original), 400)
	assert_eq(Roster.living(state, "second"), 400)
	assert_eq(Roster.fit(state, "second"), 0)

func test_one_ship_larger_than_cap_keeps_water_point_and_empty_fleet_child() -> void:
	state.army_roster[original].cavalry = "0"
	state.army_roster[original].fleet = "1"
	state.army_roster[original].is_naval = "1"
	state.army_roster[original].source_parts[0].arm = "fleet"
	state.army_roster[original].source_parts[0].equipment_count = 1
	state.army_roster[original].source_parts[0].crew_per_element = int(repo.world_row("military", "unit_types", "fleet").crew)
	var at := Vector2i.ZERO
	for cell: Dictionary in repo.cells.values():
		if MapTerrain.is_sea(cell):
			at = ArmySystem.pack_to_metres(repo, MapTerrain.cell_center(repo, cell))
			break
	state.regiments[original].x_m = at.x
	state.regiments[original].y_m = at.y
	assert_eq(_reconcile().status, "complete")
	var children := _children()
	if children.size() != 2: return
	var child: String = children[1]
	assert_eq(int(state.army_roster[original].fleet), 1)
	assert_eq(int(state.army_roster[child].fleet), 0)
	assert_eq(MapObjects.regiment_arm(repo, state.army_roster[child]), "fleet")
	assert_eq(state.army_roster[child].source_parts, [])
	assert_eq(state.regiments[child].x_m, at.x)
	assert_eq(state.regiments[child].y_m, at.y)
	assert_eq(Roster.personnel_capacity(repo, state.army_roster[child]), 0)
	assert_eq(ArmySystem.power_of_arms(repo, state.army_roster[child], 500, 100, 100, "steady", "plains", ""), 0)
	assert_false(ArmySplit.saved_sources(repo, state.army_roster[child]).has("error"))

func test_completed_frozen_day_migrates_at_its_first_empty_boundary() -> void:
	state.prisoner_batches.clear()
	state.military_cohorts.common.captured_current = 0
	state.military_cohorts.common.initial -= 77
	state.day_resolution = DayResolution.begin(state.day, false, state.absolute_day())
	state.day_resolution.phase_cursor = DayResolution.PHASES.size() - 1
	state.day_resolution.phase = "COMPLETE"
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)
	var rng_before := state.rng.to_dict()
	for candidate: GameState in [state, restored]:
		assert_eq(MilitaryReorganization.reconcile(repo, candidate).status, "deferred")
		assert_eq(TickEngine.new(repo).resolve_day(candidate).status, "complete")
		assert_true(candidate.day_resolution.is_empty())
		assert_eq(int(candidate.military_migration.get("living_cap_version", 0)), 2, "Do not wait for another day call")
	assert_eq(SaveLoad.state_hash(state), SaveLoad.state_hash(restored))
	assert_eq(state.rng.to_dict(), rng_before)

func test_custody_proposal_and_release_still_resolve_original_cohort() -> void:
	var realm: String = state.army_roster[original].kingdom_code
	state.prisoner_batches = {"batch": {"id": "batch", "source_cohort": "common", "origin_realm": realm,
		"holder_code": original, "captor_code": original, "commoners": 77, "nobles": 0,
		"named_ids": [], "wounded_subset": 0, "initial_count": 77, "disposition": "held"}}
	state.prisoner_proposals = {"old": {"source_cohort": "common", "holder": original}}
	var batches := state.prisoner_batches.duplicate(true)
	var proposals := state.prisoner_proposals.duplicate(true)
	assert_eq(_reconcile().status, "complete")
	assert_eq(state.prisoner_batches, batches)
	assert_eq(state.prisoner_proposals, proposals)
	var release := PrisonerSystem.release(repo, state, "release", [{"batch_id": "batch", "count": 77, "wounded_count": 0}], "Saved captives released")
	assert_false(release.has("error"), str(release))
	assert_eq(state.military_cohorts.common.captured_current, 0)
	assert_eq(state.military_cohorts.common.released, 89)
	var before := SaveLoad.state_hash(state)
	assert_eq(PrisonerSystem.release(repo, state, "release", [{"batch_id": "batch", "count": 77, "wounded_count": 0}], "Saved captives released"), release)
	assert_eq(SaveLoad.state_hash(state), before)

func test_paid_legacy_assembly_completes_once_after_json_and_split() -> void:
	var row: Dictionary = state.army_roster[original]
	var realm: String = row.kingdom_code
	var town: String = repo.kingdoms[realm].capital_burg
	var origin: String = repo.burgs[town].province_code
	var at := ArmyGround.town_point_m(repo, town)
	repo.world_table("military", "unit_types").cavalry.crew = "2"
	row.cavalry = "599"
	row.source_parts = [{"regiment_code": "saved_source", "province_code": origin, "arm": "cavalry", "equipment_count": 599, "crew_per_element": 2}]
	ArmySplit._put(repo, row, at)
	row.camp_town = town
	state.regiments[original].x_m = at.x
	state.regiments[original].y_m = at.y
	state.regiments[original].camp_town = town
	state.regiments[original].order = ArmySystem.ORDER_GARRISON
	state.military_cohorts.common.fit = 1197
	state.military_cohorts.common.wounded = 0
	state.military_cohorts.common.captured_current = 0
	state.military_cohorts.common.dead = 0
	state.military_cohorts.common.released = 0
	state.military_cohorts.common.initial = 1197
	for cohort: Dictionary in state.military_cohorts.values(): cohort.source_province = origin
	state.metrics.treasury = 1_000_000
	state.world[MilitaryPopulation.path(origin, "rural_population")] = 100_000
	repo.balance.army_split_cap_men = 1800
	repo.balance.recruitment_eligible_permille = 1000
	repo.recruitment.cavalry = {"commoner_gold": "2", "noble_gold": "10", "commander_gold": "0", "equipment_gold_per_element": "3", "build_days": "2", "requires_port": "0"}
	var request := {"request_id": "legacy-paid", "mode": "reinforce", "unit_code": original, "total": 2,
		"noble_permille": 0, "source_province": origin, "source_population_field": "rural_population",
		"assembly_town": town, "commander_id": state.military_rosters[original].commander_id}
	var receipt := RecruitmentSystem.recruit(repo, state, request)
	assert_false(receipt.has("error"), str(receipt))
	if receipt.has("error"): return
	repo.balance.army_split_cap_men = 600
	state.military_migration.organization_pending = true
	var chest: float = state.metrics.treasury
	var residents := state.world.duplicate(true)
	assert_eq(_reconcile().status, "complete")
	var children := _children()
	assert_eq(children.size(), 2)
	if children.size() != 2: return
	state = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)
	RecruitmentSystem.step_day(repo, state)
	state.day += 1
	RecruitmentSystem.step_day(repo, state)
	assert_eq(state.recruitment_projects["legacy-paid"].status, "complete", str(state.recruitment_projects["legacy-paid"].get("pause_reason", "")))
	assert_eq(state.recruitment_projects["legacy-paid"].result, receipt)
	assert_eq(Roster.living(state, children[0]), 600)
	assert_eq(Roster.living(state, children[1]), 600)
	assert_eq(int(state.army_roster[children[0]].cavalry) + int(state.army_roster[children[1]].cavalry), 600)
	assert_eq(state.metrics.treasury, chest)
	assert_eq(state.world, residents)
	var before := SaveLoad.state_hash(state)
	RecruitmentSystem.step_day(repo, state)
	assert_eq(RecruitmentSystem.recruit(repo, state, request), receipt)
	assert_eq(SaveLoad.state_hash(state), before)
	assert_false(MilitaryBootstrap.migrate(repo, state).has("error"))

func test_anonymous_fit_precedes_wounds_across_sorted_origins() -> void:
	state.military_cohorts.common.wounded = 500
	state.military_cohorts.common.initial -= 500
	_add("later", 500, 0)
	assert_eq(_reconcile().status, "complete")
	var children := _children()
	if children.size() != 2: return
	assert_eq(Roster.fit(state, children[0]), 501)
	assert_eq(Roster.fit(state, children[1]), 0)

func test_wounded_named_officer_and_named_captive_keep_single_original_id() -> void:
	state.military_cohorts.officer.fit = 0
	state.military_cohorts.officer.wounded = 1
	state.military_rosters[original].commander_id = ""
	state.military_rosters[original].commander_cohort_id = ""
	var serving: String = state.military_cohorts.officer.person_id
	var people := repo.commanders.keys()
	people.sort()
	for person: String in people:
		if person != serving:
			_add("named-captive", 0, 0, 1, 0, 0, person, state.characters[person].family_name)
			break
	assert_true(state.military_cohorts.has("named-captive"))
	var captive: Dictionary = state.military_cohorts["named-captive"].duplicate(true)
	assert_eq(_reconcile().status, "complete")
	assert_eq(state.military_cohorts["named-captive"], captive)
	assert_eq(state.military_cohorts.officer.unit_code, original)
	assert_eq(state.military_migration.living_cohort_mapping.officer, ["officer"])
	assert_eq(state.military_migration.living_cohort_mapping["named-captive"], ["named-captive"])
	var unique: Dictionary = {}
	for cohort: Dictionary in state.military_cohorts.values():
		if cohort.has("person_id"):
			assert_false(unique.has(cohort.person_id))
			unique[cohort.person_id] = true
	assert_eq(unique.size(), 2)

func test_exact_wounded_cap_has_no_split_and_no_fit_models() -> void:
	state.military_cohorts.officer.fit = 0
	state.military_cohorts.officer.wounded = 1
	state.military_rosters[original].commander_id = ""
	state.military_rosters[original].commander_cohort_id = ""
	state.military_cohorts.common.wounded = 999
	state.military_cohorts.common.initial -= 1
	assert_eq(_reconcile().status, "complete")
	assert_eq(state.army_roster.size(), 1)
	assert_eq(Roster.living(state, original), 1000)
	assert_eq(Roster.fit(state, original), 0)

func test_running_supply_debt_is_partitioned_once() -> void:
	state.regiments[original].run_supply_rem = 9999
	assert_eq(_reconcile().status, "complete")
	var debts: Array = []
	for child: String in _children():
		debts.append(state.regiments[child].run_supply_rem)
	assert_eq(debts, [5004, 4995], "501:500 living shares conserve the original 9999 debt")

func test_reenlisted_named_person_keeps_released_history() -> void:
	var person: String = state.military_cohorts.officer.person_id
	_add("released-officer", 0, 0, 0, 0, 1, person, state.characters[person].family_name)
	var history: Dictionary = state.military_cohorts["released-officer"].duplicate(true)
	assert_eq(_reconcile().status, "complete")
	assert_eq(state.military_cohorts["released-officer"], history)
	assert_eq(state.military_cohorts.officer.unit_code, original)
	assert_false(MilitaryBootstrap.migrate(repo, state).has("error"))
