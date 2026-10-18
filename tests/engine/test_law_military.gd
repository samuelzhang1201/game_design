extends GutTest
const Personnel := preload("res://tests/engine/personnel_helpers.gd")
const SuiteData := preload("res://tests/suite_data.gd")
## The thirteen military laws pay their effects (spec 2026-10-08-laws-tab-design
## §2.4, §4.1, §4.2, §4.4; rows in data/realm/law_effects.csv).
##
## - A UNIT channel (morale mark, pace) is paid by each land unit on its own
##   value in force (`LawSystem.value`).
## - A REALM channel is scaled by the share of the realm's land men under the
##   value: the share a whole per mille, the line rounded ONCE — to tenths, or
##   to whole gold for the treasury, whose rows are per 1,000 men under the
##   value (root invariant 11).
## - A unit settling into a camp takes the newer of its own decree and the
##   camp's; one leaving copies what it read; a camp lost or emptied is
##   forgotten (`LawSystem.reconcile`).
##
## Men are set by hand in the roster where a share is computed, so every
## figure below is worked out here, never through LawEffects.

const EPS := 0.000001

var repo: DataRepository
var s: GameState
var realm: String


func before_all() -> void:
	RoadGraph.forget()


func after_all() -> void:
	RoadGraph.forget()
	Weather.forget()


func before_each() -> void:
	repo = SuiteData.repo()
	s = SuiteData.campaign(repo, 42)
	realm = repo.resolve_realm("player_realm")
	s.metrics["treasury"] = 5000.0
	Weather.forget()


func _land_units(state: GameState = s) -> Array:
	var out: Array = []
	for r: Dictionary in MapObjects.regiments_of(repo, realm, state):
		if String(r.get("is_naval", "0")) != "1":
			out.append(String(r["regiment_code"]))
	return out


func _put(state: GameState, key: String, law: String, value: String, id: int) -> void:
	var here: Dictionary = state.law_in_force.get(key, {})
	here[law] = {"value": value, "decree_id": id}
	state.law_in_force[key] = here


func _entry(state: GameState, key: String, law: String) -> Dictionary:
	return (state.law_in_force.get(key, {}) as Dictionary).get(law, {})


## Every land unit's men set by hand: the units of `sizes` (code -> men, all
## infantry), every other land unit none.
func _set_men(sizes: Dictionary) -> void:
	for code: String in _land_units():
		var row: Dictionary = s.army_roster[code]
		for arm: String in repo.world_table("military", "unit_types"):
			if row.has(arm):
				row[arm] = "0"
		row["infantry"] = str(int(sizes.get(code, 0)))
		assert_false(Personnel.replace(repo, s, code, int(sizes.get(code, 0))).has("error"))


## The sum of `law_effects.csv`'s `channel` rows for `law` at `value`.
func _rows_sum(law: String, value: String, channel: String) -> float:
	var sum := 0.0
	for row: Dictionary in repo.law_effects:
		if String(row["law_code"]) == law and String(row["value"]) == value and String(row["channel"]) == channel:
			sum += float(row["amount"])
	return sum


## A held town with a camp, and a land unit camped by it.
func _a_camp() -> Dictionary:
	for code: String in _land_units():
		var town := ArmyGround.camped_by(repo, s, code)
		if town != "":
			return {"town": town, "unit": code}
	return {}


## A land unit with arms not camped by `town`.
func _another_unit(town: String) -> String:
	for code: String in _land_units():
		if ArmyGround.camped_by(repo, s, code) != town \
				and ArmySystem.base_pace_km(repo, ArmySystem.regiment(repo, code, s)) > 0:
			return code
	return ""


## `code` arrives at `town` and halts there (as march_day's arrival does).
func _arrive(code: String, town: String) -> void:
	var p := ArmyGround.town_point_m(repo, town)
	var entry: Dictionary = s.regiments[code]
	entry["x_m"] = p.x
	entry["y_m"] = p.y
	entry["dest_x_m"] = p.x
	entry["dest_y_m"] = p.y
	entry["order"] = ArmySystem.ORDER_GARRISON
	entry["camp_town"] = ""
	ArmyGround.settle(repo, s, code)


