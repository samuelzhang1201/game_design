extends GutTest
## Several units selected at once on the 3D map (spec 2026-10-07-army-split-and-ground
## §5.6; plan ruling R4: the box is Shift + left drag, a plain drag pans), and the
## order menu's orders riding to each of them — each its own action, its own
## courier and its own charge. Driven through the view's real input path
## (Map3DView._gui_input), the way tests/map3d/test_map3d_military.gd clicks
## its counters, with the menu following the live view.

const RunDir := preload("res://tests/run_dir.gd")
var _fixture := RunDir.dir("army_multi_select").path_join("test_army_multi_select_world.tscn")
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


func _view() -> Map3DView:
	var v := Map3DView.create(Game.data, _fixture)
	v.size = Vector2(800, 450)
	add_child_autofree(v)
	v.activate()
	v.set_military(true)
	return v


func _menu_on(v: Map3DView) -> ArmyOrderMenu:
	var menu := ArmyOrderMenu.new()
	add_child_autofree(menu)
	menu.follow(v)
	return menu


func _realm() -> String:
	return Game.data.resolve_realm("player_realm")


func _capital_xy() -> Vector2:
	var b: Dictionary = Game.data.burgs[String(Game.data.kingdoms[_realm()]["capital_burg"])]
	return Vector2(float(b["x"]), float(b["y"]))


## The realm's land units that take a courier and can march.
func _marchers() -> Array:
	var out: Array = []
	for r: Dictionary in MapObjects.regiments_of(Game.data, _realm(), Game.state):
		if String(r.get("is_naval", "0")) != "1" and CourierSystem.carries_orders(r) \
				and ArmySystem.base_pace_km(Game.data, r) > 0:
			out.append(String(r["regiment_code"]))
	return out


func _is_land(code: String) -> bool:
	return String(ArmySystem.regiment(Game.data, code, Game.state).get("is_naval", "0")) != "1"


## A point on screen whose pick is the unit `code` (its piece or its counter);
## (-1, -1) when it is not on screen.
func _point_of(v: Map3DView, code: String) -> Vector2:
	var tries: Array = []
	if v.unit_rects().has(code):
		tries.append((v.unit_rects()[code] as Rect2).get_center())
	for m: Dictionary in v.army_markers():
		if String(m["code"]) == code:
			tries.append((m["rect"] as Rect2).get_center())
	for p: Vector2 in tries:
		if v.pick_at(p) == {"kind": "army", "code": code}:
			return p
	return Vector2(-1, -1)


## Two marchers both clickable on screen round the capital.
func _two_on_screen(v: Map3DView) -> Array:
	var out: Array = []
	for c: String in _marchers():
		var p := _point_of(v, c)
		if p.x >= 0.0:
			out.append([c, p])
		if out.size() == 2:
			return out
	return out


