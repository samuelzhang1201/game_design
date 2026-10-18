extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
var repo: DataRepository
var state: GameState
var battle: Dictionary
var player: String
var enemy: String

func before_each() -> void:
	repo = SuiteData.repo()
	state = GameState.new()
	state.rng = Rng.new(53)
	player = repo.resolve_realm("player_realm")
	enemy = repo.resolve_realm("raider_realm")
	for code: String in ["home", "away"]:
		state.army_roster[code] = {"regiment_code": code, "label": code, "kingdom_code": player if code == "home" else enemy, "is_naval": "0"}
		state.regiments[code] = {"x_m": 1000000, "y_m": 1000000, "supplies": 100}
		state.military_rosters[code] = {"cohort_ids": [code], "commander_id": ""}
		state.military_cohorts[code] = {"id": code, "unit_code": code, "identity": "commoner", "stage": "active",
			"fit": 600, "wounded": 0, "dead": 0, "captured_current": 0, "released": 0, "initial": 600,
			"source_province": String(repo.provinces.keys()[0]), "source_population_field": "rural_population"}
	state.foes["away"] = state.regiments["away"]
	state.regiments.erase("away")
	state.king_state = {"x_m": 0, "y_m": 0}
	battle = {"id": 53, "att": ["home"], "def": ["away"], "start_day": 0, "rounds": 2, "town": "", "place_x_m": 1000000, "place_y_m": 1000000}
	state.battles.append(battle)
	BattleReport.enroll(state, battle, "home", "att")
	BattleReport.enroll(state, battle, "away", "def")

func _capture() -> void:
	assert_false(PrisonerSystem.capture(repo, state, {"capture_id": "p53", "battle_id": 53, "participants": {"home": 1},
		"reason": "Accepted surrender", "changes": [{"cohort_id": "away", "from": "fit", "to": "captured_current", "count": 60}]}).has("error"))

func test_details_freeze_and_preserve_600_accounting() -> void:
	_capture()
	state.military_cohorts.home.fit = 490
	state.military_cohorts.home.wounded = 70
	state.military_cohorts.home.dead = 40
	# The other sixty are captured by the enemy.
	assert_false(PrisonerSystem.capture(repo, state, {"capture_id": "p53-home", "battle_id": 53, "participants": {"away": 1},
		"reason": "Intercepted survivors", "changes": [{"cohort_id": "home", "from": "fit", "to": "captured_current", "count": 60}]}).has("error"))
	assert_eq(int(state.military_cohorts.home.fit), 430, "capture transfers the remaining sixty from fit personnel")
	var record := BattleReport.snapshot(repo, state, 53)
	for key: String in ["place", "duration_days", "participants", "formations", "orders", "events", "equipment", "supplies", "family_changes", "outcome"]:
		assert_has(record, key)
	assert_eq(record.personnel.att.participants, 600)
	assert_eq(record.personnel.att.fit + record.personnel.att.wounded + record.personnel.att.dead + record.personnel.att.captured, 600)
	var frozen := JSON.stringify(record)
	var batch: Dictionary = state.prisoner_batches.values()[0]
	var selection := {"batch_id": batch.id, "count": 10, "wounded_count": 0, "named_ids": []}
	assert_false(PrisonerSystem.release(repo, state, "p53-release", [selection], "Civilian release").has("error"))
	assert_eq(JSON.stringify(BattleReport.snapshot(repo, state, 53)), frozen)

func test_result_is_visible_on_delivery() -> void:
	_capture()
	BattleReport.snapshot(repo, state, 53)
	var payload := MissiveWriter.king_report_payload(repo, state, [{"kind": "end", "rounds": 2, "battle_id": 53, "why": "emptied", "winner": "att", "att": ["home"], "def": [], "town": "", "place_x_m": 1000000, "place_y_m": 1000000}])
	payload.merge({"battle_id": 53, "day": state.absolute_day()})
	var before := BattlePresentation.snapshot(repo, state, player)
	assert_eq(before.get("detailed_reports", []).size(), 0)
	assert_eq(before.get("prisoners", {}).get("current_count", -1), 0, "Remote custody must not reveal the result")
	BattleEvents.receive_report(state, payload)
	var after := BattlePresentation.snapshot(repo, state, player)
	assert_eq(after.get("detailed_reports", []).size(), 1)
	if after.get("detailed_reports", []).is_empty(): return
	var detail: Dictionary = after.detailed_reports[0]
	assert_eq(detail.personnel.own.participants, 600)
	assert_false(detail.personnel.enemy.has("fit"), "No enemy exact survivors")
	assert_true(detail.personnel.enemy.dead is Dictionary)
	assert_eq(after.prisoners.current_count, 60)
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	assert_eq(BattlePresentation.snapshot(repo, restored, player).detailed_reports, after.detailed_reports)
	state.prisoner_batches.values()[0].holder_code = "away"
	var stale := BattlePresentation.snapshot(repo, state, player)
	assert_eq(stale.prisoners.batches[0].holder_code, "home", "An unreported transfer does not leak")
	state.king_state.x_m = 1000000
	state.king_state.y_m = 1000000
	assert_eq(BattlePresentation.snapshot(repo, state, player).prisoners.batches[0].holder_code, "away", "Local observation names the actual holder")

