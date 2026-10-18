extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Play := preload("res://tests/invasion_play.gd")
## Raiding and spoils (spec 2026-10-07-enemy-ai-and-battle-design §5.3): a host
## in RAID standing at its target takes raid_plunder_permille of the manor's
## MONTH (whole gold, ManorEconomy's own line) a thirtieth a day, up to that
## share of the month; the take is its plunder, part of it food for its
## columns (raid_supply_permille, at a supply unit's gold, never past what
## they can carry), and a ledger line with its reason off the controlling
## purse (Ruling 4); the first take marks the manor Raided (a public hazard).
## A host beaten by the crown hands battle_spoils_permille of its plunder to the
## strategic stores, once. A host that has stripped its manor bare chooses
## again. Hosts are placed by hand for the rules and played on the day loop
## for the whole of it.

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()
	Weather.forget()


## --- helpers ----------------------------------------------------------------

func _host(role: String) -> String:
	for h: Dictionary in repo.raid_hosts:
		if String(h["role"]) == role:
			return String(h["host_code"])
	return ""


## The month a manor yields, in whole gold: its tax and its goods' worth.
func _month(s: GameState, cell: int) -> int:
	return ManorBars.worth_of(ManorEconomy.line_of(repo, s, cell, s.tick))


## A manor (no town) of the player's realm worth at least `least` gold a
## month, in a province the crown controls or not; -1 for none. Far from every
## player regiment when `far_km` > 0.
func _manor(s: GameState, controlled: bool, least: int, far_km := 0.0) -> int:
	var provs: Array = MapOwnership.provinces_of(repo, s, repo.resolve_realm("player_realm"))
	provs.sort()
	for prov: String in provs:
		if MapManors.crown_controls(repo, s, prov) != controlled:
			continue
		var cells: Array = MapManors.manors_of_province(repo, prov, s)
		cells.sort()
		for cell: int in cells:
			if MapManors.burg_of(repo, cell) != "" or _month(s, cell) < least:
				continue
			if far_km > 0.0 and _near_mine(s, EnemyAi.target_point_m(repo, "manor", str(cell)), far_km):
				continue
			return cell
	return -1


func _near_mine(s: GameState, at: Vector2i, km: float) -> bool:
	var r := int(km * 1000.0)
	for c: Variant in s.regiments:
		var e: Dictionary = s.regiments[c]
		var p := Vector2i(int(e.get("x_m", 0)), int(e.get("y_m", 0)))
		if not e.has("x_m"):
			p = ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, String(c))))
		if (p - at).length_squared() <= r * r:
			return true
	return false


func _place(s: GameState, code: String, at: Vector2i, order: String) -> void:
	var e: Dictionary = s.foes.get(code, s.regiments.get(code, {}))
	e["x_m"] = at.x
	e["y_m"] = at.y
	e["dest_x_m"] = at.x
	e["dest_y_m"] = at.y
	e["order"] = order


## `host` in RAID on manor `cell`, every column of it standing on the manor.
func _raid(s: GameState, host: String, cell: int) -> void:
	var at := EnemyAi.target_point_m(repo, "manor", str(cell))
	for c: String in EnemyAi.regiments_of(s, host):
		_place(s, c, at, ArmySystem.ORDER_GARRISON)
	var mind: Dictionary = s.ai_hosts[host]
	mind["mode"] = "RAID"
	mind["target_kind"] = "manor"
	mind["target_id"] = str(cell)


func _supplies(s: GameState, host: String) -> int:
	var n := 0
	for c: String in EnemyAi.regiments_of(s, host):
		n += int(s.foes[c]["supplies"])
	return n


func _of(events: Array, kind: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return String(e.get("kind", "")) == kind)


func _modes(events: Array, host: String, mode: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool:
		return String(e.get("type", "")) == "host_mode" and String(e["host"]) == host and String(e["mode"]) == mode)


func _last_log(s: GameState) -> Dictionary:
	return {} if s.world_log.is_empty() else s.world_log[s.world_log.size() - 1]