func _mouse(v: Map3DView, button: MouseButton, at: Vector2, pressed: bool, shift := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.position = at
	e.shift_pressed = shift
	if pressed:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	v._gui_input(e)


func _click(v: Map3DView, at: Vector2, shift := false) -> void:
	_mouse(v, MOUSE_BUTTON_LEFT, at, true, shift)
	_mouse(v, MOUSE_BUTTON_LEFT, at, false, shift)


func _right_click(v: Map3DView, at: Vector2) -> void:
	_mouse(v, MOUSE_BUTTON_RIGHT, at, true)
	_mouse(v, MOUSE_BUTTON_RIGHT, at, false)


func _drag_motion(v: Map3DView, from: Vector2, to: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = to
	m.relative = to - from
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	m.shift_pressed = true
	v._gui_input(m)


## A row chosen the way PopupMenu chooses it: hidden first, then id_pressed.
func _choose(menu: ArmyOrderMenu, id: int) -> void:
	menu.hide()
	menu.id_pressed.emit(id)


## The screen point over a pack point (the camera's own projection).
func _screen_of(v: Map3DView, pack_px: Vector2) -> Vector2:
	var p: Variant = v.context().project(v.context().ground_of_pack(pack_px))
	return p as Vector2 if p != null else Vector2(-1, -1)


func _land_near(from: Vector2) -> Vector2:
	for i in range(2, 60):
		var probe := from + Vector2(float(i), 0.0)
		if MapEconomy.cell_at(Game.data, probe) >= 0:
			return probe
	return Vector2.ZERO


func _news(of: Object) -> Array:
	var out: Array = []
	for i in get_signal_emit_count(of, "news_published"):
		out.append(String(get_signal_parameters(of, "news_published", i)[0]))
	return out


func test_shift_click_adds_and_removes() -> void:
	var v := _view()
	v.look_at_pack(_capital_xy(), AT_M)
	await wait_process_frames(2)
	var two := _two_on_screen(v)
	assert_eq(two.size(), 2, "two of the player's units are on screen")
	if two.size() < 2:
		return
	var a := String(two[0][0])
	var b := String(two[1][0])
	# each point read again before its click: a selected counter is placed
	# first and never moves, so the others may shift round it
	_click(v, _point_of(v, a), true)
	assert_eq(v.selected_armies(), [a])
	_click(v, _point_of(v, b), true)
	assert_eq(v.selected_armies(), [a, b], "Shift-click adds")
	_click(v, _point_of(v, a), true)
	assert_eq(v.selected_armies(), [b], "Shift-click again takes it out")
	_click(v, _point_of(v, a))
	assert_eq(v.selected_armies(), [a], "a plain click selects one unit")


## Every land unit of the realm whose piece or counter touches the box.
func _touched(v: Map3DView, box: Rect2) -> Array:
	var out: Array = []
	for code: String in v.unit_rects():
		if (v.unit_rects()[code] as Rect2).intersects(box) and not out.has(code):
			out.append(code)
	for m: Dictionary in v.army_markers():
		if (m["rect"] as Rect2).intersects(box) and not out.has(String(m["code"])):
			out.append(String(m["code"]))
	return out.filter(func(c: String) -> bool:
		return String(ArmySystem.regiment(Game.data, c, Game.state).get("kingdom_code", "")) == _realm() \
			and _is_land(c))


func test_shift_drag_box_selects_the_units_inside() -> void:
	var v := _view()
	v.look_at_pack(_capital_xy(), AT_M)
	await wait_process_frames(2)
	# two units whose joint box touches no third
	var box := Rect2()
	var pair: Array = []
	var marks := v.army_markers()
	for i in marks.size():
		for j in range(i + 1, marks.size()):
			var r := (marks[i]["rect"] as Rect2).merge(marks[j]["rect"] as Rect2).grow(2.0)
			var hit := _touched(v, r)
			hit.sort()
			var want := [String(marks[i]["code"]), String(marks[j]["code"])]
			want.sort()
			if hit == want and r.size.length() > Map3DInput.CLICK_SLOP * 2.0:
				box = r
				pair = want
				break
		if not pair.is_empty():
			break
	assert_eq(pair.size(), 2, "two units stand apart from the rest")
	if pair.is_empty():
		return
	var target := v.target()
	_mouse(v, MOUSE_BUTTON_LEFT, box.position, true, true)
	_drag_motion(v, box.position, box.position + box.size * 0.5)
	assert_true(v.box_rect.has_area(), "the box is drawn while dragging")
	_drag_motion(v, box.position + box.size * 0.5, box.end)
	_mouse(v, MOUSE_BUTTON_LEFT, box.end, false, true)
	assert_eq(v.selected_armies(), pair, "exactly the units inside, sorted")
	assert_eq(v.target(), target, "the camera did not pan")
	assert_false(v.box_rect.has_area(), "the box goes on release")


func test_one_march_sends_a_courier_to_each() -> void:
	var v := _view()
	var menu := _menu_on(v)
	v.look_at_pack(_capital_xy(), AT_M)
	await wait_process_frames(2)
	var two := _two_on_screen(v)
	assert_eq(two.size(), 2)
	if two.size() < 2:
		return
	var a := String(two[0][0])
	var b := String(two[1][0])
	_click(v, _point_of(v, a), true)
	_click(v, _point_of(v, b), true)
	assert_eq(v.selected_armies(), [a, b])
	_right_click(v, _point_of(v, a))
	assert_true(menu.visible, "the unit's orders are open")
	assert_eq(menu.selected_codes(), [a, b], "the orders go to the selection")
	var march := -1
	for i in Game.data.army_orders.size():
		if String(Game.data.army_orders[i]["action_code"]) == "ARMY_MARCH":
			march = i
	_choose(menu, march)
	assert_eq(menu.aiming(), a)
	var to := _land_near(_capital_xy() + Vector2(12.0, 6.0))
	var at := _screen_of(v, to)
	assert_true(Rect2(Vector2.ZERO, v.size).has_point(at), "the destination is on screen")
	_click(v, at)
	assert_true(menu.pending().x >= 0.0, "the confirm is asked")
	var before: float = Game.state.metrics["treasury"]
	var panel := menu.shown_confirm()
	assert_not_null(panel, "the confirm panel stands")
	if panel == null:
		return
	autofree(panel)   # made beside the menu, a child of this test
	panel.select_supply("")   # the march alone is charged here (the default supply town is its own order)
	panel.confirm_button().pressed.emit()
	var marches: Array = []
	for c: Dictionary in Game.state.couriers:
		if String((c["order"] as Dictionary).get("action_code", "")) == "ARMY_MARCH":
			marches.append(c)
	assert_eq(marches.size(), 2, "one courier per unit")
	var targets: Array = marches.map(func(c: Dictionary) -> String: return String(c["target"]))
	targets.sort()
	var want := [a, b]
	want.sort()
	assert_eq(targets, want)
	if marches.size() == 2:
		assert_eq(int(marches[0]["order"]["dest_x_m"]), int(marches[1]["order"]["dest_x_m"]), "the same point")
		assert_eq(int(marches[0]["order"]["dest_y_m"]), int(marches[1]["order"]["dest_y_m"]), "the same point")
	var one := OrderCosts.gold_of(Game.data, "ARMY_MARCH") \
		+ float(CourierSystem.fee_gold(Game.data, CourierSystem.ORDINARY))
	assert_gt(one, 0.0)
	assert_almost_eq(before - float(Game.state.metrics["treasury"]), 2.0 * one, 0.001,
		"each order charged on its own")


func _fleet() -> String:
	for r: Dictionary in MapObjects.regiments_of(Game.data, _realm(), Game.state):
		if String(r.get("is_naval", "0")) == "1":
			return String(r["regiment_code"])
	return ""


func test_mixed_selection_sends_what_it_can() -> void:
	var v := _view()
	var menu := _menu_on(v)
	var fleet := _fleet()
	assert_ne(fleet, "", "the realm has a fleet")
	if fleet == "":
		return
	# the fleet toggled in where it lies (the box takes land units only, spec §5.6)
	v.look_at_pack(ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, fleet, Game.state)), AT_M)
	await wait_process_frames(2)
	var fat := _point_of(v, fleet)
	assert_true(fat.x >= 0.0, "the fleet is on screen")
	_click(v, fat, true)
	v.look_at_pack(_capital_xy(), AT_M)
	await wait_process_frames(2)
	var two := _two_on_screen(v)
	assert_gt(two.size(), 0)
	if two.is_empty():
		return
	var land := String(two[0][0])
	_click(v, _point_of(v, land), true)
	assert_eq(v.selected_armies(), [fleet, land])
	_right_click(v, _point_of(v, land))
	assert_eq(menu.selected_codes(), [fleet, land])
	var add := menu.get_item_index(ArmyOrderMenu.SUPPLY_ADD)
	assert_ne(add, -1, "Add supply point is offered: the land unit can take it")
	assert_false(menu.is_item_disabled(add))
	_choose(menu, ArmyOrderMenu.SUPPLY_ADD)
	assert_eq(menu.supply_picking(), land)
	var town := ""
	for t: String in v.supply_pick:
		if String(v.supply_pick[t]) == "":
			town = t
			break
	assert_ne(town, "", "a lit town")
	var b: Dictionary = Game.data.burgs[town]
	var town_xy := Vector2(float(b["x"]), float(b["y"]))
	v.look_at_pack(town_xy, AT_M)
	await wait_process_frames(2)
	_click(v, _screen_of(v, town_xy))
	assert_eq(menu.supply_town(), town, "the town's rate is asked")
	watch_signals(Game)
	_choose(menu, ArmyOrderMenu.RATE_BASE + 1)
	var sets: Array = []
	for c: Dictionary in Game.state.couriers:
		if String((c["order"] as Dictionary).get("action_code", "")) == "SUPPLY_POINT_SET":
			sets.append(String(c["target"]))
	assert_eq(sets, [land], "only the land unit's courier rides")
	var label := String(ArmySystem.regiment(Game.data, fleet, Game.state)["label"])
	assert_true(_news(Game).has("%s is a fleet: it carries no supply train" % label),
		"the fleet is refused aloud: %s" % str(_news(Game)))


