extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## A group's figures do not march in lock-step (owner 2026-10-12, R5): each
## starts its clip at a hashed phase, jitters its pace (clamped after), and trails
## its slot by a lag spring. No timers: everything is hashed from regiment id +
## figure index, reproducible, and inside the balance ranges.

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()


func _anim() -> AnimationPlayer:
	var anim := AnimationPlayer.new()
	var lib := AnimationLibrary.new()
	for name in ["MARCH", "STANDBY"]:
		var a := Animation.new()
		a.length = 2.0
		a.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation(name, a)
	anim.add_animation_library("", lib)
	add_child_autofree(anim)
	return anim


func test_phase_hashed_in_range_and_stable() -> void:
	var seen := {}
	for i in 9:
		var p := Map3DMarchLag.phase("reg_a", i)
		assert_eq(p, Map3DMarchLag.phase("reg_a", i), "stable")
		assert_true(p >= 0.0 and p < 1.0, "in [0,1)")
		seen[p] = true
	assert_gte(seen.size(), 6, "the figures do not share one phase")


## Distinct is not enough: String.hash gave figure 0..8 of a real regiment code
## consecutive hashes, phases 0.1736..0.1744 — one phase in all but name. Nine
## figures' shares must SPREAD over the unit range.
func test_hashed_shares_spread_over_the_range() -> void:
	for code: String in ["kelvarn_10th_rothbridbu_regiment_foot", "reg_a"]:
		var phases: Array = range(9).map(func(i: int) -> float: return Map3DMarchLag.phase(code, i))
		assert_gte(phases.max() - phases.min(), 0.5, code + ": phases spread")
		var statures: Array = range(9).map(func(i: int) -> float: return Map3DMarchLag.stature(code, i, 0.06))
		assert_gte(statures.max() - statures.min(), 0.06, code + ": statures spread")


func test_play_march_starts_now_at_its_phase() -> void:
	var anims: Array = [_anim(), _anim(), _anim()]
	Map3DUnitRig.play(anims, "MARCH", 0.0, "reg_a")
	for i in 3:
		var anim: AnimationPlayer = anims[i]
		assert_eq(anim.current_animation, "MARCH", "no waiting on a timer")
		assert_almost_eq(anim.current_animation_position, Map3DMarchLag.phase("reg_a", i) * 2.0, 0.001)


func test_jitter_never_exceeds_anim_max() -> void:
	var lo := repo.bal("map3d_unit_anim_min")
	var hi := repo.bal("map3d_unit_anim_max")
	var spread := repo.bal("map3d_march_desync_pace")
	for i in 12:
		assert_lte(Map3DMarchLag.pace("reg_a", i, hi, spread, lo, hi), hi, "clamped after the jitter")
		assert_gte(Map3DMarchLag.pace("reg_a", i, lo, spread, lo, hi), lo)
	var paces := {}
	for i in 12:
		paces[Map3DMarchLag.pace("reg_a", i, 1.0, spread, lo, hi)] = true
	assert_gte(paces.size(), 6, "the figures do not share one pace")


## An exact-pace arm marches out of step WITHOUT a slipping foot (owner
## 2026-10-14: 步伐要参差不齐): each figure has its own stature 1 +/- spread,
## hashed, and plays the piece's rate over it — a taller man's longer stride
## at a slower cadence covers the same ground.
func test_stature_hashed_in_range_and_stable() -> void:
	var seen := {}
	for i in 9:
		var s := Map3DMarchLag.stature("reg_a", i, 0.06)
		assert_eq(s, Map3DMarchLag.stature("reg_a", i, 0.06), "stable")
		assert_true(s >= 0.94 and s <= 1.06, "within the spread")
		seen[s] = true
	assert_gte(seen.size(), 6, "the figures are not one height")
	assert_eq(Map3DMarchLag.stature("reg_a", 3, 0.0), 1.0, "no spread, one height")


## By hand: the piece's true rate 5.0; figures of statures 0.9 / 1.0 / 1.25
## play 5.556 / 5.0 / 4.0 — rate x stature is 5.0 for each, so every foot keeps
## the ground.
func test_an_exact_figure_plays_the_rate_over_its_stature() -> void:
	var node := Node3D.new()
	node.scale = Vector3.ONE * 10.0
	var anims: Array = []
	for i in 3:
		var a := AnimationPlayer.new()
		node.add_child(a)
		anims.append(a)
	var piece := {"node": node, "anims": anims, "clip_s": 2.0, "stride_m": 4.0, "exact_pace": true,
		"statures": [0.9, 1.0, 1.25]}
	Map3DUnitRig.keep_pace(repo, piece, {"from": Vector2.ZERO, "to": Vector2(800.0, 0.0), "s0": 0.0}, 0.1, 1, "R1")
	assert_almost_eq((anims[0] as AnimationPlayer).speed_scale, 5.0 / 0.9, 0.0001)
	assert_almost_eq((anims[1] as AnimationPlayer).speed_scale, 5.0, 0.0001)
	assert_almost_eq((anims[2] as AnimationPlayer).speed_scale, 4.0, 0.0001)
	node.free()


