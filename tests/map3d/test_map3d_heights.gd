extends GutTest
## HEIGHTS on the 3D map (owner 2026-09-19, spec 2026-09-19-map3d-heights).

const RunDir := preload("res://tests/run_dir.gd")
var _fixture := RunDir.dir("map3d_heights").path_join("test_map3d_heights_world.tscn")
const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}

func before_all() -> void:
	var root := Node3D.new()
	root.name = "Fixture"
	root.set_meta("map3d_world", WORLD)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, _fixture)
	root.free()

func before_each() -> void:
	Game.start_campaign(42)

func _view() -> Map3DView:
	var v := Map3DView.create(Game.data, _fixture)
	v.size = Vector2(800, 450)
	add_child_autofree(v)
	v.activate()
	return v

func test_heights_is_a_theme_of_its_own() -> void:
	var v := _view()
	assert_eq(v.manor_theme(), "", "the view opens on no theme")
	v.set_manor_theme("heights")
	assert_eq(v.manor_theme(), "heights")
	assert_true(v.heat_on())
	assert_null(v.cell_lut(), "no manor colours under HEIGHTS")
	v.set_manor_theme("manors")
	assert_eq(v.manor_theme(), "manors", "the theme is remembered")
	assert_false(v.heat_on())
	v.set_manor_theme("")
	assert_false(v.heat_on())

## A manor's pixel (a land cell in a province) with no settlement and no
## landmark within 60 pack px, and the manor it lies in.
func _open_land() -> Dictionary:
	var img := (load(Game.data.cell_texture_path) as Texture2D).get_image()
	var near: Array = []
	for b: Dictionary in Game.data.burgs.values():
		near.append(Vector2(float(b["x"]), float(b["y"])))
	for m: Dictionary in Elevation.landmarks(Game.data):
		near.append(m["pos"])
	for y in range(40, img.get_height() - 40, 25):
		for x in range(40, img.get_width() - 40, 25):
			var id := MapIndex.id_at(img, Vector2i(x, y))
			if not Game.data.manors.has(id) or MapManors.province_of(Game.data, id) == "":
				continue
			var clear := true
			for q: Vector2 in near:
				if q.distance_to(Vector2(x, y)) < 60.0:
					clear = false
					break
			if clear:
				return {"px": Vector2(x + 0.5, y + 0.5), "cell": id}
	return {}