func _folio_morale(code: String) -> Dictionary:
	for sec: Dictionary in WarFolio.sections(repo, s, code):
		if String(sec["key"]) == "morale":
			var out := {}
			for row: Dictionary in sec["rows"]:
				out[String(row["label"])] = String(row["text"])
			return out
	return {}


func _lines_named(lines: Array, head: String) -> Array:
	return lines.filter(func(l: Dictionary) -> bool: return String(l["reason"]).begins_with(head))


func _line_of(lines: Array, head: String, metric: String) -> Dictionary:
	for l: Dictionary in _lines_named(lines, head):
		if String(l["metric"]) == metric:
			return l
	return {}


# --- unit channels ------------------------------------------------------------

func test_a_unit_pays_the_mark_of_its_own_value() -> void:
	var units := _land_units()
	var a := String(units[0])
	var b := String(units[1])
	_put(s, LawSystem.UNIT_PREFIX + a, "plunder", "allow", 1)
	_put(s, LawSystem.UNIT_PREFIX + b, "plunder", "forbid", 1)
	# a camped unit reads the newer of its own entry and its camp's (none here)
	assert_eq(LawSystem.value(repo, s, "plunder", a), "allow")
	assert_eq(LawEffects.unit_mark(repo, s, a), 2, "allow plunder: morale mark +2")
	assert_eq(LawEffects.unit_mark(repo, s, b), 0, "forbid plunder: no mark")
	# the folio names the law's mark beside the stores' (WarFolio._morale)
	assert_eq(_folio_morale(a).get("The camp laws", ""), "+2")
	assert_false(_folio_morale(b).has("The camp laws"), "no row for no mark")
	# both start AT their stores' mark: A drifts up by its law's 2, B stays
	var step := int(repo.bal("army_morale_drift_per_month"))
	assert_gt(step, 2, "a month's drift covers the law's 2")
	var base := {}
	for code: String in [a, b]:
		var reg := ArmySystem.regiment(repo, code, s)
		var st: Dictionary = s.regiments[code]
		var score := ArmySystem.supply_score(repo, int(st["supplies"]), ArmySystem.supply_use(repo, reg, s))
		base[code] = ArmySystem.morale_mark(repo, score, ArmyGround.seated_in(repo, s, code) != "")
		st["morale"] = int(base[code])
	ArmySystem.settle_month(repo, s)
	assert_eq(int(s.regiments[a]["morale"]), mini(int(base[a]) + 2, 100), "A heads for its mark + 2")
	assert_eq(int(s.regiments[b]["morale"]), int(base[b]), "B holds its mark")


func test_a_fresh_host_carries_no_law_mark() -> void:
	# every toggle defaults off and plunder to forbid (spec §4.4, default
	# first): no default value has a unit row
	for code: String in _land_units():
		assert_eq(LawEffects.unit_mark(repo, s, code), 0, code)
		assert_eq(LawEffects.unit_pace_permille(repo, s, code), 1000, code)


func test_the_conduct_laws_add_their_marks_rounded_once() -> void:
	var laws := ["obey_command", "protect_women", "no_havoc", "no_feuds"]
	var sum := 0.0
	for law: String in laws:
		LawSystem.impose(repo, s, law, "on")
		sum += _rows_sum(law, "on", "morale_mark")
	# the rows as shipped: +1 -0.5 -1 +1 = +0.5, rounded once, half away from zero: +1
	assert_almost_eq(sum, 0.5, EPS, "the rows' sum")
	var want := int(signf(sum) * floorf(absf(sum) + 0.5))
	for code: String in _land_units():
		assert_eq(LawEffects.unit_mark(repo, s, code), want, code)


