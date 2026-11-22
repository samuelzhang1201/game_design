extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Play := preload("res://tests/invasion_play.gd")
## What a crown capture gives, and where the crown's control stops (player
## siege spec §7, step 3b): control counts only the realm's provinces; a
## crown capture of a foreign town moves the council by TOWN_TAKEN (the mirror
## of DefeatSystem's BATTLE_LOST), sacks the town under plunder: allow, once
## per occupation (GameState.town_takes).

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()
	Weather.forget()


## --- helpers ----------------------------------------------------------------

func _of(events: Array, kind: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return String(e.get("kind", "")) == kind)


func _opinions(s: GameState) -> Dictionary:
	var out := {}
	for seat: String in s.council:
		var c: Character = s.characters[s.council[seat]]
		out[seat] = [c.opinion, c.opinion_log.size()]
	return out


## A campaign with an undefended raider town and one crown unit, every other
## unit at the depot: {s, town, unit, away}.
func _ready_to_take() -> Dictionary:
	var s := SuiteData.campaign(repo, 7)
	repo = SuiteData.open_country(repo)
	var raider := repo.resolve_realm("raider_realm")
	var town := ""
	var codes: Array = repo.burgs.keys()
	codes.sort()
	for t: String in codes:
		if SiegeSystem.holder_of(repo, s, t) == raider and SiegeSystem.defenders_of(repo, s, t).is_empty() \
				and not SiegeSystem.taken_cells(repo, s, t).is_empty():
			town = t
			break
	assert_ne(town, "", "an undefended town of the raider realm")
	var unit := ""
	for c: String in Play.land_regiments(repo):
		if s.regiments.has(c) and ArmySystem.fit_count(repo, s, c) > 0:
			unit = c
			break
	var away := Play.town_m(repo, TownStores.depot(repo, s))
	for c: String in s.regiments.keys():
		if c != unit:
			Play.place(repo, s, c, away, ArmySystem.ORDER_STANDBY)
	return {"s": s, "town": town, "unit": unit, "away": away}


## The crown's unit takes the town (under plunder: allow when `allow`, decreed
## where the unit stands): the day's events.
func _take(f: Dictionary, allow := false) -> Array:
	var s: GameState = f.s
	Play.place(repo, s, String(f.unit), Play.town_m(repo, String(f.town)), ArmySystem.ORDER_GARRISON)
	if allow:
		assert_false(LawSystem.impose(repo, s, "plunder", "allow").has("error"))
		assert_eq(LawSystem.value(repo, s, "plunder", String(f.unit)), "allow", "the unit reads it")
	SiegeRecord.open_units(repo, s, String(f.town), repo.resolve_realm("player_realm"), [String(f.unit)], "task_test")
	var ev := SiegeSystem.settle_day(repo, s, [])
	assert_eq(_of(ev, "siege_ours_taken").size(), 1, "the town falls")
	return ev


## --- control ----------------------------------------------------------------

func test_control_stops_at_the_realm() -> void:
	var s := SuiteData.campaign(repo, 7)
	var raider := repo.resolve_realm("raider_realm")
	var crown := MapManors.crown(s)
	var theirs: String = MapOwnership.provinces_of(repo, s, raider)[0]
	for cell: int in MapManors.manors_of_province(repo, theirs, s):
		MapManors.set_owner(repo, s, cell, crown, "test: the crown's house holds it")
	assert_eq(MapManors.controller_of(repo, s, theirs), crown, "the crown's house holds most of it")
	assert_false(MapManors.crown_controls(repo, s, theirs), "but it is not the realm's")
	assert_false(theirs in MapManors.controlled_provinces(repo, s), "so it is no crown province")
	var home: String = MapManors.controlled_provinces(repo, s)[0]
	MapOwnership.set_owner(repo, s, home, raider, "test: the province changes realm")
	assert_false(home in MapManors.controlled_provinces(repo, s), "a province lost to another realm leaves at once")


## --- the council ------------------------------------------------------------

