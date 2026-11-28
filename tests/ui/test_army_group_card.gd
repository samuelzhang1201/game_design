extends GutTest
## FORM ARMY on the regiment card (spec 2026-11-27-army-groups-design), driven
## through the view's real input path (Map3DView._gui_input, Shift-click as in
## test_army_multi_select.gd) with the card wired the way the screens wire it
## (Map3DView.attach): form, a plain click selects the whole army, SELECT ARMY,
## DISBAND.

const RunDir := preload("res://tests/run_dir.gd")
var _fixture := RunDir.dir("army_group_card").path_join("test_army_group_card_world.tscn")
const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}
const AT_M := 20000.0


func before_all() -> void:
	var root := Node3D.new()
	root.name = "Fixture"
	root.set_meta("map3d_world", WORLD)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, _fixture)
	root.free()
	Map3DView.world_override = _fixture


func after_all() -> void:
	Map3DView.world_override = ""
	Map3DWorldCache.clear()


func before_each() -> void:
	Game.start_campaign(42)
	Game.set_clock_speed(0)


func _capital_xy() -> Vector2:
	var realm := Game.data.resolve_realm("player_realm")
	var b: Dictionary = Game.data.burgs[String(Game.data.kingdoms[realm]["capital_burg"])]
	return Vector2(float(b["x"]), float(b["y"]))


func _point_of(v: Map3DView, code: String) -> Vector2:
	if v.unit_rects().has(code):
		var p := (v.unit_rects()[code] as Rect2).get_center()
		if v.pick_at(p) == {"kind": "army", "code": code}:
			return p
	return Vector2(-1, -1)


func _two_on_screen(v: Map3DView) -> Array:
	var out: Array = []
	var codes := Game.state.regiments.keys()
	codes.sort()
	for c: String in codes:
		if ArmyGroups.eligible(Game.data, Game.state, c) and _point_of(v, c).x >= 0.0:
			out.append(c)
		if out.size() == 2:
			break
	return out


func _click(v: Map3DView, at: Vector2, shift := false) -> void:
	for pressed: bool in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		e.shift_pressed = shift
		if pressed:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		v._gui_input(e)


func _button(card: MapDetailPanel, node_name: String) -> Button:
	return card.find_child(node_name, true, false) as Button


func test_form_reselect_and_disband() -> void:
	var host := Control.new()
	host.size = Vector2(800, 450)
	add_child_autofree(host)
	var card := MapDetailPanel.create()
	add_child_autofree(card)
	var v := Map3DView.create(Game.data, _fixture)
	v.size = Vector2(800, 450)
	Map3DView.attach(host, card, null, Callable(), null, v)
	v.visible = true
	v.activate()
	v.set_military(true)
	v.look_at_pack(_capital_xy(), AT_M)
	await wait_process_frames(2)
	var two := _two_on_screen(v)
	assert_eq(two.size(), 2, "two of the player's land units are on screen")
	if two.size() < 2:
		return
	var a := String(two[0])
	var b := String(two[1])
	_click(v, _point_of(v, a))
	assert_null(_button(card, "FormArmy"), "one unit offers no army")
	_click(v, _point_of(v, b), true)
	assert_eq(v.selected_armies(), [a, b])
	var form := _button(card, "FormArmy")
	assert_not_null(form, "two selected: the card offers FORM ARMY")
	form.pressed.emit()
	assert_eq(Game.state.army_groups.size(), 1)
	var id := ArmyGroups.group_of(Game.state, a)
	assert_eq(Game.state.army_groups[id]["members"], [a, b])
	assert_eq(Game.state.army_groups[id]["name"], Game.data.army_group_names[0])
	await wait_process_frames(1)
	assert_null(_button(card, "FormArmy"), "the selection is the army now")
	assert_not_null(card.find_child("Section_army_group", true, false), "the card lists the army")
	# the army selected: its name is the card's title, the regiment named over its own stats
	var army_name := String(Game.state.army_groups[id]["name"])
	assert_eq(card.title_label().text, army_name, "the army is the card's title")
	assert_string_starts_with(card.subtitle_label().text, "Army of ")
	assert_eq((card.find_child("Section_army_regiment", true, false) as Label).text,
		MapObjects.label_of(Game.data, {"kind": "army", "code": a}), "the stats are named for their regiment")
	# a plain click on one member selects the whole army, it first
	_click(v, _point_of(v, b))
	assert_eq(v.selected_armies(), [b, a])
	# SELECT ARMY from a lone member's card
	_click(v, _point_of(v, a), true)   # Shift takes a out: b alone
	assert_eq(v.selected_armies(), [b])
	await wait_process_frames(1)
	assert_eq(card.title_label().text, MapObjects.label_of(Game.data, {"kind": "army", "code": b}),
		"a lone member's card is the regiment's")
	assert_null(card.find_child("Section_army_regiment", true, false))
	_button(card, "SelectArmy").pressed.emit()
	assert_eq(v.selected_armies(), [a, b], "the army's entry selects it")
	await wait_process_frames(1)
	_button(card, "DisbandArmy").pressed.emit()
	assert_true(Game.state.army_groups.is_empty(), "disbanded")
	_click(v, _point_of(v, a))
	assert_eq(v.selected_armies(), [a], "with no army a plain click is one unit again")