## --- the take (whole gold, capped) ---------------------------------------------

func test_daily_take_is_whole_gold_and_capped() -> void:
	# hand-computed: month 3000, raid_plunder_permille 600 -> 3000 x 600 / 1000
	# = 1800 over the month, 1800 / 30 = 60 a day; after 30 days nothing is left
	var taken := 0
	for d in 30:
		var t := RaidSystem.take_on(3000, 600, d, taken)
		assert_eq(t, 60, "day %d takes 60" % (d + 1))
		taken += t
	assert_eq(taken, 1800, "the month's share, whole")
	assert_eq(RaidSystem.take_on(3000, 600, 30, taken), 0, "capped: the 31st day takes nothing")
	assert_eq(RaidSystem.cap_of(3000, 600), 1800)
	# a month that does not divide: 70 x 600 / 1000 = 42 over thirty days, a
	# day 1 or 2 (70 x 600 x n / 30000 = 1.4 n, rounded down on the running sum)
	taken = 0
	for d in 30:
		var t := RaidSystem.take_on(70, 600, d, taken)
		assert_true(t == 1 or t == 2, "whole gold a day: %d" % t)
		taken += t
	assert_eq(taken, 42, "the remainders carried: the sum is the share exactly")
	assert_eq(RaidSystem.take_on(70, 600, 30, taken), 0)


func test_the_take_reads_the_manors_own_month_on_the_campaign() -> void:
	repo.balance["raid_plunder_permille"] = 600.0
	var s := SuiteData.campaign(repo, 11)
	var h := _host("raider")
	var cell := _manor(s, false, 100)
	assert_gt(cell, 0, "the realm has a manor worth raiding")
	_raid(s, h, cell)
	var month := _month(s, cell)
	@warning_ignore("integer_division")
	var cap := month * 600 / 1000
	var total := 0
	for d in 30:
		var t := RaidSystem.day_take(repo, s, h)
		@warning_ignore("integer_division")
		var want := month * 600 * (d + 1) / 30000 - month * 600 * d / 30000
		assert_eq(t, want, "day %d: month %d x 600 / 30000, the running sum rounded down" % [d + 1, month])
		total += t
	assert_eq(total, cap, "thirty days take the share of the month: %d" % cap)
	assert_eq(RaidSystem.day_take(repo, s, h), 0, "and no more")
	assert_eq(typeof(s.ai_hosts[h]["plunder"]), TYPE_INT, "plunder is whole")


func test_no_take_off_the_target_or_in_a_battle_or_out_of_raid() -> void:
	var s := SuiteData.campaign(repo, 11)
	var h := _host("raider")
	var cell := _manor(s, false, 100)
	_raid(s, h, cell)
	var far := EnemyAi.target_point_m(repo, "manor", str(cell)) + Vector2i(40_000, 0)
	for c: String in EnemyAi.regiments_of(s, h):
		_place(s, c, far, ArmySystem.ORDER_GARRISON)
	assert_eq(RaidSystem.day_take(repo, s, h), 0, "no column at the manor: nothing taken")
	_raid(s, h, cell)
	s.ai_hosts[h]["mode"] = "ADVANCE"
	assert_eq(RaidSystem.day_take(repo, s, h), 0, "only a raiding host takes")
	_raid(s, h, cell)
	var c0: String = EnemyAi.regiments_of(s, h)[0]
	s.battles.append({"id": 99, "att": [c0], "def": [], "start_day": 1, "rounds": 1,
		"place_x_m": 0, "place_y_m": 0, "town": ""})
	assert_eq(RaidSystem.day_take(repo, s, h), 0, "a host fighting takes nothing")
	s.battles.clear()
	s.foes[c0]["disengaging"] = 1
	assert_eq(RaidSystem.day_take(repo, s, h), 0, "nor one falling back beaten")
	s.foes[c0]["disengaging"] = 0
	assert_gt(RaidSystem.day_take(repo, s, h), 0, "at the manor, raiding, free: it takes")


