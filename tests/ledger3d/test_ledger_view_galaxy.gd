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
