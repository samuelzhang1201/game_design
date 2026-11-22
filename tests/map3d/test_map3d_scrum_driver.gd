extends GutTest
## The mixed fight in the duel driver (Map3DDuelDriver + Map3DDuelScrum; spec
## 2026-11-21-infantry-melee-scrum-design.md): both ranks of two opposed
## infantry sides leave their blocks for ONE fighting area per battle, keep
## their space, pair nearest across it; the standard bearer keeps its slot.

const SuiteData = preload("res://tests/suite_data.gd")
const ART := {"duel": "STRIKE:ATTACK;SLASH|BLOCK:BLOCK|HIT:HIT|DEATH:DEATH",
	"contact": "ATTACK:0.4;SLASH:0.35;BLOCK:0.25;HIT:0.1"}
const DT := 0.05

var repo: DataRepository
var state: GameState
var ctx: Map3DContext
var unit := 1.0  ## world metres per saved metre
var tune: Dictionary


func before_each() -> void:
	repo = SuiteData.repo()
	repo.army_art["duellist"] = ART
	repo.army_art["bowman"] = {}
	state = GameState.new()
	ctx = Map3DContext.new(repo, {"pack_origin": [0, 0], "m_per_px": 2.0})
	ctx.state_fn = func() -> GameState: return state
	unit = ctx.to_world(ArmySystem.metres_to_pack(repo, Vector2i(1, 0))).distance_to(
		ctx.to_world(ArmySystem.metres_to_pack(repo, Vector2i.ZERO)))
	tune = Map3DDuelDriver.tune_of(repo)
	for key: String in ["steal", "double", "hit"]:
		tune[key] = 0.0
	tune["open_max"] = 0.0


func _anim(clips := ["GARRISON", "MARCH", "ATTACK", "SLASH", "BLOCK", "HIT", "DEATH"]) -> AnimationPlayer:
	var anim := AnimationPlayer.new()
	var lib := AnimationLibrary.new()
	for name: String in clips:
		var clip := Animation.new()
		clip.length = 1.0
		clip.loop_mode = Animation.LOOP_LINEAR if name in ["GARRISON", "MARCH"] else Animation.LOOP_NONE
		lib.add_animation(name, clip)
	anim.add_animation_library("", lib)
	add_child_autofree(anim)
	return anim


## A battle unit of `n` groups (the first five front, the rest reserve), files
## 2 saved metres apart from `x0`, its front at `y` and its reserve 2 m behind
## (`back`: the way behind it); a figure 2 saved metres tall.
func _piece(n: int, x0: int, y: int, back: int, model := "duellist") -> Dictionary:
	var piece := {"layout": "physical_groups", "model": model, "facing_deg": 0, "groups": []}
	for i in n:
		var node := Node3D.new()
		add_child_autofree(node)
		var child := {"anims": [_anim()], "height_m": 2.0 * unit, "node": node, "stand_deg": 0.0}
		piece["groups"].append({"slot": i, "role": "front" if i < 5 else "reserve", "count": 100,
			"x_m": x0 + (i % 5) * 2, "y_m": y + (0 if i < 5 else back * 2), "piece": child})
	return piece


func _fight(att: Dictionary, def: Dictionary) -> Dictionary:
	state.battles = [{"id": 1, "rounds": 1, "att": att.keys(), "def": def.keys()}]
	var pieces := att.duplicate()
	pieces.merge(def)
	return pieces


func _claimed(piece: Dictionary) -> Array:
	return (piece["groups"] as Array).filter(func(g: Dictionary) -> bool:
		return (g["piece"]["anims"][0] as AnimationPlayer).has_meta("duel"))


func _inside(p: Vector2, area: Dictionary, slack := 1e-4) -> bool:
	var d: Vector2 = p - area["centre"]
	return absf(d.dot(area["along"])) <= float(area["half_len"]) + slack \
		and absf(d.dot(area["across"])) <= float(area["half_depth"]) + slack


func test_both_ranks_enter_the_area() -> void:
	var a := _piece(10, 0, 0, -1)
	var b := _piece(10, 0, 8, 1)
	var pieces := _fight({"A": a}, {"B": b})
	var driver := Map3DDuelDriver.new()
	driver.run(Map3DDuelDriver.gather(ctx, pieces), DT, true, tune)
	assert_eq(_claimed(a).size() + _claimed(b).size(), 18, "both ranks of both sides, bearers out")
	var targets := driver.scrum_targets(1)
	var area := driver.scrum_area(1)
	assert_eq(targets.size(), 18)
	for piece: Dictionary in [a, b]:
		for g: Dictionary in _claimed(piece):
			var key := "%s:%d" % ["A" if piece == a else "B", int(g["slot"])]
			assert_true(_inside(targets[key], area), key + " targets inside the area")
			var stand := Map3DBattleGroups.stand_xz(ctx, piece, g)
			assert_almost_eq(((g["piece"]["duel_offset"] as Vector2) + stand).distance_to(targets[key]), 0.0, 1e-4,
				key + " walks to its target, no step limit")


