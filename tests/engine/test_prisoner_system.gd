extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Person := preload("res://scripts/engine/character.gd")
const Prisoners := preload("res://scripts/engine/prisoner_system.gd")

func test_capture_has_one_holder() -> void:
	assert_eq(Prisoners.allocate({"u_b": 3, "u_c": 2, "u_a": 5}, 7), {"u_a": 4, "u_b": 2, "u_c": 1})
	assert_eq(Prisoners.allocate({"u_b": 1, "u_a": 1}, 1), {"u_a": 1, "u_b": 0})

func _fixture() -> Dictionary:
	var repo := SuiteData.repo()
	var state := GameState.new()
	state.rng = Rng.new(501)
	var province := String(repo.provinces.keys()[0])
	for code: String in ["source", "u_a", "u_b", "rescue", "other"]:
		var realm := "origin" if code in ["source", "rescue"] else "captor"
		state.army_roster[code] = {"code": code, "kingdom_code": realm, "is_naval": "0"}
		state.regiments[code] = {}
		var id := code + "_cohort"
		state.military_rosters[code] = {"cohort_ids": [id], "commander_id": ""}
		state.military_cohorts[id] = {"id": id, "unit_code": code, "stage": "active", "identity": "commoner",
			"source_province": province, "source_population_field": "rural_population", "initial": 10,
			"fit": 8, "wounded": 2, "captured_current": 0, "dead": 0, "released": 0}
	return {"repo": repo, "state": state}

func _request() -> Dictionary:
	return {"capture_id": "capture_one", "battle_id": 1, "round": 2,
		"participants": {"u_a": 1, "u_b": 1}, "named_holders": {}, "reason": "Accepted surrender",
		"changes": [{"cohort_id": "source_cohort", "from": "fit", "to": "captured_current", "count": 8},
			{"cohort_id": "source_cohort", "from": "wounded", "to": "captured_current", "count": 2}]}

func test_capture_is_atomic_and_replays_before_source_validation() -> void:
	var f := _fixture()
	var s: GameState = f.state
	var request := _request()
	request.changes.append(request.changes[0].duplicate())
	var before := s.to_dict()
	assert_true(Prisoners.capture(f.repo, s, request).has("error"))
	assert_eq(s.to_dict(), before)
	request = _request()
	var result := Prisoners.capture(f.repo, s, request)
	assert_false(result.has("error"), str(result))
	assert_eq(result.get("personnel", -1), 10)
	assert_eq(s.military_cohorts.source_cohort.fit, 0)
	assert_eq(s.military_cohorts.source_cohort.wounded, 0)
	assert_eq(s.military_cohorts.source_cohort.captured_current, 10)
	assert_eq(Prisoners.held_counts(s, "u_a").total + Prisoners.held_counts(s, "u_b").total, 10)
	assert_eq(Prisoners.held_counts(s, "u_a").wounded + Prisoners.held_counts(s, "u_b").wounded, 2)
	before = s.to_dict()
	assert_eq(Prisoners.capture(f.repo, s, request), result)
	assert_eq(s.to_dict(), before)
	request.reason = "Conflicting retry"
	assert_true(Prisoners.capture(f.repo, s, request).has("error"))
	assert_eq(s.to_dict(), before)

func test_named_captives_reserve_places_and_king_is_rejected() -> void:
	var f := _fixture()
	var s: GameState = f.state
	var person := Person.new()
	person.id = "officer"
	person.category = "noble"
	s.characters.officer = person
	s.military_cohorts.officer_cohort = s.military_cohorts.source_cohort.duplicate(true)
	s.military_cohorts.officer_cohort.merge({"id": "officer_cohort", "initial": 1, "fit": 1, "wounded": 0,
		"person_id": "officer", "identity": "noble"}, true)
	s.military_rosters.source.cohort_ids.append("officer_cohort")
	s.military_rosters.source.commander_id = "officer"
	s.military_rosters.source.commander_cohort_id = "officer_cohort"
	var request := _request()
	request.named_holders = {"officer": "u_b"}
	request.changes.append({"cohort_id": "officer_cohort", "from": "fit", "to": "captured_current", "count": 1})
	person.category = "player"
	var before := s.to_dict()
	assert_true(Prisoners.capture(f.repo, s, request).has("error"))
	assert_eq(s.to_dict(), before)
	person.category = "noble"
	var result := Prisoners.capture(f.repo, s, request)
	assert_false(result.has("error"), str(result))
	assert_eq(Prisoners.held_counts(s, "u_b").nobles, 1)
	assert_eq(s.military_rosters.source.commander_id, "")
	for batch: Dictionary in s.prisoner_batches.values():
		if "officer" in batch.named_ids:
			assert_eq(batch.holder_code, "u_b")
	var promises := [{"person": "officer", "kind": "no_fighting"}]
	s.promises = promises.duplicate(true)
	var rescue := Prisoners.holder_defeated(f.repo, s, "u_b", ["rescue"])
	assert_gt(int(rescue.get("released", 0)), 0)
	assert_eq(s.military_cohorts.officer_cohort.released, 1)
	assert_eq(s.military_rosters.source.commander_id, "")
	assert_eq(s.promises, promises)
	assert_eq(Prisoners.holder_defeated(f.repo, s, "u_b", ["rescue"]), rescue)

