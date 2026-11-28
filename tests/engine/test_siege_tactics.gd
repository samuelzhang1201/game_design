extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Play := preload("res://tests/invasion_play.gd")
## Player siege spec §3 and §4 "The men pool", step 7 (SiegeTactics): each day
## the pool is the stationed besiegers' fit men (no wounded, no guards, none
## fighting a battle elsewhere); `alloc` splits it over the five tactics in
## whole men, never more than the pool; a shrinking pool cuts a standing plan
## engines → ladders → mine → bombard → blockade, each cut a reasoned line; an
## AI host plans by its doctrine's per-mille columns; the blockade closes
## entries only with the men allocated to it.

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()
	Weather.forget()


## --- helpers ----------------------------------------------------------------

## A raider town with the crown's unit `units[0]` at it and the rest standing
## by far off, all in one crown record: {s, town, id, units}.
func _crown(n: int) -> Dictionary:
	var s := SuiteData.campaign(repo, 7)
	repo = SuiteData.no_clearance(repo)
	var raider := repo.resolve_realm("raider_realm")
	var towns: Array = repo.burgs.keys()
	towns.sort()
	var town := ""
	for t: String in towns:
		if SiegeSystem.holder_of(repo, s, t) == raider:
			town = t
			break
	assert_ne(town, "", "a raider town")
	var units: Array = Play.land_regiments(repo, 300).slice(0, n)
	assert_eq(units.size(), n, "%d units of 300 men" % n)
	Play.place(repo, s, units[0], Play.town_m(repo, town), ArmySystem.ORDER_GARRISON)
	for i in range(1, units.size()):
		Play.place(repo, s, units[i], Play.town_m(repo, town) + Vector2i(0, 400000 + 10000 * i),
			ArmySystem.ORDER_STANDBY)
	var id := SiegeRecord.open_units(repo, s, town, repo.resolve_realm("player_realm"), units, "task_test")
	return {"s": s, "town": town, "id": id, "units": units}


## Leaves exactly `men` fit in unit `code`: the rest are wounded.
func _trim(s: GameState, code: String, men: int) -> void:
	var extra := ArmySystem.fit_count(repo, s, code) - men
	assert_true(extra >= 0, "%s has %d men" % [code, men])
	var changes: Array = []
	for cid: String in s.military_rosters[code]["cohort_ids"]:
		var take := mini(extra, int(s.military_cohorts[cid]["fit"]))
		if take > 0:
			changes.append({"cohort_id": cid, "from": "fit", "to": "wounded", "count": take})
			extra -= take
	if not changes.is_empty():
		assert_false(MilitaryRoster.transition(repo, s, "trim:%s:%d" % [code, men], changes, "test trim").has("error"))
	assert_eq(ArmySystem.fit_count(repo, s, code), men)


## --- the plan (P6.2's 300-men fixture) ------------------------------------------

func test_three_hundred_men_plan() -> void:
	var plan := {"mine": 120, "engines": 100, "blockade": 80}
	assert_eq(SiegeTactics.refusal(plan, 300), "", "120 + 100 + 80 = 300: legal")
	var more := plan.duplicate()
	more["ladders"] = 1
	assert_ne(SiegeTactics.refusal(more, 300), "", "301 > 300: refused")
	assert_ne(SiegeTactics.refusal({"mine": -1}, 300), "", "no negative men")
	assert_ne(SiegeTactics.refusal({"sapping": 1}, 300), "", "no unknown tactic")


func test_allocate_keeps_the_plan_on_a_refusal() -> void:
	var f := _crown(1)
	var s: GameState = f["s"]
	_trim(s, f["units"][0], 300)
	assert_eq(SiegeTactics.pool(repo, s, f["id"]), 300)
	var out := SiegeTactics.allocate(repo, s, f["id"], {"mine": 120, "engines": 100, "blockade": 80})
	assert_false(out.has("error"))
	var kept := {"blockade": 80, "mine": 120, "bombard": 0, "ladders": 0, "engines": 100}
	assert_eq(s.sieges[f["id"]]["alloc"], kept, "all five tactics, whole men")
	var refused := SiegeTactics.allocate(repo, s, f["id"],
		{"mine": 120, "engines": 100, "blockade": 80, "ladders": 1})
	assert_true(refused.has("error"), "ladders 1 more: refused")
	assert_eq(s.sieges[f["id"]]["alloc"], kept, "the plan kept")


