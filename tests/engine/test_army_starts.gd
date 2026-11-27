extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const ArmyStarts := preload("res://tools/army_starts.gd")
## The opening regiments of the game's own arms (data/army/game_arm_starts.csv, tools/army_starts.gd;
## specs 2026-11-20-heavy-infantry-arm-design and 2026-11-26-militia-arm-design, "Opening
## regiments"): the rule on a hand-made world, the share rule by hand,
## the default pack's rows against the rule re-derived here from the pack's own tables, a new
## campaign raising them and an old save gaining none.

const RULE := {"arm": "heavy_infantry", "units_min": 1, "units_max": 2, "men_min": 100, "men_max": 400,
	"men_step": 50, "avg_strongest": 300, "avg_weakest": 150, "place": "largest_towns", "offset_km": 2.0,
	"bearings": [0.0, 90.0], "code_word": "hv", "label_word": "Heavy"}


func _burg(code: String, label: String, kingdom: String, people: int, x: float, y: float) -> Dictionary:
	return {"burg_code": code, "label": label, "province_code": "p_" + code, "kingdom_code": kingdom,
		"population": people, "x": x, "y": y}


func test_the_rule_on_a_hand_made_world() -> void:
	# Ranked a (1000), b (400), c (0): the upper half (2 of 3, the middle counts upper) take
	# units_max 2, c units_min 1. Averages: a 300; b 150 + 150 x 400 / 1000 = 210; c 150.
	# a: 300 + 50 = 350, 300 - 50 = 250. b: 260 -> 250 (5.2 steps), 160 -> 150 (3.2). c has no town.
	var kingdoms := [{"code": "a", "strength": 1000.0}, {"code": "b", "strength": 400.0},
		{"code": "c", "strength": 0.0}]
	# a's two towns tie at 500 people: "aa" before "ax" by code. An export regiment stands 0.5 px
	# from aa, so aa's regiment moves out one ring (2 px at 1,000 m a px) along bearing 0: (32, 10),
	# 2.06 px from it. b has one town: its second regiment stands there again, moved to (102, 100).
	var burgs := [_burg("ax", "AX", "a", 500, 10.0, 10.0), _burg("aa", "AA", "a", 500, 30.0, 10.0),
		_burg("bt", "BT", "b", 100, 100.0, 100.0)]
	var plan := ArmyStarts.plan([RULE], kingdoms, burgs, [Vector2(30.0, 10.5)], 1000, {})
	assert_false(plan.has("error"), str(plan))
	assert_eq(plan["skipped"], ["c"])
	var got: Array = []
	for row: Dictionary in plan["rows"]:
		got.append([row["regiment_code"], row["province_code"], row["label"], row["x"], row["y"], row["men"]])
	assert_eq(got, [
		["a_1st_hv_aa", "p_aa", "1st (AA) Heavy", 32.0, 10.0, 350],
		["a_2nd_hv_ax", "p_ax", "2nd (AX) Heavy", 10.0, 10.0, 250],
		["b_1st_hv_bt", "p_bt", "1st (BT) Heavy", 100.0, 100.0, 250],
		["b_2nd_hv_bt", "p_bt", "2nd (BT) Heavy", 102.0, 100.0, 150]])
	var taken := ArmyStarts.plan([RULE], kingdoms, burgs, [], 1000, {"a_1st_hv_aa": true})
	assert_true(taken.has("error"), "a code already written is refused")


func test_sizes_round_half_up_and_clamp() -> void:
	# span 1000 hundredths: strength 500 -> 150 + 75 = 225, +50 = 275 -> 300 (5.5 steps, half up)
	assert_eq(ArmyStarts.size_of(RULE, 500, 1000, 0, 0, 3), 300)
	assert_eq(ArmyStarts.size_of(RULE, 500, 1000, 0, 1, 3), 250, "225 -> 4.5 steps -> 250")
	assert_eq(ArmyStarts.size_of(RULE, 500, 1000, 0, 2, 3), 200, "175 -> 3.5 steps -> 200")
	var tight := RULE.duplicate()
	tight["men_min"] = 200
	tight["men_max"] = 300
	assert_eq(ArmyStarts.size_of(tight, 1000, 1000, 0, 0, 2), 300, "350 clamped to men_max")
	assert_eq(ArmyStarts.size_of(tight, 0, 1000, 0, 1, 2), 200, "100 clamped to men_min")
	assert_eq(ArmyStarts.size_of(RULE, 7, 7, 7, 0, 1), 300, "one kingdom is the strongest")


