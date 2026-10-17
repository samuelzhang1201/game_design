extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")

func _state(phase := "camped") -> GameState:
	var s := GameState.new()
	s.regiments["u"] = {"camp_state": {"phase": phase, "idle_days": 0, "build_progress": 0,
		"pack_start_day": -1, "move_not_before_day": -1, "last_updated_day": -1, "site": {"x_m": 0, "y_m": 0}}}
	return s

func test_local_order_uses_one_full_day() -> void:
	var s := _state()
	CampSystem.request_departure(s, "u", 10, false)
	assert_false(CampSystem.can_march(s, "u", 10))
	assert_true(CampSystem.can_march(s, "u", 11))

func test_late_order_packs_next_day() -> void:
	var s := _state()
	CampSystem.request_departure(s, "u", 10, true)
	assert_false(CampSystem.can_march(s, "u", 11))
	assert_true(CampSystem.can_march(s, "u", 12))

func test_reissue_and_json_resume_keep_deadline() -> void:
	var s := SuiteData.campaign(SuiteData.repo(), 3)
	s.regiments["u"] = {"camp_state": {"phase": "camped", "idle_days": 0, "build_progress": 1000,
		"pack_start_day": -1, "move_not_before_day": -1, "last_updated_day": -1, "site": {"x_m": 0, "y_m": 0}}}
	CampSystem.request_departure(s, "u", 10, true)
	var deadline := int(s.regiments["u"]["camp_state"]["move_not_before_day"])
	CampSystem.request_departure(s, "u", 11, true)
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_eq(int(restored.regiments["u"]["camp_state"]["move_not_before_day"]), deadline)
	assert_true(CampSystem.can_march(restored, "u", deadline))

func test_building_is_not_immediately_camped() -> void:
	var s := _state("building")
	CampSystem.request_departure(s, "u", 10, false)
	assert_false(CampSystem.can_march(s, "u", 10))

func test_no_camp_has_no_departure_delay() -> void:
	var s := _state("none")
	CampSystem.request_departure(s, "u", 10, true)
	assert_true(CampSystem.can_march(s, "u", 10))

func test_camp_progress_is_once_per_day_and_combat_pauses_it() -> void:
	var repo: DataRepository = SuiteData.repo()
	repo.balance["army_camp_idle_days"] = 2.0
	repo.balance["army_camp_build_days"] = 2.0
	var s := SuiteData.campaign(repo, 3)
	s.regiments["u"] = {"x_m": 1, "y_m": 1, "order": ArmySystem.ORDER_GARRISON}
	CampSystem.finish_day(repo, s, 1)
	assert_eq(s.regiments["u"]["camp_state"]["idle_days"], 1)
	CampSystem.finish_day(repo, s, 1)
	assert_eq(s.regiments["u"]["camp_state"]["idle_days"], 1, "same day is idempotent")
	CampSystem.finish_day(repo, s, 2)
	assert_eq(s.regiments["u"]["camp_state"]["phase"], CampSystem.BUILDING)
	s.battles.append({"id": 1, "att": ["u"], "def": ["foe"]})
	CampSystem.finish_day(repo, s, 3)
	assert_eq(s.regiments["u"]["camp_state"]["build_progress"], 0, "combat does not clear or advance build")
	s.battles.clear()
	CampSystem.finish_day(repo, s, 4)
	assert_eq(s.regiments["u"]["camp_state"]["build_progress"], 500)
	CampSystem.finish_day(repo, s, 5)
	assert_eq(s.regiments["u"]["camp_state"]["phase"], CampSystem.CAMPED)
	assert_eq(CampSystem.defence_factor(repo, s, "u"), 1200)
	CampSystem.request_departure(s, "u", 6, true)
	s.battles.append({"id": 2, "att": ["u"], "def": ["foe"]})
	CampSystem.finish_day(repo, s, 7)
	assert_eq(s.regiments["u"]["camp_state"]["pack_start_day"], 7)
	assert_eq(s.regiments["u"]["camp_state"]["move_not_before_day"], 8)

