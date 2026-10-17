extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Play := preload("res://tests/invasion_play.gd")
## The crown's sight and the enemy's ghosts (spec docs/superpowers/specs/
## 2026-10-10-player-sight-and-ghosts-design.md, Sighting): a foe unit is SEEN
## within player_sight_km of a land unit of the crown's or of a town it holds;
## what the crown last knew — a sight, a spy's count, the border rumour — is a
## ghost in GameState.sightings, forgotten after ghost_keep_days or with its
## unit. Hand-computed figures; positions are whole metres.

var repo: DataRepository
var s: GameState
var r := 0          # the sight's reach, whole metres
var far := Vector2i.ZERO   # a point more than three reaches from every held town
var nowhere := Vector2i.ZERO   # where the foes stand out of everyone's way
var foe := ""       # a live foe unit, moved about by the tests
var other := ""     # another, left far away


func before_each() -> void:
	repo = SuiteData.repo()
	s = SuiteData.campaign(repo, 11)
	s.tick = 1
	s.day = 5
	Intel.dev_all = false
	# the figures below are worked by hand on these values
	repo.balance["player_sight_km"] = 12.0
	repo.balance["ghost_keep_days"] = 20.0
	repo.balance["player_sight_estimate_quality"] = 1000.0
	repo.balance["spy_width_best"] = 100.0
	repo.balance["spy_width_worst"] = 450.0
	(repo.intel_facts["foe_troops"] as Dictionary)["round_to"] = 100
	r = Sighting.sight_m(repo)
	# the assembly point farthest from the crown's held towns
	var best := -1
	for h: String in EnemyAi.host_codes(s):
		var at := EnemyAi.home_m(repo, h)
		var d := _nearest_town_m(at)
		if d > best:
			best = d
			far = at
	assert_gt(best, 3 * r, "a point beyond every held town's sight")
	Play.park_army(repo, s, far)
	# out of the way: over two reaches from every held town, four from `far`
	nowhere = far
	for k in range(4, 40):
		for step: Vector2i in [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0)]:
			var p := far + step * k * r
			if nowhere == far and _nearest_town_m(p) > 2 * r:
				nowhere = p
	assert_ne(nowhere, far, "open country for the foes to stand in")
	var codes: Array = s.foes.keys()
	codes.sort()
	foe = String(codes[0])
	other = String(codes[1])
	for c: String in codes:
		Play.place(repo, s, c, nowhere, ArmySystem.ORDER_STANDBY)


func after_each() -> void:
	Intel.dev_all = false


func _nearest_town_m(at: Vector2i) -> int:
	var best := -1
	for t: String in TownStores.realm_towns(repo, s):
		if not ArmyGround.holds(repo, s, repo.resolve_realm("player_realm"), t):
			continue
		var d := int(Vector2(ArmyGround.town_point_m(repo, t)).distance_to(Vector2(at)))
		best = d if best < 0 else mini(best, d)
	return best


## A land unit of the player's with men, by code.
func _land_unit(i: int = 0) -> String:
	return String(Play.land_regiments(repo)[i])


func _fleet() -> String:
	for reg: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), s):
		if String(reg.get("is_naval", "0")) == "1" and s.regiments.has(String(reg["regiment_code"])):
			return String(reg["regiment_code"])
	return ""


## --- the sight ----------------------------------------------------------------

func test_a_foe_at_exactly_the_reach_is_seen_and_a_metre_beyond_is_not() -> void:
	assert_eq(r, 12000, "player_sight_km 12 is 12,000 m")
	Play.place(repo, s, _land_unit(), far, ArmySystem.ORDER_STANDBY)
	Play.place(repo, s, foe, far + Vector2i(r, 0), ArmySystem.ORDER_STANDBY)
	assert_eq(Sighting.seen_foes(repo, s), [foe], "12,000 m off: seen (inclusive)")
	Play.place(repo, s, foe, far + Vector2i(r + 1, 0), ArmySystem.ORDER_STANDBY)
	assert_eq(Sighting.seen_foes(repo, s), [], "12,001 m off: not seen")
	Play.place(repo, s, foe, far + Vector2i(0, -r), ArmySystem.ORDER_STANDBY)
	assert_eq(Sighting.seen_foes(repo, s), [foe], "the same reach on the other axis")


func test_the_nearest_of_several_units_counts() -> void:
	Play.place(repo, s, _land_unit(0), far + Vector2i(r, 3 * r), ArmySystem.ORDER_STANDBY)
	Play.place(repo, s, foe, far + Vector2i(r, 0), ArmySystem.ORDER_STANDBY)
	assert_eq(Sighting.seen_foes(repo, s), [], "3 reaches from the one unit: not seen")
	Play.place(repo, s, _land_unit(1), far, ArmySystem.ORDER_STANDBY)
	assert_eq(Sighting.seen_foes(repo, s), [foe], "3 reaches from the first unit, 1 from the second")


