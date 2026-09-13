extends GutTest
## MapDashCache: the map's dashed lines cut ONCE per zoom in native
## coordinates and kept, so a pan only transforms them (bench 2026-09-13:
## re-cutting every ring every frame held the map at 6–8 fps).

const ON := MapDashCache.ON
const OFF := MapDashCache.OFF
const JUMP := MapDashCache.JUMP

func _square() -> PackedVector2Array:
	return PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(100, 100),
		Vector2(0, 100), Vector2(0, 0)])

## Arc length of the segments whose two ends share `phase`.
func _length_in(entry: Dictionary, phase: int) -> float:
	var pts: PackedVector2Array = entry["points"]
	var ph: PackedByteArray = entry["phase"]
	var total := 0.0
	for i in range(1, pts.size()):
		if ph[i - 1] == phase and ph[i] == phase:
			total += pts[i - 1].distance_to(pts[i])
	return total

func _count(entry: Dictionary, phase: int) -> int:
	var n := 0
	for p in entry["phase"]:
		if p == phase:
			n += 1
	return n

## A 400-native-px square at zoom 2 is 800 screen px; a 20/20 screen-px
## pattern is 10/10 native, so exactly twenty dashes and twenty gaps.
func test_a_line_is_cut_in_native_px_for_the_zoom() -> void:
	var cache := MapDashCache.new()
	var e := cache.cut("sq", 2.0, 0, [_square()], 20.0, 20.0)
	assert_eq((e["points"] as PackedVector2Array).size(), (e["phase"] as PackedByteArray).size())
	assert_eq((e["points"] as PackedVector2Array)[0], Vector2(0, 0), "starts on the line's first point")
	assert_eq((e["phase"] as PackedByteArray)[0], ON, "and starts with a dash")
	assert_almost_eq(_length_in(e, ON), 200.0, 0.5, "half the ring is dash")
	assert_almost_eq(_length_in(e, OFF), 200.0, 0.5, "half is gap, drawn as the pale phase")
	assert_eq(_count(e, JUMP), 0, "one line needs no jump")
	assert_eq(e["bbox"], Rect2(0, 0, 100, 100), "bbox in native px, for culling")

## The dash boundary is a HARD edge: the boundary point appears twice, a
## hair apart along the line, once in each phase — a polyline's colours
## interpolate between vertices, and without the twin the dash would fade
## across its whole length into the gap.
func test_each_dash_boundary_is_a_twin_vertex_a_hair_apart() -> void:
	var cache := MapDashCache.new()
	var e := cache.cut("sq", 2.0, 0, [_square()], 20.0, 20.0)
	var pts: PackedVector2Array = e["points"]
	var ph: PackedByteArray = e["phase"]
	var flips := 0
	for i in range(1, pts.size()):
		if ph[i] != ph[i - 1]:
			flips += 1
			assert_lt(pts[i - 1].distance_to(pts[i]), MapDashCache.HAIR * 1.5,
				"a phase change sits on a twin vertex")
	assert_eq(flips, 39, "twenty dashes and twenty gaps alternate 39 times")

## Several lines become ONE polyline with an invisible JUMP between them
## (one draw command for a whole kingdom's seams instead of thousands). The
## jump is fenced by a hair of the line's own phase on each side, so the
## strip's join at the true end of the line still runs along the line and
## the dash does not pinch there.
func test_lines_are_joined_by_an_invisible_jump() -> void:
	var cache := MapDashCache.new()
	var a := PackedVector2Array([Vector2(0, 0), Vector2(50, 0)])
	var b := PackedVector2Array([Vector2(0, 30), Vector2(50, 30)])
	var e := cache.cut("two", 1.0, 0, [a, b], 10.0, 10.0)
	assert_eq(_count(e, JUMP), 2, "the jump is two vertices")
	var pts: PackedVector2Array = e["points"]
	var ph: PackedByteArray = e["phase"]
	var j := -1
	for i in pts.size():
		if ph[i] == JUMP:
			j = i
			break
	assert_almost_eq(pts[j].x, 50.0, MapDashCache.HAIR * 3.0, "it leaves at a's end")
	assert_almost_eq(pts[j].y, 0.0, 0.001)
	assert_ne(ph[j - 1], JUMP, "fenced by a's own phase")
	assert_almost_eq(pts[j - 1].distance_to(Vector2(50, 0)), MapDashCache.HAIR, 0.0001)
	assert_almost_eq(pts[j + 1].x, 0.0, MapDashCache.HAIR * 3.0, "and lands at b's start")
	assert_almost_eq(pts[j + 1].y, 30.0, 0.001)
	assert_ne(ph[j + 2], JUMP, "fenced by b's own phase")
	assert_almost_eq(pts[j + 2].distance_to(Vector2(0, 30)), MapDashCache.HAIR, 0.0001)
	assert_almost_eq(_length_in(e, ON), 60.0, 0.5, "each line cut on its own: 3 dashes of 10 each")
	assert_eq(e["bbox"], Rect2(0, 0, 50, 30), "bbox is the union")

