# tests/ledger3d/test_ledger_view_galaxy.gd
extends GutTest
## The galaxy view (spec 2026-09-30-ledger-galaxy-design §5-§6). Headless
## instancing is fine: the dummy renderer draws nothing, the scene, its nodes
## and its maths are all there.

var repo: DataRepository
var s: GameState
var view: LedgerView3D


func before_each() -> void:
	repo = DataRepository.load_all("res://data")
	s = GameState.new_campaign(repo, 42)
	RealmEconomy.forget()
	view = (load("res://scenes/ledger/ledger_view.tscn") as PackedScene).instantiate()
	add_child_autofree(view)
	view.set_anchors_preset(Control.PRESET_TOP_LEFT)  # set its own size, not the parent's
	view.size = Vector2(1000, 600)
	view.bind(repo)


func after_each() -> void:
	RealmEconomy.forget()


func _show(opened: Dictionary = {}) -> Dictionary:
	var g := Ledger.galaxy(repo, s, opened)
	view.show_snapshot(g, false)
	view.settle_now()
	return g


func _first(prefix: String) -> String:
	for id: String in view.stars():
		if id.begins_with(prefix):
			return id
	return ""


func test_every_node_is_one_star_and_every_link_is_drawn() -> void:
	var g := _show()
	assert_eq(view.stars().size(), (g["nodes"] as Array).size())
	var drawn := {}
	for seg: Dictionary in view.segments():
		drawn[String(seg["link"])] = true
	for l: Dictionary in g["links"]:
		assert_true(drawn.has(String(l["id"])), String(l["id"]))


func test_a_star_wears_its_clusters_colour() -> void:
	_show()
	var c := view.star_colour("character:you")
	var want: Color = repo.ledger_palette["cluster_court"]
	assert_eq(Color(c, 1.0), Color(want, 1.0))


func test_choosing_a_cluster_dims_the_others() -> void:
	_show()
	view.focus_cluster("court")
	assert_eq(view.cluster(), "court")
	assert_eq(view.star_colour("character:you").a, 1.0)
	assert_almost_eq(view.star_colour(_first("regiment:")).a, repo.bal("ledger_galaxy_other_fade"), 0.001)
	view.focus_cluster("all")
	assert_eq(view.star_colour(_first("regiment:")).a, 1.0, "All dims nothing")


func test_selecting_a_star_lights_its_web_and_fades_the_rest() -> void:
	_show()
	view.select("character:you")
	var lit := -1.0
	var faint := -1.0
	for seg: Dictionary in view.segments():
		var mine := String(seg["a_id"]) == "character:you" or String(seg["b_id"]) == "character:you"
		if mine:
			lit = maxf(lit, (seg["ca"] as Color).a)
		else:
			faint = maxf(faint, (seg["ca"] as Color).a)
	assert_gt(lit, faint, "his web stands out")
	assert_lte(faint, pow(repo.bal("ledger_focus_fade"), 2.2) + 0.001, "the rest at the focus fade, as the eye reads it")


func test_a_vanished_selection_clears() -> void:
	var g := _show()
	view.select("character:you")
	var g2: Dictionary = g.duplicate(true)
	g2["nodes"] = (g2["nodes"] as Array).filter(func(n: Dictionary) -> bool: return String(n["id"]) != "character:you")
	g2["links"] = (g2["links"] as Array).filter(func(l: Dictionary) -> bool:
		return String(l["from"]) != "character:you" and String(l["to"]) != "character:you")
	view.show_snapshot(g2, true)
	assert_eq(view._selected, "")


func test_a_star_is_picked_in_3d_and_in_2d() -> void:
	_show()
	var id := "character:you"
	assert_eq(view._pick(view.screen_pos_of(id) as Vector2), {"kind": "sphere", "id": id})
	view.set_flat(true)
	view.settle_now()
	assert_true(view.is_flat())
	assert_eq(view.camera().projection, Camera3D.PROJECTION_ORTHOGONAL)
	for sid: String in view.stars():
		assert_eq(view.drawn(sid).y, 0.0, sid)
	assert_eq(String(view._pick(view.screen_pos_of(id) as Vector2).get("id", "")), id, "picked in the flat chart")


func test_link_width_uniform_follows_the_viewport() -> void:
	_show()
	view.size = Vector2(800, 500)
	view._fit_viewport()
	view._update_link_uniforms()
	var h := float(view._viewport.size.y)
	assert_almost_eq(float(view.link_material().get_shader_parameter("px_per_dist")),
		2.0 * tan(deg_to_rad(view.camera().fov) * 0.5) / h, 1e-7)