func test_pace_follows_truce_days() -> void:
	repo = SuiteData.flat_ground(SuiteData.repo())
	for key in repo.weather_odds:
		repo.weather_odds[key] = {"clear": 1, "rain": 0, "mud": 0, "snow": 0, "blizzard": 0}
	Weather.forget()
	s = SuiteData.campaign(repo, 42)
	var code := _another_unit("")
	var reg := ArmySystem.regiment(repo, code, s)
	s.regiments[code]["supplies"] = ArmySystem.max_units(repo, ArmySystem.supply_use(repo, reg, s))
	assert_eq(LawEffects.unit_pace_permille(repo, s, code), 1000, "truce days off: the pace untouched")
	var off := ArmySystem.day_step_m(repo, s, code)
	var off_km := ArmySystem.speed_km_per_day(repo, s, code)
	_put(s, LawSystem.UNIT_PREFIX + code, "truce_days", "on", 1)
	assert_eq(LawEffects.unit_pace_permille(repo, s, code), 950, "truce days on: pace -50 per mille")
	@warning_ignore("integer_division")
	assert_eq(ArmySystem.day_step_m(repo, s, code), off * 950 / 1000, "the day's metres are 950/1000 of off")
	assert_almost_eq(ArmySystem.speed_km_per_day(repo, s, code), off_km * 0.95, 0.0001, "the shown pace agrees")
	# the estimate is the march: a town some five days off
	var home: Vector2 = ArmySystem.position_of(repo, s, reg)
	var want := 5.0 * float(ArmySystem.day_step_m(repo, s, code)) / float(ArmySystem.metres_per_pack_px(repo))
	var dest := home
	for b: String in repo.burgs:
		var at := Vector2(float(repo.burgs[b]["x"]), float(repo.burgs[b]["y"]))
		if String(repo.burgs[b]["kingdom_code"]) == realm \
				and absf(at.distance_to(home) - want) < absf(dest.distance_to(home) - want):
			dest = at
	var promised := ArmySystem.march_days_between(repo, s, code, home, dest)
	ArmySystem.set_march(repo, s, code, dest)
	assert_eq(LawSystem.value(repo, s, "truce_days", code), "on", "it carries its law on the march")
	var n := ArmySystem.days_out(repo, s, code)
	assert_gt(n, 3, "a march of days")
	assert_eq(n, promised, "one figure before and after the order")
	var engine := TickEngine.new(repo)
	for day in n:
		engine.advance_day(s)
		if day < n - 1:
			assert_false(code in engine.day_arrivals, "on the road at the end of day %d" % (day + 1))
	assert_true(code in engine.day_arrivals, "it arrives as day %d ends" % n)


# --- realm channels -----------------------------------------------------------

func test_a_realm_channel_is_scaled_by_the_share_of_men() -> void:
	var units := _land_units()
	assert_gt(units.size(), 9, "enough land units")
	# eight units of 450 allow plunder (3,600 men); one of 6,400 does not; the
	# rest have none: 3,600 of 10,000 men is 360 per mille, 36%
	var sizes := {}
	for i in 8:
		sizes[units[i]] = 450
		_put(s, LawSystem.UNIT_PREFIX + String(units[i]), "plunder", "allow", 1)
	sizes[units[8]] = 6400
	_set_men(sizes)
	assert_eq(LawEffects.army_share_permille(repo, s, "plunder", "allow"), 360)
	assert_eq(LawEffects.army_share_permille(repo, s, "plunder", "forbid"), 640)
	var lines := LawEffects.month_lines(repo, s)
	# contentment -0.4 x 360/1000 = -0.144 -> -0.1; church -0.2 x 0.36 = -0.072
	# -> -0.1; legitimacy -0.1 x 0.36 = -0.036 -> 0.0, no line
	var content := _line_of(lines, "allow plunder", "peasant_contentment")
	assert_almost_eq(float(content.get("delta", 0.0)), -0.1, EPS)
	assert_eq(String(content.get("reason", "")), "allow plunder: contentment −0.1 (8 units, 36% of the host)")
	assert_almost_eq(float(_line_of(lines, "allow plunder", "church_opinion").get("delta", 0.0)), -0.1, EPS)
	assert_true(_line_of(lines, "allow plunder", "legitimacy").is_empty(), "a line rounding to zero is skipped")
	assert_eq(_lines_named(lines, "forbid plunder"), [], "forbid has no rows")