func test_received_custody_tracks_actual_fulfilled_release_once() -> void:
	_capture()
	BattleReport.snapshot(repo, state, 53)
	BattleEvents.receive_report(state, {"battle_id": 53, "day": state.absolute_day(), "custody": BattlePresentation.custody_observations(repo, state, player, 53)})
	var batch: Dictionary = state.prisoner_batches.values()[0]
	var proposal := {"id": "p53-release", "kind": "release", "money": 0, "batches": [{"batch_id": batch.id, "count": 10, "wounded_count": 0}],
		"parties": {"proposer": player, "payer": ""}, "terms": {}, "reason": "Ten return to civilian life"}
	assert_false(PrisonerDisposition.propose(repo, state, proposal).has("error"))
	assert_eq(BattlePresentation.prisoner_view(repo, state, player).current_count, 60)
	var result := PrisonerDisposition.settle(repo, state, "p53-release")
	assert_false(result.has("error"), str(result))
	var view := BattlePresentation.prisoner_view(repo, state, player)
	assert_eq(view.current_count, 50)
	assert_eq(view.historical_captured, 60)
	assert_eq(view.proposals[0].status, "fulfilled")
	assert_eq(PrisonerDisposition.settle(repo, state, "p53-release"), result)
	assert_eq(BattlePresentation.prisoner_view(repo, state, player), view)
	assert_eq(state.battle_records["53"].personnel.def.captured, 60)

func test_enemy_precision_is_an_estimate_and_snapshot_copies_are_detached() -> void:
	state.military_cohorts.away.fit = 477
	state.military_cohorts.away.dead = 123
	repo.balance.battle_foe_estimate_quality = 1000
	repo.intel_facts.foe_losses.round_to = 10
	var record := BattleReport.snapshot(repo, state, 53)
	var detail := BattleReport.for_realm(repo, record, player)
	assert_eq(detail.personnel.enemy.dead, {"lo": 110, "hi": 140})
	assert_false(detail.personnel.enemy.has("participants"))
	assert_eq(detail.participants.size(), 1)
	record.personnel.att.fit = -1
	assert_eq(BattleReport.snapshot(repo, state, 53).personnel.att.fit, 600)

func test_remote_live_figures_are_private_and_prisoners_have_no_map_models() -> void:
	_capture()
	assert_true(BattlePresentation.awaits_report(repo, state, "home"))
	assert_eq(BattlePresentation.known_unit(repo, state, "home"), {})
	assert_eq(BattlePresentation.map_snapshot(repo, state, player).map_units.home.get("prisoners", {}), {})
	state.king_state.x_m = 1000000
	state.king_state.y_m = 1000000
	assert_false(BattlePresentation.awaits_report(repo, state, "home"))
	assert_false(BattlePresentation.map_snapshot(repo, state, player).map_units.home.has("prisoners"))
	assert_eq(BattlePresentation.prisoner_view(repo, state, player).current_count, 60)

func test_called_off_battle_freezes_and_can_be_delivered() -> void:
	var terminal := BattleSystem.call_off(state, 53, repo)
	assert_eq(terminal.kind, "end")
	assert_eq(state.battles.size(), 0)
	assert_eq(state.battle_records["53"].outcome.why, "called_off")
	assert_eq(SiegeSystem.news([terminal]).size(), 1)
	var payload := MissiveWriter.king_report_payload(repo, state, [terminal])
	assert_eq(payload.details.battle_id, 53)
	assert_eq(payload.details.outcome.why, "called_off")

func test_departed_unit_supplies_stay_at_departure_when_battle_ends_later() -> void:
	state.regiments.home.supplies = 80
	BattleReport.leave(state, battle, "home")
	state.regiments.home.supplies = 20
	var record := BattleReport.snapshot(repo, state, 53)
	assert_eq(record.supplies[0], {"unit_code": "home", "before": 100, "after": 80})

func test_rejoining_unit_supplies_follow_its_returned_service() -> void:
	state.regiments.home.supplies = 80
	BattleReport.leave(state, battle, "home")
	state.regiments.home.supplies = 20
	BattleReport.enroll(state, battle, "home", "att")
	state.regiments.home.supplies = 15
	BattleReport.leave(state, battle, "home")
	state.regiments.home.supplies = 5
	assert_eq(BattleReport.snapshot(repo, state, 53).supplies[0], {"unit_code": "home", "before": 100, "after": 15})

