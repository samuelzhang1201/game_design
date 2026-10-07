extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The opening army as units (spec 2026-10-07-army-split-and-ground §3).

var repo: DataRepository
var split: Dictionary
var roster: Dictionary


func before_all() -> void:
	repo = SuiteData.repo()
	split = ArmySplit.split(repo)
	roster = split["roster"]


func _pack_rows() -> Array:
	var rows: Array = repo.world_table("military", "regiments").values()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["regiment_code"]) < String(b["regiment_code"]))
	return rows


func _arms() -> Array:
	return repo.army_split.filter(func(r: Dictionary) -> bool: return not bool(r["pooled"])) \
		.map(func(r: Dictionary) -> String: return String(r["arm"]))


func test_shares_are_even_and_larger_first() -> void:
	assert_eq(ArmySplit.shares(1268, 600), [423, 423, 422])
	assert_eq(ArmySplit.shares(1200, 600), [600, 600])
	assert_eq(ArmySplit.shares(1201, 600), [401, 400, 400])
	assert_eq(ArmySplit.shares(500, 600), [500])
	assert_eq(ArmySplit.shares(37, 600), [37], "fewer than 300 is still a unit")
	assert_eq(ArmySplit.shares(0, 600), [])


func test_every_unit_is_one_arm_and_within_the_cap() -> void:
	var cap := int(repo.bal("army_split_cap_men"))
	for code: String in roster:
		var r: Dictionary = roster[code]
		if String(r["is_naval"]) == "1" or String(r["parent_code"]) == "":
			continue
		var armed := 0
		for arm: String in repo.world_table("military", "unit_types"):
			if int(float(r.get(arm, 0))) > 0:
				armed += 1
		assert_eq(armed, 1, code)
		assert_lte(int(MapObjects.regiment_size(repo, r)), cap, code)


func test_the_count_is_the_packs_own() -> void:
	var cap := int(repo.bal("army_split_cap_men"))
	var want := 0
	var gunned: Dictionary = {}
	for r: Dictionary in _pack_rows():
		if String(r["is_naval"]) == "1":
			want += 1
			continue
		for arm: String in _arms():
			want += ArmySplit.shares(int(float(r.get(arm, 0))), cap).size()
		if int(float(r.get("artillery", 0))) > 0:
			gunned[String(r["kingdom_code"])] = true
	assert_eq(roster.size(), want + gunned.size())


func test_men_are_conserved_per_arm_and_kingdom() -> void:
	var before: Dictionary = {}
	var after: Dictionary = {}
	for r: Dictionary in _pack_rows():
		for arm: String in repo.world_table("military", "unit_types"):
			var k := "%s|%s" % [r["kingdom_code"], arm]
			before[k] = int(before.get(k, 0)) + int(float(r.get(arm, 0)))
	for code: String in roster:
		var r: Dictionary = roster[code]
		for arm: String in repo.world_table("military", "unit_types"):
			var k := "%s|%s" % [r["kingdom_code"], arm]
			after[k] = int(after.get(k, 0)) + int(float(r.get(arm, 0)))
	for k: String in before:
		assert_eq(int(after.get(k, 0)), int(before[k]), k)


func test_codes_and_labels() -> void:
	for r: Dictionary in _pack_rows():
		if String(r["is_naval"]) == "1":
			assert_true(roster.has(String(r["regiment_code"])), "a fleet keeps its code")
			continue
		var armed: Array = _arms().filter(func(a: String) -> bool: return int(float(r.get(a, 0))) > 0)
		for row: Dictionary in repo.army_split:
			if bool(row["pooled"]) or not armed.has(String(row["arm"])):
				continue
			var n := ArmySplit.shares(int(float(r[String(row["arm"])])), int(repo.bal("army_split_cap_men"))).size()
			var base := "%s_%s" % [r["regiment_code"], row["code_word"]]
			var code := base if n == 1 else base + "_1"
			assert_true(roster.has(code), code)
			var label := String(roster[code]["label"])
			if armed.size() == 1:
				assert_true(label.begins_with(String(r["label"])), "a one-arm regiment keeps its label: " + label)
			else:
				assert_true(label.contains(String(row["label_word"])), label)
			if n > 1:
				assert_true(label.ends_with(" I"), label)
				assert_true(String(roster[base + "_2"]["label"]).ends_with(" II"))


func test_one_royal_train_a_gunned_kingdom_at_its_capital() -> void:
	var guns: Dictionary = {}
	for r: Dictionary in _pack_rows():
		guns[String(r["kingdom_code"])] = int(guns.get(String(r["kingdom_code"]), 0)) + int(float(r.get("artillery", 0)))
	var word := ""
	for row: Dictionary in repo.army_split:
		if bool(row["pooled"]):
			word = String(row["code_word"])
	for k: String in guns:
		var code := "%s_%s" % [k, word]
		if int(guns[k]) == 0:
			assert_false(roster.has(code))
			continue
		var t: Dictionary = roster[code]
		assert_eq(int(t["artillery"]), int(guns[k]))
		assert_eq(String(t["parent_code"]), "")
		assert_eq(String(t["camp_town"]), String(repo.kingdoms[k]["capital_burg"]))


