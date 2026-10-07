extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## A supposed piece read in the WAR ROOM's slip (spec
## 2026-10-07-war-room-annotations-and-planning-pieces §1.2, §1.4): its men on
## this ground, worked by hand; works only in a town its side holds; with a
## crown regiment chosen both sides side by side, never an odds.

var repo: DataRepository
var state: GameState


func before_each() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 42)


## An open land point (no town) on the given terrain.
func _open(terrain: String) -> Vector2:
	var ids: Array = repo.cells.keys()
	ids.sort()
	for id: int in ids:
		var c: Dictionary = repo.cells[id]
		if MapTerrain.is_water(c):
			continue
		var at := MapTerrain.cell_center(repo, c)
		if MapEconomy.cell_at(repo, at) == id and ArmySystem.terrain_at(repo, at) == terrain \
				and ArmySystem.town_at(repo, at) == "":
			return at
	return Vector2(-1, -1)


func _piece(arm: String, heads: int, side: String, at: Vector2) -> Dictionary:
	return {"arm": arm, "heads": heads, "side": side, "at": at}


func _land_code() -> String:
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) != "1":
			return String(r["regiment_code"])
	return ""


## Hand figures (test_army_power.gd): 2,000 archers at the assumed training 10
## and morale 75 — plains 972 both ways; hills defend 1117 (x1150), attack
## 1020 (x1050). Factors 1117*1000/972 = 1149, 1020*1000/972 = 1049.
func test_men_on_this_ground_by_hand() -> void:
	var at := _open("hills")
	assert_ne(at, Vector2(-1, -1), "the pack has open hills")
	var r := WarGround.plan_reading(repo, state, _piece("archers", 2000, WarPlans.UNKNOWN, at), "")
	var p: Dictionary = r["plan"]
	assert_eq(int(p["defend_f"]), 1149)
	assert_eq(int(p["attack_f"]), 1049)
	assert_eq(int(p["defend"]), 2298)
	assert_eq(int(p["attack"]), 2098)
	assert_eq(String(r["terrain"]), "hills")


func test_the_slip_writes_men_and_factors() -> void:
	var at := _open("hills")
	var r := WarGround.plan_reading(repo, state, _piece("archers", 2000, WarPlans.UNKNOWN, at), "")
	var texts: Array = WarGround.plan_lines(repo, r).map(func(l: Dictionary) -> String: return String(l["text"]))
	assert_eq(texts[0], "Supposed bows")
	assert_eq(texts[1], "Unknown")
	assert_true(texts.has("2,000 archers · assumed %s" % ArmySystem.training_grade(repo, int(repo.bal("war_plan_training"))).to_lower()))
	assert_true(texts.has("Defends as 2,298 (×1.15 hills)"), str(texts))
	assert_true(texts.has("Attacks as 2,098 (×1.05)"), str(texts))


## A town a foreign kingdom holds: its works count for that side only.
func test_works_only_in_a_town_its_side_holds() -> void:
	var mine := repo.resolve_realm("player_realm")
	var town := ""
	var holder := ""
	var codes: Array = repo.burgs.keys()
	codes.sort()
	for code: String in codes:
		var b: Dictionary = repo.burgs[code]
		var h := MapOwnership.owner_of(repo, state, String(b.get("province_code", "")))
		if h != "" and h != mine and ("walls" in String(b.get("features", "")) or "citadel" in String(b.get("features", ""))):
			town = code
			holder = h
			break
	assert_ne(town, "", "the pack has a walled foreign town")
	var at := Vector2(float(repo.burgs[town]["x"]), float(repo.burgs[town]["y"]))
	var theirs := WarGround.plan_reading(repo, state, _piece("infantry", 1000, holder, at), "")
	assert_ne(String(theirs["plan"]["works"]), "")
	var other := WarGround.plan_reading(repo, state, _piece("infantry", 1000, WarPlans.UNKNOWN, at), "")
	assert_eq(String(other["plan"]["works"]), "", "Unknown never has works")
	assert_gt(int(theirs["plan"]["defend"]), int(other["plan"]["defend"]))
	assert_eq(int(theirs["plan"]["attack"]), int(other["plan"]["attack"]), "works never help the attacker")


func test_with_a_regiment_both_sides_side_by_side_and_no_odds() -> void:
	var code := _land_code()
	var at := _open("hills")
	var r := WarGround.plan_reading(repo, state, _piece("archers", 2000, WarPlans.UNKNOWN, at), code)
	var g: Dictionary = r["regiment"]
	var reg := ArmySystem.regiment(repo, code)
	var delta := ArmySystem.elevation_of(repo, reg, state) - int(r["metres"])
	assert_eq(int(g["delta_m"]), delta)
	var fit := ArmySystem.headcount(repo, reg) - int(ArmySystem.state_of(repo, state, code)["wounded"])
	var ours_f := ArmySystem.power_on(repo, state, code, "attack", "hills", "") * 1000 / ArmySystem.power_on(repo, state, code, "attack", "plains", "")
	assert_eq(int(g["ours"]), fit * ours_f / 1000 * ArmySystem.height_factor(repo, delta) / 1000)
	assert_eq(int(g["theirs"]), 2298 * ArmySystem.height_factor(repo, -delta) / 1000)
	var texts: Array = WarGround.plan_lines(repo, r).map(func(l: Dictionary) -> String: return String(l["text"]))
	assert_true(texts.has("Theirs %s · ours %s on this ground" % [Intel.num(int(g["theirs"])), Intel.num(int(g["ours"]))]), str(texts))
	for t: String in texts:
		assert_false("%" in t or "odds" in t.to_lower() or "win" in t.to_lower(), "no odds or verdict: " + t)


func test_the_reading_writes_nothing() -> void:
	var before := JSON.stringify(state.to_dict())
	WarGround.plan_reading(repo, state, _piece("cavalry", 3000, WarPlans.UNKNOWN, _open("hills")), _land_code())
	assert_eq(JSON.stringify(state.to_dict()), before)
