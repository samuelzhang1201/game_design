extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The dust a marching column raises (owner 2026-10-07: 扬起的一串灰尘，短距离，
## 持续一天左右): puffs only while a piece walks and the clock runs, a short
## string behind it, gone a day after.

const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}


## A units layer whose drawn spots the test sets.
@warning_ignore("missing_tool")
class FakeUnits extends Map3DLayerUnits:
	var pos: Dictionary = {}

	func shown_positions() -> Dictionary:
		return pos


var _s: GameState
var _clock := 1
var _share := 0.0


func _layer() -> Array:
	var repo := SuiteData.repo()
	_s = SuiteData.campaign(repo, 42)
	var ctx := Map3DContext.new(repo, WORLD)
	ctx.view_size = Vector2(800, 450)
	ctx.state_fn = func() -> GameState: return _s
	ctx.clock_fn = func() -> int: return _clock
	ctx.day_fn = func() -> float: return _share
	var host := Node3D.new()
	add_child_autofree(host)
	var units := FakeUnits.new()
	units.name = "Units"
	host.add_child(units)
	var dust := Map3DLayerDust.new()
	host.add_child(dust)
	dust.bind(ctx)
	var ref_m := Map3DGeometry.distance_for_bar(repo, WORLD, repo.bal("map3d_zoom_start_scale"), 450.0)
	var h := Map3DUnits.height_m(repo, repo.bal("map3d_fov_deg"), 450.0, ref_m)
	return [dust, units, h]


func test_a_puff_fades_over_the_strings_last_half() -> void:
	assert_eq(Map3DLayerDust.fade_behind(0.0, 100.0), 1.0)
	assert_eq(Map3DLayerDust.fade_behind(50.0, 100.0), 1.0, "whole over the first half")
	assert_almost_eq(Map3DLayerDust.fade_behind(75.0, 100.0), 0.5, 0.0001)
	assert_eq(Map3DLayerDust.fade_behind(100.0, 100.0), 0.0, "gone at its end")
	assert_true(Map3DLayerDust.alive(10.0, 10.9, 1.0, 20.0, 100.0))
	assert_false(Map3DLayerDust.alive(10.0, 11.0, 1.0, 20.0, 100.0), "a day on, settled")
	assert_false(Map3DLayerDust.alive(10.0, 10.1, 1.0, 100.0, 100.0), "too far behind")


func test_dust_rises_only_while_a_piece_walks_and_the_clock_runs() -> void:
	var got := _layer()
	var dust: Map3DLayerDust = got[0]
	var units: FakeUnits = got[1]
	var h: float = got[2]
	units.pos = {"r": Vector2(0, 0)}
	dust.step()
	units.pos = {"r": Vector2(h * 2.0 * 0.9, 0)}
	_clock = 0
	dust.step()
	assert_eq(dust.puff_count(), 0, "a paused clock raises nothing")
	_clock = 1
	for i in 20:
		units.pos = {"r": Vector2(h * 1.5 + h * 0.5 * float(i), 0)}
		dust.step()
	assert_gt(dust.puff_count(), 3, "a walking column raises a string of dust")
	var n := dust.puff_count()
	assert_lte(float(n), dust.tail_share / dust.step_share + 2.0, "a short string, never longer than its tail")
	for i in 5:
		dust.step()  # it halts
	assert_eq(dust.puff_count(), n, "a halted column raises no more")
	_share = 0.5
	dust.step()
	assert_eq(dust.puff_count(), n, "half a day on, the dust still hangs")
	_s.day += 1
	_share = 0.6
	dust.step()
	assert_eq(dust.puff_count(), 0, "a day on, it has settled")


func test_a_jump_raises_no_dust_across_the_gap() -> void:
	var got := _layer()
	var dust: Map3DLayerDust = got[0]
	var units: FakeUnits = got[1]
	var h: float = got[2]
	units.pos = {"r": Vector2(0, 0)}
	dust.step()
	units.pos = {"r": Vector2(h * 40.0, 0)}
	dust.step()
	assert_eq(dust.puff_count(), 0, "a snapped piece leaves no trail of dust behind it")
