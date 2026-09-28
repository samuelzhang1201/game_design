extends GutTest
## Map3DPicker and Map3DSelection (spec 2026-09-20 §1): the pick and the hover
## are one script, the selection another; the view re-emits their signals
## under its own names, so the screens change nothing.

const RunDir := preload("res://tests/run_dir.gd")
var _fixture := RunDir.dir("map3d_picker").path_join("test_map3d_picker_world.tscn")
const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}


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
	var probe := (house_m + min_m) * 0.5
	v.look_at_pack(Vector2(float(burg["x"]), float(burg["y"])), probe)
	assert_eq(v.pick_at(v.size * 0.5), {"kind": "burg", "code": code})


## Final review M4: a courier not yet ridden waits in the capital, and a click
## there opens the capital, not him; once he is on the road he ranks before
## the settlements again. His real rect, laid over the capital's own point.
func test_a_waiting_courier_yields_the_click_to_the_town_under_him() -> void:
	var v := _view()
	var code := ""
	for r: Dictionary in MapObjects.regiments_of(Game.data, Game.data.resolve_realm("player_realm")):
		if CourierSystem.carries_orders(r):
			code = String(r["regiment_code"])
			break
	var c := CourierSystem.dispatch(Game.data, Game.state, CourierSystem.ORDINARY, code,
		{"action_code": "ARMY_GARRISON"})
	var layer := v.get_node("Viewport/Couriers") as Map3DLayerCouriers
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
