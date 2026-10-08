extends GutTest
## The laws screen (spec 2026-10-08-laws-tab-design §5): LAWS in the bottom
## bar opens it over the map while the clock runs; three pages, a row a law;
## a value chosen shows the preview's cost, Decree sends LAW_SET, and the row's
## delivery follows the couriers; Esc closes it. Driven through real input:
## mouse presses at the controls' centres, the OptionButton's own popup, a real
## Escape key.


## The court on a fresh reign (as test_war_room_screen.gd begins it), the
## opening event answered so nothing waits on the table.
func _court() -> GameRoot:
	Game.start_campaign(44)
	Game.next_tick()
	if not Game.state.pending_event.is_empty():
		Game.apply_event_choice(String(Game.state.pending_event["choices"][0]["choice_id"]))
	Game.state.metrics["treasury"] = 5000.0
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	await wait_process_frames(2)
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_process_frames(2)
	return r


## GUT's own window is a CanvasLayer over the game: it would take the clicks
## meant for the bottom bar, so it steps aside while these tests click.
var _gut_layer: CanvasLayer


func before_each() -> void:
	_gut_layer = get_tree().root.find_child("GutLayer", true, false) as CanvasLayer
	if _gut_layer != null:
		_gut_layer.visible = false


func after_each() -> void:
	if _gut_layer != null:
		_gut_layer.visible = true
	if Game.state != null:
		Game.set_clock_speed(0)


## A real left click: press and release at `at`, a frame apart.
func _click(r: GameRoot, at: Vector2) -> void:
	for pressed: bool in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		e.global_position = at
		r.get_viewport().push_input(e)
		await wait_process_frames(1)


func _click_on(r: GameRoot, c: Control) -> void:
	assert_true(c.is_visible_in_tree(), "%s is there to be clicked" % c.name)
	await _click(r, c.get_global_rect().get_center())
	await wait_process_frames(1)


func _key(r: GameRoot, code: Key) -> void:
	for pressed: bool in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		r.get_viewport().push_input(e)
		await wait_process_frames(1)


func _open(r: GameRoot) -> LawsScreen:
	await _click_on(r, r.bottom_bar().button("LAWS"))
	await wait_process_frames(2)
	return r.laws_screen()


## Choose `value` in a row's menu as a player does: click the menu open, then
## what a click on the item does (PopupMenu.activate_item: the popup hides,
## THEN reports the item's id and index).
func _choose(r: GameRoot, row: LawRow, value: String) -> void:
	var menu := row.choice()
	var idx := -1
	for i in menu.item_count:
		if String(menu.get_item_metadata(i)) == value:
			idx = i
	assert_gt(idx, -1, "%s offers %s" % [row.law(), value])
	await _click_on(r, menu)
	var popup := menu.get_popup()
	assert_true(popup.visible, "the menu opened on the click")
	popup.hide()
	popup.id_pressed.emit(popup.get_item_id(idx))
	popup.index_pressed.emit(idx)
	await wait_process_frames(2)


## A value of the tax law other than the decreed one.
func _other_tax() -> String:
	var now := int(LawSystem.decreed(Game.data, Game.state, "tax_rate"))
	return str(now + 1 if now < 10 else now - 1)


func _word(key: String) -> String:
	return String(Game.data.law_words[key])


func test_the_laws_tab_opens_the_screen_and_not_the_info_table() -> void:
	var r: GameRoot = await _court()
	var screen := await _open(r)
	assert_not_null(screen)
	assert_true(screen.visible, "LAWS opens the laws screen")
	assert_false(r.info_screen().visible, "not the old info table")
	assert_ne(r.info_screen().current_tab(), "LAWS")
	assert_eq(screen.page(), "economy", "it opens on the first page")


func test_three_pages_show_their_laws() -> void:
	var r: GameRoot = await _court()
	var screen := await _open(r)
	for page: String in ["economy", "politics", "military"]:
		await _click_on(r, screen.page_button(page))
		assert_eq(screen.page(), page)
		var shown: Array = screen.rows().filter(func(row: LawRow) -> bool: return row.is_visible_in_tree())
		var laws: Array = shown.map(func(row: LawRow) -> String: return row.law())
		assert_eq(laws, LawSystem.codes_on(Game.data, page), page + "'s laws, in file order")
	assert_eq(LawSystem.codes_on(Game.data, "economy").size(), 3)
	assert_eq(LawSystem.codes_on(Game.data, "politics").size(), 2)
	assert_eq(LawSystem.codes_on(Game.data, "military").size(), 12)
	# the military page: a title over the first row of each group, in order
	var titles: Array = []
	var last := ""
	for row: LawRow in screen.rows():
		if not row.is_visible_in_tree():
			continue
		var group := String(Game.data.laws[row.law()]["group"])
		assert_eq(row.group_title().visible, group != last, row.law() + ": a title only over its group's first row")
		if group != last:
			titles.append(row.group_title().text)
			last = group
	assert_eq(titles, [_word("group_conduct"), _word("group_discipline"), _word("group_chivalry")])


