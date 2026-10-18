extends RefCounted
## The invasion played on the real day loop, for the tests that drive it
## (test_enemy_invasion, test_siege, test_invasion_end_to_end): a campaign
## opened as GameRoot opens it, a day played as Game.advance_day plays it, the
## pack's hosts and the player's regiments looked up by role and size, and
## the save's no-float walk. Nothing here names a map pack.

const SuiteData := preload("res://tests/suite_data.gd")


## A campaign of `repo` on `seed_value` after its opening tick (GameRoot's):
## tick 1, day 1.
static func opened(repo: DataRepository, engine: TickEngine, seed_value: int = 11) -> GameState:
	var s := SuiteData.campaign(repo, seed_value)
	engine.advance(s)
	return s


## One day, exactly as Game.advance_day plays it: the thirtieth is the tick.
static func day(engine: TickEngine, s: GameState) -> void:
	# This test-playback helper explicitly chooses auto-confirm for encounter
	# decisions so long simulations can proceed without a UI.
	if s.day >= Calendar.DAYS_PER_TICK:
		var report := engine.advance(s)
		while report.status == "blocked":
			DayResolution.acknowledge(s.day_resolution, String(report.pending_decision["token"]), "continue")
			report = engine.advance(s)
	else:
		var result := engine.resolve_day(s)
		while String(result.get("status", "")) == "blocked":
			DayResolution.acknowledge(s.day_resolution, String(result["decision"]["token"]), "continue")
			result = engine.resolve_day(s)


## Plays days until the absolute day `last` has ended.
static func play_through(engine: TickEngine, s: GameState, last: int) -> void:
	while s.absolute_day() <= last:
		day(engine, s)


## The first raid host of `role` in the pack's table; "" for none.
static func host(repo: DataRepository, role: String) -> String:
	for h: Dictionary in repo.raid_hosts:
		if String(h["role"]) == role:
			return String(h["host_code"])
	return ""


## The earliest appear_day among the pack's hosts; -1 for none.
static func first_appear(repo: DataRepository) -> int:
	var first := -1
	for h: Dictionary in repo.raid_hosts:
		var d := int(h["appear_day"])
		first = d if first < 0 else mini(first, d)
	return first


## The letters of `kind` filed so far.
static func letters(s: GameState, kind: String) -> Array:
	return s.missives.filter(func(m: Dictionary) -> bool: return String(m["kind"]) == kind)


## The player's land units (the army's roster, ArmySplit) of at least
## `min_heads` men, in code order.
static func land_regiments(repo: DataRepository, min_heads: int = 1) -> Array:
	var out: Array = []
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) != "1" and ArmySystem.headcount(repo, r) >= min_heads:
			out.append(String(r["regiment_code"]))
	out.sort()
	return out


## `codes` by pack headcount, the smallest first (`smallest`) else the
## largest first; code order on ties.
static func by_size(repo: DataRepository, codes: Array, smallest: bool) -> Array:
	var out := codes.duplicate()
	out.sort_custom(func(a: String, b: String) -> bool:
		var ha := ArmySystem.headcount(repo, ArmySystem.regiment(repo, a))
		var hb := ArmySystem.headcount(repo, ArmySystem.regiment(repo, b))
		return (ha < hb if smallest else ha > hb) or (ha == hb and a < b))
	return out


## The units of the player's `n` smallest (`smallest`) or largest pack
## regiments — by the men of their units (ArmySplit: a regiment's units share
## its `parent_code`), code order on ties — in code order. The same pick as
## tools/sim_invasion.gd's defences.
static func regiment_units(repo: DataRepository, smallest: bool, n: int) -> Array:
	var men: Dictionary = {}
	var units: Dictionary = {}
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		var parent := String(r.get("parent_code", ""))
		if parent == "" or String(r.get("is_naval", "0")) == "1":
			continue
		men[parent] = int(men.get(parent, 0)) + ArmySystem.headcount(repo, r)
		if not units.has(parent):
			units[parent] = []
		(units[parent] as Array).append(String(r["regiment_code"]))
	var parents := men.keys()
	parents.sort_custom(func(a: String, b: String) -> bool:
		var ha := int(men[a])
		var hb := int(men[b])
		return (ha < hb if smallest else ha > hb) or (ha == hb and a < b))
	var out: Array = []
	for parent: String in parents.slice(0, n):
		out.append_array(units[parent])
	out.sort()
	return out