## --- plunder feeds the host ------------------------------------------------------

func test_plunder_feeds_the_host() -> void:
	# hand-computed: a take of 60 gold, raid_supply_permille 300 -> 18 gold of
	# it is food; at a unit's gold of army_supply_gold_permille 100 (0.1 gold)
	# that is 60 x 300 / 100 = 180 units, worth 180 x 100 / 1000 = 18 gold
	assert_eq(RaidSystem.food_units(60, 300, 100), 180)
	assert_eq(RaidSystem.food_gold(180, 100), 18)
	assert_eq(RaidSystem.food_gold(181, 100), 19, "a part of a gold is a whole gold spent")
	repo.balance["raid_plunder_permille"] = 600.0
	repo.balance["raid_supply_permille"] = 300.0
	repo.balance["army_supply_gold_permille"] = 100.0
	var s := SuiteData.campaign(repo, 11)
	var h := _host("raider")
	var cell := _manor(s, false, 200)
	assert_gt(cell, 0)
	_raid(s, h, cell)
	for c: String in EnemyAi.regiments_of(s, h):
		s.foes[c]["supplies"] = 0
	var t := RaidSystem.day_take(repo, s, h)
	assert_gt(t, 0)
	@warning_ignore("integer_division")
	var units := t * 300 / 100
	@warning_ignore("integer_division")
	var food := (units * 100 + 999) / 1000
	assert_eq(_supplies(s, h), units, "the take's food share in units: %d" % units)
	assert_eq(int(s.ai_hosts[h]["plunder"]), t - food, "the rest is plunder: %d - %d" % [t, food])
	# the columns carry no more than army_supply_max_days: one unit of room each
	var room := 0
	for c: String in EnemyAi.regiments_of(s, h):
		var use := ArmySystem.supply_use(repo, ArmySystem.regiment(repo, c), s)
		s.foes[c]["supplies"] = ArmySystem.max_units(repo, use) - 1
		room += 1
	var before := _supplies(s, h)
	var plunder := int(s.ai_hosts[h]["plunder"])
	var t2 := RaidSystem.day_take(repo, s, h)
	assert_gt(t2, 0)
	assert_eq(_supplies(s, h), before + room, "filled to the carry cap and no further")
	for c: String in EnemyAi.regiments_of(s, h):
		var use := ArmySystem.supply_use(repo, ArmySystem.regiment(repo, c), s)
		assert_lte(int(s.foes[c]["supplies"]), ArmySystem.max_units(repo, use), c + " within its carry")
	@warning_ignore("integer_division")
	var food2 := (room * 100 + 999) / 1000
	assert_eq(int(s.ai_hosts[h]["plunder"]), plunder + t2 - food2, "what is not carried as food stays plunder")


## --- the crown's books (Ruling 4) ------------------------------------------------

func test_the_take_is_a_ledger_line_off_the_controlling_purse() -> void:
	repo.balance["raid_plunder_permille"] = 600.0
	repo.balance["crown_share_permille"] = 200.0
	var s := SuiteData.campaign(repo, 11)
	var h := _host("raider")
	# a manor of the lord's own province: the lord's purse bears the whole take
	var own := _manor(s, true, 100)
	assert_gt(own, 0, "the crown controls a province with a manor worth raiding")
	_raid(s, h, own)
	var lord := float(s.metrics["lord_gold"])
	var treasury := float(s.metrics["treasury"])
	var t := RaidSystem.day_take(repo, s, h)
	assert_gt(t, 0)
	assert_eq(float(s.metrics["lord_gold"]), lord - float(t), "the lord's purse loses the take")
	assert_eq(float(s.metrics["treasury"]), treasury, "the treasury is untouched")
	var line := _last_log(s)
	assert_eq(String(line.get("path", "")), "metrics.lord_gold")
	assert_eq(float(line.get("delta", 0.0)), -float(t))
	var label := MapManors.label_of(repo, own)
	assert_eq(String(line.get("reason", "")), "raided by %s: %s" % [SiegeSystem.host_label(repo, h), label],
		"the line carries its reason")
	# a manor of another house's province: the crown loses its share of the take,
	# on the running sum (hand: 200 per mille of the total, rounded down once)
	var s2 := SuiteData.campaign(repo, 11)
	var other := _manor(s2, false, 100)
	_raid(s2, h, other)
	var t0 := float(s2.metrics["treasury"])
	var l0 := float(s2.metrics["lord_gold"])
	var total := 0
	for d in 5:
		total += RaidSystem.day_take(repo, s2, h)
	@warning_ignore("integer_division")
	assert_eq(float(s2.metrics["treasury"]), t0 - float(total * 200 / 1000),
		"the treasury loses the crown's share of %d" % total)
	assert_eq(float(s2.metrics["lord_gold"]), l0, "the lord's purse is untouched")


