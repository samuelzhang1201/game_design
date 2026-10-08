extends GutTest
## The council's resolutions (spec 2026-10-02-war-room-v2 §3.3): the scroll
## lists the drafts with their costs, the seal sends them once.

var scroll: WarDeployScroll
var codes: Array = []


func before_each() -> void:
	Game.start_campaign(44)
	codes.clear()
	for r: Dictionary in MapObjects.regiments_of(Game.data, Game.data.resolve_realm("player_realm"), Game.state):
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
		ArmySystem.regiment(Game.data, codes[i], Game.state)) + Vector2(12, 0))


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


func test_the_crowns_arms_are_read_when_sealing_not_when_built() -> void:
	scroll._seal_tex = null   # built before any reign existed, as GameRoot builds it
	_draft(0)
	scroll.unroll()
	scroll.seal()
	assert_not_null(scroll.seal_texture(), "the arms of the reign being played")


func test_a_seal_in_flight_never_sends_another_reigns_drafts() -> void:
	_draft(0)
	scroll.unroll()
	watch_signals(scroll)
	scroll.seal()
	Game.start_campaign(45)   # a load or restart under the flying envelope
	var other := String(codes[0])
	Game.plant_draft(other, "garrison", Vector2.ZERO)
	var riders := Game.state.couriers.size()
	await wait_seconds(Game.data.bal("war_deploy_wax_s") + Game.data.bal("war_deploy_press_s")
		+ Game.data.bal("war_deploy_roll_s") + Game.data.bal("missive_seal_s") + Game.data.bal("missive_fly_s") + 0.6)
	assert_signal_not_emitted(scroll, "sealed")
	assert_eq(Game.state.couriers.size(), riders, "nothing rode for the new reign")
	assert_true(WarDrafts.any(Game.state), "its drafts untouched")
	assert_false(scroll.sealing())


func test_cancelling_a_seal_puts_it_away_and_sends_nothing() -> void:
	_draft(0)
	scroll.unroll()
	watch_signals(scroll)
	scroll.seal()
	scroll.cancel()
	assert_false(scroll.sealing())
	assert_false(scroll.review_open())
	await wait_seconds(Game.data.bal("war_deploy_wax_s") + Game.data.bal("war_deploy_press_s")
		+ Game.data.bal("war_deploy_roll_s") + Game.data.bal("missive_seal_s") + Game.data.bal("missive_fly_s") + 0.6)
	assert_signal_not_emitted(scroll, "sealed")
	assert_true(WarDrafts.any(Game.state))


## A march drafted with a supply town (spec 2026-10-08-war-room-draw-orders
## ruling 15): the line names the town and counts the supply courier's gold,
## and the seal runs the supply point, then the march — each its own courier.
func test_a_draft_with_a_supply_town_counts_its_courier_and_sends_it_first() -> void:
	var code := String(codes[0])
	var here := ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, code, Game.state))
	var town := ""
	var ok := SupplyLines.march_eligibility(Game.data, Game.state, code, here + Vector2(12, 0))
	var towns: Array = ok.keys()
	towns.sort()
	for t: String in towns:
		if String(ok[t]) == "":
			town = t
			break
	assert_ne(town, "", "some town supplies a march next door")
	_draft(0)
	var plain := int(Game.review_drafts()["lines"][0]["gold"])
	Game.plant_draft(code, "march", here + Vector2(12, 0), [], -1, town, 1000)
	var line: Dictionary = Game.review_drafts()["lines"][0]
	assert_eq(String(line["supply"]), String(Game.data.burgs[town]["label"]))
	assert_gt(int(line["gold"]), plain, "the supply courier's fee is counted")
	var couriers := Game.state.couriers.size()
	Game.deploy_drafts()
	assert_eq(Game.state.couriers.size(), couriers + 2, "a courier to the town and one to the column")
	assert_eq(String(SupplyLines.line(Game.state, code).get("town", "")), town, "the line waits ORDERED for its town")
	scroll.refresh()