## Sends a unit of the player's to `at` (whole metres) as if its march had
## been carried out, through the engine: ordered there (ArmySystem.set_march_m:
## it leaves its camp and seat), standing on the point, then halted
## (set_garrison), so it settles as an arrival does (ArmyGround.settle: an
## empty seat of a town there, else a camp slot round it).
static func arrive(repo: DataRepository, s: GameState, code: String, at: Vector2i) -> void:
	ArmySystem.set_march_m(repo, s, code, at)
	var e: Dictionary = s.regiments[code]
	e["x_m"] = at.x
	e["y_m"] = at.y
	ArmySystem.set_garrison(repo, s, code)


## Takes the player's whole land army out of a test's way: every land unit
## leaves its seat and camp and stands by at the realm's town farthest from
## `away_from` (whole metres), so no camp round the test's ground joins its
## battles or garrisons its town; a test brings up the units it wants.
static func park_army(repo: DataRepository, s: GameState, away_from: Vector2i) -> void:
	var far := ""
	var far_d := -1.0
	for t: String in TownStores.realm_towns(repo, s):
		var d := Vector2(town_m(repo, t)).distance_to(Vector2(away_from))
		if d > far_d or (d == far_d and t < far):
			far = t
			far_d = d
	var at := town_m(repo, far)
	for c: String in s.regiments:
		if String(ArmySystem.regiment(repo, c, s).get("is_naval", "0")) != "1":
			place(repo, s, c, at, ArmySystem.ORDER_STANDBY)


## A town's point in whole metres.
static func town_m(repo: DataRepository, town: String) -> Vector2i:
	return EnemyAi.target_point_m(repo, EnemyAi.KIND_TOWN, town)


## Stands a unit (the player's or a foe) at `at` under `order`, as an order
## already carried out. A unit of the player's leaves its camp and any seat it
## held (state.town_seat); under a garrison order within the reach of a town
## the crown holds whose seat is empty, it takes the seat (ArmyGround: one
## unit per town holds it), as an arrival there does.
static func place(repo: DataRepository, s: GameState, code: String, at: Vector2i, order: String) -> void:
	var e: Dictionary = s.foes.get(code, s.regiments.get(code, {}))
	e["x_m"] = at.x
	e["y_m"] = at.y
	e["dest_x_m"] = at.x
	e["dest_y_m"] = at.y
	e["order"] = order
	if ArmySystem.is_foe(s, code) or not s.regiments.has(code):
		return
	e["camp_town"] = ""
	for t: Variant in s.town_seat.keys():
		if String(s.town_seat[t]) == code:
			s.town_seat.erase(t)
	if order != ArmySystem.ORDER_GARRISON:
		return
	var town := ArmySystem.town_at(repo, ArmySystem.metres_to_pack(repo, at))
	var k := String(ArmySystem.regiment(repo, code, s).get("kingdom_code", ""))
	if town != "" and ArmyGround.holds(repo, s, k, town) and ArmyGround.seat_of(repo, s, town) == "":
		s.town_seat[town] = code
		e["camp_town"] = town


## Every float under `v`, by path (the save holds none in the war's state).
static func floats_in(v: Variant, path: String, out: Array) -> void:
	if typeof(v) == TYPE_FLOAT:
		out.append(path)
	elif v is Dictionary:
		for k: Variant in v:
			floats_in(v[k], path + "/" + str(k), out)
	elif v is Array:
		for i in (v as Array).size():
			floats_in(v[i], path + "[%d]" % i, out)