func test_choosing_a_value_shows_the_cost_from_the_preview() -> void:
	var r: GameRoot = await _court()
	var screen := await _open(r)
	var row := screen.row("tax_rate")
	assert_eq(row.preview_text(), _word("refusal_unchanged"), "the decreed value: law_words' refusal")
	assert_true(row.decree_button().disabled)
	var v := _other_tax()
	await _choose(r, row, v)
	var p := LawSystem.preview(Game.data, Game.state, "tax_rate", v)
	assert_eq(String(p["refusal"]), "")
	assert_string_contains(row.preview_text(), "%d %s" % [int(p["couriers"]), _word("couriers")])
	assert_string_contains(row.preview_text(), "%d %s" % [int(p["max_days"]), _word("days_at_most")])
	assert_false(row.decree_button().disabled, "Decree may be pressed")
	assert_eq(row.effects_text(), "", "the tax law's rows in law_effects.csv: none")
	# a chest that cannot pay: Decree greys and the row says why
	Game.state.metrics["treasury"] = 0.0
	Game.state_changed.emit()
	await wait_process_frames(2)
	var refused := LawSystem.preview(Game.data, Game.state, "tax_rate", v)
	assert_ne(String(refused["refusal"]), "")
	assert_true(row.decree_button().disabled, "a refused choice greys Decree")
	assert_eq(String(refused["refusal_key"]), "gold")
	assert_eq(row.preview_text(), _word("refusal_gold"), "the row says why in law_words' words")
	# a value that does something says so, spelled from law_effects.csv
	await _click_on(r, screen.page_button("politics"))
	var church := screen.row("church_policy")
	await _choose(r, church, "endow")
	var said := LawEffects.summary(Game.data, "church_policy", "endow")
	assert_ne(said, "")
	assert_eq(church.effects_text(), "%s: %s" % [_word("effects"), said])


func test_decree_sends_the_order_and_the_delivery_text_follows_the_days() -> void:
	var r: GameRoot = await _court()
	var screen := await _open(r)
	var row := screen.row("tax_rate")
	var v := _other_tax()
	await _choose(r, row, v)
	var p := LawSystem.preview(Game.data, Game.state, "tax_rate", v)
	var n := int(p["couriers"])
	assert_gt(n, 0)
	var before := Game.state.couriers.size()
	watch_signals(screen)
	await _click_on(r, row.decree_button())
	assert_signal_emit_count(screen, "decreed", 1, "one order given")
	var out: Dictionary = get_signal_parameters(screen, "decreed")[0]
	assert_true(bool(out["ok"]))
	assert_eq(String(out["outcome"]["action_code"]), "LAW_SET")
	assert_eq(Game.state.couriers.size(), before + n, "a courier a province")
	assert_eq(LawSystem.decreed(Game.data, Game.state, "tax_rate"), v)
	await wait_process_frames(2)
	assert_string_contains(row.delivery_text(), "0 / %d %s" % [n, _word("provinces")])
	assert_string_contains(row.decreed_text(), LawSystem.value_label(Game.data, v))
	for i in int(p["max_days"]) + 2:
		Game.advance_day()
		await wait_process_frames(1)
		if int(LawSystem.delivery(Game.data, Game.state, "tax_rate")["reached"]) == n:
			break
	await wait_process_frames(2)
	assert_string_contains(row.delivery_text(), "%d / %d %s" % [n, n, _word("provinces")],
		"the row follows the couriers home")