## The infantry's piece stands its figures at their statures, and keeps them.
func test_an_exact_regiment_stands_its_figures_at_their_statures() -> void:
	var reg := {}
	var all := ArmySystem.roster(repo, null)
	for c: String in all:
		if MapObjects.army_piece(repo, all[c]) == "infantry":
			reg = all[c]
			break
	assert_false(reg.is_empty(), "the suite has an infantry regiment")
	var built := Map3DFormation.of_regiment(repo, reg,
		{"slots": [Vector2(0, 0), Vector2(1, 0), Vector2(2, 0)]}, 1.0)
	var spread := repo.bal("map3d_march_stature_spread")
	var figs: Array = built["figs"]
	for i in figs.size():
		var s := Map3DMarchLag.stature(String(reg["regiment_code"]), i, spread)
		assert_almost_eq((figs[i] as Node3D).scale.x, s, 0.0001)
		assert_almost_eq(float(built["statures"][i]), s, 0.0001)
	(built["node"] as Node3D).free()


func test_tau_in_the_balance_range() -> void:
	var a := repo.bal("map3d_march_lag_min_s")
	var b := repo.bal("map3d_march_lag_max_s")
	for i in 9:
		assert_between(Map3DMarchLag.tau("reg_a", i, a, b), a, b)


func test_lag_spring_by_hand() -> void:
	# tau 0.5, v (2,0,0), dt 0.5: e^-1 = 0.367879, so each step is
	# o*0.367879 - 1.0*0.632121 -> -0.632121, -0.864665, -0.950213
	var v := Vector3(2, 0, 0)
	var o := Map3DMarchLag.step(Vector3.ZERO, v, 0.5, 0.5, 5.0)
	assert_almost_eq(o.x, -0.632121, 0.00001)
	o = Map3DMarchLag.step(o, v, 0.5, 0.5, 5.0)
	assert_almost_eq(o.x, -0.864665, 0.00001)
	o = Map3DMarchLag.step(o, v, 0.5, 0.5, 5.0)
	assert_almost_eq(o.x, -0.950213, 0.00001)
	o = Map3DMarchLag.step(o, v, 0.5, 0.5, 0.9)
	assert_almost_eq(o.length(), 0.9, 0.00001, "held to the cap")
	assert_lt(o.x, 0.0, "behind its slot")
	# standing: the offset relaxes by e^-1 a step
	assert_almost_eq(Map3DMarchLag.step(Vector3(-1, 0, 0), Vector3.ZERO, 0.5, 0.5, 5.0).x, -0.367879, 0.00001)


func test_blended_play_still_seeks_march_phase() -> void:
	var anims: Array = [_anim(), _anim()]
	Map3DUnitRig.play(anims, "MARCH", 0.2, "reg_a")
	for i in 2:
		var anim: AnimationPlayer = anims[i]
		assert_almost_eq(anim.current_animation_position, Map3DMarchLag.phase("reg_a", i) * 2.0, 0.001)


## A piece of two figures at x = -1 and +1, lag cap 0.2 m (tau range 0.25..0.7).
func _lag_piece() -> Dictionary:
	var node := Node3D.new()
	add_child_autofree(node)
	var figs: Array = []
	for x in [-1.0, 1.0]:
		var f := Node3D.new()
		f.position = Vector3(x, 0, 0)
		node.add_child(f)
		figs.append(f)
	var glow := Node3D.new()
	glow.name = "Map3DUnitGlow"
	node.add_child(glow)  # a selection quad, after the figures were taken
	return {"node": node, "figs": figs, "lag_cap": 0.2,
		"slots": [Vector3(-1, 0, 0), Vector3(1, 0, 0)]}


func test_steady_lag_is_tau_over_max_times_cap() -> void:
	# v limited to cap / max_s = 0.2 / 0.7 = 0.285714 m/s; steady -v*tau:
	# tau 0.25 -> 0.0714286, tau 0.5 -> 0.142857 (a 3 m/s march alike);
	# max_s pinned here so the formula is checked, not the tuning
	repo.balance["map3d_march_lag_max_s"] = 0.7
	var piece := _lag_piece()
	Map3DUnitRig.lag(repo, piece, "reg_a", Vector2(1, 0), 0.0)  # builds the caches
	piece["taus"] = [0.25, 0.5]
	Map3DUnitRig.lag(repo, piece, "reg_a", Vector2(3, 0), 5.0)
	var figs: Array = piece["figs"]
	assert_almost_eq((figs[0] as Node3D).position.x, -1.0 - 0.0714286, 0.00001)
	assert_almost_eq((figs[1] as Node3D).position.x, 1.0 - 0.142857, 0.00001)
	var glow: Node3D = (piece["node"] as Node3D).get_child(2)
	assert_eq(glow.position, Vector3.ZERO, "the glow is never a figure")


func test_figures_settle_back_and_pause_freezes() -> void:
	var piece := _lag_piece()
	Map3DUnitRig.lag(repo, piece, "reg_a", Vector2(1, 0), 0.0)
	piece["taus"] = [0.25, 0.5]
	Map3DUnitRig.lag(repo, piece, "reg_a", Vector2(3, 0), 5.0)
	var figs: Array = piece["figs"]
	var held := (figs[1] as Node3D).position
	Map3DUnitRig.lag(repo, piece, "reg_a", Vector2.ZERO, 0.0)
	assert_eq((figs[1] as Node3D).position, held, "dt 0: a paused column keeps its offsets")
	for _i in 6:
		Map3DUnitRig.lag(repo, piece, "reg_a", Vector2.ZERO, 5.0)
	assert_eq((figs[0] as Node3D).position, Vector3(-1, 0, 0), "settled in its slot")
	assert_eq((figs[1] as Node3D).position, Vector3(1, 0, 0))
	assert_eq((piece["node"] as Node3D).get_child(2).position, Vector3.ZERO, "glow put")
