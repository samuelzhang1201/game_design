extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
var repo: DataRepository
var state: GameState
var request: Dictionary
var town: String
var province: String
var officer: String

func before_each() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 42)
	SuiteData.open_country(repo)
	var realm := repo.resolve_realm("player_realm")
	var towns := repo.burgs.keys()
	towns.sort()
	for code: String in towns:
		if String(repo.burgs[code]["kingdom_code"]) == realm:
			town = code
			break
	province = String(repo.burgs[town]["province_code"])
	state.army_roster.clear()
	state.regiments.clear()
	state.foes.clear()
	state.town_seat.clear()
	state.military_rosters.clear()
	state.military_cohorts.clear()
	state.military_events.clear()
	state.military_migration.clear()
	state.recruitment_projects.clear()
	state.battles.clear()
	var ids := repo.commanders.keys()
	ids.sort()
	for id: String in ids:
		if (state.characters[id] as Character).kingdom == realm \
				and MilitaryCommanders.candidate_error(repo, state, id) == "" \
				and "infantry" in String(repo.commanders[id]["unit_kinds"]).split("|"):
			officer = id
			break
	state.metrics["treasury"] = 2000
	repo.balance["recruitment_eligible_permille"] = 1000
	state.world[MilitaryPopulation.path(province, "rural_population")] = 1000
	if repo.get("recruitment") != null:
		repo.get("recruitment")["infantry"] = {"arm": "infantry", "commoner_gold": "2", "noble_gold": "10",
			"commander_gold": "0", "equipment_gold_per_element": "0", "build_days": "2", "requires_port": "0"}
	request = {"request_id": "test-paid-600", "mode": "new", "arm": "infantry", "total": 600,
		"source_province": province, "source_population_field": "rural_population", "assembly_town": town,
		"noble_permille": 50, "commander_id": officer}

func _system() -> Script:
	var path := "res://scripts/engine/recruitment_system.gd"
	assert_true(FileAccess.file_exists(path), "paid recruitment needs a real transaction")
	return load(path) if FileAccess.file_exists(path) else null

func test_quote_and_paid_reservation_include_commander_without_free_supplies() -> void:
	var system := _system()
	if system == null: return
	var before := SaveLoad.state_hash(state)
	var quote: Dictionary = system.quote(repo, state, request)
	assert_false(quote.has("error"), str(quote))
	assert_eq(quote.get("gold"), 1440)
	assert_eq(quote.get("composition"), {"commoners": 570, "noble_troops": 29, "commander": 1})
	assert_eq(quote.get("quality", {}).get("power_permille"), 1050)
	assert_eq(quote.get("quality", {}).get("discipline_permille"), 1050)
	assert_gt(int(quote.get("food_per_month", 0)), 0)
	assert_eq(SaveLoad.state_hash(state), before, "a preview reserves nothing")
	var result: Dictionary = system.recruit(repo, state, request)
	assert_false(result.has("error"), str(result))
	assert_eq(int(state.metrics["treasury"]), 560)
	assert_eq(MilitaryPopulation.available(repo, state, province, "rural_population"), 400)
	assert_eq(int(WorldLedger.value_of(repo, state, MilitaryPopulation.path(province, "rural_population"))), 1000)
	assert_eq(state.army_roster.size(), 0, "assembling people cannot be commanded or drawn as ready")
	assert_eq(MilitaryRoster.fit(state, String(result.get("unit_code", ""))), 0)
	assert_eq(state.recruitment_projects.size(), 1)

func test_insufficient_gold_or_population_changes_nothing() -> void:
	var system := _system()
	if system == null: return
	state.metrics["treasury"] = 1439
	var before := SaveLoad.state_hash(state)
	var unaffordable: Dictionary = system.quote(repo, state, request)
	assert_true(unaffordable.has("error"))
	assert_eq(unaffordable.get("gold"), 1440, "an unaffordable preview still explains the complete price")
	assert_eq(unaffordable.get("composition", {}).get("commoners"), 570)
	assert_true(system.recruit(repo, state, request).has("error"))
	assert_eq(SaveLoad.state_hash(state), before)
	state.metrics["treasury"] = 2000
	state.world[MilitaryPopulation.path(province, "rural_population")] = 599
	before = SaveLoad.state_hash(state)
	assert_true(system.recruit(repo, state, request).has("error"))
	assert_eq(SaveLoad.state_hash(state), before)

