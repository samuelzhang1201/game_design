extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const BattleScenario := preload("res://tests/fixtures/battle_scenario.gd")
## The foe / AI-host / battle state in the save (spec
## 2026-10-07-enemy-ai-and-battle-design §2, §4, §7): a filled state round-trips
## item for item, holds no float anywhere (invariant 2: whole metres, whole
## numbers), serializes to the same text twice, and a save written before the
## keys existed loads with them empty.

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()


## A state with a foe, an AI host and a battle, every value a whole number,
## string, bool, array or dictionary of them.
func _filled() -> GameState:
	var s := SuiteData.campaign(repo, 11)
	var code := String(EnemyAi.host_units(repo, null, repo.raid_hosts[0])[0])
	s.foes[code] = {"morale": 80, "wounded": 3, "dead": 1, "supplies": 40, "x_m": 5100,
		"y_m": -620, "order": "march", "dest_x_m": 7000, "dest_y_m": 8800, "stance": "steady",
		"host": "raid_main", "wounded_arms": {"infantry": 2, "archer": 1}}
	s.ai_hosts["raid_main"] = {"mode": "ADVANCE", "role": "main", "target": "burg_3",
		"regiments": [code], "plunder": 12, "assault": 0, "next_think": 17, "sieged_days": 0}
	s.battles.append({"id": 1, "x_m": 5100, "y_m": -620, "start_day": 16, "rounds": 2,
		"attackers": [code], "defenders": ["player_reg"], "stance": {"player_reg": "hold"},
		"log": [{"round": 1, "eff": 640, "lines": ["The raiders press the ford."]}],
		"decided": false, "tier": ""})
	s.foe_next_id = 4
	return s


func _floats_in(v: Variant, path: String, out: Array) -> void:
	if typeof(v) == TYPE_FLOAT:
		out.append(path)
	elif v is Dictionary:
		for k in v:
			_floats_in(v[k], path + "/" + str(k), out)
	elif v is Array:
		for i in (v as Array).size():
			_floats_in(v[i], path + "[%d]" % i, out)


## An encoded float is the string "f" + 16 hex digits (GameState._float_to_hex);
## none may appear among the encoded keys, since none was put in.
func _encoded_floats_in(v: Variant, path: String, out: Array) -> void:
	if v is String and GameState._is_encoded_float(v):
		out.append(path)
	elif v is Dictionary:
		for k in v:
			_encoded_floats_in(v[k], path + "/" + str(k), out)
	elif v is Array:
		for i in (v as Array).size():
			_encoded_floats_in(v[i], path + "[%d]" % i, out)


func test_foes_ai_hosts_battles_round_trip() -> void:
	var s := _filled()
	var back := GameState.from_dict(s.to_dict())
	assert_eq(back.foes, s.foes, "foes item for item")
	assert_eq(back.ai_hosts, s.ai_hosts, "ai_hosts item for item")
	assert_eq(back.battles, s.battles, "battles item for item")
	assert_eq(back.foe_next_id, 4)
	var code := String(EnemyAi.host_units(repo, null, repo.raid_hosts[0])[0])
	assert_eq(int(back.foes[code]["x_m"]), 5100)
	assert_eq(int(back.foes[code]["y_m"]), -620, "a negative metre survives")
	assert_eq(String(back.ai_hosts["raid_main"]["mode"]), "ADVANCE")
	assert_eq(back.battles.size(), 1)
	var b: Dictionary = back.battles[0]
	assert_eq((b["attackers"] as Array)[0], code, "the battle's attackers list survives in order")
	assert_eq(int(((b["log"] as Array)[0] as Dictionary)["eff"]), 640, "nested log lines survive")
	assert_false(bool(b["decided"]))