## --- the cut ----------------------------------------------------------------------

func test_cut_order_on_a_loss() -> void:
	# 300 planned, 150 left: 150 to cut — engines 100 → 0, ladders none, mine
	# 120 → 70; bombard none and the blockade's 80 kept
	var plan := {"blockade": 80, "mine": 120, "bombard": 0, "ladders": 0, "engines": 100}
	var cuts := SiegeTactics.cut(plan, 150)
	assert_eq(cuts, [{"tactic": "engines", "from": 100, "to": 0}, {"tactic": "mine", "from": 120, "to": 70}])
	assert_eq(plan, {"blockade": 80, "mine": 70, "bombard": 0, "ladders": 0, "engines": 0})
	# 60 left: then the bombard (none), then the blockade 80 → 60
	plan = {"blockade": 80, "mine": 0, "bombard": 10, "ladders": 5, "engines": 0}
	assert_eq(SiegeTactics.cut(plan, 60), [{"tactic": "ladders", "from": 5, "to": 0},
		{"tactic": "bombard", "from": 10, "to": 0}, {"tactic": "blockade", "from": 80, "to": 60}])
	assert_eq(SiegeTactics.cut(plan, 60), [], "a plan inside the pool is not cut")


func test_a_loss_cuts_the_standing_plan_with_a_reason() -> void:
	var f := _crown(1)
	var s: GameState = f["s"]
	var code: String = f["units"][0]
	_trim(s, code, 300)
	SiegeTactics.allocate(repo, s, f["id"], {"mine": 120, "engines": 100, "blockade": 80})
	_trim(s, code, 150)
	SiegeTactics.day(repo, s, f["id"])
	var rec: Dictionary = s.sieges[f["id"]]
	assert_eq(rec["alloc"], {"blockade": 80, "mine": 70, "bombard": 0, "ladders": 0, "engines": 0})
	var lines: Array = rec["history"]
	assert_eq(lines.size(), 2, "one line a cut")
	assert_eq([String(lines[0]["tactic"]), int(lines[0]["from"]), int(lines[0]["to"])], ["engines", 100, 0])
	assert_eq([String(lines[1]["tactic"]), int(lines[1]["from"]), int(lines[1]["to"])], ["mine", 120, 70])
	assert_eq(String(lines[0]["kind"]), "alloc_cut")
	assert_eq(int(lines[0]["day"]), s.absolute_day())
	assert_string_contains(String(lines[0]["reason"]), "150 men")
	SiegeTactics.day(repo, s, f["id"])
	assert_eq((rec["history"] as Array).size(), 2, "nothing more to cut")


## --- the pool ------------------------------------------------------------------------

func test_the_pool_leaves_out_the_wounded_and_a_battle_elsewhere() -> void:
	var f := _crown(1)
	var s: GameState = f["s"]
	var code: String = f["units"][0]
	_trim(s, code, 250)
	assert_eq(SiegeTactics.pool(repo, s, f["id"]), 250, "the wounded are not in it")
	s.battles.append({"id": 9999, "att": [code], "def": [], "town": ""})
	assert_eq(SiegeTactics.pool(repo, s, f["id"]), 0, "in a field battle: none")
	s.battles[s.battles.size() - 1]["town"] = f["town"]
	assert_eq(SiegeTactics.pool(repo, s, f["id"]), 250, "storming this town: still in it")


func test_staggered_arrival() -> void:
	# 100 men at the town, 200 on the road, a third column far off: the pool is what stands
	# at the town, from the day it arrives
	var f := _crown(3)
	var s: GameState = f["s"]
	var u: Array = f["units"]
	_trim(s, u[0], 100)
	_trim(s, u[1], 200)
	assert_eq(SiegeTactics.pool(repo, s, f["id"]), 100, "only the first column is there")
	assert_eq(SiegeTactics.men_for(repo, s, f["id"], "blockade"), 100, "no plan yet: the pool blockades")
	Play.place(repo, s, u[1], Play.town_m(repo, f["town"]), ArmySystem.ORDER_GARRISON)
	assert_eq(SiegeTactics.pool(repo, s, f["id"]), 300, "the second has arrived")
	assert_eq(SiegeTactics.men_for(repo, s, f["id"], "blockade"), 300)
	assert_false(SiegeSystem.deployed_at(repo, s, u[2], f["town"]), "the third never came")


