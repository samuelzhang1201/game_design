extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Personnel := preload("res://tests/engine/personnel_helpers.gd")

func _fixture(survivor: int) -> Dictionary:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 9447)
	var mine := state.regiments.keys()
	mine.sort()
	var foes := state.foes.keys()
	foes.sort()
	var p1 := String(mine[0])
	var p2 := String(mine[1])
	var f1 := String(foes[0])
	var f2 := String(foes[1])
	var at := {p1: Vector2i(0, 0), f1: Vector2i(0, 3000), p2: Vector2i(5000, 20000), f2: Vector2i(80, 0)}
	for code: String in at:
		var e := BattleSystem._stored(state, code)
		e.x_m = at[code].x
		e.y_m = at[code].y
		assert_false(Personnel.replace(repo, state, code, 40).has("error"))
		var cohort := String(state.military_rosters[code].cohort_ids.back())
		state.military_cohorts[cohort].identity = "noble"
		if ArmySystem.is_foe(state, code):
			e.received_laws["ransom"] = {"value": "execute", "decree_id": 99}
		else:
			state.law_in_force["unit:" + code] = {"ransom": {"value": "execute", "decree_id": 99}}
	state.tick = 1
	state.day = 7
	var b1 := {"id": 1, "att": [f1], "def": [p1], "town": "", "rounds": 1, "start_day": 5, "place_x_m": 0, "place_y_m": 0, "actions": {},
		"parley": {"agreed": {"noble_ransom": {"policy": "allow", "until_day": state.absolute_day()}},
			"parties": {"att": [f1], "def": [p1]}}}
	var b2 := {"id": 2, "att": [p2], "def": [f2], "town": "T" if survivor == 2 else "", "rounds": 3, "start_day": 3, "place_x_m": 80, "place_y_m": 0, "actions": {},
		"parley": {"agreed": {}, "parties": {"att": [p2], "def": [f2]}}}
	state.battles = [b1, b2]
	for b: Dictionary in state.battles:
		BattleFormation.ensure(b)
		BattleGroups.refresh(repo, state, b)
	BattleMerge.day(repo, state)
	assert_eq(state.battles.size(), 1)
	assert_eq(int(state.battles[0].id), survivor)
	state.battles[0].town = ""
	return {"repo": repo, "state": state, "p1": p1, "p2": p2, "f1": f1, "f2": f2}

func _cohort(f: Dictionary, source: String) -> String:
	return String(f.state.military_rosters[source].cohort_ids.back())

func _request(f: Dictionary, holder: String, source: String, id := "scope") -> Dictionary:
	return {"capture_id": id, "battle_id": int(f.state.battles[0].id), "participants": {holder: 1},
		"reason": "Noble captured after merged contact", "changes": [
			{"cohort_id": _cohort(f, source), "from": "fit", "to": "captured_current", "count": 1}]}

func _capture(f: Dictionary, holder: String, source: String, id := "scope") -> Dictionary:
	var result := PrisonerSystem.capture(f.repo, f.state, _request(f, holder, source, id))
	assert_false(result.has("error"), str(result))
	return f.state.prisoner_batches[result.batch_ids[0]]

func test_capture_protection_follows_each_original_pair_in_both_merge_orientations() -> void:
	for survivor: int in [1, 2]:
		for pair: Array in [["p1", "f1", true], ["f1", "p1", true], ["p1", "f2", false], ["p2", "f1", false], ["p2", "f2", false]]:
			var f := _fixture(survivor)
			var batch := _capture(f, f[pair[0]], f[pair[1]])
			assert_eq(batch.ransom_protected, pair[2], str([survivor, pair]))
			var refusal := LawSystem.prisoner_refusal(f.repo, f.state, batch, "ransom")
			assert_eq(refusal == "", pair[2], "received execution law yields only to that pair's agreement")

func test_unfrozen_disposition_checks_actual_holder_and_source_in_live_and_archived_battles() -> void:
	for survivor: int in [1, 2]:
		for archived: bool in [false, true]:
			var f := _fixture(survivor)
			if archived:
				f.state.battle_records[str(survivor)] = f.state.battles[0].duplicate(true)
				f.state.battles.clear()
			for pair: Array in [["p1", "f1", true], ["f1", "p1", true], ["p1", "f2", false], ["p2", "f1", false], ["p2", "f2", false]]:
				var batch := {"holder_code": f[pair[0]], "source_cohort": _cohort(f, f[pair[1]]),
					"battle_id": 1, "nobles": 1, "commoners": 0}
				assert_eq(LawSystem.prisoner_refusal(f.repo, f.state, batch, "ransom") == "", pair[2], str([survivor, archived, pair]))
				batch.captor_code = f.p1
				if pair[0] == "p2":
					assert_ne(LawSystem.prisoner_refusal(f.repo, f.state, batch, "ransom"), "", "original captor cannot grant a new holder an unfrozen obligation")

