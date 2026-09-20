extends GutTest
## HEIGHTS on the 3D map (owner 2026-09-19, spec 2026-09-19-map3d-heights).

const FIXTURE := "user://test_map3d_heights_world.tscn"
const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}

func before_all() -> void:
	var root := Node3D.new()
	root.name = "Fixture"
	root.set_meta("map3d_world", WORLD)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, FIXTURE)
	root.free()

func before_each() -> void:
	Game.start_campaign(42)

func _view() -> Map3DView:
	var v := Map3DView.create(Game.data, FIXTURE)
	v.size = Vector2(800, 450)
	add_child_autofree(v)
	v.activate()
	return v

func test_heights_is_a_theme_of_its_own() -> void:
	var v := _view()
	v.set_manor_theme("heights")
	assert_eq(v.manor_theme(), "heights")
	assert_true(v.heat_on())
	assert_null(v.cell_lut(), "no manor colours under HEIGHTS")
	v.set_manor_theme("manors")
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
	_frame_on(v, top, Game.data.bal("map3d_landmark_lod_far_view_m") * 1.5)
	var marks := v.landmark_marks()
	assert_gt(marks.size(), 0)
	for mk: Dictionary in marks:
		assert_eq(int(Elevation.landmark_at(Game.data, int(mk["cell"]))["lod"]), 0)

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
	assert_eq(box, Rect2(Vector2(m, v.size.y - m - 160.0), Vector2(14.0, 160.0)))
	var ticks := v.heat_legend_ticks()
	# (45-20)*30, (62-20)*30, (72-20)*30 over a 2400 m ramp; plains (0) is below the sea line.
	assert_eq(ticks.map(func(t: Dictionary) -> String: return String(t["label"])),
		["Hills 750 m", "Mountains 1260 m", "Peak 1560 m"])
	assert_almost_eq(float(ticks[0]["y"]), box.end.y - 160.0 * 750.0 / 2400.0, 0.01)
	assert_almost_eq(float(ticks[2]["y"]), box.end.y - 160.0 * 1560.0 / 2400.0, 0.01)

func test_the_hud_draws_marks_and_legend_without_error() -> void:
	var v := _view()
	v.set_manor_theme("heights")
	_frame_on(v, Elevation.landmarks(Game.data)[0], 20000.0)
	await wait_process_frames(3)
	assert_gt(v.landmark_marks().size(), 0)

## A burg on screen now: its code, its centre and its click reach, design px
## (pick_reach_px — its own geometry, not whether a dot is drawn there).
func _burgs_on_screen(v: Map3DView) -> Array:
	var out: Array = []
	var s := v._render_scale()
	var cam := v.camera()
	for code: String in Game.data.burgs:
		var burg: Dictionary = Game.data.burgs[code]
		var spec: Dictionary = Game.data.map3d_settlements[String(burg.get("group", ""))]
		var bxz := v._burg_xz(burg)
		var world := Vector3(bxz.x, v._height_at(bxz), bxz.y)
		var dist_m := cam.global_position.distance_to(world)
		if cam.is_position_behind(world) or dist_m >= float(spec["max_view_m"]) * Game.data.bal("map3d_ring_fade_start"):
			continue
		out.append({"code": code, "c": cam.unproject_position(world) / s,
			"r": v.pick_reach_px(code, spec, dist_m)})
	return out

## The point of `rect` nearest `c`.
func _nearest_in(rect: Rect2, c: Vector2) -> Vector2:
	return Vector2(clampf(c.x, rect.position.x, rect.end.x), clampf(c.y, rect.position.y, rect.end.y))

## A click on a settlement's dot opens the settlement even where a landmark's
## grown pick rect reaches over it (Task 6 review: the grown rect stole it).
func test_a_click_on_a_settlement_dot_beside_a_mark_opens_the_settlement() -> void:
	var v := _view()
	v.set_manor_theme("heights")
	var grow := Game.data.bal("map3d_pick_px") * 0.5
	var found := {}
	for m: Dictionary in Elevation.landmarks(Game.data):
		for dist: float in [Game.data.bal("map3d_zoom_min_m") * 2.0, 6000.0, 15000.0]:
			_frame_on(v, m, dist)
			var burgs := _burgs_on_screen(v)
			for mk: Dictionary in v.landmark_marks():
				var grown := (mk["rect"] as Rect2).grow(grow)
				for b: Dictionary in burgs:
					var q := _nearest_in(grown, b["c"])
					var at: Vector2 = (b["c"] as Vector2).move_toward(q, float(b["r"]) * 0.8)
					if grown.has_point(at) and (b["c"] as Vector2).distance_to(at) < float(b["r"]):
						found = {"at": at, "code": b["code"]}
						break
				if not found.is_empty():
					break
			if not found.is_empty():
				break
		if not found.is_empty():
			break
	assert_false(found.is_empty(), "somewhere a mark's grown rect reaches a settlement's dot")
	if found.is_empty():
		return
	var picked := v.pick_at(found["at"])
	assert_eq(String(picked.get("kind", "")), "burg")

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

## The legend steps back (drawn faint) while a MEASUREMENT ruler crosses it,
## so the ruler's reading is never printed over a tier's name (Task 7 look pass).
func test_the_legend_yields_to_a_ruler_across_it() -> void:
	var v := _view()
	v.set_manor_theme("heights")
	v.look_at_home(40000.0)
	assert_false(v.heat_legend_yields(), "no ruler, no yielding")
	v.ruler_on = true
	var box := v.heat_legend_rect()
	# a ruler far from the legend, top-right
	v._ruler_click(v.size * Vector2(0.6, 0.2))
	v._ruler_click(v.size * Vector2(0.8, 0.3))
	assert_false(v.heat_legend_yields(), "a ruler elsewhere leaves the legend alone")
	# one from the legend's foot out across its labels
	v._ruler_click(box.position + Vector2(4.0, box.size.y - 4.0))
	v._ruler_click(box.position + Vector2(260.0, -120.0))
	assert_true(v.heat_legend_yields())
	v.ruler_on = false
	assert_false(v.heat_legend_yields(), "the tab off, the legend back")

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