## TOWN_TAKEN has BATTLE_LOST's axes (militarism 20, expansionism 10; norm 30),
## so with base 5 each seat's gain is the loss of test_defeat's fixture turned:
##   marshal  (70, 50, sens 70, prag 35): w = 1900/3000 x 0.70 x 0.65 = 0.2882
##            -> round(5 x 1.2882) = +6
##   chaplain (-30, -20, sens 80, prag 30): w = -800/3000 x 0.80 x 0.70 = -0.1493
##            -> round(5 x 0.8507) = +4
##   chancellor: +5 (test_defeat's -5).
func test_council_gain_is_hand_computed() -> void:
	repo.balance["battle_victory_opinion"] = 5.0
	var f := _ready_to_take()
	var s: GameState = f.s
	var before := _opinions(s)
	var ev := _take(f)
	var want := {"marshal": 6, "chaplain": 4, "chancellor": 5}
	for seat: String in want:
		var c: Character = s.characters[s.council[seat]]
		assert_eq(c.opinion - int(before[seat][0]), int(want[seat]), seat)
	var what := "took %s from %s (supports, " % [String(repo.burgs[f.town]["label"]), repo.realm_label("raider_realm")]
	for seat: String in s.council:
		var c: Character = s.characters[s.council[seat]]
		var fresh: Array = c.opinion_log.slice(int(before[seat][1]))
		assert_eq(fresh.size(), 1, seat + " has one change for the capture")
		assert_true(String(fresh[0]["reason"]).begins_with(what), seat + ": " + String(fresh[0]["reason"]))
	assert_eq((_of(ev, "siege_ours_taken")[0]["opinion"] as Array).size(), s.council.size(), "the event lists them")


func test_opinion_gain_is_never_a_loss() -> void:
	assert_eq(SiegeSystem.opinion_gain(5, -1.0), 0)
	assert_eq(SiegeSystem.opinion_gain(5, -3.0), 0, "clamped")
	assert_eq(SiegeSystem.opinion_gain(5, 1.0), 10)
	assert_eq(SiegeSystem.opinion_gain(5, 0.2882), 6)


## --- the sack ---------------------------------------------------------------

func test_no_sack_without_plunder_allowed() -> void:
	var f := _ready_to_take()
	var s: GameState = f.s
	var was := int(s.metrics.get("strategic", 0))
	var ev := _take(f)
	assert_eq(int(_of(ev, "siege_ours_taken")[0]["sack"]), 0)
	assert_eq(int(s.metrics.get("strategic", 0)), was, "the stores are untouched")


func test_sack_under_plunder_allow() -> void:
	repo.balance["siege_sack_permille"] = 250.0
	var f := _ready_to_take()
	var s: GameState = f.s
	var own := EnemyAi.target_cell(repo, s, EnemyAi.KIND_TOWN, String(f.town))
	var month := RaidSystem.month_of(repo, s, own)
	assert_gt(month, 0, "the town is worth something")
	var was := int(s.metrics.get("strategic", 0))
	var ev := _take(f, true)
	@warning_ignore("integer_division")
	var want := month * 250 / 1000
	assert_eq(int(_of(ev, "siege_ours_taken")[0]["sack"]), want)
	assert_eq(int(s.metrics.get("strategic", 0)) - was, want, "into the strategic stores")


## --- once per occupation ----------------------------------------------------

func test_town_takes_once_per_occupation() -> void:
	repo.balance["battle_victory_opinion"] = 5.0
	var f := _ready_to_take()
	var s: GameState = f.s
	var town: String = f.town
	_take(f)
	assert_eq(s.town_takes, [{"town": town, "day": s.absolute_day()}], "the key")
	var marshal: Character = s.characters[s.council["marshal"]]
	var mo := marshal.opinion
	assert_eq(SiegeSystem._gains(repo, s, town, repo.resolve_realm("raider_realm"), [String(f.unit)], 100),
		{"opinion": [], "sack": 0}, "the same occupation pays once")
	assert_eq(marshal.opinion, mo)
	var back := GameState.from_dict(s.to_dict())
	assert_eq(back.town_takes, s.town_takes, "saved")
	# freed, then taken again on a later day: a new occupation, paid again
	Play.place(repo, s, String(f.unit), f.away, ArmySystem.ORDER_STANDBY)
	SiegeSystem.settle_day(repo, s, [])
	assert_false(s.occupations.has(town), "freed")
	s.day += 1
	_take(f)
	assert_eq(s.town_takes.size(), 2, "a second occupation")
	assert_gt(marshal.opinion, mo, "paid again")
