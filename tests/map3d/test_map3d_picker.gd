extends GutTest
## Map3DPicker and Map3DSelection (spec 2026-09-20 §1): the pick and the hover
## are one script, the selection another; the view re-emits their signals
## under its own names, so the screens change nothing.

const RunDir := preload("res://tests/run_dir.gd")
var _fixture := RunDir.dir("map3d_picker").path_join("test_map3d_picker_world.tscn")
const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}


class CountedSymbolView extends Map3DView:
	var marker_calls := 0
	var marks: Array = [{"code": "sample", "pos": Vector2(25, 25), "rect": Rect2(20, 20, 10, 10)}]
	func army_markers() -> Array:
		marker_calls += 1
		return marks
	func unit_rects() -> Dictionary:
		var out: Dictionary = {}
		for marker: Dictionary in army_markers(): out[marker["code"]] = marker["rect"]
		return out


class NoGroundContext extends Map3DContext:
	var ground_calls := 0
	func ground_at(_pos: Vector2) -> Variant:
		ground_calls += 1
		return null


func before_all() -> void:
	Game.start_campaign(42)
	var root := Node3D.new()
	root.name = "Fixture"
	root.set_meta("map3d_world", WORLD)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, _fixture)
	root.free()


func _view() -> Map3DView:
	var v := Map3DView.create(Game.data, _fixture)
	v.size = Vector2(800, 450)
	add_child_autofree(v)
	v.activate()
	return v


func _capital() -> String:
	return String(Game.data.kingdoms[Game.data.resolve_realm("player_realm")]["capital_burg"])


func test_the_picker_picks_what_the_view_picks() -> void:
	var v := _view()
	var picker := v.component("picker") as Map3DPicker
	assert_not_null(picker)
	# the units' pieces stand round their towns and one may cover
	# the view's middle: this asks about the town, so the layer is off
	v.set_military(false)
	var at := v.size * 0.5
	assert_eq(picker.pick_at(at), v.pick_at(at))
	assert_eq(picker.pick_at(at), {"kind": "burg", "code": _capital()}, "the capital sits mid-view")
	var pick := {"kind": "burg", "code": _capital()}
	assert_eq(Map3DPicker.kingdom_of_pick(Game.data, Game.state, pick),
		Map3DView.kingdom_of_pick(Game.data, Game.state, pick))


func test_the_selection_speaks_through_the_views_signals() -> void:
	var v := _view()
	var sel := v.component("selection") as Map3DSelection
	assert_not_null(sel)
	watch_signals(v)
	var province := String(Game.data.burgs[_capital()]["province_code"])
	sel.select({"kind": "province", "code": province})
	assert_signal_emitted_with_parameters(v, "province_selected", [province])
	assert_eq(v.selected_province(), province)
	assert_not_null(v.line_mesh("Selection"))
	v.clear_selection()
	assert_signal_emitted_with_parameters(v, "object_selected", [{}])
	assert_null(v.line_mesh("Selection"))


func test_the_hover_signals_through_the_view() -> void:
	var v := _view()
	watch_signals(v)
	v.hover_pick({"kind": "burg", "code": _capital()}, v.size * 0.5)
	assert_signal_emitted(v, "country_hovered")
	assert_ne(v.hover_tooltip(), "")
	assert_eq(v.hovered_kingdom(), (v.component("picker") as Map3DPicker).hovered_kingdom())


