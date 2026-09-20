extends GutTest
## Map3DPicker and Map3DSelection (spec 2026-09-20 §1): the pick and the hover
## are one script, the selection another; the view re-emits their signals
## under its own names, so the screens change nothing.

const FIXTURE := "user://test_map3d_picker_world.tscn"
const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}


func before_all() -> void:
	Game.start_campaign(42)
	var root := Node3D.new()
	root.name = "Fixture"
	root.set_meta("map3d_world", WORLD)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, FIXTURE)
	root.free()


func _view() -> Map3DView:
	var v := Map3DView.create(Game.data, FIXTURE)
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


## A town is still clickable at 20 km (change 3, owner 2026-09-20): between
## map3d_house_view_m (9 km, houses stop) and map3d_dot_min_view_m (40 km,
## the dot appears), a settlement is marked by nothing but its ground patch —
## picking must not depend on a dot that is not drawn there.
func test_a_town_is_still_clickable_at_20km_with_no_dot_shown() -> void:
	var v := _view()
	var code := ""
	for c: String in Game.data.burgs:
		if String(Game.data.burgs[c].get("group", "")) == "town":
			code = c
			break
	assert_ne(code, "", "the pack has a town")
	var burg: Dictionary = Game.data.burgs[code]
	v.look_at_pack(Vector2(float(burg["x"]), float(burg["y"])), 20000.0)
	assert_true(20000.0 < Game.data.bal("map3d_dot_min_view_m"), "the fixture is inside the no-dot gap")
	assert_eq(v.pick_at(v.size * 0.5), {"kind": "burg", "code": code})


## The kept world (Map3DWorldCache) must not leak into the next file.
func after_all() -> void:
	Map3DWorldCache.clear()