func test_no_float_in_the_values_or_the_encoding() -> void:
	var s := _filled()
	var found: Array = []
	_floats_in(s.foes, "foes", found)
	_floats_in(s.ai_hosts, "ai_hosts", found)
	_floats_in(s.battles, "battles", found)
	assert_eq(found, [], "no float in the state's own values")
	var d := s.to_dict()
	for key: String in ["foes", "ai_hosts", "battles", "foe_next_id"]:
		_encoded_floats_in(d[key], key, found)
	assert_eq(found, [], "no encoded float in the saved foes / ai_hosts / battles")
	var back := GameState.from_dict(d)
	_floats_in(back.foes, "foes", found)
	_floats_in(back.ai_hosts, "ai_hosts", found)
	_floats_in(back.battles, "battles", found)
	assert_eq(found, [], "and none comes back from a load")
	assert_eq(typeof(back.foe_next_id), TYPE_INT)


func test_save_is_stable() -> void:
	var s := _filled()
	var a := JSON.stringify(s.to_dict(), "", true)
	var b := JSON.stringify(s.to_dict(), "", true)
	assert_eq(a, b, "the same state writes the same text twice")
	var back := GameState.from_dict(JSON.parse_string(a))
	assert_eq(JSON.stringify(back.to_dict(), "", true), a, "and a load then a save changes nothing")

func test_blocked_day_transaction_round_trip_preserves_cursor_and_journal() -> void:
	var s := _filled()
	s.day_resolution = DayResolution.begin(16, false)
	s.day_resolution["phase"] = "FIXED_TACTICAL_SUBSTEPS"
	s.day_resolution["substep_index"] = 2
	s.day_resolution["battle_ids"] = [3, 4]
	s.day_resolution["battle_index"] = 1
	s.day_resolution["journal"]["works"] = [{"cell": 7, "building": "manor_house"}]
	DayResolution.block_on_encounter(s.day_resolution, 4)
	var packed := JSON.stringify(s.to_dict(), "", true)
	var back := GameState.from_dict(JSON.parse_string(packed))
	assert_eq(back.day_resolution, s.day_resolution)
	assert_eq(JSON.stringify(back.to_dict(), "", true), packed)


func test_real_substep_encounter_save_resumes_the_same_round_once() -> void:
	var state := BattleScenario.contact(repo, 10)
	var blocked := TickEngine.new(repo).resolve_day(state)
	assert_eq(blocked["status"], "blocked")
	var cursor := int(state.day_resolution["substep_index"])
	assert_lt(cursor, int(state.day_resolution["substep_count"]), "the save pauses inside the movement substeps")
	var pending: Dictionary = state.day_resolution["pending_decision"]
	var battle_id := int(pending["battle_id"])
	assert_eq(int(BattleSystem.battle_by_id(state, battle_id)["rounds"]), 0, "no losses before confirmation")
	var back := BattleScenario.roundtrip(state)
	assert_eq(DayResolution.acknowledge(state.day_resolution, String(pending["token"]), "continue")["status"], "accepted")
	var live_result := TickEngine.new(repo).resolve_day(state)
	assert_eq(live_result["status"], "complete")
	assert_eq(DayResolution.acknowledge(back.day_resolution, String(pending["token"]), "continue")["status"], "accepted")
	var resumed := TickEngine.new(repo).resolve_day(back)
	assert_eq(resumed["status"], "complete")
	var rounds: Array = (resumed["journal"]["battles"] as Array) \
			.filter(func(e: Dictionary) -> bool: return String(e.get("kind", "")) == "round" and int(e["battle_id"]) == battle_id)
	assert_eq(rounds.size(), 1, "the acknowledged contact substep resolves one battle round")
	assert_eq(SaveLoad.state_hash(state), SaveLoad.state_hash(back), "save/resume matches uninterrupted continuation")


func test_old_save_without_keys_loads() -> void:
	var d := _filled().to_dict()
	for k: String in ["foes", "ai_hosts", "battles", "foe_next_id"]:
		assert_true(d.has(k), "the new save writes " + k)
		d.erase(k)
	var old := GameState.from_dict(d)
	assert_eq(old.foes, {})
	assert_eq(old.ai_hosts, {})
	assert_eq(old.battles, [])
	assert_eq(old.foe_next_id, 0)
	assert_eq(old.tick, _filled().tick, "the rest of the save is untouched")
