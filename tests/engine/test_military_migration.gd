extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")

func _subject() -> GDScript:
	var path := "res://scripts/engine/military_migration.gd"
	var subject: GDScript = load(path) if ResourceLoader.exists(path) else null
	assert_not_null(subject, "saved organizations have a personnel migration")
	return subject

func _fixture(elements: int = 200, crew: int = 2) -> Dictionary:
	var repo := SuiteData.repo()
	var state := GameState.new()
	state.rng = Rng.new(7)
	state.metrics = GameState.from_dict(state.to_dict()).metrics
	var provinces := repo.world_table("economy", "provinces").keys()
	provinces.sort()
	var province: String = provinces[0]
	state.world["economy.provinces.%s.rural_population" % province] = 1000
	state.world["economy.provinces.%s.urban_population" % province] = 500
	repo.world_table("military", "unit_types")["cavalry"]["crew"] = str(crew)
	state.army_roster = {"saved": {"regiment_code": "saved", "kingdom_code": repo.resolve_realm("player_realm"),
		"province_code": province, "parent_code": "ancestor", "is_naval": "0", "is_royal": "0",
		"cavalry": str(elements), "x": "0", "y": "0", "camp_town": "", "label": "Saved"}}
	var land: Array = ArmySplit.roster_of(repo).values().filter(func(r: Dictionary) -> bool: return String(r.get("is_naval", "0")) != "1")
	state.army_roster.saved.x = String(land[0].x)
	state.army_roster.saved.y = String(land[0].y)
	state.army_roster.saved.camp_town = String(land[0].get("camp_town", ""))
	state.regiments = {"saved": {"dead": 10, "wounded": 20, "deserted": 5, "supplies": 101}}
	return {"repo": repo, "state": state, "province": province}

func test_crew_and_old_losses_are_personnel_once() -> void:
	var subject := _subject()
	if subject == null: return
	var f := _fixture()
	var s: GameState = f.state
	assert_false(subject.ensure(f.repo, s).has("error"))
	assert_eq(MilitaryRoster.fit(s, "saved"), 365)
	assert_eq(MilitaryRoster.count(s, "saved", "wounded"), 20)
	assert_eq(MilitaryRoster.count(s, "saved", "dead"), 10)
	assert_eq(MilitaryRoster.count(s, "saved", "released"), 5)
	assert_eq(s.army_roster.saved.cavalry, "200")
	assert_eq(s.world["economy.provinces.%s.rural_population" % f.province], 1000)
	var snapshot := s.to_dict()
	assert_false(subject.ensure(f.repo, s).has("error"))
	assert_eq(s.to_dict(), snapshot)
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(snapshot)))
	assert_false(subject.ensure(f.repo, restored).has("error"))
	for key: String in snapshot:
		assert_eq(restored.to_dict()[key], snapshot[key], key)

func test_weighted_sources_are_160_rural_20_urban() -> void:
	var subject := _subject()
	if subject == null: return
	var f := _fixture(90, 2)
	var s: GameState = f.state
	s.regiments.saved = {}
	assert_false(subject.ensure(f.repo, s).has("error"))
	assert_eq(MilitaryPopulation.occupied(s, f.province, "rural_population"), 160)
	assert_eq(MilitaryPopulation.occupied(s, f.province, "urban_population"), 20)

func test_split_preserves_first_id_inventory_and_typed_references() -> void:
	var subject := _subject()
	if subject == null: return
	var f := _fixture(301, 2)
	var s: GameState = f.state
	s.battles = [{"att": ["saved"], "def": [], "id": 7}]
	s.war_drafts = {"saved": {"order": "halt"}}
	s.law_in_force = {"unit:saved": {"camp": {"value": "on"}}}
	s.supply_lines = {"saved": {"fee_milli": 13, "m_bought": {"house": 7}}}
	s.couriers = [{"id": 2, "target": "saved", "orders": [{"action_code": "ARMY_HALT", "regiment": "saved"}], "kind": "ordinary"}]
	s.regiments.saved.order_id = 9
	s.metrics.treasury = 87
	s.ai_hosts = {"host": {"unit_codes": ["saved"], "target_id": "town"}}
	s.war_plans.strokes = {"front": {"codes": ["saved"], "name": "saved"}}
	assert_false(subject.ensure(f.repo, s).has("error"))
	var ids: Array = s.military_unit_aliases.saved
	assert_eq(ids.size(), 2)
	assert_eq(ids[0], "saved")
	assert_eq(int(s.army_roster[ids[0]].cavalry), 151)
	assert_eq(int(s.army_roster[ids[1]].cavalry), 150)
	assert_eq(s.battles[0].att, ids)
	assert_eq(s.ai_hosts.host.unit_codes, ids)
	assert_eq(s.ai_hosts.host.target_id, "town")
	assert_eq(s.war_plans.strokes.front.codes, ids)
	assert_eq(s.war_plans.strokes.front.name, "saved")
	assert_eq(s.war_drafts.size(), 2)
	assert_eq(s.law_in_force["unit:" + ids[1]], s.law_in_force["unit:" + ids[0]], "split inherits saved laws")
	s.law_in_force["unit:" + ids[1]].camp.value = "off"
	assert_eq(s.law_in_force["unit:" + ids[0]].camp.value, "on", "each descendant keeps independent law history")
	assert_eq(s.supply_lines[ids[0]].fee_milli + s.supply_lines[ids[1]].fee_milli, 13)
	assert_eq(s.regiments[ids[0]].supplies + s.regiments[ids[1]].supplies, 101)
	assert_eq(s.couriers.size(), 2)
	assert_gt(int(s.regiments[ids[1]].order_id), int(s.couriers[1].id), "a stale saved warrant remains stale for its child")
	assert_eq(s.metrics.treasury, 87)
	assert_eq(MilitaryRoster.fit(s, ids[0]) + MilitaryRoster.fit(s, ids[1]), 567)

