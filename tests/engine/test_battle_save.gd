extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
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
	var code := String((repo.raid_hosts[0]["regiments"] as Array)[0])
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
	var code := String((repo.raid_hosts[0]["regiments"] as Array)[0])
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
