extends GutTest
## The council's resolutions (spec 2026-10-02-war-room-v2 §3.3): the scroll
## lists the drafts with their costs, the seal sends them once.

var scroll: WarDeployScroll
var codes: Array = []


func before_each() -> void:
	Game.start_campaign(44)
	codes.clear()
	for r: Dictionary in MapObjects.regiments_of(Game.data, Game.data.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) != "1" and ArmySystem.base_pace_km(Game.data, r) > 0:
			codes.append(String(r["regiment_code"]))
	codes.sort()
	var host := Control.new()
	host.size = Vector2(1000, 600)
	add_child_autofree(host)
	scroll = load("res://scenes/war_room/war_deploy_scroll.tscn").instantiate()
	host.add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await wait_process_frames(1)


func _draft(i: int) -> void:
	Game.plant_draft(codes[i], "march", ArmySystem.position_of(Game.data, Game.state,
		ArmySystem.regiment(Game.data, codes[i])) + Vector2(12, 0))


func test_the_button_is_grey_without_drafts() -> void:
	scroll.refresh()
	assert_true(scroll.button().disabled)
	_draft(0)
	scroll.refresh()
	assert_false(scroll.button().disabled)


func test_the_button_stands_in_the_bottom_right_corner() -> void:
	var r := scroll.button().get_global_rect()
	var host := scroll.get_global_rect()
	assert_gt(r.position.x, host.get_center().x)
	assert_gt(r.position.y, host.get_center().y)


func test_unrolled_it_lists_each_draft_and_the_total() -> void:
	_draft(0)
	_draft(1)
	scroll.button().pressed.emit()
	await wait_process_frames(1)
	assert_true(scroll.review_open())
	assert_eq(scroll.line_labels().size(), 2)
	assert_string_contains(scroll.total_text(), WarRoom.group(int(Game.review_drafts()["total"])))


func test_a_line_the_chest_cannot_pay_reads_its_reason() -> void:
	_draft(0)
	_draft(1)
	Game.state.metrics["treasury"] = float(Game.review_drafts()["lines"][0]["gold"])
	scroll.unroll()
	var last := scroll.line_labels()[1] as Label
	var why := String(Game.review_drafts()["lines"][1]["refusal"])
	assert_ne(why, "")
	assert_string_contains(last.text, why, "the line reads the reason it would be refused")
	assert_false(last.text.contains(" 0 gold"), "and no price for an order that cannot run")
	assert_eq(last.get_theme_color("font_color"), UiPalette.ink("bad"))


func test_the_seal_sends_once_however_often_it_is_pressed() -> void:
	_draft(0)
	scroll.unroll()
	watch_signals(scroll)
	var riders := Game.state.couriers.size()
	scroll.seal()
	scroll.seal()   # pressed again while the wax is still warm
	assert_true(scroll.sealing())
	scroll.unroll()   # and no unroll mid-seal
	await wait_for_signal(scroll.sealed, 8.0)
	await wait_process_frames(2)
	assert_signal_emit_count(scroll, "sealed", 1)
	assert_eq(Game.state.couriers.size(), riders + 1)
	assert_false(WarDrafts.any(Game.state))
	assert_false(scroll.sealing())
	assert_true(scroll.button().disabled, "nothing left to seal")


func test_not_yet_rolls_it_away_and_keeps_the_drafts() -> void:
	_draft(0)
	scroll.unroll()
	watch_signals(scroll)
	scroll.withdraw()
	assert_false(scroll.review_open())
	assert_signal_emitted(scroll, "withdrawn")
	assert_true(WarDrafts.any(Game.state))


func test_deploy_works_on_a_running_clock() -> void:
	_draft(0)
	Game.set_clock_speed(1)
	scroll.refresh()
	assert_false(scroll.button().disabled)
	scroll.unroll()
	assert_true(scroll.review_open())
	Game.set_clock_speed(0)