## --- the hazard ---------------------------------------------------------------------

func test_hazard_added_once_and_known() -> void:
	var s := SuiteData.campaign(repo, 11)
	var h := _host("raider")
	var cell := _manor(s, false, 100)
	_raid(s, h, cell)
	var before: Array = s.hazards.keys()
	RaidSystem.day_take(repo, s, h)
	var added: Array = s.hazards.keys().filter(func(id: String) -> bool: return not id in before)
	assert_eq(added.size(), 1, "the first take marks the manor")
	if added.is_empty():
		return
	var hid := String(added[0])
	assert_true(hid.contains(str(cell)), "the hazard's id names the manor's cell: " + hid)
	var hz: Dictionary = s.hazards[hid]
	assert_eq(String(hz["kind"]), "Raided")
	assert_eq(hz["cells"], [cell])
	assert_eq(int(hz["start"]), s.tick)
	assert_eq(int(hz["end"]), s.tick + int(Hazards.kind_of(repo, "Raided")["months"]))
	assert_true(Hazards.is_active(s, hid), "in force now")
	assert_true(Hazards.known(repo, s, hid), "the crown knows its land is raided")
	assert_true(bool(Hazards.kind_of(repo, "Raided")["public"]), "a public kind")
	var rev := s.hazards_rev
	RaidSystem.day_take(repo, s, h)
	RaidSystem.day_take(repo, s, h)
	assert_eq(s.hazards.size(), before.size() + 1, "once: the next days add none")
	assert_eq(s.hazards_rev, rev, "and touch none")


func test_raided_kind_is_a_row_of_the_table() -> void:
	var k := Hazards.kind_of(repo, "Raided")
	assert_false(k.is_empty(), "data/army/hazard_kinds.csv has a Raided row")
	assert_gt(int(k.get("months", 0)), 0, "it ends of itself")
	assert_eq(int(k.get("wounds_permille", -1)), 0)
	assert_lt(int(k.get("morale", 0)), 0, "it weighs on the men who stand in it")
	assert_gt(int(k.get("supply_loss_permille", 0)), 0, "a supply line through it loses a share")
	assert_lt(int(k.get("pace_permille", 1000)), 1000, "a march through it is slower")


## --- spoils ---------------------------------------------------------------------------

func test_spoils_into_strategic_with_reason() -> void:
	# hand-computed: plunder 1800, battle_spoils_permille 500 -> 900
	repo.balance["battle_spoils_permille"] = 500.0
	var s := SuiteData.campaign(repo, 11)
	var h := _host("raider")
	s.ai_hosts[h]["plunder"] = 1800
	var strategic := float(s.metrics["strategic"])
	var got := RaidSystem.spoils(repo, s, h, repo.resolve_realm("player_realm"), "Foxbridge")
	assert_eq(got, 900)
	assert_eq(float(s.metrics["strategic"]), strategic + 900.0, "into the crown's strategic stores")
	var line := _last_log(s)
	assert_eq(String(line.get("path", "")), "metrics.strategic")
	assert_eq(String(line.get("reason", "")), "spoils: %s routed at Foxbridge" % SiegeSystem.host_label(repo, h))
	assert_eq(int(s.ai_hosts[h]["plunder"]), 0, "the plunder is gone once paid out")
	assert_eq(RaidSystem.spoils(repo, s, h, repo.resolve_realm("player_realm"), "Foxbridge"), 0, "never twice")
	assert_eq(float(s.metrics["strategic"]), strategic + 900.0)
	s.ai_hosts[h]["plunder"] = 1800
	assert_eq(RaidSystem.spoils(repo, s, h, repo.resolve_realm("raider_realm"), "Foxbridge"), 0,
		"no spoils to a winner that is not the crown")