func test_replay_survives_json_and_changed_world_but_conflicting_payload_refuses() -> void:
	var system := _system()
	if system == null: return
	var receipt: Dictionary = system.recruit(repo, state, request)
	state = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)
	state.metrics["treasury"] = 0
	var before := SaveLoad.state_hash(state)
	assert_eq(system.recruit(repo, state, request), receipt)
	assert_eq(SaveLoad.state_hash(state), before)
	request["total"] = 500
	assert_true(system.recruit(repo, state, request).has("error"))
	assert_eq(SaveLoad.state_hash(state), before)

func test_two_effective_day_ends_pause_and_resume_without_catching_up() -> void:
	var system := _system()
	if system == null: return
	var receipt: Dictionary = system.recruit(repo, state, request)
	var code := String(receipt.get("unit_code", ""))
	system.step_day(repo, state)
	assert_eq(MilitaryRoster.fit(state, code), 0)
	assert_eq(state.recruitment_projects[request["request_id"]]["worked_days"], 1)
	var before := SaveLoad.state_hash(state)
	system.step_day(repo, state)
	assert_eq(SaveLoad.state_hash(state), before)
	state.day += 1
	MapOwnership.set_owner(repo, state, province, repo.resolve_realm("raider_realm"), "fixture town lost")
	system.step_day(repo, state)
	assert_eq(state.recruitment_projects[request["request_id"]]["status"], "paused")
	assert_eq(MilitaryRoster.fit(state, code), 0)
	state = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)
	MapOwnership.set_owner(repo, state, province, repo.resolve_realm("player_realm"), "fixture town regained")
	state.day += 1
	system.step_day(repo, state)
	assert_eq(MilitaryRoster.fit(state, code), 600)
	assert_eq(state.military_rosters[code]["commander_id"], officer)
	assert_eq(state.regiments[code]["supplies"], 0, "equipment purchase creates no grain")
	assert_eq(int(state.army_roster[code]["infantry"]), 600)
	assert_eq(int(state.metrics["treasury"]), 560)
	before = SaveLoad.state_hash(state)
	system.step_day(repo, state)
	assert_eq(SaveLoad.state_hash(state), before)

func test_invalid_counts_commander_and_unfinished_journal_refuse_atomically() -> void:
	var system := _system()
	if system == null: return
	for patch: Dictionary in [{"total": 600.5}, {"noble_permille": 101}, {"commander_id": "you"},
		{"source_province": "unknown"}, {"assembly_town": "unknown"}, {"total": 1001}]:
		var bad := request.duplicate(true)
		bad.merge(patch, true)
		var before := SaveLoad.state_hash(state)
		assert_true(system.recruit(repo, state, bad).has("error"), str(patch))
		assert_eq(SaveLoad.state_hash(state), before)
	state.day_resolution = {"phase": "battles"}
	var before := SaveLoad.state_hash(state)
	assert_true(system.recruit(repo, state, request).has("error"))
	assert_eq(SaveLoad.state_hash(state), before)

func test_reserved_officer_cannot_enlist_twice() -> void:
	var system := _system()
	if system == null: return
	system.recruit(repo, state, request)
	state.metrics["treasury"] = 2000
	var second := request.duplicate(true)
	second["request_id"] = "second"
	second["total"] = 100
	var before := SaveLoad.state_hash(state)
	assert_true(system.recruit(repo, state, second).has("error"))
	assert_eq(SaveLoad.state_hash(state), before)

func test_action_order_replay_has_no_second_cost_drift_or_history() -> void:
	var actions := ActionSystem.new(repo)
	var req := ActionRequest.make("ARMY_RECRUIT", request)
	assert_eq(actions.validate(req, state), "")
	if actions.validate(req, state) != "": return
	var result := actions.execute(req, state)
	assert_true(result.get("ok", false), str(result))
	assert_eq(int(state.metrics["treasury"]), 560)
	state = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)
	var before := SaveLoad.state_hash(state)
	assert_eq(actions.execute(req, state), result)
	assert_eq(SaveLoad.state_hash(state), before)