func test_the_screen_works_while_the_clock_runs() -> void:
	var r: GameRoot = await _court()
	Game.set_clock_speed(1)
	assert_eq(Game.clock_speed, 1)
	var held := Game.clock_held
	var screen := await _open(r)
	assert_true(screen.visible)
	assert_eq(Game.clock_speed, 1, "opening the laws stops nothing")
	assert_eq(Game.clock_held, held, "and holds nothing")
	assert_false(Game.holds_clock("laws"))
	var row := screen.row("tax_rate")
	await _choose(r, row, _other_tax())
	watch_signals(screen)
	await _click_on(r, row.decree_button())
	assert_signal_emit_count(screen, "decreed", 1, "an order is given on a running clock")
	assert_eq(Game.clock_speed, 1)


func test_esc_closes_it_before_the_pause_menu() -> void:
	var r: GameRoot = await _court()
	var screen := await _open(r)
	assert_true(screen.visible)
	await _key(r, KEY_ESCAPE)
	assert_false(screen.visible, "Escape closes the laws")
	assert_false(r.pause_menu().visible, "and does not open the pause menu")
	await _key(r, KEY_ESCAPE)
	assert_true(r.pause_menu().visible, "closed, Escape is the pause menu's again")


func test_the_missing_places_list_names_each_with_days_left() -> void:
	var r: GameRoot = await _court()
	var screen := await _open(r)
	var row := screen.row("tax_rate")
	await _choose(r, row, _other_tax())
	await _click_on(r, row.decree_button())
	# one courier is lost on the road
	var gone_key := ""
	for i in Game.state.couriers.size():
		var o: Dictionary = Game.state.couriers[i].get("order", {})
		if String(o.get("law", "")) == "tax_rate":
			gone_key = String(o["scope_key"])
			Game.state.couriers.remove_at(i)
			break
	Game.state_changed.emit()
	await wait_process_frames(2)
	await _click_on(r, row.places_button())
	assert_true(screen.detail().visible, "the list of places not yet told opens")
	var text := screen.detail_text()
	var untold := LawSystem.untold(Game.data, Game.state, "tax_rate")
	assert_gt(untold.size(), 1)
	for u: Dictionary in untold:
		assert_string_contains(text, String(u["label"]))
		if bool(u["lost"]):
			assert_eq(String(u["scope_key"]), gone_key)
			assert_string_contains(text, "%s — %s" % [String(u["label"]), _word("lost")])
		else:
			var d := int(u["days"])
			assert_string_contains(text, "%s — %d %s" % [String(u["label"]), d, _word("day") if d == 1 else _word("days")])
	# the lost place may be decreed again (R5): one courier, to it alone
	var send := screen.send_again_button()
	assert_false(send.disabled, "a lost place is offered again")
	var before := Game.state.couriers.size()
	watch_signals(screen)
	await _click_on(r, send)
	assert_signal_emit_count(screen, "decreed", 1)
	assert_eq(Game.state.couriers.size(), before + 1)
	var again: Dictionary = Game.state.couriers[Game.state.couriers.size() - 1]
	assert_eq(String(again["order"]["scope_key"]), gone_key)


func test_a_second_press_of_laws_closes_it() -> void:
	var r: GameRoot = await _court()
	var screen := await _open(r)
	assert_true(screen.visible)
	await _click_on(r, r.bottom_bar().button("LAWS"))
	await wait_process_frames(2)
	assert_false(screen.visible, "LAWS is a toggle, like MISSIVE")


func test_another_screen_puts_the_laws_away() -> void:
	var r: GameRoot = await _court()
	var screen := await _open(r)
	await _click_on(r, r.bottom_bar().button("MISSIVE"))
	assert_false(screen.visible, "the Missive board takes its place")
	assert_true(r.missive_screen().visible)


## A law just changed waits out its cooldown: the row says so in law_words'
## words, the wait in days, never the engine's ticks.
func test_a_cooldown_refusal_names_days_not_ticks() -> void:
	var r: GameRoot = await _court()
	var screen := await _open(r)
	var row := screen.row("tax_rate")
	var v := _other_tax()
	await _choose(r, row, v)
	await _click_on(r, row.decree_button())
	var back := str(int(v) - 1) if int(v) > 1 else str(int(v) + 1)
	await _choose(r, row, back)
	var p := LawSystem.preview(Game.data, Game.state, "tax_rate", back)
	assert_eq(String(p["refusal_key"]), "cooldown")
	var n := int(p["wait_days"])
	assert_gt(n, 0)
	assert_eq(row.preview_text(), _word("refusal_cooldown").format({"n": n, "days": _word("day") if n == 1 else _word("days")}))
	assert_string_contains(row.preview_text(), "%d %s" % [n, _word("days")])
	assert_false(row.preview_text().contains("tick"), "no engine unit in the player's words")
	assert_true(row.decree_button().disabled)