func test_a_drag_pins_the_star_and_moves_only_its_links() -> void:
	_show()
	var id := "character:you"
	var before := {}
	for seg: Dictionary in view.segments():
		before[String(seg["id"])] = [seg["a"], seg["b"]]
	var at := view.screen_pos_of(id) as Vector2
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = at
	view._gui_input(press)
	var mm := InputEventMouseMotion.new()
	mm.position = at + Vector2(60, 0)
	mm.relative = Vector2(60, 0)
	view._gui_input(mm)
	var up := press.duplicate() as InputEventMouseButton
	up.pressed = false
	up.position = mm.position
	view._gui_input(up)
	assert_true(view._lay.pinned.has(id), "held where the pointer left it")
	for seg: Dictionary in view.segments():
		var mine := String(seg["a_id"]) == id or String(seg["b_id"]) == id
		var was: Array = before[String(seg["id"])]
		if not mine:
			assert_eq([seg["a"], seg["b"]], was, "untouched: " + String(seg["id"]))


func test_a_node_and_an_edge_written_down_are_drawn() -> void:
	repo.ledger_types.append({"type_id": "shrine", "layer": "things", "lenses": "court|all", "label": "Shrines",
		"icon": "", "x": "0", "z": "0", "instances": "static", "status": "live", "milestone": "",
		"cluster": "court", "fold_to": "", "star": "instance"})
	repo.ledger_links.append({"link_id": "venerates", "from_type": "character", "to_type": "shrine",
		"verb": "venerates", "lenses": "court|all", "status": "live", "resolver": "static", "governor_seat": "",
		"governor_kind": "", "milestone": "", "planned_note": "", "look": "tie"})
	repo.ledger_static_nodes.append({"node_id": "shrine:saint_odo", "type_id": "shrine", "label": "Shrine of St Odo",
		"note": ""})
	repo.ledger_static_links.append({"link_id": "venerates", "from": "character:you", "to": "shrine:saint_odo",
		"flow": 40, "note": ""})
	_show()
	assert_has(view.stars(), "shrine:saint_odo")
	assert_true(view.segments().any(func(seg: Dictionary) -> bool:
		return String(seg["link"]) == "venerates|character:you|shrine:saint_odo"))


func _drag(id: String, by: Vector2) -> void:
	var at := view.screen_pos_of(id) as Vector2
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = at
	view._gui_input(press)
	var mm := InputEventMouseMotion.new()
	mm.position = at + by
	mm.relative = by
	view._gui_input(mm)
	var up := press.duplicate() as InputEventMouseButton
	up.pressed = false
	up.position = mm.position
	view._gui_input(up)


## Review focus 4: a pinned star keeps its pin across a redraw and a turn to
## the flat chart, and a click there still finds it.
func test_a_pin_survives_a_redraw_and_the_flat_chart() -> void:
	var g := _show()
	var id := "character:you"
	_drag(id, Vector2(60, 0))
	var held := view.drawn(id)
	view.show_snapshot(g, true)
	view.settle_now()
	assert_true(view._lay.pinned.has(id), "a redraw keeps the pin")
	assert_eq(view.drawn(id), held, "and the star where the pointer left it")
	view.set_flat(true)
	view.settle_now()
	assert_true(view._lay.pinned.has(id), "the flat chart keeps the pin")
	assert_eq(view.drawn(id), Vector3(held.x, 0.0, held.z), "laid flat where it was held")
	assert_eq(String(view._pick(view.screen_pos_of(id) as Vector2).get("id", "")), id, "and a click finds it")


## The star under a drag vanishes from the next snapshot (a courier
## arrived): the drag ends quietly, the rest of the gesture neither pans
## nor turns.
func test_a_drag_survives_its_star_vanishing() -> void:
	var g := _show()
	var id := "character:you"
	var at := view.screen_pos_of(id) as Vector2
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = at
	view._gui_input(press)
	assert_eq(view._drag_id, id)
	var g2: Dictionary = g.duplicate(true)
	g2["nodes"] = (g2["nodes"] as Array).filter(func(n: Dictionary) -> bool: return String(n["id"]) != id)
	g2["links"] = (g2["links"] as Array).filter(func(l: Dictionary) -> bool:
		return String(l["from"]) != id and String(l["to"]) != id)
	view.show_snapshot(g2, true)
	var pose := view.orbit().pose()
	var mm := InputEventMouseMotion.new()
	mm.position = at + Vector2(60, 25)
	mm.relative = Vector2(60, 25)
	view._gui_input(mm)
	var up := press.duplicate() as InputEventMouseButton
	up.pressed = false
	up.position = mm.position
	view._gui_input(up)
	assert_eq(view._drag_id, "", "the drag ended")
	assert_eq(view.orbit().pose(), pose, "the rest of the gesture neither pans nor turns")
	assert_false(view.stars().has(id), "the star is gone")