const SHARE := {"arm": "militia", "units_min": 2, "units_max": 3, "men_min": 250, "men_max": 1000,
	"men_step": 50, "avg_strongest": 0, "avg_weakest": 0, "share_permille": 50, "total_min": 500,
	"place": "largest_towns", "offset_km": 2.0, "bearings": [0.0, 90.0], "code_word": "mil", "label_word": "Militia"}


func test_the_share_rule_by_hand() -> void:
	# army 20,500: 20,500 x 50 / 1000 = 1,025 -> 20.5 steps, half up -> T 1,050.
	# n 3: 350 -> 400 / 350 / 300. n 2: 525 -> 10.5 steps -> 550 -> 600 / 500.
	var got: Array = []
	for i in 3:
		got.append(ArmyStarts.share_size_of(SHARE, 20500, i, 3))
	assert_eq(got, [400, 350, 300])
	assert_eq([ArmyStarts.share_size_of(SHARE, 20500, 0, 2), ArmyStarts.share_size_of(SHARE, 20500, 1, 2)], [600, 500])
	# army 20,400: 1,020 -> 20.4 steps -> T 1,000. n 3: 333.3 -> 6.67 steps -> 350 -> 400 / 350 / 300.
	assert_eq(ArmyStarts.share_size_of(SHARE, 20400, 1, 3), 350)
	# army 2,000: 100 men is under total_min, T 500. n 2: 250 -> 300, and 200 clamped to men_min 250.
	assert_eq([ArmyStarts.share_size_of(SHARE, 2000, 0, 2), ArmyStarts.share_size_of(SHARE, 2000, 1, 2)], [300, 250])
	# army 100,000: T 5,000. n 3: 1,666.7 -> 1,650; 1,700 / 1,650 / 1,600 all clamped to men_max.
	assert_eq(ArmyStarts.share_size_of(SHARE, 100000, 2, 3), 1000)
	assert_eq(ArmyStarts.share_size_of(SHARE, 20500, 0, 1), 1000, "one regiment is the base: 1,050 clamped")


func test_a_share_rule_counts_the_rows_of_the_rules_before_it() -> void:
	# One kingdom (the strongest: units_max of each rule), army 9,000, one town at (10, 10).
	# RULE first: 2 heavy regiments, 350 + 250 = 600 men, so the militia's army is 9,600.
	# Share 500 permille, men_max 2,000: T 4,800; n 3: 1,600 -> 1,650 / 1,600 / 1,550
	# (9,000 alone would give T 4,500 and 1,550 / 1,500 / 1,450).
	var wide := SHARE.duplicate()
	wide["share_permille"] = 500
	wide["men_max"] = 2000
	var kingdoms := [{"code": "a", "strength": 10.0, "army": 9000}]
	var burgs := [_burg("at", "AT", "a", 500, 10.0, 10.0)]
	var plan := ArmyStarts.plan([RULE, wide], kingdoms, burgs, [], 1000, {})
	assert_false(plan.has("error"), str(plan))
	var got: Array = []
	for row: Dictionary in plan["rows"]:
		got.append([row["regiment_code"], row["x"], row["y"], row["men"]])
	# Places: the town, then ring 1 along 0 and 90, then ring 2 along 0 and 90 (2 px a ring).
	assert_eq(got, [
		["a_1st_hv_at", 10.0, 10.0, 350], ["a_2nd_hv_at", 12.0, 10.0, 250],
		["a_1st_mil_at", 10.0, 12.0, 1650], ["a_2nd_mil_at", 14.0, 10.0, 1600], ["a_3rd_mil_at", 10.0, 14.0, 1550]])


