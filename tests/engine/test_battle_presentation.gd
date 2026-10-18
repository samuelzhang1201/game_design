extends GutTest

const SuiteData := preload("res://tests/suite_data.gd")
const Scenario := preload("res://tests/fixtures/battle_scenario.gd")
var repo: DataRepository
var state: GameState
var presentation: GDScript

func before_each() -> void:
	repo = SuiteData.no_clearance(SuiteData.open_country(SuiteData.repo()))
	state = Scenario.contact(repo, 10)
	BattleSystem.detect_contacts(repo, state)
	presentation = load("res://scripts/engine/battle_presentation.gd") if ResourceLoader.exists("res://scripts/engine/battle_presentation.gd") else null

func _view() -> Dictionary:
	assert_not_null(presentation, "The informed projection must exist")
	return {} if presentation == null else presentation.snapshot(repo, state, repo.resolve_realm("player_realm"))

func test_hidden_enemy_changes_leave_projection_identical() -> void:
	var code := String(state.battles[0]["att"][0])
	state.sightings[code] = {"kind": "unit", "code": code, "x_m": 100, "y_m": 200, "day": 8, "source": "spy", "men": 500}
	var before := _view()
	state.foes[code]["x_m"] = 900000
	state.foes[code]["morale"] = 1
	state.foes[code]["dead"] = 999999
	state.foes[code]["order"] = "secret"
	state.battles[0]["pending_round"] = {"roll": 53, "secret": "hidden"}
	assert_eq(_view(), before)
	state.foes.erase(code)
	assert_eq(_view(), before, "A hidden disappearance must not erase received knowledge")

func test_projection_has_estimates_and_no_engine_dictionaries() -> void:
	state.sightings["enemy"] = {"kind": "unit", "code": "enemy", "x_m": 100, "y_m": 200, "day": 8, "source": "spy", "men": 500, "secret": 123}
	var view := _view()
	if view.is_empty(): return
	assert_eq(view["enemies"][0]["estimate"], 500)
	assert_eq(view["enemies"][0]["observed_day"], 8)
	assert_false(view["enemies"][0].has("secret"))
	for row: Dictionary in view["battles"]:
		for key: String in ["att", "def", "pending_round", "received_laws", "rng", "evidence"]:
			assert_false(row.has(key))

func test_projection_is_detached_and_does_not_mutate_state_or_rng() -> void:
	var hash := SaveLoad.state_hash(state)
	var view := _view()
	if view.is_empty(): return
	view["battles"].clear()
	assert_eq(SaveLoad.state_hash(state), hash)
	assert_eq(_view()["battles"].size(), 1)

func test_other_realm_receives_no_crown_commands() -> void:
	if _view().is_empty(): return
	assert_eq(presentation.snapshot(repo, state, repo.resolve_realm("raider_realm")), {"battles": [], "decision": {}, "enemies": [], "reports": [], "detailed_reports": [], "prisoners": {}})

func test_orders_explain_reservation_cooldown_and_law() -> void:
	var battle: Dictionary = state.battles[0]
	battle["inspire_cooldown"] = {"def": state.absolute_day() + 3}
	var view := _view()
	if view.is_empty(): return
	var orders: Array = view["battles"][0]["orders"]
	assert_eq(orders.size(), 5)
	var inspire: Dictionary = orders.filter(func(o: Dictionary) -> bool: return o["id"] == "inspire")[0]
	assert_string_contains(String(inspire["reason"]), "cooldown")
	assert_eq(inspire["cooldown_days"], 3)
	assert_true(inspire.has("courier_gold"))
	assert_true(inspire.has("effects_text"))

func test_reports_only_become_visible_on_receipt_and_never_expose_payload_state() -> void:
	state.battle_events["private"] = {"token":"private", "event_id":"ev_31", "battle_id":1, "day":8, "selected":"rally", "received_day":-1, "authority":"commander", "evidence":{"secret":999}, "receipt":{"reason":"The line rallied."}}
	var view := _view()
	if view.is_empty(): return
	assert_eq(view["reports"], [])
	state.king_state["battle_reports"] = [{"battle_id":1,"day":8,"received_day":10,"title":"A report", "secret":55,"facts":[MissiveLog.words("round", "Result", "Our line held.")]}]
	view = _view()
	assert_eq(view["reports"].size(), 1)
	assert_string_contains(view["reports"][0]["text"], "Our line held")
	assert_false(view["reports"][0].has("secret"))

