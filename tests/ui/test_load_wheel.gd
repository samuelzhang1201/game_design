extends GutTest
## The loading wheel (owner 2026-10-12): the map compass's ship's wheel turns in
## the launch black's bottom-right corner, and the black shows (with the wheel
## turning) before GameRoot has made its overlays, which it makes one per frame
## (R3, owner-approved).

const SuiteData := preload("res://tests/suite_data.gd")
const WHEEL_SCENE := "res://scenes/hud/load_wheel.tscn"

func after_each() -> void:
	GameRoot.stepwise_overlays = false

func test_wheel_turns_over_frames() -> void:
	var w := LoadWheel.new()
	w.custom_minimum_size = Vector2(96, 96)
	add_child_autofree(w)
	await wait_process_frames(1)
	var before := w.rotation
	await wait_process_frames(5)
	assert_gt(w.rotation, before, "the wheel turns clockwise while it is on screen")
	assert_eq(w.pivot_offset, w.size * 0.5, "about its own centre")

func test_the_turn_rate_is_the_compass_key() -> void:
	var w := LoadWheel.new()
	add_child_autofree(w)
	await wait_process_frames(1)
	var r0 := w.rotation
	w._process(1.0)
	assert_almost_eq(w.rotation - r0, deg_to_rad(Game.data.bal("map_compass_turn_deg_per_s")), 0.0001)

func test_overlays_exist_after_the_menu_shows() -> void:
	GameRoot.stepwise_overlays = true
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	assert_null(r.current_screen, "the first frame is the black alone")
	await wait_process_frames(1)
	assert_true(r.current_screen is MainMenu, "the title is up the frame after")
	assert_false(r.overlays_are_ready(), "and the overlays are not yet made")
	assert_null(r.ledger_screen(), "the first of them waits a frame")
	await wait_process_frames(3)
	assert_false(r.overlays_are_ready(), "they come one per frame")
	await wait_until(func() -> bool: return r.overlays_are_ready(), 5.0)
	for o in [r.ledger_screen(), r.war_room_screen(), r.missive_screen(), r.laws_screen(),
			r.report_popup(), r.info_screen(), r.bottom_bar(), r.news_ticker(), r.pause_menu(), r.fps_counter()]:
		assert_not_null(o, "every overlay is made")
	assert_false(r.bottom_bar().visible, "the bar stays off the title")
	assert_eq(r.get_child(r.get_child_count() - 1), r.pause_menu(), "the pause menu is topmost")

func test_a_start_in_the_first_frames_waits_for_the_overlays() -> void:
	GameRoot.stepwise_overlays = true
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	await wait_process_frames(1)
	r.current_screen.start_requested.emit()
	assert_ne(r.state, GameRoot.State.CONVERSATION)
	await wait_until(func() -> bool: return r.state != GameRoot.State.MENU, 10.0)
	assert_true(r.overlays_are_ready(), "the reign began only once the overlays were in")

func test_title_curtain_holds_the_wheel_bottom_right() -> void:
	if not ResourceLoader.exists(WHEEL_SCENE):
		pending("scenes/hud/load_wheel.tscn is Phase E3")
		return
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	await wait_process_frames(2)
	var wheel := r.current_screen.find_child("LoadWheel", true, false) as Control
	assert_not_null(wheel, "the curtain holds the wheel")
	if wheel != null:
		assert_eq(wheel.anchor_left, 1.0)
		assert_eq(wheel.anchor_top, 1.0)

func test_wheel_hides_with_the_curtain() -> void:
	if not ResourceLoader.exists(WHEEL_SCENE):
		pending("scenes/hud/load_wheel.tscn is Phase E3")
		return
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	await wait_process_frames(2)
	var wheel := r.current_screen.find_child("LoadWheel", true, false) as Control
	var curtain := r.current_screen.get_node("Curtain") as Control
	curtain.visible = false
	if wheel != null:
		assert_false(wheel.is_visible_in_tree(), "no wheel without the black")

func test_premenu_black_holds_the_wheel() -> void:
	if not ResourceLoader.exists(WHEEL_SCENE):
		pending("scenes/hud/load_wheel.tscn is Phase E3")
		return
	GameRoot.stepwise_overlays = true
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	assert_null(r.current_screen, "the first frame is GameRoot's own black")
	var wheel := r.find_child("LoadWheel", true, false) as Control
	assert_not_null(wheel, "GameRoot's pre-menu black holds the wheel")
	if wheel != null:
		assert_true(wheel.is_visible_in_tree(), "turning before the title is up")

func test_continue_twice_loads_once() -> void:
	GameRoot.stepwise_overlays = true
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	await wait_process_frames(1)
	r.current_screen.load_requested.emit()
	r.current_screen.load_requested.emit()
	assert_true(r._beginning, "the first Continue holds the launch guard")
	await wait_until(func() -> bool: return r.overlays_are_ready(), 10.0)
	await wait_process_frames(3)
	assert_false(r._beginning, "the guard is released once it ran")

func test_start_then_continue_starts_once() -> void:
	GameRoot.stepwise_overlays = true
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	await wait_process_frames(1)
	r.current_screen.start_requested.emit()
	r.current_screen.load_requested.emit()
	assert_true(r._beginning, "Start holds the guard; the Continue was dropped")
	await wait_until(func() -> bool: return r.state != GameRoot.State.MENU, 10.0)
	assert_true(r.current_screen is ConversationScene, "the opening plays, not a loaded court")