func test_holder_defeat_transfers_or_releases_and_requires_live_controllers() -> void:
	var f := _fixture()
	var s: GameState = f.state
	var request := _request()
	request.participants = {"u_a": 1}
	assert_false(Prisoners.capture(f.repo, s, request).has("error"))
	var before := s.to_dict()
	assert_true(Prisoners.holder_defeated(f.repo, s, "u_a", ["missing"]).has("error"))
	assert_eq(s.to_dict(), before)
	var transfer := Prisoners.holder_defeated(f.repo, s, "u_a", ["other"], "defeat_one")
	assert_eq(transfer.get("transferred", -1), 10)
	assert_eq(Prisoners.held_counts(s, "u_a").total, 0)
	assert_eq(Prisoners.held_counts(s, "other").total, 10)
	assert_eq(Prisoners.holder_defeated(f.repo, s, "u_a", ["other"], "defeat_one"), transfer)
	var rescue := Prisoners.holder_defeated(f.repo, s, "other", ["rescue"], "defeat_two")
	assert_eq(rescue.get("released", -1), 10)
	assert_eq(s.military_cohorts.source_cohort.released, 10)
	assert_eq(s.military_cohorts.source_cohort.captured_current, 0)
	assert_eq(MilitaryRoster.living(s, "source"), 0)
	assert_eq(Prisoners.held_counts(s, "rescue").total, 0)
	assert_eq(Prisoners.holder_defeated(f.repo, s, "other", ["rescue"], "defeat_two"), rescue)
	var noop := Prisoners.holder_defeated(f.repo, s, "other", [], "no_prisoners")
	assert_eq(Prisoners.holder_defeated(f.repo, s, "other", [], "no_prisoners"), noop)

func test_receivers_must_be_fit_live_land_units() -> void:
	for invalid: String in ["missing", "dead", "fleet", "removed"]:
		var f := _fixture()
		var s: GameState = f.state
		if invalid == "dead":
			s.military_cohorts.u_a_cohort.fit = 0
		elif invalid == "fleet":
			s.army_roster.u_a.is_naval = "1"
		elif invalid == "removed":
			s.regiments.erase("u_a")
		var request := _request()
		request.participants = {"missing" if invalid == "missing" else "u_a": 1}
		var before := s.to_dict()
		assert_true(Prisoners.capture(f.repo, s, request).has("error"), invalid)
		assert_eq(s.to_dict(), before)

func test_save_round_trip_replays_custody_and_defaults_old_keys() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 501)
	state.prisoner_batches = {"i5": {"commoners": 2, "nobles": 1, "wounded_subset": 1, "holder_code": "i5", "disposition": "held"}}
	state.prisoner_events = {"i7": {"count": 3}}
	state.battle_records = {"i9": {"personnel": 3}}
	var saved: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	var restored := GameState.from_dict(saved)
	assert_eq(restored.prisoner_batches, state.prisoner_batches)
	assert_eq(restored.prisoner_events, state.prisoner_events)
	assert_eq(restored.battle_records, state.battle_records)
	assert_typeof(restored.prisoner_batches.i5.commoners, TYPE_INT)
	for key: String in ["prisoner_batches", "prisoner_events", "battle_records"]:
		saved.erase(key)
	restored = GameState.from_dict(saved)
	assert_eq(restored.prisoner_batches, {})
	assert_eq(restored.prisoner_events, {})
	assert_eq(restored.battle_records, {})

func _legacy_capture(f: Dictionary) -> void:
	var request := _request()
	var s: GameState = f.state
	assert_false(MilitaryRoster.transition(f.repo, s, "battle_surrender:old_order", request.changes, request.reason).has("error"))
	s.battle_orders.old_order = {"status": "delivered", "result": {"capture_handoff": {
		"accepted": true, "captor_unit": "u_a", "battle_id": 1, "personnel": request.changes,
		"reason": request.reason}}}

func test_legacy_capture_migrates_without_recapturing_and_replays() -> void:
	var f := _fixture()
	_legacy_capture(f)
	var s: GameState = f.state
	var cohort_before := s.military_cohorts.duplicate(true)
	var result := Prisoners.migrate_legacy(f.repo, s)
	assert_eq(result.get("status", ""), "applied", str(result))
	assert_eq(Prisoners.held_counts(s, "u_a"), {"commoners": 10, "nobles": 0, "wounded": 2, "total": 10})
	assert_eq(s.military_cohorts, cohort_before)
	assert_eq(Prisoners.migrate_legacy(f.repo, s).get("status", ""), "unchanged")
	assert_eq(s.military_cohorts, cohort_before)