func test_attack_preserves_pack_progress_and_reduced_defence() -> void:
	var repo: DataRepository = SuiteData.repo()
	var s := SuiteData.campaign(repo, 3)
	s.regiments["u"] = {"x_m": 10, "y_m": 20, "camp_state": {"phase": CampSystem.CAMPED,
		"idle_days": 2, "build_progress": 1000, "pack_start_day": -1,
		"move_not_before_day": -1, "last_updated_day": -1, "site": {"x_m": 10, "y_m": 20}}}
	CampSystem.request_departure(s, "u", 10, true)
	var start := int(s.regiments["u"]["camp_state"]["pack_start_day"])
	var move_day := int(s.regiments["u"]["camp_state"]["move_not_before_day"])
	s.battles.append({"id": 1, "att": ["foe"], "def": ["u"]})
	CampSystem.finish_day(repo, s, 11)
	assert_eq(s.regiments["u"]["camp_state"]["phase"], CampSystem.PACKING)
	assert_eq(s.regiments["u"]["camp_state"]["pack_start_day"], start)
	assert_eq(s.regiments["u"]["camp_state"]["move_not_before_day"], move_day)
	assert_eq(CampSystem.defence_factor(repo, s, "u"), 1100)
	assert_false(CampSystem.can_march(s, "u", 11))
	assert_true(CampSystem.can_march(s, "u", 12))

func test_camp_loss_reduction_only_changes_existing_transport_loss() -> void:
	var repo: DataRepository = SuiteData.repo()
	repo.balance["army_camp_supply_loss_reduction_permille"] = 100.0
	var s := SuiteData.campaign(repo, 3)
	s.regiments["u"] = {"x_m": 10, "y_m": 20, "camp_state": {"phase": CampSystem.CAMPED,
		"site": {"x_m": 10, "y_m": 20}}}
	var reduced := CampSystem.reduced_supply_loss(repo, s, "u", 200)
	assert_eq(reduced, 100)
	assert_eq(90 + int(10 * (1000 - reduced) / 1000) - 10, 89)
	assert_eq(CampSystem.reduced_supply_loss(repo, s, "missing", 200), 200)

func test_player_and_foe_camp_states_advance_in_the_same_sorted_pass() -> void:
	var repo: DataRepository = SuiteData.repo()
	var s := GameState.new()
	for code: String in ["u", "f"]:
		var table: Dictionary = s.regiments if code == "u" else s.foes
		table[code] = {"x_m": 1, "y_m": 1, "order": ArmySystem.ORDER_GARRISON}
	CampSystem.finish_day(repo, s, 1)
	for code: String in ["u", "f"]:
		var table: Dictionary = s.regiments if code == "u" else s.foes
		assert_true(table[code].has("camp_state"))
		assert_eq(table[code]["camp_state"]["idle_days"], 1)

func test_real_march_waits_at_camp_then_moves_after_deadline() -> void:
	var repo: DataRepository = SuiteData.repo()
	var s := SuiteData.campaign(repo, 3)
	var code := ""
	for c: String in s.regiments:
		if not ArmySystem.is_naval(repo, s, c):
			code = c
			break
	assert_ne(code, "")
	var e: Dictionary = s.regiments[code]
	e["camp_state"] = {"phase": CampSystem.CAMPED, "idle_days": 2, "build_progress": 1000,
		"pack_start_day": -1, "move_not_before_day": -1, "last_updated_day": -1,
		"site": {"x_m": int(e["x_m"]), "y_m": int(e["y_m"])}}
	var origin := Vector2i(int(e["x_m"]), int(e["y_m"]))
	var dest := origin + Vector2i(3000, 0)
	ArmySystem.set_march_m(repo, s, code, dest)
	ArmySystem.march_day(repo, s)
	assert_eq(Vector2i(int(e["x_m"]), int(e["y_m"])), origin)
	s.day += 1
	ArmySystem.march_day(repo, s)
	assert_ne(Vector2i(int(e["x_m"]), int(e["y_m"])), origin)

func test_battle_keeps_due_departure_packing_and_saved() -> void:
	var repo: DataRepository = SuiteData.repo()
	var s := SuiteData.campaign(repo, 3)
	var code := ""
	for c: String in s.regiments:
		if not ArmySystem.is_naval(repo, s, c):
			code = c
			break
	var e: Dictionary = s.regiments[code]
	var origin := Vector2i(int(e["x_m"]), int(e["y_m"]))
	e["camp_state"] = {"phase": CampSystem.CAMPED, "idle_days": 2, "build_progress": 1000,
		"pack_start_day": -1, "move_not_before_day": -1, "last_updated_day": -1,
		"site": {"x_m": origin.x, "y_m": origin.y}}
	ArmySystem.set_march_m(repo, s, code, origin + Vector2i(3000, 0))
	s.day += 1
	s.battles.append({"id": 1, "att": [code], "def": ["foe"]})
	ArmySystem.march_day(repo, s)
	assert_eq(Vector2i(int(e["x_m"]), int(e["y_m"])), origin)
	assert_eq(e["camp_state"]["phase"], CampSystem.PACKING)
	assert_true(e.has("departure"))