func test_map_projection_obeys_our_delivered_law_and_omits_hidden_armies() -> void:
	if _view().is_empty(): return
	var battle: Dictionary = state.battles[0]
	var code := String(battle["def"][0])
	var enemy := String(battle["att"][0])
	var map_view: Dictionary = presentation.map_snapshot(repo, state, repo.resolve_realm("player_realm"))
	assert_true(map_view["map_units"].has(code))
	assert_false(map_view["map_units"].has(enemy))
	assert_eq(map_view["battle_signals"].filter(func(s: Dictionary) -> bool: return s["kind"] == "refusal"), [])
	battle["parley"]["agreed"].erase("surrender")
	LawSystem.impose(repo, state, "quarter", "refuse")
	map_view = presentation.map_snapshot(repo, state, repo.resolve_realm("player_realm"))
	assert_eq(map_view["battle_signals"].filter(func(s: Dictionary) -> bool: return s["kind"] == "refusal").size(), 1)
	var before := map_view.duplicate(true)
	state.foes[enemy]["order"] = "secret"
	state.foes[enemy]["morale"] = 1
	assert_eq(presentation.map_snapshot(repo, state, repo.resolve_realm("player_realm")), before)

func test_remote_missing_reading_is_unknown_and_received_reading_is_frozen() -> void:
	state.king_state = {"x_m": 10000000, "y_m": 10000000}
	var code := String(state.battles[0].def[0])
	var unit: Dictionary = _view().battles[0].units[0]
	assert_false(unit.get("known", true))
	assert_false(unit.has("fit"), "Unknown is not a fabricated zero")
	state.king_state.battle_reports = [{"unit_readings": {code: {"fit": 321, "wounded": 12, "morale": 70, "supplies": 89, "day": 8}}}]
	unit = _view().battles[0].units[0]
	assert_true(unit.get("known", false))
	assert_eq(unit.fit, 321)
	assert_eq(unit.observed_day, 8)

func test_later_received_settlements_and_fulfilled_receipts_join_by_battle_without_rewriting_details() -> void:
	var realm := repo.resolve_realm("player_realm")
	var frozen := {"battle_id": 7, "personnel": {"own": {"captured": 60, "released": 0}}, "prisoners": [{"id": "batch"}]}
	var spoils := {"battle_id": 7, "kind": "spoils", "strategic": 20, "reason": "Stores arrived"}
	state.king_state.battle_reports = [{"battle_id": 7, "details": frozen, "received_day": 8},
		{"battle_id": 7, "settlements": [spoils], "received_day": 9},
		{"battle_id": 7, "settlements": [spoils], "received_day": 9}]
	state.prisoner_proposals = {"paid": {"consents": {}, "status": "fulfilled", "request": {"id":"paid", "kind": "ransom", "reason":"Agreed ransom"}, "frozen": {"required_parties": [realm]},
		"result": {"id": "paid", "status": "fulfilled", "released": 10, "reason": "Ransom paid", "civilians": [{"batch_id": "batch", "count": 10}]}},
		"waiting": {"consents": {}, "request": {"id":"waiting", "kind": "ransom", "reason":"Pending ransom"}, "status": "accepted", "frozen": {"required_parties": [realm]}, "result": {"reason": "Not fulfilled"}}}
	var before := SaveLoad.state_hash(state)
	var reports: Array = _view().detailed_reports
	assert_eq(reports.size(), 1)
	assert_eq(reports[0].settlements.size(), 2)
	assert_eq(reports[0].personnel, frozen.personnel)
	assert_eq(reports[0].settlements[0], spoils)
	assert_eq(reports[0].settlements[1].released, 10)
	reports[0].settlements[0].strategic = 0
	assert_eq(SaveLoad.state_hash(state), before)
