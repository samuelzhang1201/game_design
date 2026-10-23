extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Personnel := preload("res://scripts/engine/military_roster.gd")
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
		assert_lte(MilitaryRoster.personnel_capacity(repo, r), cap, code)


func test_the_count_is_the_packs_own() -> void:
	var cap := int(repo.bal("army_split_cap_men"))
	var want := 0
	var gunned: Dictionary = {}
	for r: Dictionary in _pack_rows():
		if String(r["is_naval"]) == "1":
			want += 1
			continue
		for arm: String in _arms():
			want += ArmySplit.element_shares(int(float(r.get(arm, 0))), int(repo.world_table("military", "unit_types")[arm]["crew"]), cap).size()
		if int(float(r.get("artillery", 0))) > 0:
			gunned[String(r["kingdom_code"])] = true
	assert_eq(roster.size(), want + gunned.size())


func test_equipment_is_conserved_per_arm_and_kingdom() -> void:
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
			var n := ArmySplit.element_shares(int(float(r[String(row["arm"])])), int(repo.world_table("military", "unit_types")[String(row["arm"])]["crew"]), int(repo.bal("army_split_cap_men"))).size()
			var base := "%s_%s" % [r["regiment_code"], row["code_word"]]
			var code := base if n == 1 else base + "_1"
			assert_true(roster.has(code), code)
			if not roster.has(code):
				continue
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


## R16: no standing unit but the seat holder stands within its town's reach
## at the start — the camp lies outside the walls (owner 2026-10-08: 城外).
func test_only_the_seat_stands_within_its_towns_reach() -> void:
	var seats: Dictionary = split["seats"]
	var camped := 0
	var codes := roster.keys()
	codes.sort()
	for code: String in codes:
		var r: Dictionary = roster[code]
		var town := String(r.get("camp_town", ""))
		if String(r["is_naval"]) == "1" or town == "" or String(seats.get(town, "")) == code:
			continue
		camped += 1
		var b: Dictionary = repo.burgs[town]
		var d := Vector2(float(r["x"]), float(r["y"])).distance_to(Vector2(float(b["x"]), float(b["y"])))
		assert_gt(d, ArmySystem.town_reach_px(repo, b), "%s camps inside %s's reach" % [code, town])
	assert_gt(camped, 0, "premise: some unit camps round a town")


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
	# the split's seats, but for those a raid host's unit held: a raised unit
	# leaves its seat, refilled from its old camp (EnemyAi.spawn), never a foe
	var seats: Dictionary = split["seats"]
	for town: String in seats:
		var was := String(seats[town])
		if not ArmySystem.is_foe(s, was):
			assert_eq(String(s.town_seat.get(town, "")), was, town + " keeps its seat")
		elif s.town_seat.has(town):
			var now := String(s.town_seat[town])
			assert_false(ArmySystem.is_foe(s, now), town + "'s seat is no foe's")
			assert_eq(ArmyGround.camped_by(repo, s, now), town, town + "'s seat refilled from its camp")
	for town: String in s.town_seat:
		assert_true(seats.has(town), town + ": no seat the split did not make")


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


## A kingdom with no capital still keeps every gun (§3.1 step 3: no unit
## added or lost): its train camps where its first land regiment, by code,
## stands.
func test_a_kingdom_with_no_capital_keeps_its_guns() -> void:
	var r2 := SuiteData.repo()
	var rows: Array = r2.world_table("military", "regiments").values()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["regiment_code"]) < String(b["regiment_code"]))
	var guns: Dictionary = {}
	for r: Dictionary in rows:
		var k := String(r["kingdom_code"])
		guns[k] = int(guns.get(k, 0)) + int(float(r.get("artillery", 0)))
	var ks := guns.keys()
	ks.sort()
	var gunned := ""
	for k: String in ks:
		if int(guns[k]) > 0:
			gunned = k
			break
	assert_ne(gunned, "", "premise: a kingdom has guns")
	var first: Dictionary = {}
	for r: Dictionary in rows:
		if String(r["kingdom_code"]) == gunned and String(r.get("is_naval", "0")) != "1":
			first = r
			break
	r2.kingdoms[gunned]["capital_burg"] = ""
	var ro: Dictionary = ArmySplit.split(r2)["roster"]
	var men := 0
	var train: Dictionary = {}
	for c: String in ro:
		var u: Dictionary = ro[c]
		if String(u["kingdom_code"]) == gunned:
			men += int(float(u.get("artillery", 0)))
			if int(float(u.get("artillery", 0))) > 0:
				train = u
	assert_eq(men, int(guns[gunned]), "every gun kept")
	assert_false(train.is_empty(), "as a train")
	if not train.is_empty():
		var at := Vector2(float(first["x"]), float(first["y"]))
		var town := ArmySystem.town_at(r2, at)
		if town != "" and MapOwnership.owner_of(r2, null, String(r2.burgs[town].get("province_code", ""))) != gunned:
			town = ""
		assert_eq(String(train["camp_town"]), town, "it camps by the first land regiment's town")


## Exercise the complete splitter, including placement, with pack-independent counts.
func _crew_fixture(equipment: int, crew: int, cap: int) -> DataRepository:
	var fixture := SuiteData.repo()
	fixture.balance["army_split_cap_men"] = cap
	fixture.world_row("military", "unit_types", "cavalry")["crew"] = str(crew)
	var rows := fixture.world_table("military", "regiments")
	var source: Dictionary = {}
	for row: Dictionary in rows.values():
		if String(row.get("is_naval", "0")) != "1":
			source = row.duplicate(true)
			break
	for arm: String in fixture.world_table("military", "unit_types"):
		source[arm] = "0"
	source["cavalry"] = str(equipment)
	rows.clear()
	rows[String(source["regiment_code"])] = source
	return fixture