## Esc under the pause menu is the menu's: it closes the menu, and the laws
## stay open beneath.
func test_esc_over_the_laws_closes_the_pause_menu_first() -> void:
	var r: GameRoot = await _court()
	var screen := await _open(r)
	r.toggle_pause_menu()
	await wait_process_frames(1)
	assert_true(r.pause_menu().visible)
	await _key(r, KEY_ESCAPE)
	assert_false(r.pause_menu().visible, "Escape closed the pause menu")
	assert_true(screen.visible, "and left the laws open")
	await _key(r, KEY_ESCAPE)
	assert_false(screen.visible, "the next Escape is the laws'")


## A province lost on a paused clock (no day passes, no courier moves): the
## row reads its recipients again on the next state change.
func test_a_same_day_change_of_owner_redraws_the_row() -> void:
	var r: GameRoot = await _court()
	var screen := await _open(r)
	var row := screen.row("tax_rate")
	var v := _other_tax()
	await _choose(r, row, v)
	await _click_on(r, row.decree_button())
	var realm := Game.data.resolve_realm("player_realm")
	var held := MapOwnership.provinces_of(Game.data, Game.state, realm)
	var n := held.size()
	assert_string_contains(row.delivery_text(), "0 / %d %s" % [n, _word("provinces")])
	var other := ""
	var codes: Array = Game.data.kingdoms.keys()
	codes.sort()
	for k: String in codes:
		if k != realm:
			other = k
			break
	var home := MapManors.home_province(Game.data, Game.state)
	var lose := ""
	for code: String in held:
		if code != home:
			lose = code
			break
	assert_true(MapOwnership.set_owner(Game.data, Game.state, lose, other, "test: the province falls"))
	Game.state_changed.emit()
	await wait_process_frames(2)
	assert_string_contains(row.delivery_text(), "0 / %d %s" % [n - 1, _word("provinces")],
		"the lost province is no longer counted")


## A value chosen is forgotten when the screen closes, and when a new reign
## begins under it: the row opens on the decree again.
func test_the_chosen_value_is_forgotten_on_close_and_on_a_new_reign() -> void:
	var r: GameRoot = await _court()
	var screen := await _open(r)
	var row := screen.row("tax_rate")
	var decreed := LawSystem.decreed(Game.data, Game.state, "tax_rate")
	await _choose(r, row, _other_tax())
	assert_ne(String(row.choice().get_item_metadata(row.choice().selected)), decreed)
	await _click_on(r, screen.get_node("%Close"))
	assert_false(screen.visible)
	screen = await _open(r)
	assert_eq(String(row.choice().get_item_metadata(row.choice().selected)), decreed, "reopened on the decree")
	assert_eq(row.preview_text(), _word("refusal_unchanged"))
	await _choose(r, row, _other_tax())
	Game.start_campaign(45)
	Game.state_changed.emit()
	await wait_process_frames(2)
	assert_eq(String(row.choice().get_item_metadata(row.choice().selected)),
		LawSystem.decreed(Game.data, Game.state, "tax_rate"), "a new reign: the new decree")
	assert_eq(row.preview_text(), _word("refusal_unchanged"))


## A province gained since the decree has had no courier: it is listed as
## "not sent", apart from a place whose courier was lost.
func test_a_place_gained_since_is_listed_as_not_sent() -> void:
	var r: GameRoot = await _court()
	var screen := await _open(r)
	var row := screen.row("tax_rate")
	await _choose(r, row, _other_tax())
	await _click_on(r, row.decree_button())
	var realm := Game.data.resolve_realm("player_realm")
	var gained := ""
	var codes: Array = Game.data.provinces.keys()
	codes.sort()
	for code: String in codes:
		if MapOwnership.owner_of(Game.data, Game.state, code) != realm:
			gained = code
			break
	assert_true(MapOwnership.set_owner(Game.data, Game.state, gained, realm, "test: the province comes over"))
	Game.state_changed.emit()
	await wait_process_frames(2)
	assert_string_contains(row.delivery_text(), "1 %s" % _word("not_sent"))
	await _click_on(r, row.places_button())
	var label := LawSystem.place_label(Game.data, Game.state, "province:" + gained)
	assert_string_contains(screen.detail_text(), "%s — %s" % [label, _word("not_sent")])
	assert_false(screen.detail_text().contains("%s — %s" % [label, _word("lost")]))