func test_the_default_rows_pay_too() -> void:
	var n := _land_units().size()
	var lines := LawEffects.month_lines(repo, s)
	# a fresh host pays only the two defaults that carry rows (spec §4.4)
	assert_eq(lines.size(), 3, "give quarter (legitimacy, church) and ransom (legitimacy)")
	assert_eq(lines.size(), _lines_named(lines, "give quarter").size() + _lines_named(lines, "ransom captives").size())
	var give := _line_of(lines, "give quarter", "legitimacy")
	assert_almost_eq(float(give.get("delta", 0.0)), 0.2, EPS, "quarter give: legitimacy +0.2 at full share")
	assert_eq(String(give.get("reason", "")), "give quarter: legitimacy +0.2 (%d units, 100%% of the host)" % n)
	assert_almost_eq(float(_line_of(lines, "give quarter", "church_opinion").get("delta", 0.0)), 0.1, EPS)
	assert_almost_eq(float(_line_of(lines, "ransom captives", "legitimacy").get("delta", 0.0)), 0.1, EPS,
		"ransom: legitimacy +0.1 at full share")


func test_the_treasury_rows_are_whole_gold() -> void:
	var units := _land_units()
	var sizes := {}
	for i in 8:
		sizes[units[i]] = 450
	sizes[units[8]] = 6650
	_set_men(sizes)
	LawSystem.impose(repo, s, "register_prisoners", "on")
	LawSystem.impose(repo, s, "wear_badges", "on")
	assert_eq(LawEffects.army_share_permille(repo, s, "register_prisoners", "on"), 1000)
	var lines := LawEffects.month_lines(repo, s)
	# 10,250 men: register -2 per 1,000 = -20.5 -> -21; badges -1 per 1,000 =
	# -10.25 -> -10 (one rounding each, half away from zero)
	var reg := _line_of(lines, "register prisoners", "treasury")
	assert_eq(float(reg.get("delta", 0.0)), -21.0)
	assert_eq(String(reg.get("reason", "")), "register prisoners: treasury −21 (%d units, 100%% of the host)" % units.size())
	assert_eq(float(_line_of(lines, "wear badges", "treasury").get("delta", 0.0)), -10.0)


func test_no_land_men_no_share() -> void:
	_set_men({})
	assert_eq(LawEffects.army_share_permille(repo, s, "quarter", "give"), 0)
	assert_eq(LawEffects.month_lines(repo, s), [], "no host, no lines")


func test_a_year_of_a_law_is_visible_against_the_drift() -> void:
	var off := SuiteData.campaign(repo, 42)
	LawSystem.impose(repo, s, "protect_church", "on")
	assert_eq(LawEffects.army_share_permille(repo, s, "protect_church", "on"), 1000, "imposed: everyone")
	assert_eq(LawEffects.army_share_permille(repo, off, "protect_church", "on"), 0, "the default is off")
	var protect := _rows_sum("protect_church", "on", "church_opinion")
	var quarter := _rows_sum("quarter", "give", "church_opinion")
	var pull := float(repo.bal("church_drift"))
	assert_almost_eq(protect, 0.3, EPS)
	assert_almost_eq(quarter, 0.1, EPS)
	assert_almost_eq(pull, 0.2, EPS)
	assert_almost_eq(float(s.metrics["church_opinion"]), 50.0, EPS)
	assert_almost_eq(float(off.metrics["church_opinion"]), 50.0, EPS)
	var engine := TickEngine.new(repo)
	for i in 12:
		engine.advance(s)
		engine.advance(off)
	# A month: the laws' lines, then the 0.2 pull toward 50 (church_drift).
	#   on:  +0.3 (protect the church) +0.1 (give quarter) = +0.4, pulled -0.2:
	#        +0.2 a month, 12 months: 50 + 2.4 = 52.4
	#   off: +0.1 (give quarter), pulled -0.1 back to 50: 50.0
	assert_almost_eq(float(s.metrics["church_opinion"]), 52.4, EPS)
	assert_almost_eq(float(off.metrics["church_opinion"]), 50.0, EPS)