func test_completed_calendar_days_finish_assembly_once_through_day_transaction() -> void:
	var system := _system()
	if system == null: return
	var paid: Dictionary = system.recruit(repo, state, request)
	var code := String(paid.get("unit_code", ""))
	state.ai_hosts.clear()
	var engine := TickEngine.new(repo)
	var first := engine.resolve_day(state)
	assert_eq(first.get("status"), "complete")
	assert_eq(MilitaryRoster.fit(state, code), 0)
	var second := engine.resolve_day(state)
	assert_eq(second.get("status"), "complete")
	assert_eq(MilitaryRoster.fit(state, code), 600)
	assert_eq(int(state.metrics["treasury"]), 560)

func _ready_unit(system: Script, total := 400) -> String:
	request["total"] = total
	var paid: Dictionary = system.recruit(repo, state, request)
	system.step_day(repo, state)
	state.day += 1
	system.step_day(repo, state)
	return String(paid.get("unit_code", ""))

func _reinforcement(code: String, total := 100, share := 50) -> Dictionary:
	var req := request.duplicate(true)
	req["request_id"] = "reinforce"
	req["mode"] = "reinforce"
	req["unit_code"] = code
	req["total"] = total
	req["noble_permille"] = share
	return req

func test_reinforcements_fill_vacant_crews_then_purchase_only_needed_equipment() -> void:
	var system := _system()
	if system == null: return
	var code := _ready_unit(system)
	var commoners := "recruit:" + String(request["request_id"]) + ":commoners"
	assert_false(MilitaryRoster.transition(repo, state, "loss-40", [{"cohort_id": commoners, "from": "fit", "to": "dead", "count": 40}], "fixture losses").has("error"))
	var req := _reinforcement(code)
	var offer: Dictionary = system.quote(repo, state, req)
	assert_false(offer.has("error"), str(offer))
	assert_eq(offer.get("equipment"), {"infantry": 60}, "40 vacant places need no replacement weapon")
	assert_eq(offer.get("gold"), 224, "97 commoners plus 3 nobles; existing commander stays counted")
	assert_false(system.recruit(repo, state, req).has("error"))
	var duplicate := req.duplicate(true)
	duplicate["request_id"] = "concurrent"
	var before := SaveLoad.state_hash(state)
	assert_true(system.recruit(repo, state, duplicate).has("error"))
	assert_eq(SaveLoad.state_hash(state), before)
	state.day += 1
	system.step_day(repo, state)
	state.day += 1
	system.step_day(repo, state)
	assert_eq(MilitaryRoster.living(state, code), 460)
	assert_eq(int(state.army_roster[code]["infantry"]), 460)
	assert_eq(state.military_rosters[code]["commander_id"], officer)

func test_reinforcements_pause_when_target_is_away_or_commander_is_wounded() -> void:
	var system := _system()
	if system == null: return
	var code := _ready_unit(system)
	var req := _reinforcement(code)
	assert_false(system.recruit(repo, state, req).has("error"))
	state.regiments[code]["order"] = ArmySystem.ORDER_MARCH
	state.regiments[code]["camp_town"] = ""
	state.day += 1
	system.step_day(repo, state)
	assert_eq(state.recruitment_projects["reinforce"]["worked_days"], 0)
	assert_eq(state.recruitment_projects["reinforce"]["status"], "paused")
	state.regiments[code]["order"] = ArmySystem.ORDER_GARRISON
	state.regiments[code]["camp_town"] = town
	var commander_cohort := String(state.military_rosters[code]["commander_cohort_id"])
	assert_false(MilitaryRoster.transition(repo, state, "officer-wound", [{"cohort_id": commander_cohort, "from": "fit", "to": "wounded", "count": 1}], "fixture commander wounded").has("error"))
	state.day += 1
	system.step_day(repo, state)
	assert_eq(state.recruitment_projects["reinforce"]["worked_days"], 0, "an unfit officer cannot supervise a paid assembly")
	assert_eq(state.recruitment_projects["reinforce"]["status"], "paused")

