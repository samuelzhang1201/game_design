extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Play := preload("res://tests/invasion_play.gd")
## The crown's sight on the REAL day loop (spec docs/superpowers/specs/
## 2026-10-10-player-sight-and-ghosts-design.md), in the no-orders run of the
## prologue's invasion: the border rumour leaves its host's ghost on its day;
## nothing is seen while the hosts gather beyond sight; the main host is seen
## once it comes within player_sight_km of the crown's towns or units, and
## the map then draws it; a spy sent to a column out of sight leaves a ghost
## of it; the whole is deterministic across a mid-run save.

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()
	Weather.forget()
	Intel.dev_all = false


func _rumour_host() -> String:
	var first := ""
	var first_day := 0
	for h: Dictionary in repo.raid_hosts:
		var d := int(h["appear_day"])
		if first == "" or d < first_day or (d == first_day and String(h["host_code"]) < first):
			first = String(h["host_code"])
			first_day = d
	return first


func test_the_no_orders_run_sees_the_invasion() -> void:
	var engine := TickEngine.new(repo)
	var s := Play.opened(repo, engine)
	var ctx := Map3DContext.new(repo, {})
	ctx.state_fn = func() -> GameState: return s
	var first := Play.first_appear(repo)
	var rumour_day := first - int(repo.bal("raid_rumour_lead_days"))
	var host := _rumour_host()
	Play.play_through(engine, s, rumour_day - 1, true)
	assert_true(s.sightings.is_empty(), "before the rumour the crown knows of no one")
	Play.day(engine, s, true)   # the rumour's day ends
	var home := EnemyAi.home_m(repo, host)
	assert_eq(s.sightings.get(Sighting.HOST_KEY + host, {}), {"kind": "host", "code": host,
		"x_m": home.x, "y_m": home.y, "day": rumour_day, "source": "rumour", "men": 0},
		"the rumour's ghost, where its host gathers")
	assert_eq(Play.letters(s, "rumour").size(), 1, "the rumour's letter the same day")
	var ghosts := ctx.ghosts()
	assert_eq(ghosts.size(), 1)
	assert_eq(String(ghosts[0]["line"]), "Rumoured at the border, a day ago", "read the next morning")
	# the hosts gather beyond the crown's sight: nothing seen until they cross
	while s.absolute_day() <= first:
		assert_eq(Sighting.seen_foes(repo, s), [], "day %d: no host in sight" % s.absolute_day())
		Play.day(engine, s, true)
	# the main host comes into sight of the realm
	var main := Play.host(repo, "main")
	var seen_on := -1
	while seen_on < 0 and s.absolute_day() <= first + 10:
		var today := s.absolute_day()
		Play.day(engine, s, true)
		var seen := Sighting.seen_foes(repo, s).filter(func(c: String) -> bool:
			return String(s.foes[c]["host"]) == main)
		if seen.is_empty():
			continue
		seen_on = today
		var drawn: Array = ctx.regiments().map(func(r: Dictionary) -> String: return String(r["regiment_code"]))
		for c: String in seen:
			assert_true(c in drawn, c + " is drawn on the map")
			assert_eq(String(s.sightings[c]["source"]), "seen")
			assert_eq(int(s.sightings[c]["day"]), today, "refreshed as the day ended")
			assert_eq(int(s.sightings[c]["men"]) % 100, 0, "an estimate, rounded")
		for c: String in s.foes:
			if not c in Sighting.seen_foes(repo, s):
				assert_false(c in drawn, c + " is out of sight: not drawn")
		assert_false(s.sightings.has(Sighting.HOST_KEY + main), "the main host is seen: its rumour is done")
	assert_gt(seen_on, first - 1, "the main host is seen after it crosses (day %d)" % seen_on)
	# a spy sent to a column out of sight
	var hidden := ""
	var codes: Array = s.foes.keys()
	codes.sort()
	for c: String in codes:
		if Sighting.men_of(repo, s, c) > 0 and not c in Sighting.seen_foes(repo, s) and not s.sightings.has(c):
			hidden = c
			break
	assert_ne(hidden, "", "a column the crown has not seen")
	var e: Dictionary = s.foes[hidden]
	SpySystem.observe(repo, s, {"id": 0, "x_m": int(e["x_m"]), "y_m": int(e["y_m"])})
	var g: Dictionary = s.sightings.get(hidden, {})
	assert_eq(String(g.get("source", "")), "spy", "the spy's report leaves a ghost")
	assert_eq([int(g["x_m"]), int(g["y_m"]), int(g["day"])], [int(e["x_m"]), int(e["y_m"]), s.absolute_day()],
		"at the column's true place, today")
	assert_gt(int(g["men"]), 0)
	assert_eq(int(g["men"]) % 100, 0, "his estimate, rounded")
	assert_true(ctx.ghosts().any(func(x: Dictionary) -> bool: return String(x["key"]) == hidden),
		"drawn as a ghost")


func test_the_sight_is_deterministic_across_a_save() -> void:
	var last := Play.first_appear(repo) + 12
	var engine := TickEngine.new(repo)
	var a := Play.opened(repo, engine)
	Play.play_through(engine, a, last, true)
	var b := Play.opened(repo, engine)
	Play.play_through(engine, b, Play.first_appear(repo) + 2, true)
	b = GameState.from_dict(JSON.parse_string(JSON.stringify(b.to_dict())))
	Play.play_through(engine, b, last, true)
	assert_false(a.sightings.is_empty(), "the crown knows something by day %d" % last)
	assert_eq(b.sightings, a.sightings, "a run saved and loaded mid-way sees the same")
	var floats: Array = []
	Play.floats_in(a.sightings, "sightings", floats)
	assert_eq(floats, [], "whole numbers only")