## An old lens snapshot (nodes with no cluster) still draws: LedgerScreen
## hands one until it moves to the galaxy.
func test_a_lens_snapshot_draws_without_error() -> void:
	var snap := Ledger.snapshot(repo, s, "court", {})
	view.show_snapshot(snap, false)
	view.settle_now()
	assert_eq(view.stars().size(), (snap["nodes"] as Array).size())


## The chart settles as the player sees it: frame by frame through _process
## (never settle_now), the layout's own step and budget.
func _settle_by_frames() -> void:
	for i in 5000:
		if view._lay.settled() and view._mode_left <= 0.0:
			break
		view._process(1.0 / 60.0)
	view._process(1.0 / 60.0)


## I1: the opening frame is not the unsettled chart's — a framed camera
## frames again while the chart settles, so once settled every star is on
## the screen.
func test_the_opening_view_holds_every_star_once_settled() -> void:
	view.show_snapshot(Ledger.galaxy(repo, s, {}), false)
	_settle_by_frames()
	assert_true(view._lay.settled())
	var box := Rect2(Vector2.ZERO, view.size)
	for id: String in view.stars():
		var at: Variant = view.screen_pos_of(id)
		assert_not_null(at, id)
		var r := view._screen_radius(id)
		assert_true(box.encloses(Rect2((at as Vector2) - Vector2(r, r), Vector2(r, r) * 2.0)), "on screen: " + id)


## I1: a camera gesture takes the framing away; the settling chart no longer
## moves the camera.
func test_a_camera_gesture_ends_the_framing() -> void:
	view.show_snapshot(Ledger.galaxy(repo, s, {}), false)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	view._gui_input(wheel)
	var pose := view.orbit().pose()
	_settle_by_frames()
	assert_false(view._framed)
	assert_eq(view.orbit().pose(), pose, "the camera stays where the player put it")


## I2: at the opening view every cluster's title survives the cull — over its
## highest star and a name line, never on a disc.
func test_every_cluster_title_stands_at_the_opening_view() -> void:
	view.show_snapshot(Ledger.galaxy(repo, s, {}), false)
	_settle_by_frames()
	var titles: Array = view._hud._entries.filter(func(e: Dictionary) -> bool: return bool(e.get("title", false)))
	var want := {}
	for id: String in view.stars():
		want[String(view._nodes[id].get("cluster", ""))] = true
	assert_eq(titles.size(), want.size(), "one title per cluster: %s" % [titles.map(func(e: Dictionary) -> String:
		return String(e["text"]))])


## I6: a star behind the camera's edge is not counted in its title nor named
## as a hub.
func test_only_stars_in_view_count() -> void:
	_show()
	view.orbit().zoom(0.2)
	view._framed = false
	view._apply_camera()
	view._update_hud()
	var inside := 0
	for id: String in view.stars():
		if view._in_view(view.screen_pos_of(id)):
			inside += 1
	assert_lt(inside, view.stars().size(), "zoomed in, some stars leave the view")
	var counted := 0
	for e: Dictionary in view._hud._entries:
		if bool(e.get("title", false)):
			counted += int(String(e["text"]).get_slice("·", 1).strip_edges())
	assert_lte(counted, inside, "titles count only what is in view")


## I4: 3D -> 2D -> 3D gives the chart back as it stood.
func test_a_round_trip_through_the_flat_chart_keeps_the_3d_places() -> void:
	_show()
	var before := {}
	for id: String in view.stars():
		before[id] = view.drawn(id)
	view.set_flat(true)
	view.settle_now()
	view.set_flat(false)
	view.settle_now()
	for id: String in view.stars():
		assert_almost_eq(view.drawn(id), before[id] as Vector3, Vector3.ONE * 1e-4, id)


## I5: a link with no figure is as wide as the links it stands for.
func test_a_merged_link_is_as_wide_as_its_count() -> void:
	_show()
	var lo := repo.bal("ledger_link_min_px")
	var hi := repo.bal("ledger_link_max_px")
	var ref := repo.bal("ledger_link_count_ref")
	var one := {"type": "no_such_link", "flow": null, "count": 1}
	var many := {"type": "no_such_link", "flow": null, "count": int(ref)}
	assert_almost_eq(view._width_px(one), lerpf(lo, hi, log(2.0) / log(1.0 + ref)), 1e-5)
	assert_almost_eq(view._width_px(many), hi, 1e-5, "at ledger_link_count_ref, as wide as a link gets")
	var structure := {"type": "part_of", "flow": 5, "count": 3}
	assert_almost_eq(view._width_px(structure), lerpf(lo, hi, log(4.0) / log(1.0 + ref)), 1e-5,
		"a structure tie by its count, whatever its flow")