## A town is still clickable inside the no-dot gap (change 3, owner
## 2026-09-20): between map3d_house_view_m (9 km, houses stop) and the dot's
## near threshold (Map3DGeometry.settlement_dot_min_view_m — a SHARE of the
## reachable range since 2026-09-21, no longer a flat 40 km), a settlement
## is marked by nothing but its ground patch — picking must not depend on a
## dot that is not drawn there. The probe point is the gap's own midpoint,
## not a hardcoded distance, since the threshold now moves with the view.
func test_a_town_is_still_clickable_with_no_dot_shown_in_the_no_dot_gap() -> void:
	var v := _view()
	var code := ""
	for c: String in Game.data.burgs:
		if String(Game.data.burgs[c].get("group", "")) == "town":
			code = c
			break
	assert_ne(code, "", "the pack has a town")
	var burg: Dictionary = Game.data.burgs[code]
	var house_m: float = Game.data.bal("map3d_house_view_m")
	var ctx := v.context()
	var min_m := Map3DGeometry.settlement_dot_min_view_m(Game.data, ctx.meta, ctx.view_size.y)
	assert_gt(min_m, house_m, "the fixture's no-dot gap must be non-empty")
	var ring_m := float(Game.data.map3d_settlements[String(burg["group"])]["max_view_m"]) * Map3DLayerSettlements.fade_start()
	var far_m := minf(min_m, ring_m)
	assert_gt(far_m, house_m, "the invisible-dot probe remains inside the town's pickable range")
	var probe := (house_m + far_m) * 0.5
	assert_lt(probe, min_m)
	v.look_at_pack(Vector2(float(burg["x"]), float(burg["y"])), probe)
	assert_eq(v.pick_at(v.size * 0.5), {"kind": "burg", "code": code})


## Final review M4: a courier not yet ridden waits in the capital, and a click
## there opens the capital, not him; once he is on the road he ranks before
## the settlements again. His real rect, laid over the capital's own point.
func test_a_waiting_courier_yields_the_click_to_the_town_under_him() -> void:
	var v := _view()
	v.set_military(false)  # this comparison is courier versus town; symbol picking has its own test
	var code := ""
	for r: Dictionary in MapObjects.regiments_of(Game.data, Game.data.resolve_realm("player_realm"), Game.state):
		if CourierSystem.carries_orders(r):
			code = String(r["regiment_code"])
			break
	var c := CourierSystem.dispatch(Game.data, Game.state, CourierSystem.ORDINARY, code,
		{"action_code": "ARMY_GARRISON"})
	var layer := v.get_node("Viewport/World/Couriers") as Map3DLayerCouriers
	var at := Vector2.ZERO
	for e: Dictionary in v.context().projected_settlements():
		if String(e["code"]) == _capital():
			at = e["screen"]
	for days in [0, 1]:
		c["days"] = days
		layer.refresh()
		var entry: Dictionary = v.courier_rects()[int(c["id"])]
		assert_eq(bool(entry["waiting"]), days == 0)
		var box := entry["rect"] as Rect2
		entry["rect"] = Rect2(at - box.size * 0.5, box.size)
		assert_eq(v.pick_at(at), {"kind": "burg", "code": _capital()} if days == 0 \
			else {"kind": "courier", "id": int(c["id"])})
	Game.state.couriers.clear()


## The kept world (Map3DWorldCache) must not leak into the next file.
func after_all() -> void:
	Map3DWorldCache.clear()


func test_one_symbol_pick_reads_marker_geometry_once() -> void:
	var real_view := _view()
	var counted := CountedSymbolView.new()
	autofree(counted)
	counted.unit_symbol_mode = true
	var picker := real_view.component("picker") as Map3DPicker
	picker.view = counted
	var result := picker.pick_at(real_view.size * 0.5)
	assert_eq(counted.marker_calls, 1, "one hover reuses the same admitted marker geometry")
	assert_eq(String(result.get("kind", "")), "burg")


func test_overlapping_symbols_pick_the_top_painted_unit_on_land_and_off_terrain() -> void:
	var real_view := _view()
	var at := real_view.size * 0.5
	assert_not_null(real_view.context().ground_at(at), "first probe is over terrain")
	var counted := CountedSymbolView.new()
	autofree(counted)
	counted.unit_symbol_mode = true
	counted.marks = [
		{"code": "covered", "pos": at, "rect": Rect2(at - Vector2(10, 10), Vector2(20, 20))},
		{"code": "top", "pos": at, "rect": Rect2(at - Vector2(5, 5), Vector2(20, 20))},
	]
	var picker := real_view.component("picker") as Map3DPicker
	picker.view = counted
	assert_eq(picker.pick_at(at), {"kind": "army", "code": "top"}, "later ink covers earlier ink")
	assert_eq(counted.marker_calls, 1, "overlap resolution reads geometry only once")
	var sky := NoGroundContext.new(Game.data, WORLD)
	assert_null(sky.ground_at(at))
	sky.ground_calls = 0
	picker.ctx = sky
	counted.marker_calls = 0
	assert_eq(picker.pick_at(at), {"kind": "army", "code": "top"}, "visible ink remains pickable off terrain")
	assert_eq(counted.marker_calls, 1)
	assert_eq(sky.ground_calls, 0, "symbol hit precedes terrain lookup")
	assert_eq(counted.marks[0]["code"], "covered", "picking must not reorder the paint list")
	picker.ctx = real_view.context()
	picker.view = real_view