func _click(v: Map3DView, at: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = at
	v._gui_input(down)
	var up := down.duplicate() as InputEventMouseButton
	up.pressed = false
	v._gui_input(up)

## Owner 2026-10-04: neither MANORS nor HEIGHTS shows the trees (the land's
## colour is the theme's message); the plain map does.
func test_a_theme_puts_the_woods_away() -> void:
	var v := _view()
	var trees := v.get_node("Viewport/World/Trees") as Node3D
	assert_true(trees.visible, "the plain map has its woods")
	for theme_name in ["manors", "heights"]:
		v.set_manor_theme(theme_name)
		assert_false(trees.visible, "no trees under " + theme_name)
	v.set_manor_theme("")
	assert_true(trees.visible, "back off a theme, the woods return")

## The MANORS bars (owner 2026-10-04) stand only under MANORS.
func test_the_manor_bars_show_only_under_manors() -> void:
	var v := _view()
	var bars := (v.get_node("Hud") as Map3DHud).piece("ManorBars") as Map3DHudManorBars
	assert_not_null(bars)
	v.look_at_home(20000.0)
	assert_eq(bars.bars(), [], "no bars off MANORS")
	v.set_manor_theme("manors")
	assert_gt(bars.bars().size(), 0, "the crown's manors stand in bars")
	v.set_manor_theme("heights")
	assert_eq(bars.bars(), [])

func test_under_heights_land_still_means_its_province() -> void:
	var v := _view()
	var spot := _open_land()
	assert_false(spot.is_empty(), "the pack has open land")
	v.look_at_pack(spot["px"], Game.data.bal("map3d_zoom_min_m"))
	v.set_manor_theme("manors")
	assert_eq(v.pick_at(v.size * 0.5), {"kind": "manor", "cell": int(spot["cell"])})
	v.set_manor_theme("heights")
	var picked := v.pick_at(v.size * 0.5)
	assert_eq(String(picked.get("kind", "")), "province", "manors are picked only under MANORS")
	assert_eq(String(picked.get("code", "")),
		MapManors.province_of(Game.data, int(spot["cell"]), Game.state))

func test_leaving_manors_forgets_the_selected_manor() -> void:
	var v := _view()
	var spot := _open_land()
	v.look_at_pack(spot["px"], Game.data.bal("map3d_zoom_min_m"))
	v.set_manor_theme("manors")
	_click(v, v.size * 0.5)
	assert_not_null(v.line_mesh("Selection"), "the manor is outlined in gold")
	v.set_manor_theme("heights")
	assert_null(v.line_mesh("Selection"), "no manor outline off MANORS")
	assert_eq(v.selected_manor(), -1)

func _frame_on(v: Map3DView, m: Dictionary, distance: float) -> void:
	v.look_at_pack(m["pos"], distance)

func test_no_marks_off_heights() -> void:
	var v := _view()
	assert_eq(v.landmark_marks(), [])

func test_far_out_only_the_big_ones_show() -> void:
	var v := _view()
	v.set_manor_theme("heights")
	var top: Dictionary = Elevation.landmarks(Game.data)[0]
	_frame_on(v, top, (v.get_node("Hud/Landmarks") as Map3DHudLandmarks).lod_far_view_m * 1.5)
	var marks := v.landmark_marks()
	assert_gt(marks.size(), 0)
	for mk: Dictionary in marks:
		assert_eq(int(Elevation.landmark_at(Game.data, int(mk["cell"]))["lod"]), 0)
	await wait_process_frames(3)  # and the HUD draws the marks and the legend without error
	assert_gt(v.landmark_marks().size(), 0)

func test_close_in_smaller_ones_join() -> void:
	var v := _view()
	v.set_manor_theme("heights")
	var small: Dictionary = {}
	for m: Dictionary in Elevation.landmarks(Game.data):
		if int(m["lod"]) == 2:
			small = m
			break
	assert_false(small.is_empty(), "the pack has near-only landmarks")
	_frame_on(v, small, Game.data.bal("map3d_zoom_min_m") * 2.0)
	var cells: Array = v.landmark_marks().map(func(mk: Dictionary) -> int: return int(mk["cell"]))
	assert_true(int(small["cell"]) in cells)

func test_marks_never_overlap() -> void:
	var v := _view()
	v.set_manor_theme("heights")
	_frame_on(v, Elevation.landmarks(Game.data)[0], 40000.0)
	var marks := v.landmark_marks()
	assert_gt(marks.size(), 1)
	for i in marks.size():
		for j in range(i + 1, marks.size()):
			assert_false((marks[i]["rect"] as Rect2).intersects(marks[j]["rect"]))

## A mark and its height lie wholly inside the view: a number cut by the
## edge reads as a wrong number (Task 7 look pass).
func test_marks_lie_wholly_in_the_view() -> void:
	var v := _view()
	v.set_manor_theme("heights")
	var frame := Rect2(Vector2.ZERO, v.size)
	var seen := 0
	for m: Dictionary in Elevation.landmarks(Game.data).slice(0, 12):
		for dist: float in [6000.0, 20000.0, 40000.0]:
			_frame_on(v, m, dist)
			for mk: Dictionary in v.landmark_marks():
				seen += 1
				assert_true(frame.encloses(mk["rect"]), "mark %d at %s cut by the edge" % [int(mk["cell"]), mk["rect"]])
	assert_gt(seen, 0)

func test_hovering_a_mark_shows_its_tooltip_and_a_click_opens_its_card() -> void:
	var v := _view()
	v.set_manor_theme("heights")
	var top: Dictionary = Elevation.landmarks(Game.data)[0]
	_frame_on(v, top, 20000.0)
	var mk: Dictionary = {}
	for m: Dictionary in v.landmark_marks():
		if int(m["cell"]) == int(top["cell"]):
			mk = m
	assert_false(mk.is_empty())
	var picked := v.pick_at(mk["pos"])
	assert_eq(picked, {"kind": "landmark", "cell": int(top["cell"])})
	v.hover_pick(picked, mk["pos"])
	assert_true(v.hover_tooltip().begins_with(String(top["name"])))
	assert_ne(v.hovered_kingdom(), "", "a landmark on land names its kingdom")
	watch_signals(v)
	v.select_at(mk["pos"])
	assert_signal_emitted(v, "object_selected")
	var entry: Dictionary = get_signal_parameters(v, "object_selected")[0]
	assert_eq(String(entry["title"]), String(top["name"]))
	assert_eq(Array(entry["lines"]), Array(MapObjects.landmark_lines(Game.data, Game.state, int(top["cell"]))))

func test_the_legend_names_the_tier_lines_under_heights() -> void:
	var v := _view()
	assert_eq(v.heat_legend_ticks(), [], "no legend off HEIGHTS")
	assert_eq(v.heat_legend_rect(), Rect2())
	v.set_manor_theme("heights")
	var box := v.heat_legend_rect()
	var m := Game.data.bal("map_compass_margin_px")
	var legend := v.get_node("Hud/HeatLegend") as Map3DHudHeatLegend
	var h := legend.ramp_h_px
	assert_eq(box, Rect2(Vector2(m, v.size.y - m - h), Vector2(legend.ramp_w_px, h)),
		"bottom-left, inside the compass margin")
	# every supply tier above the sea line (plains is below it), bottom up, named
	# with its metres at their share of the ramp (0..the land's whole height)
	var top_m := Game.data.bal("elevation_m_per_unit") * (100.0 - Game.data.bal("elevation_sea_level"))
	var want: Array = []
	for r: Dictionary in Game.data.army_height_supply:
		var metres := Elevation.metres_of_height(Game.data, float(r["min_height"]))
		if metres > 0:
			want.push_front([String(r["tier"]).capitalize(), metres])
	var ticks := v.heat_legend_ticks()
	assert_eq(ticks.size(), want.size())
	assert_gt(ticks.size(), 0, "the high ground has tiers to name")
	for i in mini(ticks.size(), want.size()):
		assert_eq(String(ticks[i]["label"]), "%s %d m" % want[i])
		assert_almost_eq(float(ticks[i]["y"]), box.end.y - h * float(want[i][1]) / top_m, 0.01)
		assert_true(float(ticks[i]["y"]) >= box.position.y and float(ticks[i]["y"]) <= box.end.y, "inside the ramp")

## test_a_click_on_a_settlement_dot_beside_a_mark_opens_the_settlement was
## removed here (final review, 2026-09-20): it probed a two-tier pick_reach_px
## (a tight "exact dot" that always beat a mark, inside a looser "click
## floor" that could lose to a mark's grown rect) which owner 2026-09-20
## change 3 replaced with pick_reach_px as the settlement's ONE click
## geometry — see map3d_picker.gd's pick_at doc comment: "a settlement
## within reach always beats a mark". The test's probe point was constructed
## to sit inside a settlement's reach BY CONSTRUCTION (c.distance_to(at) <
## r), which under the current, single-geometry pick_at guarantees a burg
## regardless of whether marks are consulted before or after it, so the
## assertion could never fail and the precedence it named no longer exists
## as a concept to test.

## Landmarks keep off the legend's box, bottom-left.
func test_marks_keep_off_the_legend() -> void:
	var v := _view()
	v.set_manor_theme("heights")
	var box := v.heat_legend_rect()
	var top: Dictionary = Elevation.landmarks(Game.data)[0]
	_frame_on(v, top, 20000.0)
	# Pan until the top landmark's ground point sits in the legend's box.
	var xz := Map3DGeometry.pack_to_world(v._meta, top["pos"])
	var ground := Vector3(xz.x, v._height_at(xz), xz.y)
	for i in 16:
		var at := v.camera().unproject_position(ground) / v._render_scale()
		v._pan_by((box.get_center() - at) * 0.8)
	var p := v.camera().unproject_position(ground) / v._render_scale()
	assert_true(box.grow(4.0).has_point(p), "the mark's point lies in the legend (got %s, box %s)" % [p, box])
	for mk: Dictionary in v.landmark_marks():
		assert_false((mk["rect"] as Rect2).intersects(box), "mark %d over the legend" % int(mk["cell"]))

## The marks are cut once per camera pose (Task 7 bench): asked again at the
## same pose they are the same cut; a moved camera cuts them anew.
func test_marks_are_cut_once_per_pose() -> void:
	var v := _view()
	v.set_manor_theme("heights")
	_frame_on(v, Elevation.landmarks(Game.data)[0], 20000.0)
	var a := v.landmark_marks()
	assert_true(is_same(a, v.landmark_marks()), "the same pose, the same cut")
	_frame_on(v, Elevation.landmarks(Game.data)[0], 40000.0)
	assert_false(is_same(a, v.landmark_marks()), "a new pose, a new cut")
	v.set_military(true)
	var b := v.landmark_marks()
	v.set_military(false)
	assert_false(is_same(b, v.landmark_marks()), "the counters toggled, a new cut")


## The kept world (Map3DWorldCache) must not leak into the next file.
func after_all() -> void:
	Map3DWorldCache.clear()