func test_a_unit_with_no_man_under_arms_sees_nothing_and_is_not_seen() -> void:
	var u := _land_unit()
	Play.place(repo, s, u, far, ArmySystem.ORDER_STANDBY)
	Play.place(repo, s, foe, far + Vector2i(6000, 0), ArmySystem.ORDER_STANDBY)
	SuiteData.set_losses(s, foe, {"dead": ArmySystem.headcount(repo, ArmySystem.regiment(repo, foe, s))})
	assert_eq(Sighting.seen_foes(repo, s), [], "a destroyed column is no one to see")
	SuiteData.set_losses(s, foe, {"dead": 0})
	SuiteData.set_losses(s, u, {"dead": ArmySystem.headcount(repo, ArmySystem.regiment(repo, u, s))})
	assert_eq(Sighting.seen_foes(repo, s), [], "a unit with every man dead sees nothing")


func test_a_fleet_sees_nothing() -> void:
	var fleet := _fleet()
	if fleet == "":
		pending("the pack gives the crown no fleet")
		return
	Play.place(repo, s, fleet, far, ArmySystem.ORDER_STANDBY)
	Play.place(repo, s, foe, far + Vector2i(6000, 0), ArmySystem.ORDER_STANDBY)
	assert_eq(Sighting.seen_foes(repo, s), [], "a fleet beside the foe: not seen")


func test_a_held_town_sees() -> void:
	# a town whose point + reach + 1 m lies beyond every other held town's sight
	var realm := repo.resolve_realm("player_realm")
	var town := ""
	for t: String in TownStores.realm_towns(repo, s):
		if not ArmyGround.holds(repo, s, realm, t):
			continue
		var beyond := ArmyGround.town_point_m(repo, t) + Vector2i(r + 1, 0)
		if _nearest_town_m(beyond) > r:
			town = t
			break
	assert_ne(town, "", "a town with open country beyond it")
	assert_gt(Vector2(nowhere).distance_to(Vector2(ArmyGround.town_point_m(repo, town))), 2.0 * r, "the other foes stand far off")
	Play.park_army(repo, s, ArmyGround.town_point_m(repo, town))
	var at := ArmyGround.town_point_m(repo, town)
	Play.place(repo, s, foe, at + Vector2i(r, 0), ArmySystem.ORDER_STANDBY)
	assert_eq(Sighting.seen_foes(repo, s), [foe], "the town's point at the reach: seen")
	Play.place(repo, s, foe, at + Vector2i(r + 1, 0), ArmySystem.ORDER_STANDBY)
	assert_eq(Sighting.seen_foes(repo, s), [], "a metre beyond: not seen")


## --- the estimate -------------------------------------------------------------

func test_about_is_the_middle_of_the_estimate_rounded() -> void:
	# q 1000, bias 0: half 1234 × 100‰ = 123; [1100, 1400] (out to 100s); middle 1250 → 1300
	assert_eq(Sighting.about(repo, 1234, 1000, 0), 1300)
	# q 0 (width 450‰), bias +200‰: half 555, centre 1234 + 246 = 1480; [900, 2100]; 1500
	assert_eq(Sighting.about(repo, 1234, 0, 200), 1500)
	# 30 men: [0, 100], middle 50 → 100, never less than one step
	assert_eq(Sighting.about(repo, 30, 1000, 0), 100)
	assert_eq(Sighting.about(repo, 0, 1000, 0), 0, "no one: unknown")


## --- the ghosts ---------------------------------------------------------------

func _seen_now() -> void:
	Play.place(repo, s, _land_unit(), far, ArmySystem.ORDER_STANDBY)
	Play.place(repo, s, foe, far + Vector2i(r, 0), ArmySystem.ORDER_STANDBY)


func test_a_seen_unit_is_refreshed_and_left_behind_as_a_ghost() -> void:
	_seen_now()
	Sighting.update(repo, s)
	var men := Sighting.men_of(repo, s, foe)
	var g: Dictionary = s.sightings[foe]
	assert_eq(g, {"kind": "unit", "code": foe, "x_m": far.x + r, "y_m": far.y, "day": s.absolute_day(),
		"source": "seen", "men": Sighting.about(repo, men, 1000, 0)})
	assert_eq(Sighting.ghosts(repo, s), [], "a unit seen now is its piece, no ghost")
	# it marches off out of sight; two days later the crown remembers where it was
	var day := s.absolute_day()
	Play.place(repo, s, foe, far + Vector2i(3 * r, 0), ArmySystem.ORDER_STANDBY)
	s.day += 2
	Sighting.update(repo, s)
	var gs := Sighting.ghosts(repo, s)
	assert_eq(gs.size(), 1)
	assert_eq(String(gs[0]["key"]), foe)
	assert_eq([int(gs[0]["x_m"]), int(gs[0]["y_m"]), int(gs[0]["day"]), int(gs[0]["age"])],
		[far.x + r, far.y, day, 2], "where it was last seen, two days ago")
	assert_eq(String(gs[0]["source"]), "seen")