func test_ordinals() -> void:
	var got: Array = []
	for n: int in [1, 2, 3, 4, 11, 12, 13, 21, 22, 101, 111]:
		got.append(ArmyStarts.ordinal_of(n))
	assert_eq(got, ["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd", "101st", "111th"])


func test_the_default_pack_carries_the_rule() -> void:
	var repo := SuiteData.repo()
	var ruled := ArmyStarts.rules("res://data")
	assert_false(ruled.has("error"), str(ruled))
	var regs := repo.world_table("military", "regiments")
	var kings := repo.world_table("military", "kingdoms")
	var power := {}
	for arm: String in repo.world_table("military", "unit_types"):
		power[arm] = float(repo.world_table("military", "unit_types")[arm]["power"])
	var gap := 0.0
	var ruled_arms: Array = ruled["rules"].map(func(r: Dictionary) -> String: return String(r["arm"]))
	# A share rule's army: the men of the kingdom's non-naval regiments written before its rows
	# (the export's, then each earlier rule's as the loop passes it).
	var army := {}
	for code: String in regs:
		var row: Dictionary = regs[code]
		var is_ruled := false
		for a: String in ruled_arms:
			is_ruled = is_ruled or int(row[a]) > 0
		if int(row["is_naval"]) == 0 and not is_ruled:
			for col: String in power:
				army[String(row["kingdom_code"])] = int(army.get(String(row["kingdom_code"]), 0)) + int(row[col])
	for rule: Dictionary in ruled["rules"]:
		var arm := String(rule["arm"])
		gap = float(rule["offset_km"]) * 1000.0 / float(ArmySystem.metres_per_pack_px(repo))
		var mine := {}  # kingdom -> its rows of this arm, in table order
		for code: String in regs:
			if int(regs[code][arm]) > 0:
				var k := String(regs[code]["kingdom_code"])
				if not mine.has(k):
					mine[k] = []
				mine[k].append(regs[code])
		# Strength before every ruled arm's rows, ranked (ties by code).
		var before := {}
		for k: String in kings:
			var s := float(kings[k]["strength"])
			for a: String in ruled_arms:
				s -= int(kings[k][a]) * float(power[a])
			before[k] = s
		var ranked: Array = kings.keys()
		ranked.sort_custom(func(a: String, z: String) -> bool:
			return before[a] > before[z] or (before[a] == before[z] and a < z))
		var top: float = before[ranked[0]]
		var bottom: float = before[ranked[-1]]
		for k: String in kings:
			var towns: Array = []
			for b: String in repo.burgs:
				if String(repo.burgs[b]["kingdom_code"]) == k:
					towns.append(repo.burgs[b])
			towns.sort_custom(func(a: Dictionary, z: Dictionary) -> bool:
				return int(a["population"]) > int(z["population"]) or (int(a["population"]) == int(z["population"])
					and String(a["burg_code"]) < String(z["burg_code"])))
			var rows: Array = mine.get(k, [])
			if towns.is_empty():
				assert_eq(rows.size(), 0, k + " has no town")
				continue
			var n := int(rule["units_max"]) if ranked.find(k) < (ranked.size() + 1) / 2 else int(rule["units_min"])
			assert_eq(rows.size(), n, k + " regiments")
			var average: float = float(rule["avg_weakest"]) + float(int(rule["avg_strongest"]) - int(rule["avg_weakest"])) \
				* (before[k] - bottom) / (top - bottom)
			var step := float(rule["men_step"])
			var share := int(rule["share_permille"]) > 0
			if share:  # the base: the kingdom's total over its regiments, both rounded half up to a step
				var whole := maxf(float(int(army.get(k, 0)) * int(rule["share_permille"])) / 1000.0, float(rule["total_min"]))
				whole = floor(whole / step + 0.5) * step
				average = floor(whole / float(n) / step + 0.5) * step
				assert_between(rows.size(), int(rule["units_min"]), int(rule["units_max"]), k + " count")
			var total := 0
			for i in rows.size():
				var off := step if i == 0 else (-step if i == n - 1 else 0.0)
				var men := clampi(int(floor((average + off) / step + 0.5) * step), int(rule["men_min"]), int(rule["men_max"]))
				assert_eq(int(rows[i][arm]), men, "%s regiment %d" % [k, i + 1])
				total += men
				var town: Dictionary = towns[i] if i < towns.size() else towns[0]
				assert_eq(String(rows[i]["province_code"]), String(town["province_code"]), "%s %d stands in its town's province" % [k, i + 1])
				assert_true(String(rows[i]["regiment_code"]).ends_with("_%s_%s" % [rule["code_word"], town["burg_code"]]))
				var at := Vector2(float(rows[i]["x"]), float(rows[i]["y"]))
				assert_lt(at.distance_to(Vector2(float(town["x"]), float(town["y"]))), gap * 4.0, "near its town")
				for other: String in regs:
					if other != String(rows[i]["regiment_code"]):
						var there := Vector2(float(regs[other]["x"]), float(regs[other]["y"]))
						assert_true(at.distance_to(there) >= gap - 0.01, "%s clear of %s" % [rows[i]["regiment_code"], other])
				for col: String in power:
					if col != arm:
						assert_eq(int(rows[i][col]), 0, "%s holds only %s" % [rows[i]["regiment_code"], arm])
			assert_eq(int(kings[k][arm]), total, k + " total")
			if share:
				assert_gte(total, mini(int(rule["total_min"]), n * int(rule["men_min"])), k + " never under the floor")
			var count := 0
			for code: String in regs:
				count += 1 if String(regs[code]["kingdom_code"]) == k else 0
			assert_eq(int(kings[k]["regiments"]), count, k + " regiment count")
		for k: String in mine:
			for row: Dictionary in mine[k]:
				army[k] = int(army.get(k, 0)) + int(row[arm])