func test_a_zero_dash_or_gap_is_solid() -> void:
	var cache := MapDashCache.new()
	var e := cache.cut("solid", 1.0, 0, [_square()], 0.0, 9.0)
	assert_eq(e["points"], _square(), "the line itself, untouched")
	assert_eq(_count(e, ON), 5)
	assert_eq(_count(e, OFF), 0)

## Cut once per (zoom, version): a pan asks again and gets the same entry
## back; a zoom or an ownership change empties the cache.
func test_cut_once_per_zoom_and_version() -> void:
	var cache := MapDashCache.new()
	var first := cache.cut("sq", 2.0, 0, [_square()], 9.0, 9.0)
	assert_eq(cache.builds, 1)
	var again := cache.cut("sq", 2.0, 0, [_square()], 9.0, 9.0)
	assert_eq(cache.builds, 1, "a second ask at the same zoom does not cut")
	assert_same(again, first, "it is the same entry")
	cache.cut("other", 2.0, 0, [_square()], 9.0, 9.0)
	assert_eq(cache.builds, 2, "another line is cut on its own")
	assert_eq(cache.size(), 2)
	cache.cut("sq", 3.0, 0, [_square()], 9.0, 9.0)
	assert_eq(cache.builds, 3, "a new zoom cuts again")
	assert_eq(cache.size(), 1, "and dropped every other zoom's entries")
	cache.cut("sq", 3.0, 7, [_square()], 9.0, 9.0)
	assert_eq(cache.builds, 4, "a new version (ownership) cuts again")

## Zoomed out, the rings carry several vertices per screen px; a cut thins
## them to a minimum step in screen px, keeping both ends.
func test_a_cut_thins_the_line_to_a_screen_px_step() -> void:
	var line := PackedVector2Array()
	for i in 101:
		line.append(Vector2(float(i), 0.0))
	var thinned := MapDashCache.thin(line, 2.5)
	assert_eq(thinned.size(), 35, "0, 3, 6 ... 99 and the end")
	assert_eq(thinned[0], Vector2(0, 0))
	assert_eq(thinned[1], Vector2(3, 0))
	assert_eq(thinned[thinned.size() - 1], Vector2(100, 0), "the end is always kept")
	assert_eq(MapDashCache.thin(line, 0.0), line, "step 0 keeps everything")
	var cache := MapDashCache.new()
	# 1.25 screen px at zoom 0.5 is 2.5 native px; solid, so no twins.
	var e := cache.cut("line", 0.5, 0, [line], 0.0, 0.0, 1.25)
	assert_eq((e["points"] as PackedVector2Array).size(), 35)
	var full := cache.cut("full", 0.5, 0, [line], 0.0, 0.0)
	assert_eq((full["points"] as PackedVector2Array).size(), 101, "no step, no thinning")

## The view's lines cost something to gather (a kingdom's rings closed, a
## realm's seams), so cut_lazy takes a builder and calls it only on a miss.
func test_cut_lazy_gathers_the_lines_only_on_a_miss() -> void:
	var cache := MapDashCache.new()
	# A lambda captures an int by value; the count lives in an array.
	var gathered := [0]
	var build := func() -> Array:
		gathered[0] += 1
		return [_square()]
	var first := cache.cut_lazy("sq", 2.0, 0, build, 9.0, 9.0)
	assert_eq(gathered[0], 1, "gathered once to cut")
	assert_eq(cache.builds, 1)
	var again := cache.cut_lazy("sq", 2.0, 0, build, 9.0, 9.0)
	assert_eq(gathered[0], 1, "a hit gathers nothing")
	assert_same(again, first)
	cache.cut_lazy("sq", 3.0, 0, build, 9.0, 9.0)
	assert_eq(gathered[0], 2, "a new zoom gathers again")
	cache.cut_lazy("sq", 3.0, 1, build, 9.0, 9.0)
	assert_eq(gathered[0], 3, "so does a new version")

## Colours per vertex for a colour pair: ON in the ink, OFF in the pale (or
## a clear gap), JUMP always clear. Built once per pair and kept on the entry.
func test_colours_follow_the_phase_and_are_kept_per_pair() -> void:
	var cache := MapDashCache.new()
	var a := PackedVector2Array([Vector2(0, 0), Vector2(50, 0)])
	var b := PackedVector2Array([Vector2(0, 30), Vector2(50, 30)])
	var e := cache.cut("two", 1.0, 0, [a, b], 10.0, 10.0)
	var ink := Color(0.1, 0.2, 0.3, 0.9)
	var pale := Color(0.9, 0.8, 0.7, 0.9)
	var cols := cache.colors(e, ink, pale)
	var ph: PackedByteArray = e["phase"]
	assert_eq(cols.size(), ph.size())
	for i in ph.size():
		match ph[i]:
			ON:
				assert_eq(cols[i], ink)
			OFF:
				assert_eq(cols[i], pale)
			JUMP:
				assert_eq(cols[i].a, 0.0, "a jump is invisible")
	assert_same(cache.colors(e, ink, pale), cols, "the same pair is not rebuilt")
	var clear := Color(pale, 0.0)
	var other := cache.colors(e, ink, clear)
	assert_ne(other, cols, "a different pair is its own array")