func test_one_royal_household_a_kingdom_from_the_regiment_nearest_the_capital() -> void:
	var realm := repo.resolve_realm("player_realm")
	var royals: Array = roster.values().filter(func(r: Dictionary) -> bool:
		return String(r["kingdom_code"]) == realm and String(r["is_royal"]) == "1")
	assert_eq(royals.size(), 1)
	var cap: Dictionary = repo.burgs[String(repo.kingdoms[realm]["capital_burg"])]
	var seat := Vector2(float(cap["x"]), float(cap["y"]))
	var nearest := ""
	var best := INF
	for r: Dictionary in _pack_rows():
		if String(r["kingdom_code"]) != realm or String(r["is_naval"]) == "1":
			continue
		var d := seat.distance_to(Vector2(float(r["x"]), float(r["y"])))
		if d < best:
			best = d
			nearest = String(r["regiment_code"])
	assert_eq(String(royals[0]["parent_code"]), nearest)
	if int(float(repo.world_table("military", "regiments")[nearest].get("cavalry", 0))) > 0:
		assert_gt(int(royals[0]["cavalry"]), 0, "the household is horse when the regiment has any")


func test_no_two_standing_units_share_ground() -> void:
	var half := float(int(repo.bal("army_slot_spacing_m"))) / 2.0
	var pts: Array = []
	for code: String in roster:
		var r: Dictionary = roster[code]
		if String(r["is_naval"]) == "1":
			continue
		pts.append(ArmySystem.pack_to_metres(repo, Vector2(float(r["x"]), float(r["y"]))))
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			assert_gte(Vector2(pts[i] - pts[j]).length(), half - 2.0,
				"units %d and %d overlap" % [i, j])


func test_at_most_one_seat_a_town_held_by_its_holder() -> void:
	var seats: Dictionary = split["seats"]
	var seen: Dictionary = {}
	for town: String in seats:
		var code := String(seats[town])
		assert_false(seen.has(code), "one unit holds one seat")
		seen[code] = true
		var b: Dictionary = repo.burgs[town]
		assert_eq(String(roster[code]["kingdom_code"]),
			MapOwnership.owner_of(repo, null, String(b["province_code"])))
		assert_eq(ArmySystem.pack_to_metres(repo, Vector2(float(roster[code]["x"]), float(roster[code]["y"]))),
			ArmyGround.town_point_m(repo, town), "the seat stands on the town's point")


func test_the_seat_goes_to_the_most_infantry() -> void:
	var seats: Dictionary = split["seats"]
	for town: String in seats:
		var held: Dictionary = roster[String(seats[town])]
		for code: String in roster:
			var r: Dictionary = roster[code]
			if String(r["camp_town"]) == town and String(r["kingdom_code"]) == String(held["kingdom_code"]):
				assert_lte(int(r["infantry"]), int(held["infantry"]), "%s at %s" % [code, town])


func test_deterministic_and_copied() -> void:
	ArmySplit.forget()  # so _make runs again, not the cached split
	var again := ArmySplit.split(repo)
	assert_eq(JSON.stringify(again, "", true), JSON.stringify(split, "", true))
	(again["roster"] as Dictionary).clear()
	assert_false(ArmySplit.roster_of(repo).is_empty(), "split() hands out a copy")


func test_a_new_campaign_carries_the_roster_and_seats() -> void:
	var s := SuiteData.campaign(repo, 7)
	assert_eq(s.army_roster.size(), roster.size())
	assert_eq(s.town_seat, split["seats"])


func test_lists_put_the_crown_first_then_group_by_regiment() -> void:
	var s := SuiteData.campaign(repo, 2)
	var codes: Array = MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), s) \
		.map(func(r: Dictionary) -> String: return String(r["regiment_code"]))
	codes.reverse()
	var out := ArmySystem.ordered(repo, s, codes)
	assert_eq(out.size(), codes.size())
	assert_eq(String(ArmySystem.regiment(repo, String(out[0]), s)["is_royal"]), "1", "the household first")
	var trains: Array = out.filter(func(c: String) -> bool:
		return String(ArmySystem.regiment(repo, c, s)["parent_code"]) == "" \
			and String(ArmySystem.regiment(repo, c, s)["is_naval"]) == "0")
	if not trains.is_empty():
		assert_eq(out[1], trains[0], "then the royal train")
	# every regiment's units stand together (the household is one unit of its
	# regiment but leads the list, so it stands apart)
	var seen: Dictionary = {}
	var last := ""
	for c: String in out:
		if String(ArmySystem.regiment(repo, c, s)["is_royal"]) == "1":
			continue
		var p := String(ArmySystem.regiment(repo, c, s)["parent_code"])
		if p != last and p != "":
			assert_false(seen.has(p), "%s's units are split up" % p)
			seen[p] = true
		last = p