## Owner 2026-11-22 (有时候我无法选择一个我方军队): round a town the camps' pieces
## overlap on screen — the near piece's box covers the far one's figures — so
## the box whose CENTRE was nearest took the click, and a camped regiment beside
## its town was often unclickable until the refill moved it onto the town's
## point. A click on one of its figures picks it whenever no other regiment's
## figure stands nearer the camera on that ray, never the town under it.
func test_a_figure_clicked_picks_its_own_regiment_round_a_town() -> void:
	var v := Map3DView.create(Game.data, _fixture)
	v.size = Vector2(1600, 900)
	add_child_autofree(v)
	v.activate()
	var cam := v.context().camera
	var sc := v.context().viewport_px_scale()
	var units := v.get("_units") as Map3DLayerUnits
	var me := Game.data.resolve_realm("player_realm")
	var towns: Array = Game.state.town_seat.keys().filter(func(t: String) -> bool:
		return String(ArmySystem.regiment(Game.data, String(Game.state.town_seat[t]), Game.state).get("kingdom_code", "")) == me)
	towns.sort()
	var camped := 0
	var clicked := 0
	for dist: float in [3000.0, 8000.0]:
		for town: String in towns:
			var b: Dictionary = Game.data.burgs[town]
			v.look_at_pack(Vector2(float(b["x"]), float(b["y"])), dist)
			await wait_process_frames(3)
			var tally := _click_figures(v, me, cam, sc, units)
			camped += tally[0]
			clicked += tally[1]
	assert_gt(camped, towns.size(), "the realm's towns have regiments camped round them")
	assert_gt(clicked, camped, "their figures were clicked")


## [camped pieces, figures clicked] of kingdom `me`'s in the current frame.
func _click_figures(v: Map3DView, me: String, cam: Camera3D, sc: float, units: Map3DLayerUnits) -> Array:
	var rects := v.unit_rects()
	var camped := 0
	var clicked := 0
	for code: String in rects:
		var town := ArmyGround.camped_by(Game.data, Game.state, code)
		if town == "" or String(ArmySystem.regiment(Game.data, code, Game.state).get("kingdom_code", "")) != me:
			continue
		camped += 1
		for mi: MeshInstance3D in Map3DUnits.meshes(units.built_piece(code)["node"]):
			if not mi.is_visible_in_tree() or mi.skin == null or "_" in String(mi.name):
				continue  # a figure's body, not its gear
			var centre := (mi.global_transform * mi.get_aabb()).get_center()
			var px := cam.unproject_position(centre)
			if cam.is_position_behind(centre) or not Rect2(Vector2.ZERO, v.size * sc).has_point(px):
				continue  # off the screen: nothing to click
			var from := cam.project_ray_origin(px)
			var dir := cam.project_ray_normal(px)
			var own := _first_on_ray(units.built_piece(code), from, dir)
			var hidden := false
			for other: String in rects:
				hidden = hidden or (other != code and _first_on_ray(units.built_piece(other), from, dir) < own)
			if hidden:
				continue  # another regiment's figure is drawn over this one here
			clicked += 1
			assert_eq(v.pick_at(px / sc), {"kind": "army", "code": code}, "%s's figure is clicked" % code)
	return [camped, clicked]


func _first_on_ray(piece: Dictionary, from: Vector3, dir: Vector3) -> float:
	var best := INF
	for mi: MeshInstance3D in Map3DUnits.meshes(piece.get("node")) if piece.has("node") else []:
		var hit: Variant = (mi.global_transform * mi.get_aabb()).intersects_ray(from, dir) if mi.is_visible_in_tree() else null
		if hit != null:
			best = minf(best, from.distance_to(hit as Vector3))
	return best