func test_the_bearer_keeps_its_slot() -> void:
	var a := _piece(10, 0, 0, -1)
	var b := _piece(10, 0, 8, 1)
	var pieces := _fight({"A": a}, {"B": b})
	var driver := Map3DDuelDriver.new()
	for i in 40:
		driver.run(Map3DDuelDriver.gather(ctx, pieces), DT, true, tune)
	for piece: Dictionary in [a, b]:
		var bearer: Dictionary = piece["groups"][0]["piece"]
		assert_false((bearer["anims"][0] as AnimationPlayer).has_meta("duel"), "the standard bearer is never claimed")
		assert_false(bearer.has("duel_offset"), "and stands at the block")


func test_scrum_figures_keep_their_space() -> void:
	var a := _piece(10, 0, 0, -1)
	var b := _piece(10, 0, 8, 1)
	var pieces := _fight({"A": a}, {"B": b})
	var driver := Map3DDuelDriver.new()
	for i in 300:
		driver.run(Map3DDuelDriver.gather(ctx, pieces), DT, true, tune)
	var targets := driver.scrum_targets(1)
	var space := float(tune["space_h"]) * 2.0 * unit
	var keys := targets.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			assert_gte((targets[keys[i]] as Vector2).distance_to(targets[keys[j]]), space - 1e-3,
				"%s and %s keep their space" % [keys[i], keys[j]])


func test_pairs_are_nearest_across_the_area() -> void:
	var a := _piece(10, 0, 0, -1)
	var b := _piece(10, 0, 8, 1)
	var pieces := _fight({"A": a}, {"B": b})
	var driver := Map3DDuelDriver.new()
	driver.run(Map3DDuelDriver.gather(ctx, pieces), DT, true, tune)
	assert_eq(driver.paired_slots("A").size(), 9, "nine a side, all paired")
	assert_true(driver.paired_slots("A").any(func(s: int) -> bool: return s >= 5), "reserves fight too")


func test_scrum_off_keeps_the_front_line() -> void:
	repo.balance["map3d_melee_scrum"] = 0.0
	var a := _piece(10, 0, 0, -1)
	var b := _piece(10, 0, 8, 1)
	var pieces := _fight({"A": a}, {"B": b})
	var driver := Map3DDuelDriver.new()
	driver.run(Map3DDuelDriver.gather(ctx, pieces), DT, true, tune)
	assert_eq(driver.scrum_targets(1), {}, "no fighting area")
	assert_false(driver.paired_slots("A").any(func(s: int) -> bool: return s >= 5), "reserves stand guard")


func test_a_withdrawing_unit_walks_back() -> void:
	var a := _piece(10, 0, 0, -1)
	var b := _piece(10, 0, 8, 1)
	var pieces := _fight({"A": a}, {"B": b})
	var driver := Map3DDuelDriver.new()
	for i in 5:
		driver.run(Map3DDuelDriver.gather(ctx, pieces), DT, true, tune)
	pieces.erase("B")  # B withdrew
	driver.run(Map3DDuelDriver.gather(ctx, pieces), DT, true, tune)
	assert_eq(driver.scrum_targets(1), {}, "the area is gone")
	for piece: Dictionary in [a, b]:
		for g: Dictionary in piece["groups"]:
			var child: Dictionary = g["piece"]
			assert_false(child.has("duel_offset"), "slot %d's offset cleared" % int(g["slot"]))
	for g: Dictionary in _claimed(a):
		assert_true(g["piece"].get("walking", false), "A:%d walks back to its slot" % int(g["slot"]))
		assert_true(g["piece"].get("step_up", false), "turned into its way, a long walk")
		g["piece"]["walking"] = false
	driver.run(Map3DDuelDriver.gather(ctx, pieces), DT, true, tune)
	assert_eq(_claimed(a).size(), 0, "arrived, every figure is handed back")