func test_a_spy_leaves_a_ghost_with_his_estimate_and_day() -> void:
	Play.place(repo, s, foe, far + Vector2i(1000, 0), ArmySystem.ORDER_STANDBY)
	var at := ArmySystem.metres_to_pack(repo, far)
	Sighting.on_spy(repo, s, at, 0, 200)
	var men := Sighting.men_of(repo, s, foe)
	var g: Dictionary = s.sightings[foe]
	assert_eq(g, {"kind": "unit", "code": foe, "x_m": far.x + 1000, "y_m": far.y, "day": s.absolute_day(),
		"source": "spy", "men": Sighting.about(repo, men, 0, 200)}, "his estimate, the column's true place")
	assert_false(s.sightings.has(other), "a column out of his reach is not reported")


func test_a_sight_beats_a_spy_the_same_day_and_a_newer_spy_beats_an_old_sight() -> void:
	_seen_now()
	Sighting.on_spy(repo, s, ArmySystem.metres_to_pack(repo, far), 0, 200)
	Sighting.update(repo, s)
	assert_eq(String(s.sightings[foe]["source"]), "seen", "seen wins the day")
	Sighting.on_spy(repo, s, ArmySystem.metres_to_pack(repo, far), 0, 200)
	assert_eq(String(s.sightings[foe]["source"]), "seen", "a spy the same day does not undo a sight")
	s.day += 1
	Play.place(repo, s, _land_unit(), far + Vector2i(-6 * r, 6 * r), ArmySystem.ORDER_STANDBY)
	Sighting.on_spy(repo, s, ArmySystem.metres_to_pack(repo, far), 0, 200)
	assert_eq(String(s.sightings[foe]["source"]), "spy", "the next day's report is newer")


func _rumour_host() -> String:
	var first := ""
	var first_day := 0
	for h: Dictionary in repo.raid_hosts:
		var d := int(h["appear_day"])
		if first == "" or d < first_day or (d == first_day and String(h["host_code"]) < first):
			first = String(h["host_code"])
			first_day = d
	return first


func test_the_rumour_leaves_a_host_ghost_at_its_assembly_point() -> void:
	var host := _rumour_host()
	var rumour_day := Play.first_appear(repo) - int(repo.bal("raid_rumour_lead_days"))
	s.tick = 1
	s.day = rumour_day - 1
	Sighting.update(repo, s)
	assert_false(s.sightings.has(Sighting.HOST_KEY + host), "the day before: nothing")
	s.day = rumour_day
	Sighting.update(repo, s)
	var home := EnemyAi.home_m(repo, host)
	assert_eq(s.sightings[Sighting.HOST_KEY + host], {"kind": "host", "code": host, "x_m": home.x,
		"y_m": home.y, "day": rumour_day, "source": "rumour", "men": 0})
	var gs := Sighting.ghosts(repo, s)
	assert_eq(gs.size(), 1)
	assert_eq(String(gs[0]["key"]), "host:" + host)
	assert_eq(String(gs[0]["line"]), "Rumoured at the border, today")


func test_a_units_ghost_takes_its_hosts_rumour_away() -> void:
	var host := String(s.foes[foe]["host"])
	var home := EnemyAi.home_m(repo, host)
	Sighting.record(s, Sighting.HOST_KEY + host, {"kind": "host", "code": host, "x_m": home.x, "y_m": home.y,
		"day": s.absolute_day(), "source": "rumour", "men": 0})
	_seen_now()
	Sighting.update(repo, s)
	assert_false(s.sightings.has(Sighting.HOST_KEY + host), "the host is seen: the rumour is done")
	assert_true(s.sightings.has(foe))


func test_a_ghost_is_kept_until_exactly_ghost_keep_days_old() -> void:
	_seen_now()
	Sighting.update(repo, s)
	var seen_day := s.absolute_day()
	Play.place(repo, s, foe, far + Vector2i(3 * r, 0), ArmySystem.ORDER_STANDBY)
	s.day = seen_day + 20   # tick 1: the absolute day is the day
	assert_eq(s.absolute_day(), seen_day + 20)
	Sighting.update(repo, s)
	assert_true(s.sightings.has(foe), "20 days old: kept")
	assert_eq(int(Sighting.ghosts(repo, s)[0]["age"]), 20)
	s.day = seen_day + 21
	Sighting.update(repo, s)
	assert_false(s.sightings.has(foe), "21 days old: forgotten")
	assert_eq(Sighting.ghosts(repo, s), [])


