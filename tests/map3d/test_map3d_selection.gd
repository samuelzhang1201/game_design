extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")


func test_shift_toggle_keeps_unit_ids_and_one_order_request() -> void:
	var repo := SuiteData.repo()
	var st := SuiteData.campaign(repo, 7)
	var ctx := Map3DContext.new(repo, {})
	ctx.state_fn = func() -> GameState: return st
	var view := Map3DView.new()
	var selection := Map3DSelection.new()
	selection.bind(ctx, null, null, view)
	var code := String(MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), st)[0]["regiment_code"])
	watch_signals(view)
	selection.toggle_pick({"kind": "army", "code": code})
	assert_eq(selection.armies, [code])
	selection.toggle_pick({"kind": "army", "code": code})
	assert_eq(selection.armies, [])
	selection.click({"kind": "army", "code": code}, Vector2(100, 100))
	assert_eq(selection.armies, [code])
	assert_signal_emitted_with_parameters(view, "army_menu_requested", [code, Vector2(100, 100)])
	assert_signal_emit_count(view, "army_menu_requested", 1)
	view.free()