func test_fleet_crews_assemble_at_real_water_and_can_receive_port_reinforcements() -> void:
	var system := _system()
	if system == null: return
	var ports := repo.burgs.keys()
	ports.sort()
	for burg: String in ports:
		if String(repo.burgs[burg].get("is_port", "0")) == "1" \
				and ArmyGround.holds(repo, state, repo.resolve_realm("player_realm"), burg):
			town = burg
			break
	province = String(repo.burgs[town]["province_code"])
	state.world[MilitaryPopulation.path(province, "urban_population")] = 1000
	repo.recruitment["fleet"] = {"arm": "fleet", "commoner_gold": "1", "noble_gold": "2", "commander_gold": "0",
		"equipment_gold_per_element": "3", "build_days": "2", "requires_port": "1"}
	var officers: Array = system.available_commanders(repo, state, "fleet")
	assert_false(officers.is_empty(), "authored reserves include naval commanders")
	if officers.is_empty(): return
	officer = String(officers[0])
	request.merge({"arm": "fleet", "total": 200, "source_province": province, "assembly_town": town,
		"source_population_field": "urban_population", "commander_id": officer}, true)
	var paid: Dictionary = system.recruit(repo, state, request)
	assert_false(paid.has("error"), str(paid))
	if paid.has("error"): return
	var code := String(paid["unit_code"])
	system.step_day(repo, state)
	state.day += 1
	system.step_day(repo, state)
	assert_eq(MilitaryRoster.fit(state, code), 200)
	assert_eq(int(state.army_roster[code]["fleet"]), 2, "200 people are two ships, not 200 ships")
	var here := ArmySystem.position_of(repo, state, state.army_roster[code])
	var afloat := false
	for cell: Dictionary in repo.cells.values():
		if MapTerrain.is_sea(cell) and Geometry2D.is_point_in_polygon(here, MapEconomy.cell_polygon(repo, cell)):
			afloat = true
			break
	assert_true(afloat, "new fleets must occupy an actual sea polygon, not the economic nearest-land fallback")
	var move := ActionRequest.make("ARMY_MARCH", {"regiment": code, "x": here.x + 2.0, "y": here.y})
	assert_eq(ActionSystem.new(repo).validate_place(move, state), "", "a fleet can sail in the water beside its port")
	var reinforcement := _reinforcement(code, 100)
	assert_false(system.recruit(repo, state, reinforcement).has("error"))
	state.day += 1
	system.step_day(repo, state)
	state.day += 1
	system.step_day(repo, state)
	assert_eq(MilitaryRoster.fit(state, code), 300)
	assert_eq(int(state.army_roster[code]["fleet"]), 3)

func test_reinforcement_equipment_capacity_does_not_replace_living_cap() -> void:
	var system := _system()
	if system == null: return
	repo.world_table("military", "unit_types")["infantry"]["crew"] = "7"
	var code := _ready_unit(system, 399)
	var req := _reinforcement(code, 199)
	var before := SaveLoad.state_hash(state)
	var offer: Dictionary = system.quote(repo, state, req)
	assert_false(offer.has("error"), str(offer))
	assert_eq(offer.get("equipment"), {"infantry": 29}, "598 people use 602 equipment places; spare places are not people")
	assert_eq(SaveLoad.state_hash(state), before)