func test_a_destroyed_unit_takes_its_ghost_with_it() -> void:
	_seen_now()
	Sighting.update(repo, s)
	Play.place(repo, s, foe, far + Vector2i(3 * r, 0), ArmySystem.ORDER_STANDBY)
	SuiteData.set_losses(s, foe, {"dead": ArmySystem.headcount(repo, ArmySystem.regiment(repo, foe, s))})
	assert_eq(Sighting.ghosts(repo, s), [], "not drawn the moment it is gone")
	Sighting.update(repo, s)
	assert_false(s.sightings.has(foe), "forgotten at the day's end")


func test_the_ghosts_survive_a_save_and_an_old_save_has_none() -> void:
	_seen_now()
	Sighting.update(repo, s)
	Sighting.on_spy(repo, s, ArmySystem.metres_to_pack(repo, nowhere), 0, 200)
	var d := s.to_dict()
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	assert_eq(back.sightings, s.sightings, "the round trip")
	var floats: Array = []
	Play.floats_in(back.sightings, "sightings", floats)
	assert_eq(floats, [], "no float in the ghosts")
	d.erase("sightings")
	assert_eq(GameState.from_dict(d).sightings, {}, "an old save: no ghost")


## --- the words ----------------------------------------------------------------

func _g(source: String, age: int, men: int) -> Dictionary:
	return {"kind": "unit", "code": foe, "x_m": 0, "y_m": 0, "day": s.absolute_day() - age,
		"source": source, "men": men}


func test_each_sources_line() -> void:
	s.tick = 2
	s.day = 10
	assert_eq(Sighting.line_of(repo, s, _g("seen", 0, 1300)), "Seen today — about 1,300 men")
	assert_eq(Sighting.line_of(repo, s, _g("seen", 1, 1300)), "Last seen a day ago — about 1,300 men")
	assert_eq(Sighting.line_of(repo, s, _g("seen", 3, 0)), "Last seen 3 days ago")
	assert_eq(Sighting.line_of(repo, s, _g("spy", 2, 1500)), "Spy report, 2 days ago — about 1,500 men")
	assert_eq(Sighting.line_of(repo, s, _g("spy", 0, 200)), "Spy report, today — about 200 men")
	assert_eq(Sighting.line_of(repo, s, _g("rumour", 5, 0)), "Rumoured at the border, 5 days ago")


func test_a_seen_foes_card_has_the_line_and_never_its_exact_men() -> void:
	_seen_now()
	var card := MapObjects.army_card(repo, foe, s)
	var men := Sighting.men_of(repo, s, foe)
	var sighted := ""
	var words: Array = []
	for f: Array in card["fields"]:
		words.append(String(f[1]))
		if String(f[0]) == "Sighted":
			sighted = String(f[1])
	for st: Dictionary in card["stats"]:
		words.append(String(st["text"]))
		words.append(String(st["tooltip"]))
	assert_eq(sighted, "Seen today — about %s men" % Intel.num(Sighting.about(repo, men, 1000, 0)))
	assert_ne(men % 100, 0, "a figure the estimate cannot hit by chance")
	for w: String in words:
		assert_false(w.contains(str(men)) or w.contains(Intel.num(men)), "the exact men are not on the card: " + w)


func test_a_ghosts_card_stands_at_the_ghost() -> void:
	_seen_now()
	Sighting.update(repo, s)
	Play.place(repo, s, foe, far + Vector2i(3 * r, 0), ArmySystem.ORDER_STANDBY)
	s.day += 4
	var card := MapObjects.army_card(repo, Sighting.GHOST_CODE + foe, s)
	assert_eq(card["code"], Sighting.GHOST_CODE + foe)
	assert_eq(card["center"], ArmySystem.metres_to_pack(repo, far + Vector2i(r, 0)), "where it was seen, not where it is")
	var fields: Dictionary = {}
	for f: Array in card["fields"]:
		fields[String(f[0])] = String(f[1])
	assert_eq(fields["Sighted"], "Last seen 4 days ago — about %s men" % Intel.num(int(s.sightings[foe]["men"])))
	assert_eq(fields["Under arms"], "about " + Intel.num(int(s.sightings[foe]["men"])))
	assert_eq(MapObjects.label_of(repo, {"kind": "army", "code": Sighting.GHOST_CODE + foe}, s),
		String(ArmySystem.regiment(repo, foe, s)["label"]))
	assert_eq(MapObjects.army_card(repo, Sighting.GHOST_CODE + "nobody", s), {}, "no such ghost: no card")
