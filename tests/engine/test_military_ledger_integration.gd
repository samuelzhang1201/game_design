extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")

func test_realm_people_are_province_sum_and_have_no_write_bypass() -> void:
	var repo := SuiteData.repo()
	var state := GameState.new()
	var realm := repo.resolve_realm("player_realm")
	var path := "economy.kingdoms.%s.rural_population" % realm
	var total := 0
	for code: String in MapOwnership.provinces_of(repo, state, realm):
		total += int(WorldLedger.value_of(repo, state, "economy.provinces.%s.rural_population" % code))
	state.world[path] = 1
	assert_eq(int(WorldLedger.value_of(repo, state, path)), total)
	assert_true(WorldLedger.apply(repo, state, path, -10, "no origin", "test").has("error"))

func test_training_does_not_remove_a_second_population() -> void:
	var repo := SuiteData.repo()
	assert_false(String(repo.order_costs["LEVY_RAISE"]["cost"]).contains("population"))

func test_split_caps_are_people_and_keep_equipment() -> void:
	var split_script: GDScript = load("res://scripts/engine/army_split.gd")
	assert_true(split_script.has_method("element_shares"))
	if not split_script.has_method("element_shares"):
		return
	assert_eq(split_script.element_shares(1268, 2, 600), [254, 254, 254, 253, 253])
	assert_eq(split_script.element_shares(301, 2, 600), [151, 150])
	assert_eq(split_script.element_shares(7, 8, 25), [3, 2, 2])
	assert_eq(split_script.element_shares(1, 26, 25), [])

func test_population_write_cannot_erase_people_still_in_service() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 42)
	var cohort: Dictionary = state.military_cohorts.values()[0]
	var p := String(cohort.source_province)
	var field := String(cohort.source_population_field)
	var path := "economy.provinces.%s.%s" % [p, field]
	var before := state.to_dict()
	assert_true(WorldLedger.apply(repo, state, path, -int(WorldLedger.value_of(repo, state, path)), "erase residents", "test").has("error"))
	assert_eq(state.to_dict(), before)

func test_battle_retains_general_then_replaces_an_incapacitated_one() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 42)
	var codes: Array = state.regiments.keys()
	codes.sort()
	var battle := {"att": [codes[0]], "def": [], "commanders": {}}
	assert_false(BattleCommand.update_battle(repo, state, battle).has("error"))
	var incumbent := String(battle.commanders.att)
	assert_ne(incumbent, "")
	battle.att.append(codes[1])
	assert_false(BattleCommand.update_battle(repo, state, battle).has("error"))
	assert_eq(battle.commanders.att, incumbent)
	var incumbent_cohort := String(state.military_rosters[codes[0]].commander_cohort_id)
	assert_false(MilitaryRoster.transition(repo, state, "general:captured", [
		{"cohort_id": incumbent_cohort, "from": "fit", "to": "captured_current", "count": 1}], "General captured in battle").has("error"))
	assert_false(BattleCommand.update_battle(repo, state, battle).has("error"))
	assert_ne(battle.commanders.att, incumbent)

func test_battle_round_failure_leaves_both_sides_and_morale_unchanged() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 42)
	var players: Array = state.regiments.keys()
	var foes: Array = state.foes.keys()
	players.sort()
	foes.sort()
	var p: String = players[0]
	var f: String = foes[0]
	# A damaged old source cannot pay a defender death; attacker must not be charged first.
	for id: String in state.military_rosters[f].cohort_ids:
		var cohort: Dictionary = state.military_cohorts[id]
		state.world["economy.provinces.%s.%s" % [cohort.source_province, cohort.source_population_field]] = 0
	var before := state.to_dict()
	var tier := {"attacker_loss_permille": 100, "defender_loss_permille": 100,
		"wounded_share_permille": 0, "attacker_morale": -10, "defender_morale": -10}
	var result := BattleSystem.apply_round(repo, state, [p], [f], tier, "invalid defender population", Callable(), "invalid-round")
	assert_true(result.has("error"))
	assert_eq(state.to_dict(), before)

func test_delivered_march_waits_for_a_valid_commander() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 42)
	var codes: Array = state.regiments.keys()
	codes.sort()
	var code: String = codes[0]
	var roster: Dictionary = state.military_rosters[code]
	var person := String(roster.commander_id)
	var named := ""
	for id: String in roster.cohort_ids:
		if String(state.military_cohorts[id].get("person_id", "")) == person: named = id
	assert_false(MilitaryRoster.transition(repo, state, "commander-hurt", [
		{"cohort_id": named, "from": "fit", "to": "wounded", "count": 1}], "commander wounded").has("error"))
	var before: Dictionary = state.regiments[code].duplicate(true)
	var courier := {"target": code, "id": 999}
	var order := {"action_code": "ARMY_MARCH", "dest_x_m": 12345, "dest_y_m": 67890}
	var result := CourierSystem._deliver_one(repo, state, courier, order)
	assert_eq(result.type, "lapsed")
	assert_eq(state.regiments[code], before)

func test_invalid_crew_capacity_refuses_a_new_campaign() -> void:
	var repo := SuiteData.repo()
	repo.world_table("military", "unit_types").cavalry.crew = str(int(repo.bal("army_split_cap_men")) + 1)
	ArmySplit.forget()
	assert_null(GameState.new_campaign(repo, 42))