func test_legacy_capture_without_unique_receipt_is_atomic_error() -> void:
	for invalid: String in ["missing", "conflicting", "partial", "gone_holder"]:
		var f := _fixture()
		_legacy_capture(f)
		var s: GameState = f.state
		if invalid == "missing":
			s.battle_orders.clear()
		elif invalid == "conflicting":
			s.battle_orders.old_order.result.capture_handoff.reason = "Another receipt"
		elif invalid == "partial":
			s.military_cohorts.source_cohort.captured_current = 8
			s.military_cohorts.source_cohort.released = 2
		else:
			s.regiments.erase("u_a")
		var before := s.to_dict()
		assert_true(Prisoners.migrate_legacy(f.repo, s).has("error"), invalid)
		assert_eq(s.to_dict(), before)

func test_battle_receivers_need_actual_opposing_presence() -> void:
	var f := _fixture()
	var s: GameState = f.state
	s.battles = [{"id": 1, "att": ["source"], "def": ["u_a"]}]
	var before := s.to_dict()
	assert_true(Prisoners.capture(f.repo, s, _request()).has("error"))
	assert_eq(s.to_dict(), before)
	var request := _request()
	request.participants = {"u_a": 1}
	assert_false(Prisoners.capture(f.repo, s, request).has("error"))

func test_invalid_capture_shapes_are_atomic_and_null_preview_is_empty() -> void:
	for value: Variant in [0, -1, 1.5, "1"]:
		assert_true(Prisoners.allocate({"u_a": value}, 1).has("error"))
		var f := _fixture()
		var request := _request()
		request.changes[0].count = value
		var before: Dictionary = f.state.to_dict()
		assert_true(Prisoners.capture(f.repo, f.state, request).has("error"))
		assert_eq(f.state.to_dict(), before)
	assert_eq(Prisoners.held_counts(null, "u_a"), {"commoners": 0, "nobles": 0, "wounded": 0, "total": 0})

func test_no_surviving_controller_explicitly_releases_civilians_once() -> void:
	var f := _fixture()
	var s: GameState = f.state
	var request := _request()
	request.participants = {"u_a": 1}
	assert_false(Prisoners.capture(f.repo, s, request).has("error"))
	var result := Prisoners.holder_defeated(f.repo, s, "u_a", [], "mutual_destruction")
	assert_eq(result.get("released", -1), 10)
	assert_eq(s.military_cohorts.source_cohort.captured_current, 0)
	assert_eq(s.military_cohorts.source_cohort.released, 10)
	for batch: Dictionary in s.prisoner_batches.values():
		assert_true(batch.civilian)
		assert_true("No surviving field controller" in batch.reason)
	assert_eq(Prisoners.holder_defeated(f.repo, s, "u_a", [], "mutual_destruction"), result)

func test_saved_capture_replays_after_sources_and_holders_change() -> void:
	var f := _fixture()
	var s: GameState = f.state
	var request := _request()
	request.participants = {"u_a": 1.0}
	var result := Prisoners.capture(f.repo, s, request)
	assert_false(result.has("error"))
	assert_typeof(s.prisoner_events.capture_one.request.participants.u_a, TYPE_INT)
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())), false)
	restored.regiments.erase("u_a")
	var before := restored.to_dict()
	assert_eq(Prisoners.capture(f.repo, restored, request), result)
	assert_eq(restored.to_dict(), before)

func test_normalized_duplicate_requests_and_metadata_replay() -> void:
	var f := _fixture()
	var request := _request()
	var result := Prisoners.capture(f.repo, f.state, request)
	request.changes = [{"cohort_id": "source_cohort", "from": "wounded", "to": "captured_current", "count": 2},
		{"cohort_id": "source_cohort", "from": "fit", "to": "captured_current", "count": 4},
		{"cohort_id": "source_cohort", "from": "fit", "to": "captured_current", "count": 4}]
	request.ui_metadata = "ignored"
	assert_eq(Prisoners.capture(f.repo, f.state, request), result)

func test_unpinned_named_people_use_stable_ids_and_remaining_slots() -> void:
	var f := _fixture()
	var s: GameState = f.state
	var request := _request()
	request.changes.clear()
	for name: String in ["zeta", "alpha"]:
		var person := Person.new()
		person.id = name
		person.category = "noble"
		s.characters[name] = person
		var id := name + "_cohort"
		s.military_cohorts[id] = s.military_cohorts.source_cohort.duplicate(true)
		s.military_cohorts[id].merge({"id": id, "initial": 1, "fit": 1, "wounded": 0,
			"person_id": name, "identity": "noble"}, true)
		s.military_rosters.source.cohort_ids.append(id)
		request.changes.append({"cohort_id": id, "from": "fit", "to": "captured_current", "count": 1})
	assert_false(Prisoners.capture(f.repo, s, request).has("error"))
	for batch: Dictionary in s.prisoner_batches.values():
		assert_eq(batch.holder_code, "u_a" if "alpha" in batch.named_ids else "u_b")
		assert_eq(batch.nobles, 1)
		assert_eq(batch.initial_count, 1)