func test_a_fall_in_the_scrum_lies_where_it_fought() -> void:
	# Review focus 3: the body lies where it fought; the replacement walks from its own place to the scrum
	var a := _piece(10, 0, 0, -1)
	var b := _piece(6, 0, 8, 1)
	var pieces := _fight({"A": a}, {"B": b})
	var driver := Map3DDuelDriver.new()
	for i in 5:
		driver.run(Map3DDuelDriver.gather(ctx, pieces), DT, true, tune)
	var paired := driver.paired_slots("A")
	var free: Array = range(1, 10).filter(func(s: int) -> bool: return not s in paired)
	assert_false(free.is_empty(), "five foes for nine: some A figures wait")
	var removed: int = free[-1]
	var previous: Dictionary = {}
	for g: Dictionary in a["groups"]:
		previous[int(g["slot"])] = g["piece"]
	var kept: Array = previous.keys().filter(func(s: int) -> bool: return s != removed)
	var plan := driver.plan_falls("A", [removed], kept)
	var faller := int(plan[0]["faller"])
	assert_true(faller in paired, "a duellist falls for the removed waiting figure")
	var body: Dictionary = previous[faller]
	var fought: Vector2 = body["duel_offset"]
	var walker: Dictionary = previous[removed]
	var bodies := Map3DBattleGroups.fall_swap(previous, plan)
	assert_eq(bodies, [body])
	a["groups"] = (a["groups"] as Array).filter(func(g: Dictionary) -> bool: return int(g["slot"]) != removed)
	for g: Dictionary in a["groups"]:
		g["piece"] = previous[int(g["slot"])]
	driver.fall(body, ART, tune)
	for i in 3:
		driver.run(Map3DDuelDriver.gather(ctx, pieces), DT, true, tune)
	assert_true((body["anims"][0] as AnimationPlayer).has_meta("fallen"))
	assert_eq(body.get("duel_offset"), fought, "the body keeps its scrum offset: it lies where it fought")
	assert_true(walker.get("step_up", false), "the replacement walks up turned into its way")
	var key := "A:%d" % faller
	var target: Vector2 = driver.scrum_targets(1)[key]
	assert_true(_inside(target, driver.scrum_area(1)), "to a point in the area")
	var group: Dictionary = (a["groups"] as Array).filter(func(g: Dictionary) -> bool: return int(g["slot"]) == faller)[0]
	assert_almost_eq(((walker["duel_offset"] as Vector2) + Map3DBattleGroups.stand_xz(ctx, a, group)).distance_to(target),
		0.0, float(tune["settle_h"]) * 2.0 * unit + 1e-4, "its offset takes it there from the faller's row")
	assert_true(driver.is_duelling(walker["anims"][0]))


func test_no_scrum_against_unseen_figures() -> void:
	# Review focus 4: the foe's figures are not drawn (unseen, or a ghost): no scrum, the seen side stands in its block
	var a := _piece(10, 0, 0, -1)
	var pieces := _fight({"A": a}, {"B": {}})
	pieces.erase("B")
	pieces[Sighting.GHOST_CODE + "B"] = _piece(10, 0, 8, 1)
	var driver := Map3DDuelDriver.new()
	for i in 5:
		driver.run(Map3DDuelDriver.gather(ctx, pieces), DT, true, tune)
	assert_eq(driver.scrum_targets(1), {}, "no fighting area")
	assert_eq(_claimed(a).size(), 0, "nobody is claimed")
	for g: Dictionary in a["groups"]:
		assert_false((g["piece"] as Dictionary).has("duel_offset"), "A:%d stands in its block" % int(g["slot"]))


func test_one_area_per_battle_archers_stay_out() -> void:
	# Review focus 5: several units a side with archers among them: one area, the archers never enter it
	var att := {"A1": _piece(4, 0, 0, -1), "A2": _piece(4, 10, 0, -1), "A3": _piece(4, 20, 0, -1),
		"AR": _piece(4, 30, 0, -1, "bowman")}
	var def := {"B1": _piece(4, 0, 8, 1), "B2": _piece(4, 10, 8, 1)}
	var pieces := _fight(att, def)
	var battles := Map3DDuelDriver.gather(ctx, pieces)
	assert_eq(battles.size(), 1, "one battle record, one gathering")
	var driver := Map3DDuelDriver.new()
	driver.run(battles, DT, true, tune)
	var targets := driver.scrum_targets(1)
	assert_eq(targets.size(), 15, "every infantry figure but the bearers, both sides, in the one area")
	assert_false(targets.keys().any(func(k: String) -> bool: return k.begins_with("AR:")), "no archer in the area")
	assert_eq(_claimed(att["AR"]).size(), 0, "the archers keep their block")
	var area := driver.scrum_area(1)
	for key: String in targets:
		assert_true(_inside(targets[key], area), key + " in the one area")
