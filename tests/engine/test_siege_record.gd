extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Play := preload("res://tests/invasion_play.gd")
## The siege record (player siege spec §3, step 1): one saved record per
## besieged town in GameState.sieges, the hosts' minds keeping only siege_id,
## and an old save's mind figures converted once.

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()


## A crown town whose burg features are walled (or not), in code order.
func _crown_town(walled: bool) -> String:
	var mine := repo.resolve_realm("player_realm")
	var codes: Array = repo.burgs.keys()
	codes.sort()
	for t: String in codes:
		var prov := String((repo.burgs[t] as Dictionary).get("province_code", ""))
		if MapOwnership.owner_of(repo, null, prov) == mine and SiegeRecord.walled(repo, t) == walled:
			return t
	return ""


func _sit(s: GameState, host: String, town: String, mode: String = "SIEGE") -> void:
	var mind: Dictionary = s.ai_hosts[host]
	mind["mode"] = mode
	mind["target_kind"] = "town"
	mind["target_id"] = town


func _two_hosts(s: GameState, town: String) -> Array:
	var main := Play.host(repo, "main")
	var reserve := Play.host(repo, "reserve")
	_sit(s, main, town)
	_sit(s, reserve, town)
	return [main, reserve]


func test_first_record_is_s1_and_one_per_town() -> void:
	var s := SuiteData.campaign(repo, 7)
	var town := _crown_town(true)
	assert_ne(town, "", "the pack has a walled crown town")
	var hs := _two_hosts(s, town)
	SiegeRecord.ensure_for(repo, s, hs[1])
	SiegeRecord.ensure_for(repo, s, hs[0])
	assert_eq(SiegeRecord.of_town(s, town), "s1")
	assert_eq(s.siege_next_id, 1)
	assert_eq(s.sieges.size(), 1, "one record a town")
	var rec: Dictionary = s.sieges["s1"]
	var sorted := hs.duplicate()
	sorted.sort()
	assert_eq(rec["hosts"], sorted, "hosts in code order")
	assert_eq(int(rec["integrity"]), 1000)
	assert_eq(int(rec["progress"]), 0)
	assert_eq(int(rec["days"]), 0)
	assert_eq(String(rec["task_id"]), "")
	assert_eq(String(rec["attacker"]), repo.resolve_realm("raider_realm"))
	assert_eq(String(rec["defender"]), repo.resolve_realm("player_realm"))
	assert_eq(String(s.ai_hosts[hs[0]]["siege_id"]), "s1")


func test_open_town_has_no_integrity() -> void:
	var s := SuiteData.campaign(repo, 7)
	var town := _crown_town(false)
	assert_ne(town, "", "the pack has an open crown town")
	var main := Play.host(repo, "main")
	_sit(s, main, town)
	assert_eq(int(SiegeRecord.ensure_for(repo, s, main)["integrity"]), 0)


func test_other_host_gets_no_record() -> void:
	var s := SuiteData.campaign(repo, 7)
	assert_eq(SiegeRecord.ensure_for(repo, s, Play.host(repo, "main")), {}, "a host not besieging keeps none")
	assert_true(s.sieges.is_empty())


func test_leave_resets_only_when_empty() -> void:
	var s := SuiteData.campaign(repo, 7)
	var hs := _two_hosts(s, _crown_town(true))
	SiegeRecord.ensure_for(repo, s, hs[0])
	var rec := SiegeRecord.ensure_for(repo, s, hs[1])
	rec["progress"] = 300
	rec["days"] = 5
	rec["assault"] = 1
	rec["assault_due"] = 1
	rec["starved"] = 1
	SiegeRecord.leave(s, hs[0])
	assert_eq(int(rec["progress"]), 300, "a host is left: the figures stay with the town")
	assert_eq(rec["hosts"], [hs[1]])
	SiegeRecord.leave(s, hs[1])
	for f: String in ["progress", "days", "assault", "assault_due", "starved"]:
		assert_eq(int(rec[f]), 0, f + " resets once no host is left")
	assert_eq(String(s.ai_hosts[hs[1]]["siege_id"]), "s1", "the mind keeps its id until the end is told")


func test_drop_erases_when_no_mind_names_it() -> void:
	var s := SuiteData.campaign(repo, 7)
	var town := _crown_town(true)
	var hs := _two_hosts(s, town)
	for h: String in hs:
		SiegeRecord.ensure_for(repo, s, h)
	for h: String in hs:
		SiegeRecord.leave(s, h)
	SiegeRecord.drop(s, hs[0])
	assert_eq(s.sieges.size(), 1, "the other mind still names it")
	SiegeRecord.drop(s, hs[1])
	assert_true(s.sieges.is_empty())
	assert_false(s.ai_hosts[hs[0]].has("siege_id"))
	SiegeRecord.ensure_for(repo, s, hs[0])
	assert_eq(SiegeRecord.of_town(s, town), "s2", "a new siege opens a fresh id")


func test_round_trip() -> void:
	var s := SuiteData.campaign(repo, 7)
	var main := Play.host(repo, "main")
	_sit(s, main, _crown_town(true))
	var rec := SiegeRecord.ensure_for(repo, s, main)
	rec["progress"] = 412
	rec["days"] = 9
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_eq(back.sieges, s.sieges)
	assert_eq(back.siege_next_id, s.siege_next_id)
	assert_eq(typeof(back.sieges["s1"]["days"]), TYPE_INT)
	assert_eq(SaveLoad.state_hash(back), SaveLoad.state_hash(s))


func test_absent_keys_load_empty() -> void:
	var s := SuiteData.campaign(repo, 7)
	var d := s.to_dict()
	d.erase("sieges")
	d.erase("siege_next_id")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	assert_eq(back.sieges, {})
	assert_eq(back.siege_next_id, 0)