## --- the AI's plan ------------------------------------------------------------------

func test_doctrine_plan_in_whole_men() -> void:
	var doctrine := {"siege_blockade_permille": 500, "siege_mine_permille": 250, "siege_bombard_permille": 0,
		"siege_ladders_permille": 125, "siege_engines_permille": 125}
	# 100: 50 / 25 / 0 / 12.5 / 12.5 → the largest remainders, ties by name:
	# engines before ladders, so 13 / 12
	assert_eq(SiegeTactics.plan(doctrine, 100),
		{"blockade": 50, "mine": 25, "bombard": 0, "ladders": 12, "engines": 13})
	assert_eq(SiegeTactics.plan(doctrine, 300),
		{"blockade": 150, "mine": 75, "bombard": 0, "ladders": 37, "engines": 38})
	assert_eq(SiegeTactics.plan(doctrine, 0),
		{"blockade": 0, "mine": 0, "bombard": 0, "ladders": 0, "engines": 0})


func test_an_ai_siege_plans_by_its_doctrine_each_day() -> void:
	var s := SuiteData.campaign(repo, 7)
	repo = SuiteData.open_country(repo)
	var host := Play.host(repo, "main")
	var town := ""
	for c: String in Play.land_regiments(repo):
		var t := ArmyGround.seated_in(repo, s, c)
		if t != "" and t != TownStores.depot(repo, s):
			town = t
			break
	assert_ne(town, "")
	var cols := EnemyAi.regiments_of(s, host)
	cols.sort()
	Play.place(repo, s, cols[0], Play.town_m(repo, town), ArmySystem.ORDER_GARRISON)
	for i in range(1, cols.size()):
		Play.place(repo, s, cols[i], Play.town_m(repo, town) + Vector2i(0, 400000), ArmySystem.ORDER_STANDBY)
	var mind: Dictionary = s.ai_hosts[host]
	mind["mode"] = "SIEGE"
	mind["target_kind"] = "town"
	mind["target_id"] = town
	EnemyAi.ensure_deployments(repo, s)
	var rec := SiegeRecord.ensure_for(repo, s, host)
	var id := SiegeRecord.of_town(s, town)
	repo.ai_doctrines["main"].merge({"siege_blockade_permille": 500, "siege_mine_permille": 250,
		"siege_bombard_permille": 0, "siege_ladders_permille": 125, "siege_engines_permille": 125}, true)
	var first := SiegeTactics.pool(repo, s, id)
	assert_eq(first, ArmySystem.fit_count(repo, s, cols[0]), "the first column alone")
	SiegeTactics.day(repo, s, id)
	assert_eq(rec["alloc"], SiegeTactics.plan(repo.ai_doctrines["main"], first))
	if cols.size() > 1:
		Play.place(repo, s, cols[1], Play.town_m(repo, town), ArmySystem.ORDER_GARRISON)
		var both := SiegeTactics.pool(repo, s, id)
		assert_eq(both, first + ArmySystem.fit_count(repo, s, cols[1]), "the arrival adds its men")
		SiegeTactics.day(repo, s, id)
		assert_eq(rec["alloc"], SiegeTactics.plan(repo.ai_doctrines["main"], both), "planned afresh")
	assert_eq((rec.get("history", []) as Array).size(), 0, "a fresh plan cuts nothing")


## --- the blockade spends its men ---------------------------------------------------

func test_the_blockade_closes_with_its_men_only() -> void:
	var f := _crown(1)
	var s: GameState = f["s"]
	_trim(s, f["units"][0], 300)
	repo.balance["siege_blockade_men_per_entry"] = 100
	SiegeTactics.allocate(repo, s, f["id"], {"mine": 300})
	SiegeBlockade.close(repo, s, f["id"])
	assert_eq(SiegeBlockade.open_share(s.sieges[f["id"]]), 1000, "no blockade men: every entry open")
	SiegeTactics.allocate(repo, s, f["id"], {"mine": 200, "blockade": 100})
	SiegeBlockade.close(repo, s, f["id"])
	var closed := 0
	for e: Dictionary in (s.sieges[f["id"]]["entries"] as Dictionary).values():
		if String(e["closed_by"]) != "":
			closed += 1
	assert_eq(closed, 1, "100 blockade men close one entry of 100")