func test_paid_reinforcement_keeps_its_people_after_later_casualties_and_reports_actual_share() -> void:
	var system := _system()
	if system == null: return
	var code := _ready_unit(system, 300)
	var req := _reinforcement(code, 300, 100)
	var paid: Dictionary = system.recruit(repo, state, req)
	assert_false(paid.has("error"), str(paid))
	if paid.has("error"): return
	assert_eq(state.recruitment_projects["reinforce"]["quote"]["composition"],
		{"commoners": 255, "noble_troops": 45, "commander": 0})
	var treasury := int(state.metrics["treasury"])
	var commoners := "recruit:" + String(request["request_id"]) + ":commoners"
	assert_false(MilitaryRoster.transition(repo, state, "later-loss-270", [
		{"cohort_id": commoners, "from": "fit", "to": "dead", "count": 270}], "losses after the paid contract").has("error"))
	for day: int in 2:
		state.day += 1
		system.step_day(repo, state)
	var project: Dictionary = state.recruitment_projects["reinforce"]
	assert_eq(project["status"], "complete", "later casualty drift cannot strand a valid paid contract")
	assert_eq(MilitaryRoster.living(state, code), 330)
	assert_eq(project.get("completion_composition", {}).get(code, {}),
		{"commoners": 270, "noble_troops": 59, "commander": 1}, "the completion records actual survivors, not its stale target")
	assert_false(String(project.get("completion_reason", "")).is_empty())
	assert_eq(int(state.metrics["treasury"]), treasury)
	state = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)
	var before := SaveLoad.state_hash(state)
	assert_eq(system.recruit(repo, state, req), paid)
	system.step_day(repo, state)
	assert_eq(SaveLoad.state_hash(state), before, "completion, money and surviving composition are idempotent")
	state.metrics["treasury"] = 1000
	var next := _reinforcement(code, 270, 100)
	next["request_id"] = "restore-share"
	var quote: Dictionary = system.quote(repo, state, next)
	assert_false(quote.has("error"), str(quote))
	assert_eq(quote.get("composition"), {"commoners": 270, "noble_troops": 0, "commander": 0}, "next independent contract rechecks the actual survivors")
	assert_eq(quote.get("equipment"), {"infantry": 0}, "the empty places already have equipment")

func test_released_commander_is_civilian_and_reenlists_only_after_promise_and_new_payment() -> void:
	var disposition: Script = load("res://scripts/engine/prisoner_disposition.gd")
	var realm := repo.resolve_realm("player_realm")
	var enemy := repo.resolve_realm("raider_realm")
	for code: String in ["captured_unit", "captor"]:
		state.army_roster[code] = {"regiment_code": code, "kingdom_code": realm if code == "captured_unit" else enemy, "is_naval": "0"}
		state.regiments[code] = {}
	var person: Character = state.characters[officer]
	var enlisted := MilitaryRoster.mobilize(repo, state, "old_service", [
		{"id": "old_officer", "unit_code": "captured_unit", "source_province": province,
			"source_population_field": "rural_population", "identity": "noble", "stage": "active", "count": 1,
			"person_id": officer, "family_name": person.family_name},
		{"id": "old_troops", "unit_code": "captured_unit", "source_province": province,
			"source_population_field": "rural_population", "identity": "commoner", "stage": "active", "count": 59},
		{"id": "guards", "unit_code": "captor", "source_province": province,
			"source_population_field": "rural_population", "identity": "commoner", "stage": "active", "count": 10}], "Previous paid service")
	assert_false(enlisted.has("error"), str(enlisted))
	state.military_rosters.captured_unit.commander_id = officer
	state.military_rosters.captured_unit.commander_cohort_id = "old_officer"
	var captured := PrisonerSystem.capture(repo, state, {"capture_id": "named", "participants": {"captor": 1},
		"reason": "Accepted surrender", "changes": [
			{"cohort_id": "old_officer", "from": "fit", "to": "captured_current", "count": 1},
			{"cohort_id": "old_troops", "from": "fit", "to": "captured_current", "count": 59}]})
	assert_false(captured.has("error"), str(captured))
	var selections: Array = []
	for id: String in captured.batch_ids:
		var batch: Dictionary = state.prisoner_batches[id]
		selections.append({"batch_id": id, "count": int(batch.commoners) + int(batch.nobles), "named_ids": batch.named_ids})
	var proposal := {"id": "named_release", "kind": "release", "money": 0,
		"batches": selections, "parties": {"proposer": enemy, "payer": ""},
		"terms": {"no_fighting_until_day": state.absolute_day()}, "reason": "Released on a noncombat undertaking"}
	assert_false(disposition.propose(repo, state, proposal).has("error"))
	assert_false(disposition.respond(repo, state, proposal.id, realm, true).has("error"))
	var old_opinion := person.opinion
	var result: Dictionary = disposition.settle(repo, state, proposal.id)
	assert_eq(result.get("released"), 60, str(result))
	assert_eq(person.opinion, old_opinion, "Enemy release must not credit the player ruler")
	var enemy_ruler := DevelopmentSystem.ruler_of(repo, state, enemy)
	assert_not_null(enemy_ruler)
	assert_eq(int(RelationshipGraph.edge(state, officer, enemy_ruler.id).get("sentiment", 0)), 2)
	assert_eq(state.military_rosters.captured_unit.commander_id, "")
	assert_eq(state.military_cohorts.old_officer.released, 1)
	assert_eq(MilitaryRoster.living(state, "captured_unit"), 0)
	assert_eq(MilitaryPopulation.restricted(state, province, "rural_population"), 60)
	assert_true(RecruitmentSystem.quote(repo, state, request).has("error"))
	var before := state.to_dict()
	assert_eq(disposition.settle(repo, state, proposal.id), result)
	assert_eq(state.to_dict(), before)
	state.day += 1
	assert_eq(MilitaryPopulation.restricted(state, province, "rural_population"), 0)
	var quote := RecruitmentSystem.quote(repo, state, request)
	assert_false(quote.has("error"), str(quote))
	var gold := int(state.metrics.treasury)
	assert_false(RecruitmentSystem.recruit(repo, state, request).has("error"))
	assert_eq(int(state.metrics.treasury), gold - int(quote.gold))
	assert_eq(state.military_cohorts.old_officer.released, 1)
	assert_eq(MilitaryRoster.living(state, "captured_unit"), 0)
	assert_eq(person.family_name, (state.characters[officer] as Character).family_name)