func test_expiry_is_inclusive_and_capture_freezes_protection_through_json_and_retry() -> void:
	for survivor: int in [1, 2]:
		var f := _fixture(survivor)
		var request := _request(f, f.p1, f.f1)
		var batch := _capture(f, f.p1, f.f1)
		assert_true(batch.ransom_protected, "the agreement still holds on its deadline")
		f.state.day += 1
		var expired := _capture(f, f.p1, f.f1, "expired")
		assert_false(expired.ransom_protected, "a later capture gains no expired protection")
		assert_ne(LawSystem.prisoner_refusal(f.repo, f.state, expired, "ransom"), "")
		assert_false(PrisonerSystem.holder_defeated(f.repo, f.state, f.p1, [f.p2], "scope_transfer").has("error"))
		assert_eq(f.state.prisoner_batches[batch.id].holder_code, f.p2)
		assert_false(f.state.prisoner_batches[expired.id].ransom_protected, "transferring custody cannot create protection")
		f.state.battles.clear()
		f.state = GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())), false)
		var before: Dictionary = f.state.to_dict()
		assert_eq(PrisonerSystem.capture(f.repo, f.state, request).batch_ids, [batch.id])
		assert_eq(f.state.to_dict(), before, "saved receipt replays without another personnel move")
		assert_eq(LawSystem.prisoner_refusal(f.repo, f.state, f.state.prisoner_batches[batch.id], "ransom"), "", "frozen protection outlives expiry and battle removal")

func test_named_custody_uses_its_assigned_holder_instead_of_another_receiver() -> void:
	for survivor: int in [1, 2]:
		var f := _fixture(survivor)
		var person := Character.new()
		person.id = "scope_noble"
		person.category = "noble"
		person.kingdom = ArmySystem.realm_of(f.repo, f.f1, f.state)
		f.state.characters[person.id] = person
		var cohort: Dictionary = f.state.military_cohorts[_cohort(f, f.f1)]
		cohort.person_id = person.id
		cohort.initial = 1
		cohort.fit = 1
		var request := _request(f, f.p1, f.f1)
		request.participants[f.p2] = 1
		request.named_holders = {person.id: f.p2}
		var result := PrisonerSystem.capture(f.repo, f.state, request)
		assert_false(result.has("error"), str(result))
		var batch: Dictionary = f.state.prisoner_batches[result.batch_ids[0]]
		assert_eq(batch.named_ids, [person.id])
		assert_eq(batch.holder_code, f.p2)
		assert_false(batch.ransom_protected, "a participating signatory cannot protect another holder's named captive")
		assert_ne(LawSystem.prisoner_refusal(f.repo, f.state, batch, "ransom"), "")

func test_frozen_original_pair_can_negotiate_and_settle_after_battle_removal() -> void:
	var f := _fixture(2)
	var batch := _capture(f, f.p1, f.f1)
	var unrelated := _capture(f, f.p2, f.f1, "unrelated")
	f.state.battles.clear()
	f.state.day += 1
	f.state = GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())), false)
	var payer := String(batch.origin_realm)
	f.state.world["economy.kingdoms.%s.treasury" % payer] = 500
	var proposal := {"id": "scope_ransom", "kind": "ransom", "batches": [{"batch_id": batch.id, "count": 1}],
		"money": 10, "parties": {"proposer": f.repo.resolve_realm("player_realm"), "payer": payer},
		"reason": "Original bilateral ransom obligation"}
	var invalid := proposal.duplicate(true)
	invalid.id = "unrelated_ransom"
	invalid.batches = [{"batch_id": unrelated.id, "count": 1}]
	var before: Dictionary = f.state.to_dict()
	assert_true(PrisonerDisposition.propose(f.repo, f.state, invalid).has("error"))
	assert_eq(f.state.to_dict(), before)
	var offered := PrisonerDisposition.propose(f.repo, f.state, proposal)
	assert_false(offered.has("error"), str(offered))
	assert_false(PrisonerDisposition.respond(f.repo, f.state, proposal.id, payer, true).has("error"))
	var result := PrisonerDisposition.settle(f.repo, f.state, proposal.id)
	assert_eq(result.get("released"), 1, str(result))
	assert_eq(f.state.prisoner_batches[batch.id].disposition, "released")
	assert_eq(f.state.prisoner_batches[unrelated.id].disposition, "held")
	f.state = GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())), false)
	before = f.state.to_dict()
	assert_eq(PrisonerDisposition.settle(f.repo, f.state, proposal.id), result)
	assert_eq(f.state.to_dict(), before)

func test_missing_source_identity_does_not_grant_an_unfrozen_bilateral_right() -> void:
	var f := _fixture(1)
	var batch := {"holder_code": f.p1, "battle_id": 1, "nobles": 1, "commoners": 0}
	assert_ne(LawSystem.prisoner_refusal(f.repo, f.state, batch, "ransom"), "")