func test_crew_power_uses_equipment_scaled_by_fit_people() -> void:
	var repo := SuiteData.repo()
	# Neutral multipliers isolate two crew-eight equipment elements.
	repo.world_row("military", "unit_types", "artillery")["crew"] = "8"
	repo.balance["army_float_permille"] = 0
	repo.balance["army_training_base_permille"] = 1000
	repo.balance["army_training_step_permille"] = 0
	repo.balance["army_morale_base_permille"] = 1000
	repo.balance["army_morale_step_permille"] = 0
	repo.army_matchups["artillery"] = []
	var guns := {"artillery": 2}
	var full := ArmySystem.power_of_arms(repo, guns, 16, 50, 100, "attack", "plains", "")
	var half := ArmySystem.power_of_arms(repo, guns, 8, 50, 100, "attack", "plains", "")
	assert_eq(full, 2)
	assert_eq(half, 1)
	assert_eq(ArmySystem.power_of_arms(repo, guns, 0, 50, 100, "attack", "plains", ""), 0)
	assert_eq(guns, {"artillery": 2})

func test_realm_personnel_by_arm_counts_mixed_crews_and_live_states() -> void:
	var subject: GDScript = load("res://scripts/engine/army_system.gd")
	assert_true(subject.has_method("personnel_by_arm"))
	if not subject.has_method("personnel_by_arm"):
		return
	var repo := SuiteData.repo()
	for arm: String in {"infantry": 1, "cavalry": 2, "artillery": 8, "fleet": 100}:
		repo.world_row("military", "unit_types", arm)["crew"] = str({"infantry": 1, "cavalry": 2, "artillery": 8, "fleet": 100}[arm])
	var state := GameState.new()
	state.rng = Rng.new(7)
	var realm := repo.resolve_realm("player_realm")
	state.army_roster = {
		"mixed": {"regiment_code": "mixed", "kingdom_code": realm, "infantry": "40", "cavalry": "20"},
		"ship": {"regiment_code": "ship", "kingdom_code": realm, "fleet": "1", "is_naval": "1"},
		"guns": {"regiment_code": "guns", "kingdom_code": realm, "artillery": "2"}}
	for entry: Array in [["mixed", 80, 54, 7, 5, 8, 6], ["ship", 100, 70, 10, 10, 5, 5], ["guns", 16, 10, 2, 1, 2, 1]]:
		var code := String(entry[0])
		state.military_rosters[code] = {"cohort_ids": [code]}
		state.military_cohorts[code] = {"unit_code": code, "initial": entry[1], "fit": entry[2], "wounded": entry[3], "captured_current": entry[4], "dead": entry[5], "released": entry[6], "stage": "active"}
	var before := state.to_dict()
	var counts: Dictionary = subject.personnel_by_arm(repo, state, realm)
	assert_eq(counts.infantry, 31, "61 active people apportioned40:40; stable first-arm remainder")
	assert_eq(counts.cavalry, 30)
	assert_eq(counts.fleet, 80, "crew includes wounded, excludes captives and terminal states")
	assert_eq(counts.artillery, 12)
	var total := 0
	for value: Variant in counts.values():
		assert_eq(typeof(value), TYPE_INT)
		total += int(value)
	assert_eq(total, 153)
	assert_eq(state.to_dict(), before, "the query never initializes or rewrites service")
	state.military_rosters.erase("mixed")
	state.regiments.mixed = {"wounded": 7, "captured_current": 5, "dead": 8, "deserted": 6}
	var missing: Dictionary = subject.personnel_by_arm(repo, state, realm)
	assert_eq(int(missing.get("infantry", 0)), 0, "missing personnel never refill from equipment")
	assert_eq(int(missing.get("cavalry", 0)), 0)
	state.military_rosters.mixed = {"cohort_ids": ["mixed"]}
	var foreign := repo.resolve_realm("raider_realm")
	state.army_roster.foreign = {"regiment_code": "foreign", "kingdom_code": foreign, "infantry": "40", "cavalry": "20"}
	state.military_rosters.foreign = {"cohort_ids": ["foreign"]}
	state.military_cohorts.foreign = state.military_cohorts.mixed.duplicate(true)
	state.military_cohorts.foreign.unit_code = "foreign"
	var theirs: Dictionary = subject.personnel_by_arm(repo, state, foreign)
	assert_eq(theirs.infantry, 31, "foreign roster-only unit reads its cohort losses")
	assert_eq(theirs.cavalry, 30)
	assert_eq(subject.personnel_by_arm(repo, state, realm), counts, "foreign personnel never enter our total")

func test_invalid_defender_nomination_preserves_both_commander_choices() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 42)
	var players: Array = state.regiments.keys()
	var foes: Array = state.foes.keys()
	players.sort()
	foes.sort()
	var battle := {"att": [players[0]], "def": [foes[0]], "commanders": {},
		"commander_nominees": {"def": "unknown"}}
	var before := battle.duplicate(true)
	var saved := state.to_dict()
	assert_true(BattleCommand.update_battle(repo, state, battle).has("error"))
	assert_eq(battle, before)
	assert_eq(state.to_dict(), saved)

func test_departure_eligibility_is_pure_and_casualty_removes_it() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 42)
	var codes: Array = state.regiments.keys()
	codes.sort()
	var code: String = codes[0]
	var roster: Dictionary = state.military_rosters[code]
	var officer: String = roster.commander_id
	var saved := state.to_dict()
	assert_true(MilitaryCommanders.eligible_for_unit(repo, state, code, officer))
	assert_eq(state.to_dict(), saved)
	assert_false(MilitaryRoster.transition(repo, state, "depart:captured", [
		{"cohort_id": roster.commander_cohort_id, "from": "fit", "to": "captured_current", "count": 1}], "Commander captured before departure").has("error"))
	saved = state.to_dict()
	assert_false(MilitaryCommanders.eligible_for_unit(repo, state, code, officer))
	assert_eq(state.to_dict(), saved)