func _later_holder_defeat(controller_realm: String) -> Dictionary:
	_capture()
	BattleReport.snapshot(repo, state, 53)
	var first := _terminal_payload(53)
	BattleEvents.receive_report(state, first)
	var original: String = JSON.stringify(state.battle_records["53"])
	assert_eq(BattlePresentation.prisoner_view(repo, state, player).current_count, 60)
	state.day += 1
	state.army_roster.away.kingdom_code = controller_realm
	var later := {"id": 54, "att": ["home"], "def": ["away"], "start_day": state.absolute_day(), "rounds": 0,
		"town": "", "place_x_m": 1000000, "place_y_m": 1000000}
	state.battles = [later]
	BattleReport.enroll(state, later, "home", "att")
	BattleReport.enroll(state, later, "away", "def")
	state.military_cohorts.home.dead = 600
	state.military_cohorts.home.fit = 0
	assert_false(BattleSystem._settle_defeated_holders(repo, state, later).has("error"))
	BattleReport.snapshot(repo, state, 54)
	var payload := _terminal_payload(54)
	assert_eq(BattlePresentation.prisoner_view(repo, state, player).batches[0].holder_code, "home", "Remote defeat remains unknown until delivery")
	assert_eq(payload.custody.size(), 1, "B must report its change to A's captive batch")
	if payload.custody.is_empty(): return {}
	assert_eq(payload.custody[0].battle_id, 53, "Capture attribution stays with A")
	assert_eq(payload.custody[0].origin_label, repo.realm_label(enemy))
	BattleEvents.receive_report(state, payload)
	assert_eq(JSON.stringify(state.battle_records["53"]), original)
	return payload

func _terminal_payload(id: int) -> Dictionary:
	var payload := MissiveWriter.king_report_payload(repo, state, [{"kind": "end", "rounds": 0, "battle_id": id,
		"why": "emptied", "winner": "def", "att": [], "def": ["away"], "town": "", "place_x_m": 1000000, "place_y_m": 1000000}])
	payload.merge({"battle_id": id, "day": state.absolute_day()})
	return payload

func test_later_remote_holder_defeat_delivers_release_of_earlier_captives() -> void:
	var payload := _later_holder_defeat(enemy)
	if payload.is_empty(): return
	assert_eq(payload.custody[0].count, 0)
	assert_eq(payload.custody[0].released_count, 60)
	assert_eq(BattlePresentation.prisoner_view(repo, state, player).current_count, 0)
	assert_eq(BattlePresentation.prisoner_view(repo, state, player).historical_captured, 60)

func test_later_remote_holder_defeat_delivers_transfer_and_freezes_its_observation() -> void:
	var third := ""
	for realm: String in repo.kingdoms:
		if realm != player and realm != enemy:
			third = realm
			break
	assert_ne(third, "")
	var payload := _later_holder_defeat(third)
	if payload.is_empty(): return
	assert_eq(payload.custody[0].holder_code, "away")
	assert_eq(payload.custody[0].holder_realm_label, repo.realm_label(third))
	assert_eq(BattlePresentation.prisoner_view(repo, state, player).batches[0].holder_code, "away")
	var frozen: Array = payload.custody.duplicate(true)
	state.prisoner_batches.values()[0].holder_code = "home"
	state.day += 1
	assert_eq(_terminal_payload(54).custody, frozen, "B's terminal custody cannot reread a later transfer")
	assert_eq(BattlePresentation.prisoner_view(repo, state, player).batches[0].holder_code, "away")

func test_remote_fulfillment_is_hidden_until_its_receipt_arrives() -> void:
	_capture()
	BattleReport.snapshot(repo, state, 53)
	var payload := {"details":BattleReport.for_realm(repo, state.battle_records["53"], player),
		"custody":BattlePresentation.custody_observations(repo, state, player, 53)}
	payload.merge({"battle_id":53,"day":state.absolute_day()})
	BattleEvents.receive_report(state, payload)
	var batch: Dictionary = state.prisoner_batches.values()[0]
	var request := {"id":"receipt-gate","kind":"release","money":0,
		"batches":[{"batch_id":batch.id,"count":10,"wounded_count":0}],
		"parties":{"proposer":player,"payer":""},"terms":{},"reason":"Agreed civilian release"}
	assert_false(PrisonerDisposition.propose(repo, state, request).has("error"))
	var result := PrisonerDisposition.settle(repo, state, request.id)
	assert_false(result.has("error"))
	state.prisoner_proposals[request.id]["communications"] = {"visible_status":"fulfilling","received_result":{},"offers":{}}
	var view := BattlePresentation.snapshot(repo, state, player)
	assert_eq(view.prisoners.current_count, 60, "Remote execution has not yet been reported")
	assert_eq(view.prisoners.proposals[0].status, "fulfilling")
	assert_eq(view.prisoners.proposals[0].result, {})
	assert_eq(view.detailed_reports[0].settlements, [])
	state.prisoner_proposals[request.id].communications.visible_status = "fulfilled"
	state.prisoner_proposals[request.id].communications.received_result = result
	view = BattlePresentation.snapshot(repo, state, player)
	assert_eq(view.prisoners.current_count, 50)
	assert_eq(view.detailed_reports[0].settlements.size(), 1)