## A field battle by hand: the raider host's columns stand on the player's first
## regiment, the outcome table forced to the attacker's rout (the foes attack:
## neither side marched). Returns the day's battle events.
func _rout_the_raiders(s: GameState, h: String) -> Array:
	var keep: Dictionary = {}
	for r: Dictionary in repo.battle_outcomes:
		if String(r["tier"]) == "attacker_routed":
			keep = r.duplicate()
	keep["eff_min"] = 0
	keep["eff_max"] = 1000
	repo.battle_outcomes.clear()
	repo.battle_outcomes.append(keep)
	var mine := String(Play.land_regiments(repo, 400)[0])
	var at := Vector2i(int(s.regiments[mine]["x_m"]), int(s.regiments[mine]["y_m"]))
	# the rest of the army out of the way: a camp round the spot would join
	Play.park_army(repo, s, at)
	Play.place(repo, s, mine, at, ArmySystem.ORDER_STANDBY)
	for c: String in EnemyAi.regiments_of(s, h):
		_place(s, c, at + Vector2i(500, 0), ArmySystem.ORDER_GARRISON)
	s.ai_hosts[h]["mode"] = "RAID"
	for c: String in EnemyAi.regiments_of(s, h):
		s.foes[c]["battle_plan"] = "attack"
	var events := BattleSystem.settle_day(repo, s)
	# Spoils pass only after this routed host physically yields the field.
	for c: String in EnemyAi.regiments_of(s, h):
		_place(s, c, at + Vector2i(100000, 0), ArmySystem.ORDER_STANDBY)
	s.day += 1
	events.append_array(BattleSystem.settle_day(repo, s))
	return events


func test_routed_raider_pays_spoils_once_on_the_day() -> void:
	repo.balance["battle_spoils_permille"] = 500.0
	var s := SuiteData.campaign(repo, 11)
	var h := _host("raider")
	var events := _rout_the_raiders(s, h)
	var ends := events.filter(func(e: Dictionary) -> bool: return String(e.get("kind", "")) == "end")
	assert_eq(ends.size(), 1, "the battle is fought out")
	s.ai_hosts[h]["plunder"] = 1800
	var strategic := float(s.metrics["strategic"])
	var raid := RaidSystem.settle_day(repo, s, events)
	var paid := _of(raid, "raid_spoils")
	assert_eq(paid.size(), 1, "the beaten host's spoils, told")
	if paid.is_empty():
		return
	assert_eq(int(paid[0]["spoils"]), 900, "1800 x 500 / 1000")
	assert_eq(float(s.metrics["strategic"]), strategic + 900.0)
	var place := BattleSystem.place_label(repo, s, ends[0])
	assert_eq(String(_last_log(s).get("reason", "")), "spoils: %s routed at %s" % [SiegeSystem.host_label(repo, h), place])
	assert_eq(int(s.ai_hosts[h]["plunder"]), 0)
	var again := RaidSystem.settle_day(repo, s, events)
	assert_eq(_of(again, "raid_spoils").size(), 0, "the same defeat pays once")
	assert_eq(float(s.metrics["strategic"]), strategic + 900.0)


func test_routed_raider_with_no_plunder_yields_nothing() -> void:
	var s := SuiteData.campaign(repo, 11)
	var h := _host("raider")
	var events := _rout_the_raiders(s, h)
	s.ai_hosts[h]["plunder"] = 0
	var strategic := float(s.metrics["strategic"])
	var logged := s.world_log.size()
	var raid := RaidSystem.settle_day(repo, s, events)
	assert_eq(_of(raid, "raid_spoils").size(), 0, "nothing taken, nothing to give back")
	assert_eq(float(s.metrics["strategic"]), strategic)
	assert_eq(s.world_log.size(), logged, "no empty ledger line")