func test_all_arms_reserve_living_headroom_before_payment() -> void:
	for arm: String in ["infantry", "artillery", "fleet"]:
		before_each()
		state.metrics["treasury"] = 100000
		state.world[MilitaryPopulation.path(province, "rural_population")] = 10000
		repo.world_row("military", "unit_types", arm)["crew"] = "1"
		repo.recruitment[arm] = repo.recruitment["infantry"].duplicate(true)
		var choices := RecruitmentSystem.available_commanders(repo, state, arm)
		assert_false(choices.is_empty())
		if choices.is_empty(): continue
		if arm == "fleet":
			for burg: String in repo.burgs:
				if String(repo.burgs[burg].get("is_port", "0")) == "1" and ArmyGround.holds(repo, state, repo.resolve_realm("player_realm"), burg):
					town = burg
					break
			province = String(repo.burgs[town]["province_code"])
			state.world[MilitaryPopulation.path(province, "rural_population")] = 10000
		request.merge({"arm": arm, "commander_id": choices[0], "total": 900,
			"source_province": province, "assembly_town": town}, true)
		# A stationary fixture permits the same contract test for naval crews.
		var code := _ready_unit(_system(), 900)
		assert_false(code.is_empty())
		if code.is_empty(): continue
		var req := _reinforcement(code, 101)
		var before := SaveLoad.state_hash(state)
		var refused := RecruitmentSystem.recruit(repo, state, req)
		assert_true(refused.has("error"), arm)
		assert_true(String(refused.get("error", "")).contains("1000"), str(refused))
		assert_eq(SaveLoad.state_hash(state), before)
		req["total"] = 100
		var gold := int(state.metrics.treasury)
		var paid := RecruitmentSystem.recruit(repo, state, req)
		assert_false(paid.has("error"), str(paid))
		assert_eq(paid.get("gold"), 240, "95 commoners at2 +5 nobles at10; serving officer has no new fee")
		assert_eq(int(state.metrics.treasury), gold - 240)
		before = SaveLoad.state_hash(state)
		assert_eq(RecruitmentSystem.recruit(repo, state, req), paid)
		assert_eq(SaveLoad.state_hash(state), before)
		var extra := req.duplicate(true)
		extra.merge({"request_id": "extra", "total": 1}, true)
		assert_true(RecruitmentSystem.recruit(repo, state, extra).has("error"))
		assert_eq(SaveLoad.state_hash(state), before)

func test_new_overcap_request_refuses_with_limit_before_debit() -> void:
	for total: int in [1001, 2500]:
		request["total"] = total
		var before := SaveLoad.state_hash(state)
		var result := RecruitmentSystem.recruit(repo, state, request)
		assert_true(result.has("error"))
		assert_true(String(result.get("error", "")).contains("1000"), str(result))
		assert_eq(SaveLoad.state_hash(state), before)