func test_a_new_campaign_raises_them() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 42)
	var realm := repo.resolve_realm("player_realm")
	var regs := repo.world_table("military", "regiments")
	for rule: Dictionary in ArmyStarts.rules("res://data")["rules"]:
		var arm := String(rule["arm"])
		var pack := 0
		for code: String in regs:
			if String(regs[code]["kingdom_code"]) == realm and int(regs[code][arm]) > 0:
				pack += 1
		assert_between(pack, int(rule["units_min"]), int(rule["units_max"]), "the player's kingdom opens with " + arm)
		var units := 0
		for reg: Dictionary in MapObjects.regiments_of(repo, realm, state):
			if MapObjects.regiment_arm(repo, reg) == arm:
				units += 1
		assert_gt(units, 0, "and its roster has %s units" % arm)


func test_an_old_save_gains_none() -> void:
	# A campaign begun on the pack before these rows: loaded with them, it keeps its own army.
	var arms: Array = ArmyStarts.rules("res://data")["rules"].map(func(r: Dictionary) -> String: return String(r["arm"]))
	var old := SuiteData.repo()
	var regs := old.world_table("military", "regiments")
	for code: String in regs.keys():
		for arm: String in arms:
			if regs.has(code) and int(regs[code][arm]) > 0:
				regs.erase(code)
	var data: Dictionary = JSON.parse_string(JSON.stringify(SuiteData.campaign(old, 42).to_dict()))
	var repo := SuiteData.repo()
	var loaded := GameState.from_dict(data, false)
	var personnel := MilitaryBootstrap.migrate(repo, loaded)
	assert_false(personnel.has("error"), str(personnel))
	var organization := MilitaryReorganization.reconcile(repo, loaded)
	assert_ne(organization.get("status", "error"), "error", str(organization))
	ArmySystem.ensure(repo, loaded)
	for reg: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), loaded):
		assert_false(arms.has(MapObjects.regiment_arm(repo, reg)), String(reg.get("regiment_code", "")))