## --- a stripped manor ------------------------------------------------------------------

func test_a_host_that_stripped_its_manor_chooses_again() -> void:
	repo.balance["raid_plunder_permille"] = 600.0
	var s := SuiteData.campaign(repo, 11)
	var h := _host("raider")
	var cell := _manor(s, false, 100)
	_raid(s, h, cell)
	for d in 30:
		RaidSystem.day_take(repo, s, h)
	assert_true(RaidSystem.stripped(repo, s, cell), "thirty days take the manor's share")
	var events := RaidSystem.settle_day(repo, s, [])
	assert_eq(_modes(events, h, "ADVANCE").size(), 1, "it sets out again (a host_mode event)")
	var mind: Dictionary = s.ai_hosts[h]
	assert_eq(String(mind["mode"]), "ADVANCE")
	assert_eq(String(mind["target_id"]), "", "the stripped manor is dropped")
	assert_eq(int(mind["think_day"]), 0, "it chooses at the next thought")
	s.day += 1
	EnemyAi.think(repo, s, h)
	assert_ne(String(s.ai_hosts[h]["target_id"]), str(cell), "never the manor it stripped")
	for c: Dictionary in EnemyAi.candidates(repo, s, h):
		assert_ne(int(c["cell"]), cell, "a stripped manor is no candidate")


## --- determinism ----------------------------------------------------------------------

func test_raid_is_deterministic_and_draws_no_random_number() -> void:
	var a := SuiteData.campaign(repo, 11)
	var h := _host("raider")
	var cell := _manor(a, false, 100)
	_raid(a, h, cell)
	var b := GameState.from_dict(a.to_dict())
	var rng := a.rng.to_dict()
	var ea: Array = []
	var eb: Array = []
	for d in 6:
		ea.append_array(RaidSystem.settle_day(repo, a, []))
		eb.append_array(RaidSystem.settle_day(repo, b, []))
		a.day += 1
		b.day += 1
	assert_eq(a.rng.to_dict(), rng, "GameState.rng untouched")
	assert_eq(ea, eb, "the same events")
	assert_eq(SaveLoad.state_hash(a), SaveLoad.state_hash(b), "the same state")
	assert_gt(int(a.ai_hosts[h]["plunder"]), 0, "it raided")
	var c := GameState.from_dict(a.to_dict())
	assert_eq(c.ai_hosts[h], a.ai_hosts[h], "the raid's record survives the save")


## --- the day loop ----------------------------------------------------------------------

func test_a_raid_on_the_day_loop_is_told_in_the_field_report() -> void:
	var engine := TickEngine.new(repo)
	var s := SuiteData.campaign(repo, 11)
	engine.advance(s)
	var h := _host("raider")
	var cell := _manor(s, false, 100, 40.0)
	assert_gt(cell, 0, "a manor out of every regiment's way")
	_raid(s, h, cell)
	Play.day(engine, s, true)
	assert_eq(_of(engine.day_raid, "raid_begin").size(), 1, "the raid begins: TickEngine.day_raid")
	assert_gt(int(s.ai_hosts[h]["plunder"]) + _supplies(s, h), 0, "it took something")
	var letters: Array = s.missives.filter(func(m: Dictionary) -> bool: return String(m["kind"]) == "battle")
	assert_eq(letters.size(), 1, "one field report")
	if letters.is_empty():
		return
	var text := ""
	for f: Dictionary in letters[0]["facts"]:
		text += String(f.get("text", "")) + "\n"
	assert_true(text.contains(MapManors.label_of(repo, cell)), "it names the manor: " + text)
	assert_false(text.contains("[missing template"), text)
	assert_false(text.contains("{"), "every slot filled: " + text)
	assert_true(text.contains(repo.realm_label("raider_realm")), "the raider realm through its slot")
	Play.day(engine, s, true)
	assert_eq(_of(engine.day_raid, "raid_begin").size(), 0, "told once")


