extends GutTest
## The folio opens on a chosen piece and closes on ×, Escape or a click outside (spec §4).

var panel: WarFolioPanel
var code := ""


func before_each() -> void:
	Game.start_campaign(42)
	panel = load("res://scenes/war_room/war_folio.tscn").instantiate()
	panel.size = Vector2(1000, 640)
	add_child_autofree(panel)
	for r: Dictionary in MapObjects.regiments_of(Game.data, Game.data.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) != "1":
			code = String(r["regiment_code"])
			break


func test_the_right_page_lays_out_every_section_and_row() -> void:
	panel.open_for(code)
	assert_true(panel.visible)
	var secs := WarFolio.sections(Game.data, Game.state, code)
	var right: VBoxContainer = panel.get_node("%Right")
	assert_eq(right.get_child_count(), secs.size())
	var first: Node = right.get_child(0)
	assert_eq((first.get_node("Header") as Label).text, String(secs[0]["label"]).to_upper())
	assert_eq(first.get_node("Rows").get_child_count(), (secs[0]["rows"] as Array).size())


func test_escape_closes_it() -> void:
	panel.open_for(code)
	watch_signals(panel)
	var e := InputEventKey.new()
	e.keycode = KEY_ESCAPE
	e.pressed = true
	panel._unhandled_input(e)
	assert_false(panel.visible)
	assert_signal_emitted(panel, "closed")


func test_a_click_on_the_dim_closes_it() -> void:
	panel.open_for(code)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	(panel.get_node("%Dim") as ColorRect).gui_input.emit(e)
	assert_false(panel.visible)
