extends GutTest
## Show on map (spec 2026-09-28-missive-board-and-spies §2, Task 7 fix round 1):
## GameRoot._on_missive_show re-emits the 3D view's own object_selected /
## province_selected signals for a manor / province / burg subject, and does
## nothing (but never crashes) for a subject kind it does not know — a spy
## report's "point" or a regiment. A live view is needed to see the left
## column's card follow, so this uses the GameRoot.force_map3d_scene(true)
## seam (tests/map3d/test_map3d_hover.gd, tests/map3d/test_map3d_military.gd).


func before_each() -> void:
	Game.start_campaign(42)


func _letter(subj: Dictionary) -> int:
	return MissiveLog.add(Game.data, Game.state, MissiveLog.make("spy", "credible", 3, subj,
		"A letter", [MissiveLog.exact("people", "People", 100)]))


func _court() -> GameRoot:
	Game.data.balance["map3d_default"] = 1.0
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	r.force_map3d_scene(true)
	await wait_process_frames(2)
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_process_frames(2)
	Game.data.balance["map3d_default"] = 0.0
	return r


## A manor the crown holds outright, so nothing about the letter or the card
## is entangled with fog rules this test is not about.
func _crowns_manor() -> int:
	for c: int in MapManors.manors_of_house(Game.data, Game.state, MapManors.crown(Game.state),
			Game.data.resolve_realm("player_realm")):
		return c
	return -1


func _own_province() -> String:
	return String(MapOwnership.provinces_of(Game.data, Game.state,
		Game.data.resolve_realm("player_realm"))[0])


func _show(r: GameRoot, id: int) -> void:
	r.toggle_missives()
	var ms := r.missive_screen()
	ms.select(id)
	ms.show_on_map_button().pressed.emit()


func test_a_manors_letter_opens_its_card_and_closes_the_board() -> void:
	var r: GameRoot = await _court()
	var screen: CourtScreen = r.current_screen
	var view := screen.map3d_view()
	assert_not_null(view)
	var cell := _crowns_manor()
	assert_gt(cell, -1, "the founding realm holds at least one manor outright")
	var id := _letter(MissiveLog.subject("manor", "", cell, Vector2(500, 300)))
	watch_signals(view)
	_show(r, id)
	assert_signal_emitted_with_parameters(view, "object_selected",
		[{"title": MapManors.label_of(Game.data, cell), "obj": {"kind": "manor", "cell": cell}}])
	await wait_process_frames(1)
	assert_false(r.missive_screen().visible, "the board closed")
	assert_eq(screen.detail_panel().shown_manor(), cell, "the left column followed the signal")
	assert_eq(screen.detail_panel().title_label().text, MapManors.label_of(Game.data, cell))


func test_a_provinces_letter_emits_province_selected() -> void:
	var r: GameRoot = await _court()
	var screen: CourtScreen = r.current_screen
	var view := screen.map3d_view()
	var code := _own_province()
	var id := _letter(MissiveLog.subject("province", code, -1, Vector2(500, 300)))
	watch_signals(view)
	_show(r, id)
	assert_signal_emitted_with_parameters(view, "province_selected", [code])
	await wait_process_frames(1)
	assert_false(r.missive_screen().visible, "the board closed")
	assert_eq(screen.detail_panel().shown_province(), code, "the left column followed the signal")


func test_a_burgs_letter_emits_object_selected_with_its_label() -> void:
	var r: GameRoot = await _court()
	var screen: CourtScreen = r.current_screen
	var view := screen.map3d_view()
	var code := String(Game.data.kingdoms[Game.data.resolve_realm("player_realm")]["capital_burg"])
	var id := _letter(MissiveLog.subject("burg", code, -1, Vector2(500, 300)))
	watch_signals(view)
	_show(r, id)
	assert_signal_emitted_with_parameters(view, "object_selected",
		[{"title": String(Game.data.burgs[code]["label"]), "obj": {"kind": "burg", "code": code}}])


## Defensive (fix round 1): an unknown burg code must not crash the read.
func test_a_letter_naming_an_unknown_burg_does_not_crash() -> void:
	var r: GameRoot = await _court()
	var id := _letter(MissiveLog.subject("burg", "not_a_real_burg", -1, Vector2(500, 300)))
	_show(r, id)
	await wait_process_frames(1)
	assert_false(r.missive_screen().visible, "the board still closed")


## A spy report's subject ("point") or a regiment's: GameRoot does not know
## either kind, so Show on map only closes the board — no signal, no crash.
func test_a_point_or_regiment_subject_only_closes_the_board() -> void:
	var r: GameRoot = await _court()
	var screen: CourtScreen = r.current_screen
	var view := screen.map3d_view()
	watch_signals(view)
	var point_id := _letter(MissiveLog.subject("point", "", -1, Vector2(500, 300)))
	_show(r, point_id)
	await wait_process_frames(1)
	assert_false(r.missive_screen().visible)
	assert_signal_not_emitted(view, "object_selected")
	assert_signal_not_emitted(view, "province_selected")
	var reg_id := _letter(MissiveLog.subject("regiment", "some_code", -1, Vector2(400, 200)))
	_show(r, reg_id)  # _show opens the board again before selecting and clicking
	await wait_process_frames(1)
	assert_false(r.missive_screen().visible)
	assert_signal_not_emitted(view, "object_selected")
	assert_signal_not_emitted(view, "province_selected")


## The kept world (Map3DWorldCache) must not leak into the next file.
func after_all() -> void:
	Map3DWorldCache.clear()