func test_raid_templates_spell_no_kingdom() -> void:
	var raw := FileAccess.get_file_as_string("res://data/council/templates.csv")
	var found := 0
	for line: String in raw.split("\n"):
		if line.begins_with("raid_begin,") or line.begins_with("raid_spoils,"):
			found += 1
			assert_true(line.contains("_realm}"), "a realm by its slot: " + line)
			for k: Variant in repo.kingdoms:
				var label := String((repo.kingdoms[k] as Dictionary).get("label", ""))
				if label != "":
					assert_false(line.contains(label), "a template names no kingdom: " + line)
	assert_eq(found, 2, "raid_begin and raid_spoils are rows of templates.csv")


## --- the tutorial, no orders (the T8 finding: every host went home hungry
## about day 33) ---------------------------------------------------------------------

## The bound is four months (it was three before the unit clearance, spec
## 2026-10-14: the hosts no longer share one stacked point, a raid on a manor
## runs its own thirty days and the town falls near day 99): a host whose last manor is stripped may come on
## a town the crown's camp holds (its garrison, ArmyGround.garrison_town) and
## sit down to a siege on what it carries until hunger turns it home.
func test_raiding_keeps_a_host_in_the_field_but_not_for_ever() -> void:
	var engine := TickEngine.new(repo)
	var s := SuiteData.campaign(repo, 11)
	engine.advance(s)
	var raiding_late := ""
	var home_by := -1
	var days_played := 0
	while s.absolute_day() <= 120:
		days_played += 1
		assert_lte(days_played, 121, "the day loop makes bounded progress")
		if days_played > 121:
			return
		var today := s.absolute_day()
		Play.day(engine, s, true)
		for h: String in EnemyAi.host_codes(s):
			var m: Dictionary = s.ai_hosts[h]
			if today > 33 and String(m["mode"]) == "RAID" and int(m["plunder"]) > 0 and raiding_late == "":
				raiding_late = h
		# done: turned for home, or holding a town it took (HOLD never thinks
		# again; on the pack's real roads, spec 2026-10-10-march-slope-detour,
		# the raiders come on Castleton and take it)
		var all_home := true
		for h: String in EnemyAi.host_codes(s):
			all_home = all_home and String(s.ai_hosts[h]["mode"]) in EnemyAi.HOMEWARD + [EnemyAi.MODE_HOLD]
		if all_home and home_by < 0:
			home_by = today
	assert_ne(raiding_late, "", "plunder feeds a raiding host: one still raids after day 33")
	assert_gt(home_by, 33, "the invasion outlasts the hosts' own stores")
	assert_true(home_by > 0 and home_by <= 120, "and every host has turned for home or holds what it took by day 120 (%d)" % home_by)
	gut.p("raiding past day 33: %s; every host homeward from day %d" % [raiding_late, home_by])


## --- a town target (Ruling 5: an open town is raided like a manor) ----------------

## A town of the player's realm no regiment of his garrisons; "" for none.
func _open_town(s: GameState) -> String:
	var player := repo.resolve_realm("player_realm")
	var codes: Array = repo.burgs.keys()
	codes.sort()
	for t: Variant in codes:
		var b: Dictionary = repo.burgs[t]
		if MapOwnership.owner_of(repo, s, String(b.get("province_code", ""))) != player:
			continue
		var cell := EnemyAi.target_cell(repo, s, "town", String(t))
		if cell < 0 or not EnemyAi.garrison_of(repo, s, String(t)).is_empty() or _month(s, cell) < 100:
			continue
		return String(t)
	return ""