func test_pending_new_unit_survives_real_save_load_and_migration() -> void:
	state = SuiteData.campaign(repo, 42)
	state.metrics.treasury = 1000000
	state.world[MilitaryPopulation.path(province, "rural_population")] = 100000
	request["commander_id"] = RecruitmentSystem.available_commanders(repo, state, "infantry")[0]
	var receipt := RecruitmentSystem.recruit(repo, state, request)
	assert_false(receipt.has("error"), str(receipt))
	if receipt.has("error"): return
	var path := "user://pending_new_living_cap.json"
	assert_true(SaveLoad.save_game(state, path))
	state = SaveLoad.load_game(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var before := SaveLoad.state_hash(state)
	var migrated := MilitaryBootstrap.migrate(repo, state)
	assert_false(migrated.has("error"), str(migrated))
	if migrated.has("error"): return
	assert_eq(MilitaryReorganization.reconcile(repo, state).get("status"), "complete")
	assert_eq(RecruitmentSystem.recruit(repo, state, request), receipt)
	assert_eq(SaveLoad.state_hash(state), before, "loading never re-enlists, pays or activates the pending new unit")
	RecruitmentSystem.step_day(repo, state)
	state.day += 1
	RecruitmentSystem.step_day(repo, state)
	assert_eq(state.recruitment_projects[request.request_id].status, "complete")
	assert_eq(MilitaryRoster.fit(state, receipt.unit_code), 600)

func test_legacy_paid_new_fleet_is_partitioned_and_completes_once() -> void:
	state = SuiteData.campaign(repo, 42)
	state.metrics.treasury = 1000000
	for burg: String in repo.burgs:
		if String(repo.burgs[burg].get("is_port", "0")) == "1" and ArmyGround.holds(repo, state, repo.resolve_realm("player_realm"), burg):
			town = burg
			break
	province = String(repo.burgs[town].province_code)
	state.world[MilitaryPopulation.path(province, "urban_population")] = 100000
	repo.recruitment.fleet = {"commoner_gold": "1", "noble_gold": "2", "commander_gold": "11",
		"equipment_gold_per_element": "3", "build_days": "2", "requires_port": "1"}
	request.merge({"request_id": "legacy-new-fleet", "arm": "fleet", "total": 2500,
		"source_province": province, "source_population_field": "urban_population", "assembly_town": town,
		"commander_id": RecruitmentSystem.available_commanders(repo, state, "fleet")[0]}, true)
	# Reproduce an already-paid historical fleet contract, then restore today's cap.
	repo.balance.army_living_cap_men = 3000
	var receipt := RecruitmentSystem.recruit(repo, state, request)
	repo.balance.army_living_cap_men = 1000
	assert_false(receipt.has("error"), str(receipt))
	if receipt.has("error"): return
	assert_eq(receipt.gold, 2711, "2375 commoners +125 nobles×2 +25 ships×3 +11 officer fee")
	var gold := int(state.metrics.treasury)
	var residents := state.world.duplicate(true)
	state.military_migration.erase("living_cap_version")
	state.military_migration.organization_pending = true
	state = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)
	state.day_resolution = DayResolution.begin(state.day, false, state.absolute_day(), int(repo.bal("battle_substeps")))
	var frozen := SaveLoad.state_hash(state)
	assert_eq(MilitaryReorganization.reconcile(repo, state).get("status"), "deferred")
	assert_eq(SaveLoad.state_hash(state), frozen, "a frozen day never partitions its future units early")
	state.day_resolution.clear()
	var conflict := GameState.from_dict(state.to_dict(), false)
	conflict.military_rosters[String(receipt.unit_code) + ":living:v2:01"] = {"commander_id": "", "cohort_ids": []}
	var conflict_hash := SaveLoad.state_hash(conflict)
	var refused := MilitaryReorganization.reconcile(repo, conflict)
	assert_true(refused.has("error"))
	assert_true(String(refused.get("error", "")).contains("already exists"))
	assert_eq(SaveLoad.state_hash(conflict), conflict_hash, "failed future-unit allocation publishes no reservations or payment changes")
	var migrated := MilitaryBootstrap.migrate(repo, state)
	assert_false(migrated.has("error"), str(migrated))
	if migrated.has("error"): return
	assert_eq(MilitaryReorganization.reconcile(repo, state).get("status"), "complete")
	var project: Dictionary = state.recruitment_projects[request.request_id]
	var codes: Array = project.get("unit_codes", [receipt.unit_code])
	assert_eq(codes.size(), 4)
	for code: String in codes:
		assert_eq(MilitaryRoster.assigned_living(state, code), 625)
		assert_false(state.army_roster.has(code), "reserved new detachments are not deployed before completion")
	var reserved := SaveLoad.state_hash(state)
	var missing_gear := GameState.from_dict(state.to_dict(), false)
	missing_gear.recruitment_projects[request.request_id].erase("equipment_by_unit")
	var missing_hash := SaveLoad.state_hash(missing_gear)
	assert_true(MilitaryBootstrap.migrate(repo, missing_gear).has("error"), "split paid reservations must not load without their equipment allocation")
	assert_eq(SaveLoad.state_hash(missing_gear), missing_hash, "missing gear cannot publish a partial migration")
	state = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)
	assert_false(MilitaryBootstrap.migrate(repo, state).has("error"))
	assert_eq(MilitaryReorganization.reconcile(repo, state).get("status"), "complete")
	assert_eq(SaveLoad.state_hash(state), reserved, "allocated future-unit reservations reload without a second split")
	RecruitmentSystem.step_day(repo, state)
	state.day += 1
	RecruitmentSystem.step_day(repo, state)
	project = state.recruitment_projects[request.request_id]
	assert_eq(project.status, "complete", str(project.get("pause_reason", "")))
	var people := 0
	var ships := 0
	var officers := 0
	var equipment: Array = []
	var source_parts := 0
	for code: String in codes:
		people += MilitaryRoster.fit(state, code)
		ships += int(state.army_roster.get(code, {}).get("fleet", 0))
		equipment.append(int(state.army_roster.get(code, {}).get("fleet", 0)))
		for part: Dictionary in state.army_roster.get(code, {}).get("source_parts", []):
			assert_eq(part.regiment_code, "recruit:" + String(request.request_id))
			source_parts += int(part.equipment_count)
		assert_eq(int(state.regiments.get(code, {}).get("supplies", -1)), 0)
		assert_false(MapEconomy.contains_land(repo, ArmySystem.position_of(repo, state, state.army_roster[code])))
		if state.military_rosters[code].get("commander_id", "") != "": officers += 1
	assert_eq(people, 2500)
	assert_eq(ships, 25)
	assert_eq(equipment, [7, 6, 6, 6], "whole ships use larger-remainder priority; no fractional or invented vessel")
	assert_eq(source_parts, 25)
	assert_eq(officers, 1)
	assert_eq(int(state.metrics.treasury), gold)
	assert_eq(state.world, residents)
	assert_eq(project.result, receipt)
	state = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)
	var before := SaveLoad.state_hash(state)
	RecruitmentSystem.step_day(repo, state)
	assert_eq(RecruitmentSystem.recruit(repo, state, request), receipt)
	assert_eq(SaveLoad.state_hash(state), before)

func test_pending_new_save_requires_the_original_paid_contract_and_unique_cohorts() -> void:
	state = SuiteData.campaign(repo, 42)
	state.metrics.treasury = 1000000
	state.world[MilitaryPopulation.path(province, "rural_population")] = 100000
	request.commander_id = RecruitmentSystem.available_commanders(repo, state, "infantry")[0]
	assert_false(RecruitmentSystem.recruit(repo, state, request).has("error"))
	var original := state.to_dict()
	var code := String(state.recruitment_projects[request.request_id].unit_code)
	for patch: Dictionary in [{"quote": {}}, {"result": {}}, {"equipment": {}}, {"cohort_ids": ["missing"]},
		{"equipment_by_unit": {code: {"infantry": 601}}}, {"equipment_by_unit": {}}, {"last_processed_day": {}}]:
		state = GameState.from_dict(original, false)
		state.recruitment_projects[request.request_id].merge(patch, true)
		var before := SaveLoad.state_hash(state)
		assert_true(MilitaryBootstrap.migrate(repo, state).has("error"), str(patch))
		assert_eq(SaveLoad.state_hash(state), before)