func test_transaction_preserves_cursor_then_reorganizes_once() -> void:
	var subject := _subject()
	if subject == null: return
	var f := _fixture(301, 2)
	var s: GameState = f.state
	s.day_resolution = {"phase": "battles", "cursor": 1, "participants": ["saved"]}
	var transaction := s.day_resolution.duplicate(true)
	assert_false(subject.ensure(f.repo, s).has("error"))
	assert_eq(s.army_roster.keys(), ["saved"])
	assert_eq(s.day_resolution, transaction)
	assert_true(s.military_migration_pending)
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_false(subject.ensure(f.repo, restored).has("error"))
	assert_eq(restored.day_resolution, transaction)
	s.day_resolution = {}
	restored.day_resolution = {}
	assert_false(subject.ensure(f.repo, s).has("error"))
	assert_false(subject.ensure(f.repo, restored).has("error"))
	for key: String in s.to_dict():
		assert_eq(restored.to_dict()[key], s.to_dict()[key], key)
	assert_eq(s.military_organization_version, 1)
	assert_false(s.military_migration_pending)

func test_handcomputed_large_split_preserves_capacity_and_nobles() -> void:
	var subject := _subject()
	if subject == null: return
	var f := _fixture(1268, 2)
	var s: GameState = f.state
	s.regiments.saved = {}
	assert_false(subject.ensure(f.repo, s).has("error"))
	var ids: Array = s.military_unit_aliases.saved
	var elements: Array = []
	var people: Array = []
	for id: String in ids:
		elements.append(int(s.army_roster[id].cavalry))
		people.append(MilitaryRoster.fit(s, id))
		var nobles := 0
		for cohort_id: String in s.military_rosters[id].cohort_ids:
			var cohort: Dictionary = s.military_cohorts[cohort_id]
			if cohort.identity == "noble": nobles += int(cohort.fit)
		assert_eq(nobles, 1, id)
	assert_eq(elements, [254, 254, 254, 253, 253])
	assert_eq(people, [508, 508, 508, 506, 506])

func test_invalid_crew_and_small_remnant_do_not_drop_equipment() -> void:
	var subject := _subject()
	if subject == null: return
	var f := _fixture(1, 0)
	var s: GameState = f.state
	assert_true(subject.ensure(f.repo, s).has("error"))
	assert_eq(s.army_roster.saved.cavalry, "1")
	assert_true(s.military_cohorts.is_empty())
	f = _fixture(1, 2)
	s = f.state
	s.regiments.saved = {"wounded": 1}
	assert_false(subject.ensure(f.repo, s).has("error"))
	assert_eq(MilitaryRoster.fit(s, "saved"), 1)
	assert_eq(MilitaryRoster.count(s, "saved", "wounded"), 1)
	assert_eq(s.army_roster.saved.cavalry, "1")

func test_unknown_train_provenance_preserves_force_and_bootstraps_other_units() -> void:
	var subject := _subject()
	if subject == null: return
	var f := _fixture()
	var s: GameState = f.state
	var train: Dictionary = s.army_roster.saved.duplicate(true)
	train.regiment_code = "old_train"
	train.cavalry = "0"
	train.artillery = "2"
	s.army_roster.old_train = train
	var before := s.army_roster.duplicate(true)
	assert_true(subject.ensure(f.repo, s).has("error"))
	assert_true(s.military_migration_pending)
	assert_eq(s.army_roster, before)
	assert_eq(MilitaryRoster.fit(s, "saved"), 365)
	assert_false(s.military_rosters.has("old_train"))