# --- flags --------------------------------------------------------------------

func test_the_flags_are_readable() -> void:
	LawSystem.decree(repo, s, "plunder", "allow")
	for i in int(repo.bal("courier_max_days")) + 2:
		if s.couriers.is_empty():
			break
		CourierSystem.ride_day(repo, s)
	for code: String in _land_units():
		assert_eq(LawSystem.value(repo, s, "plunder", code), "allow", code)


# --- entering and leaving camp ------------------------------------------------

func test_a_units_entering_a_camp_takes_the_higher_decree() -> void:
	var camp := _a_camp()
	var town := String(camp["town"])
	var u := _another_unit(town)
	_put(s, LawSystem.TOWN_PREFIX + town, "plunder", "allow", 2)
	_put(s, LawSystem.UNIT_PREFIX + u, "plunder", "forbid", 1)
	_arrive(u, town)
	assert_eq(ArmyGround.camped_by(repo, s, u), town, "it camped there")
	assert_eq(_entry(s, LawSystem.UNIT_PREFIX + u, "plunder"), {"value": "allow", "decree_id": 2},
		"the camp's newer decree is its own now")
	assert_eq(LawSystem.value(repo, s, "plunder", u), "allow")


func test_an_older_town_entry_does_not_beat_a_newer_unit_entry() -> void:
	var camp := _a_camp()
	var town := String(camp["town"])
	var u := _another_unit(town)
	_put(s, LawSystem.TOWN_PREFIX + town, "plunder", "forbid", 2)
	_put(s, LawSystem.UNIT_PREFIX + u, "plunder", "allow", 3)
	_arrive(u, town)
	assert_eq(ArmyGround.camped_by(repo, s, u), town)
	assert_eq(_entry(s, LawSystem.UNIT_PREFIX + u, "plunder"), {"value": "allow", "decree_id": 3},
		"it keeps the newer order it carried")
	assert_eq(LawSystem.value(repo, s, "plunder", u), "allow", "and follows it in camp")
	assert_eq(LawSystem.value(repo, s, "plunder", String(camp["unit"])), "forbid", "the camp keeps its own")
	assert_eq(_entry(s, LawSystem.TOWN_PREFIX + town, "plunder"), {"value": "forbid", "decree_id": 2},
		"only a courier writes the camp's entry")


func test_take_seat_takes_the_higher_decree() -> void:
	var camp := _a_camp()
	var town := String(camp["town"])
	var u := _another_unit(town)
	_arrive(u, town)
	_put(s, LawSystem.TOWN_PREFIX + town, "obey_command", "off", 4)
	_put(s, LawSystem.UNIT_PREFIX + u, "obey_command", "on", 1)
	assert_true(ArmyGround.take_seat(repo, s, u))
	assert_eq(_entry(s, LawSystem.UNIT_PREFIX + u, "obey_command"), {"value": "off", "decree_id": 4})


func test_leaving_a_camp_copies_what_it_read() -> void:
	var camp := _a_camp()
	var town := String(camp["town"])
	var c := String(camp["unit"])
	_put(s, LawSystem.TOWN_PREFIX + town, "plunder", "allow", 2)
	_put(s, LawSystem.TOWN_PREFIX + town, "truce_days", "on", 1)
	_put(s, LawSystem.UNIT_PREFIX + c, "truce_days", "off", 3)
	assert_eq(LawSystem.value(repo, s, "plunder", c), "allow", "in camp it reads the camp")
	var reg := ArmySystem.regiment(repo, c, s)
	var home: Vector2 = ArmySystem.position_of(repo, s, reg)
	ArmySystem.set_march(repo, s, c, home + Vector2(30.0, 0.0))
	assert_eq(ArmySystem.order_of(repo, s, c), ArmySystem.ORDER_MARCH)
	assert_eq(ArmyGround.camped_by(repo, s, c), "", "on the march")
	assert_eq(_entry(s, LawSystem.UNIT_PREFIX + c, "plunder"), {"value": "allow", "decree_id": 2},
		"it took the camp's plunder law with it")
	assert_eq(_entry(s, LawSystem.UNIT_PREFIX + c, "truce_days"), {"value": "off", "decree_id": 3},
		"and kept its own newer truce")
	assert_eq(LawSystem.value(repo, s, "plunder", c), "allow")