func test_a_town_is_raided_through_its_own_manor_from_inside_its_reach() -> void:
	# battle_contact_km 0.5 so only the town's reach (army_town_reach.csv, at
	# least 1 km) lets the column in: SiegeSystem.at_town is the branch tested
	repo.balance["battle_contact_km"] = 0.5
	repo.balance["raid_plunder_permille"] = 600.0
	repo.balance["raid_supply_permille"] = 0.0
	repo.balance["crown_share_permille"] = 200.0
	var s := SuiteData.campaign(repo, 11)
	var h := _host("raider")
	var town := _open_town(s)
	assert_ne(town, "", "the realm has an open town worth raiding")
	var cell := EnemyAi.target_cell(repo, s, "town", town)
	var reach_km := float(repo.army_town_reach.get(String((repo.burgs[town] as Dictionary).get("group", "")), 0.0))
	assert_gt(reach_km, 0.5, "the town's reach is wider than the contact distance set here")
	var at := EnemyAi.target_point_m(repo, "town", town) + Vector2i(int(reach_km * 1000.0) - 100, 0)
	for c: String in EnemyAi.regiments_of(s, h):
		_place(s, c, at, ArmySystem.ORDER_GARRISON)
	var mind: Dictionary = s.ai_hosts[h]
	mind["mode"] = "RAID"
	mind["target_kind"] = "town"
	mind["target_id"] = town
	var month := _month(s, cell)
	var treasury := float(s.metrics["treasury"])
	var events := RaidSystem.settle_day(repo, s, [])
	# by hand: day 1 = month x 600 / 30000, rounded down; no food, so all plunder
	@warning_ignore("integer_division")
	var t1 := month * 600 / 30000
	assert_eq(int(mind["plunder"]), t1, "the town's manor's month %d x 600 / 30000" % month)
	assert_eq(int((mind["raided"] as Dictionary)[str(cell)]["taken"]), t1, "kept on the town's MANOR cell")
	assert_true(s.hazards.has(RaidSystem.hazard_id(cell)), "the town's manor is marked Raided")
	assert_eq(_of(events, "raid_begin").size(), 1)
	if not MapManors.crown_controls(repo, s, MapManors.province_of(repo, cell, s)):
		@warning_ignore("integer_division")
		assert_eq(float(s.metrics["treasury"]), treasury - float(t1 * 200 / 1000), "the crown's share of it")
	# a column further out than the reach takes nothing
	var s2 := SuiteData.campaign(repo, 11)
	for c: String in EnemyAi.regiments_of(s2, h):
		_place(s2, c, EnemyAi.target_point_m(repo, "town", town) + Vector2i(maxi(int(reach_km * 1000.0), int(repo.bal("army_spread_reach_m"))) + 500, 0),
			ArmySystem.ORDER_GARRISON)
	s2.ai_hosts[h]["mode"] = "RAID"
	s2.ai_hosts[h]["target_kind"] = "town"
	s2.ai_hosts[h]["target_id"] = town
	assert_eq(RaidSystem.day_take(repo, s2, h), 0, "outside the town's reach: nothing")


## --- two hosts on one manor ----------------------------------------------------------

func test_two_hosts_on_one_manor_never_take_more_than_its_share() -> void:
	repo.balance["raid_plunder_permille"] = 600.0
	var s := SuiteData.campaign(repo, 11)
	var a := _host("raider")
	var b := _host("main")
	var cell := _manor(s, false, 100)
	_raid(s, a, cell)
	_raid(s, b, cell)
	var cap := RaidSystem.cap_of(_month(s, cell), 600)
	var total := 0
	var stripped_on := -1
	for d in 40:
		total += RaidSystem.day_take(repo, s, a)
		total += RaidSystem.day_take(repo, s, b)
		assert_lte(RaidSystem.taken_of(s, cell), cap, "day %d: never past the manor's share" % (d + 1))
		if stripped_on < 0 and RaidSystem.stripped(repo, s, cell):
			stripped_on = d + 1
	assert_eq(total, cap, "together they take the share of the month exactly: %d" % cap)
	assert_eq(RaidSystem.taken_of(s, cell), cap)
	assert_between(stripped_on, 1, 29, "two running sums strip it faster than thirty days (%d)" % stripped_on)