## A screen point on land a box of `half` px round touches no unit, with what a
## plain click there picks; [] when none on screen.
func _empty_land(v: Map3DView, half: float) -> Array:
	for iy in range(2, 9):
		for ix in range(2, 15):
			var p := Vector2(v.size.x * ix / 16.0, v.size.y * iy / 10.0)
			var kind := String(v.pick_at(p).get("kind", ""))
			if kind not in ["province", "burg"]:
				continue
			if _touched(v, Rect2(p - Vector2.ONE * half, Vector2.ONE * half * 2.0)).is_empty():
				return [p, kind]
	return []


## An empty Shift-box clears what was clicked before it, and its card closes.
func test_an_empty_shift_box_closes_the_card() -> void:
	var v := _view()
	v.look_at_pack(_capital_xy(), AT_M)
	await wait_process_frames(2)
	var half := Map3DInput.CLICK_SLOP * 2.0
	var spot := _empty_land(v, half)
	assert_false(spot.is_empty(), "premise: a patch of land with no unit on screen")
	if spot.is_empty():
		return
	var p: Vector2 = spot[0]
	_click(v, p)
	assert_true(v.selected_province() != "" or v.selected_burg() != "", "the click selected the ground")
	watch_signals(v)
	var a := p - Vector2.ONE * half
	var b := p + Vector2.ONE * half
	_mouse(v, MOUSE_BUTTON_LEFT, a, true, true)
	_drag_motion(v, a, b)
	_mouse(v, MOUSE_BUTTON_LEFT, b, false, true)
	assert_eq(v.selected_armies(), [], "nothing in the box")
	assert_eq(v.selected_province(), "")
	assert_eq(v.selected_burg(), "")
	assert_signal_emitted_with_parameters(v, "object_selected", [{}])


## A Shift press whose release was lost leaves no box armed: the next plain
## press-drag pans the camera.
func test_a_plain_drag_after_a_lost_shift_release_pans() -> void:
	var v := _view()
	v.look_at_pack(_capital_xy(), AT_M)
	await wait_process_frames(2)
	var mid := v.size * 0.5
	_mouse(v, MOUSE_BUTTON_LEFT, mid, true, true)   # its release never comes
	var target := v.target()
	_mouse(v, MOUSE_BUTTON_LEFT, mid, true)
	var m := InputEventMouseMotion.new()
	m.position = mid + Vector2(80, 30)
	m.relative = Vector2(80, 30)
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	v._gui_input(m)
	await wait_process_frames(2)
	assert_false(v.box_rect.has_area(), "no box is drawn")
	assert_ne(v.target(), target, "the camera panned")
	_mouse(v, MOUSE_BUTTON_LEFT, mid + Vector2(80, 30), false)
	assert_eq(v.selected_armies(), [], "the release toggles nothing")