# --- reconcile ----------------------------------------------------------------

func _another_kingdom() -> String:
	var codes: Array = repo.kingdoms.keys()
	codes.sort()
	for k: String in codes:
		if k != realm:
			return k
	return ""


func test_reconcile_forgets_a_lost_province_and_a_campless_town() -> void:
	var held := MapOwnership.provinces_of(repo, s, realm)
	var camp := _a_camp()
	var town := String(camp["town"])
	var c := String(camp["unit"])
	var province := String(repo.burgs[town]["province_code"])
	# a province with no camp, decreed a tax of 8
	var other := ""
	for p: String in held:
		if p != province:
			other = p
			break
	_put(s, LawSystem.PROVINCE_PREFIX + other, "tax_rate", "8", 1)
	# a held town with no camp at all
	var empty := ""
	var burgs: Array = repo.burgs.keys()
	burgs.sort()
	for b: String in burgs:
		if ArmyGround.holds(repo, s, realm, b) and not LawSystem._has_camp(repo, s, b):
			empty = b
			break
	assert_ne(empty, "", "a held town with no camp")
	_put(s, LawSystem.TOWN_PREFIX + empty, "plunder", "allow", 1)
	_put(s, LawSystem.TOWN_PREFIX + town, "plunder", "allow", 1)
	LawSystem.reconcile(repo, s)
	assert_false(s.law_in_force.has(LawSystem.TOWN_PREFIX + empty), "a campless town is forgotten")
	assert_true(s.law_in_force.has(LawSystem.TOWN_PREFIX + town), "a camp keeps its entry")
	assert_true(s.law_in_force.has(LawSystem.PROVINCE_PREFIX + other), "a held province keeps its entry")
	# the province is lost, then retaken: it reads the default (R13)
	MapOwnership.set_owner(repo, s, other, _another_kingdom(), "test: lost")
	LawSystem.reconcile(repo, s)
	assert_false(s.law_in_force.has(LawSystem.PROVINCE_PREFIX + other), "a lost province is forgotten")
	MapOwnership.set_owner(repo, s, other, realm, "test: retaken")
	assert_eq(LawSystem.value(repo, s, "tax_rate", other), String(repo.laws["tax_rate"]["default"]))
	# the camp's town is lost: its units keep what they read, the town is forgotten
	MapOwnership.set_owner(repo, s, province, _another_kingdom(), "test: the camp's town lost")
	LawSystem.reconcile(repo, s)
	assert_false(s.law_in_force.has(LawSystem.TOWN_PREFIX + town), "a lost town is forgotten")
	assert_eq(_entry(s, LawSystem.UNIT_PREFIX + c, "plunder"), {"value": "allow", "decree_id": 1},
		"its camp's units keep the law they followed")