func test_split_counts_personnel_without_splitting_equipment() -> void:
	for example: Array in [[1268, 2, 600, [254, 254, 254, 253, 253]],
			[301, 2, 600, [151, 150]], [7, 8, 25, [3, 2, 2]]]:
		var fixture := _crew_fixture(example[0], example[1], example[2])
		var original := fixture.world_table("military", "regiments").duplicate(true)
		var result := ArmySplit._make(fixture)
		var units: Dictionary = result["roster"]
		var codes := units.keys()
		codes.sort()
		var quantities: Array = []
		for code: String in codes:
			quantities.append(int(units[code]["cavalry"]))
			assert_lte(MilitaryRoster.personnel_capacity(fixture, units[code]), int(example[2]))
		assert_eq(quantities, example[3], "crew-aware even equipment shares")
		assert_eq(fixture.world_table("military", "regiments"), original)
		assert_eq(ArmySplit._make(fixture), result, "IDs and placement are reproducible")


func test_invalid_personnel_split_configuration_refuses_whole_roster() -> void:
	for example: Array in [[10, 0, 600], [10, -1, 600], [10, 2, 0], [10, 2, -1], [10, 8, 7]]:
		var fixture := _crew_fixture(example[0], example[1], example[2])
		var result := ArmySplit._make(fixture)
		assert_true(result.has("error"), str(example))
		assert_eq(result["roster"], {}, "no partial army on rejected construction")
		assert_eq(result["seats"], {})
	var missing := _crew_fixture(10, 2, 600)
	missing.world_row("military", "unit_types", "cavalry").erase("crew")
	assert_true(ArmySplit._make(missing).has("error"), "missing crew must not assume one person")

func test_campaign_rejects_an_invalid_split_instead_of_starting_without_armies() -> void:
	var fixture := _crew_fixture(10, 2, 0)
	assert_null(GameState.new_campaign(fixture, 42))

func test_fleet_and_pooled_train_still_require_valid_personnel_crews() -> void:
	for arm: String in ["fleet", "artillery"]:
		for crew: String in ["0", "-1", "1.5", "missing"]:
			var fixture := _crew_fixture(1, 2, 600)
			var row: Dictionary = fixture.world_table("military", "regiments").values()[0]
			row["cavalry"] = "0"
			row[arm] = "1"
			row["is_naval"] = "1" if arm == "fleet" else "0"
			fixture.world_row("military", "unit_types", arm)["crew"] = crew
			var result := ArmySplit._make(fixture)
			assert_true(result.has("error"), arm + ":" + crew)
			assert_eq(result["roster"], {})
			assert_eq(result["seats"], {})

func test_split_preserves_equipment_origins_before_pooling_the_royal_train() -> void:
	var fixture := _crew_fixture(301, 2, 600)
	fixture.world_row("military", "unit_types", "fleet")["crew"] = "100"
	var rows := fixture.world_table("military", "regiments")
	var original: Dictionary = rows.values()[0].duplicate(true)
	var provinces := fixture.provinces.keys()
	provinces.sort()
	var first := original.duplicate(true)
	first["regiment_code"] = "source_a"
	first["province_code"] = provinces[0]
	first["artillery"] = "2"
	var second := first.duplicate(true)
	second["regiment_code"] = "source_b"
	second["province_code"] = provinces[1]
	second["cavalry"] = "0"
	second["artillery"] = "3"
	var fleet := second.duplicate(true)
	fleet["regiment_code"] = "source_c"
	fleet["is_naval"] = "1"
	fleet["artillery"] = "0"
	fleet["fleet"] = "2"
	rows.clear()
	rows["source_a"] = first
	rows["source_b"] = second
	rows["source_c"] = fleet
	var units: Dictionary = ArmySplit._make(fixture)["roster"]
	assert_eq(units["source_a_horse_1"].get("source_parts", []), [
		{"regiment_code": "source_a", "province_code": provinces[0], "arm": "cavalry", "equipment_count": 151, "crew_per_element": 2}])
	assert_eq(units["source_a_horse_2"].get("source_parts", []), [
		{"regiment_code": "source_a", "province_code": provinces[0], "arm": "cavalry", "equipment_count": 150, "crew_per_element": 2}])
	var train_code := String(first["kingdom_code"]) + "_royal_train"
	assert_eq(units[train_code].get("source_parts", []), [
		{"regiment_code": "source_a", "province_code": provinces[0], "arm": "artillery", "equipment_count": 2, "crew_per_element": 8},
		{"regiment_code": "source_b", "province_code": provinces[1], "arm": "artillery", "equipment_count": 3, "crew_per_element": 8}])
	assert_eq(units["source_c"].get("source_parts", []), [
		{"regiment_code": "source_c", "province_code": provinces[1], "arm": "fleet", "equipment_count": 2, "crew_per_element": 100}])
	var saved := GameState.new()
	saved.rng = Rng.new(42)
	saved.army_roster = units
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(saved.to_dict())))
	assert_eq(restored.army_roster, units, "origins are save facts, not reconstructed from the capital")

func test_recursive_living_halves() -> void:
	var script: GDScript = load("res://scripts/engine/army_split.gd")
	assert_true(script.has_method("halves"))
	if not script.has_method("halves"):
		return
	for example: Array in [[0, []], [1000, [1000]], [1001, [501, 500]], [2001, [501, 500, 1000]], [2500, [625, 625, 625, 625]]]:
		assert_eq(script.call("halves", example[0], 1000), example[1])