## M-a: the selected star and the hubs are named in the larger size.
func test_the_selected_star_and_hubs_are_named_larger() -> void:
	_show()
	view.select("character:you")
	var strong := repo.bal("ledger_label_strong_px")
	var label := repo.bal("ledger_label_px")
	var big := 0
	for e: Dictionary in view._hud._entries:
		if bool(e.get("title", false)):
			continue
		var px := float(e.get("px", label))
		assert_true(px == strong or px == label, String(e["text"]))
		if String(e["text"]) == String(view._nodes["character:you"]["label"]):
			assert_eq(px, strong, "the selected star")
		if px == strong:
			big += 1
	assert_gt(big, 0, "the hubs in view are named in the larger size")



## Task 11 (the look pass, 2a): no name or title is drawn in the LEDGER
## screen's own top chrome (ledger_frame_top_px: its title, lenses and crumb)
## — the framing keeps a title and a name line clear under it — at the
## opening view and at every cluster the camera flies to; the framed
## cluster's own title always stands.
func test_no_name_stands_in_the_top_chrome() -> void:
	view.show_snapshot(Ledger.galaxy(repo, s, {}), false)
	_settle_by_frames()
	var chrome := repo.bal("ledger_frame_top_px")
	for c: String in ["all", "economy", "war", "court", "intelligence"]:
		view.focus_cluster(c)
		for i in 120:
			view._process(1.0 / 60.0)
		var titled := {}
		for e: Dictionary in view._hud._entries:
			var px := float(e.get("px", repo.bal("ledger_label_px")))
			var top := (e["at"] as Vector2).y - px * 0.45
			if bool(e.get("gauges_up", false)):
				top -= LedgerHud.gauge_row_h(e.get("props", []), view._hud._gauge)
			assert_true(top >= chrome - 0.01, "%s: '%s' at %.1f stands in the chrome" % [c, e["text"], top])
			if bool(e.get("title", false)):
				titled[String(e["text"]).get_slice(" ", 0)] = true
		if c != "all":
			var label := ""
			for row: Dictionary in repo.ledger_clusters:
				if String(row["cluster"]) == c:
					label = String(row["label"])
			assert_true(titled.has(label), "%s: its own title stands (%s)" % [c, titled.keys()])


## Task 11 (2b, spec §7): the selected star is always named, however dense
## its neighbourhood — selected by a single click at the opening view, with
## no web framed.
func test_the_selected_star_is_always_named() -> void:
	view.show_snapshot(Ledger.galaxy(repo, s, {}), false)
	_settle_by_frames()
	for id: String in ["character:you", _first("character:"), _first("regiment:")]:
		view.select(id)
		var names: Array = view._hud._entries.map(func(e: Dictionary) -> String: return String(e["text"]))
		assert_true(names.has(String(view._nodes[id]["label"])), "named: " + id)


## Task 11 (2c, spec §7 `ledger_label_hubs`): the hubs — the largest stars in
## view — are always named at the opening view, a pool with its gauge row.
func test_the_hubs_are_always_named_at_the_opening_view() -> void:
	view.show_snapshot(Ledger.galaxy(repo, s, {}), false)
	_settle_by_frames()
	var by_name := {}
	for e: Dictionary in view._hud._entries:
		by_name[String(e["text"])] = e
	var hubs := view._hubs()
	assert_eq(hubs.size(), int(repo.bal("ledger_label_hubs")))
	for id: String in hubs:
		var label := String(view._nodes[id]["label"])
		assert_true(by_name.has(label), "the hub is named: " + id)
	var pool: Dictionary = by_name.get(String(view._nodes["type:strategic_goods"]["label"]), {})
	assert_false((pool.get("props", []) as Array).is_empty(), "the strategic pool keeps its gauge")


## Task 11: a hub dimmed by the selection is named only where there is room —
## it never stands on a star's disc over the web being read.
func test_a_dimmed_hub_never_stands_on_a_star() -> void:
	view.show_snapshot(Ledger.galaxy(repo, s, {}), false)
	_settle_by_frames()
	view.select("character:you")
	var discs: Array[Rect2] = []
	for id: String in view.stars():
		var at: Variant = view.screen_pos_of(id)
		if view._in_view(at):
			var r := view._screen_radius(id)
			discs.append(Rect2((at as Vector2) - Vector2(r, r), Vector2(r, r) * 2.0))
	var px := repo.bal("ledger_label_strong_px")
	for id: String in view._hubs():
		if view.star_colour(id).a >= 1.0:
			continue
		for e: Dictionary in view._hud._entries:
			if String(e["text"]) != String(view._nodes[id]["label"]):
				continue
			var font: Font = view._hud._font
			var w := font.get_string_size(String(e["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(px)).x
			var box := Rect2((e["at"] as Vector2) - Vector2(w * 0.5, px * 0.45), Vector2(w, px * 1.05))
			for d in discs:
				assert_false(d.intersects(box), "the dimmed hub %s stands on a star" % id)