func test_authored_multi_source_train_never_moves_all_crew_to_capital() -> void:
	var subject := _subject()
	if subject == null: return
	var f := _fixture(0, 2)
	var s: GameState = f.state
	var provinces: Array = f.repo.world_table("economy", "provinces").keys()
	provinces.sort()
	var other: String = provinces[1]
	s.world["economy.provinces.%s.rural_population" % other] = 1000
	s.world["economy.provinces.%s.urban_population" % other] = 500
	var row: Dictionary = s.army_roster.saved
	row.artillery = "2"
	f.repo.world_table("military", "unit_types").artillery.crew = "8"
	row.source_parts = [{"regiment_code": "a", "province_code": f.province, "arm": "artillery", "equipment_count": 1, "crew_per_element": 8},
		{"regiment_code": "b", "province_code": other, "arm": "artillery", "equipment_count": 1, "crew_per_element": 8}]
	s.regiments.saved = {}
	assert_false(subject.ensure(f.repo, s).has("error"))
	assert_eq(MilitaryRoster.fit(s, "saved"), 16)
	assert_eq(MilitaryPopulation.occupied(s, f.province), 8)
	assert_eq(MilitaryPopulation.occupied(s, other), 8)
	assert_eq(s.army_roster.saved.artillery, "2")

func test_new_campaign_all_player_and_raider_units_have_one_counted_commander() -> void:
	var subject := _subject()
	if subject == null: return
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 71)
	assert_eq(state.military_organization_version, 1)
	var named: Dictionary = {}
	var checked := 0
	for code: String in state.army_roster:
		var row: Dictionary = state.army_roster[code]
		if String(row.kingdom_code) not in [repo.resolve_realm("player_realm"), repo.resolve_realm("raider_realm")]: continue
		checked += 1
		var roster: Dictionary = state.military_rosters.get(code, {})
		var commander := String(roster.get("commander_id", ""))
		assert_ne(commander, "", code)
		assert_false(named.has(commander), code)
		named[commander] = true
		var matches := 0
		for id: String in roster.get("cohort_ids", []):
			var cohort: Dictionary = state.military_cohorts[id]
			if String(cohort.get("person_id", "")) == commander:
				matches += 1
				assert_eq(cohort.identity, "noble")
				assert_eq(cohort.initial, 1)
		assert_eq(matches, 1, code)
	assert_gt(checked, 0)

func test_crew_eight_cap_twentyfive_splits_equipment_three_two_two() -> void:
	var subject := _subject()
	if subject == null: return
	var f := _fixture(7, 8)
	var s: GameState = f.state
	f.repo.balance["army_split_cap_men"] = 25
	s.regiments.saved = {}
	assert_false(subject.ensure(f.repo, s).has("error"))
	var elements: Array = []
	var people: Array = []
	for id: String in s.military_unit_aliases.saved:
		elements.append(int(s.army_roster[id].cavalry))
		people.append(MilitaryRoster.fit(s, id))
	assert_eq(elements, [3, 2, 2])
	assert_eq(people, [24, 16, 16])

func test_one_ship_crew_hundred_preserves_one_ship_and_personnel() -> void:
	var subject := _subject()
	if subject == null: return
	var f := _fixture(0, 2)
	var s: GameState = f.state
	f.repo.world_table("military", "unit_types")["test_ship"] = {"crew": "100", "rural_rate": "0.12", "urban_rate": "0.03"}
	s.army_roster.saved.is_naval = "1"
	s.army_roster.saved.test_ship = "1"
	s.regiments.saved = {}
	assert_false(subject.ensure(f.repo, s).has("error"))
	assert_eq(s.army_roster.saved.test_ship, "1")
	assert_eq(MilitaryRoster.fit(s, "saved"), 100)
	var snapshot := s.to_dict()
	assert_false(subject.ensure(f.repo, s).has("error"))
	assert_eq(s.to_dict(), snapshot)


func test_pending_supply_metadata_and_desertion_remainder_are_conserved() -> void:
	var f := _fixture(301, 2)
	var state: GameState = f.state
	state.supply_lines = {"saved": {"pending": {"town": "depot", "rate": 750, "order_id": 7}}}
	state.regiments.saved.desert_rem = 13
	state.couriers = [{"id": 7, "target": "saved", "orders": [{"action_code": "SUPPLY_POINT_SET"}]}]
	assert_false(MilitaryMigration.ensure(f.repo, state).has("error"))
	var remainder := 0
	for code: String in state.military_unit_aliases.saved:
		remainder += int(state.regiments[code].desert_rem)
		assert_eq(state.supply_lines[code].pending.town, "depot")
		assert_eq(state.supply_lines[code].pending.rate, 750)
		var courier: Dictionary = state.couriers.filter(func(c: Dictionary) -> bool: return c.target == code)[0]
		assert_eq(state.supply_lines[code].pending.order_id, courier.id)
	assert_eq(remainder, 13)