func test_reconcile_drops_a_gone_units_entry_and_gives_none_to_a_foreign_one() -> void:
	_put(s, LawSystem.UNIT_PREFIX + "no_such_unit", "plunder", "allow", 1)
	var own: String = _land_units()[0]
	_put(s, LawSystem.UNIT_PREFIX + own, "plunder", "allow", 1)
	# another kingdom's column with a state entry (as an invader's), told to
	# camp round a held town of ours
	var foreign := ""
	var kingdoms: Array = repo.kingdoms.keys()
	kingdoms.sort()
	for k: String in kingdoms:
		if k == realm or foreign != "":
			continue
		for reg: Dictionary in MapObjects.regiments_of(repo, k, s):
			if String(reg.get("is_naval", "0")) != "1":
				foreign = String(reg["regiment_code"])
				s.regiments[foreign] = ArmySystem.starting_state(repo, reg)
				break
	assert_ne(foreign, "", "another kingdom has a land column")
	var empty := ""
	var burgs: Array = repo.burgs.keys()
	burgs.sort()
	for b: String in burgs:
		if ArmyGround.holds(repo, s, realm, b) and not LawSystem._has_camp(repo, s, b):
			empty = b
			break
	assert_ne(empty, "", "a held town with no camp of ours")
	_put(s, LawSystem.TOWN_PREFIX + empty, "plunder", "allow", 1)
	s.regiments[foreign]["camp_town"] = empty
	LawSystem.reconcile(repo, s)
	assert_false(s.law_in_force.has(LawSystem.UNIT_PREFIX + "no_such_unit"), "a gone unit's entry goes")
	assert_true(s.law_in_force.has(LawSystem.UNIT_PREFIX + own), "the realm's unit keeps its own")
	assert_false(s.law_in_force.has(LawSystem.UNIT_PREFIX + foreign), "another kingdom's column takes no law")
	assert_false(s.law_in_force.has(LawSystem.TOWN_PREFIX + empty), "the campless town is forgotten")
	_put(s, LawSystem.UNIT_PREFIX + foreign, "plunder", "allow", 1)
	LawSystem.reconcile(repo, s)
	assert_false(s.law_in_force.has(LawSystem.UNIT_PREFIX + foreign), "nor keeps one it was given")


func test_a_camp_whose_units_all_carry_the_decree_is_told() -> void:
	var camp := _a_camp()
	var town := String(camp["town"])
	var key := LawSystem.TOWN_PREFIX + town
	LawSystem.decree(repo, s, "plunder", "allow")
	var id := int(s.law_decree["plunder"]["decree_id"])
	s.couriers = []
	assert_true(key in (LawSystem.delivery(repo, s, "plunder")["missing"] as Array), "no courier reached it")
	var here: Array = []
	for code: String in _land_units():
		if ArmyGround.camped_by(repo, s, code) == town:
			here.append(code)
	for code: String in here:
		_put(s, LawSystem.UNIT_PREFIX + code, "plunder", "allow", id)
	var d := LawSystem.delivery(repo, s, "plunder")
	assert_false(key in (d["missing"] as Array), "every unit camped there carries the decree: told")
	assert_gt(here.size(), 0, "the camp has units")
	if here.size() > 0:
		s.law_in_force[LawSystem.UNIT_PREFIX + String(here[0])]["plunder"]["decree_id"] = id - 1
		assert_true(key in (LawSystem.delivery(repo, s, "plunder")["missing"] as Array),
			"one unit on an older decree: still missing")


func test_a_day_reconciles_the_laws() -> void:
	var held := MapOwnership.provinces_of(repo, s, realm)
	var p := String(held[held.size() - 1])
	MapOwnership.set_owner(repo, s, p, _another_kingdom(), "test: lost")
	TickEngine.new(repo).advance_day(s)
	assert_false(s.law_in_force.has(LawSystem.PROVINCE_PREFIX + p), "the day's end forgot it")


# --- the screen's words ------------------------------------------------------

func test_the_summary_spells_the_rows() -> void:
	assert_eq(LawEffects.summary(repo, "plunder", "allow"),
		"Morale +2 · Contentment −0.4/month · Church −0.2/month · Legitimacy −0.1/month · A standing order")
	assert_eq(LawEffects.summary(repo, "plunder", "forbid"), "")
	assert_eq(LawEffects.summary(repo, "register_prisoners", "on"),
		"Treasury −2/month per 1,000 men · Legitimacy +0.1/month · A standing order")
	assert_eq(LawEffects.summary(repo, "truce_days", "on"), "Church +0.3/month · Pace −50‰ · Chivalry +1/month")
	assert_eq(LawEffects.summary(repo, "justice_severity", "4"),
		"Unrest −2 per point, once · Contentment −2 per point, once")
