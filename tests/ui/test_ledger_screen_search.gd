extends GutTest
## The LEDGER's search box (owner 2026-10-01: 在ledger界面新增一个搜索栏，
## 可以搜索node), driven by real key events through the window.

func _court() -> GameRoot:
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	await wait_frames(2)
	var menu: MainMenu = r.current_screen
	menu.menu_column().get_node("StartGame").pressed.emit()
	await wait_frames(2)
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_frames(2)
	return r


func _open(r: GameRoot) -> LedgerScreen:
	r.bottom_bar().button("LEDGER").pressed.emit()
	await wait_frames(2)
	return r.ledger_screen()


func _key(code: Key, unicode: int = 0) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.unicode = unicode if pressed else 0
		ev.pressed = pressed
		get_tree().root.push_input(ev)


func _type(screen: LedgerScreen, text: String) -> void:
	screen.search_box().grab_focus()
	for ch in text:
		var u := ch.unicode_at(0)
		_key(OS.find_keycode_from_string(ch.to_upper()) if ch != " " else KEY_SPACE, u)
	await wait_frames(1)


func test_typing_lists_matches_by_label_in_any_case() -> void:
	var r: GameRoot = await _court()
	var screen := await _open(r)
	var home := "province:" + MapManors.home_province(Game.data, Game.state)
	var label := LedgerResolvers.label_of(Game.data, Game.state, home)
	await _type(screen, label.to_upper())
	assert_eq(screen.search_box().text, label.to_upper(), "the keys reached the box")
	var found := screen.search_matches()
	assert_false(found.is_empty())
	assert_eq(String(found[0]["id"]), home, "the province's own star first")
	assert_true(screen.find_child("SearchList", true, false).visible, "the list shows")
	assert_lte(found.size(), int(Game.data.bal("ledger_search_max_matches")))


func test_enter_picks_the_first_match() -> void:
	var r: GameRoot = await _court()
	var screen := await _open(r)
	var king := LedgerResolvers.label_of(Game.data, Game.state, "character:you")
	await _type(screen, king.to_lower().substr(0, 4))
	var found := screen.search_matches()
	assert_false(found.is_empty())
	var first := String(found[0]["id"])
	_key(KEY_ENTER)
	await wait_frames(1)
	assert_eq(screen.view().selected(), first, "selected")
	var detail: MapDetailPanel = r.current_screen.detail_panel()
	assert_eq(detail.title_label().text, LedgerResolvers.label_of(Game.data, Game.state, first), "its card")
	assert_eq(screen.search_box().text, "", "the box empties")
	assert_false(screen.find_child("SearchList", true, false).visible)


func test_a_folded_manor_opens_its_province_and_is_selected() -> void:
	var r: GameRoot = await _court()
	var screen := await _open(r)
	var folded: Dictionary = screen.snapshot()["folded"]
	var manor := ""
	for id: String in folded:
		if id.begins_with("manor:"):
			manor = id
			break
	assert_ne(manor, "")
	var prov := String(folded[manor])
	await _type(screen, LedgerResolvers.label_of(Game.data, Game.state, manor))
	var at := -1
	var found := screen.search_matches()
	for i in found.size():
		if String(found[i]["id"]) == manor:
			at = i
	if at < 0:
		# a common name: the box lists the first few; go there as a pick would
		screen.go_to(manor, prov)
	else:
		(screen.find_child("Match%d" % at, true, false) as Button).pressed.emit()
	await wait_frames(1)
	assert_true(screen.opened().has(prov.substr(9)), "its province opened")
	assert_true((screen.snapshot()["nodes"] as Array).any(func(n: Dictionary) -> bool:
		return String(n["id"]) == manor), "so its star exists")
	assert_eq(screen.view().selected(), manor, "and is selected")


func test_escape_clears_the_box_and_opens_no_menu() -> void:
	var r: GameRoot = await _court()
	var screen := await _open(r)
	await _type(screen, "a")
	assert_true(screen.find_child("SearchList", true, false).visible)
	_key(KEY_ESCAPE)
	await wait_frames(1)
	assert_eq(screen.search_box().text, "")
	assert_false(screen.find_child("SearchList", true, false).visible)
	assert_false(screen.search_box().has_focus())
	assert_false(r._pause_menu.visible, "Escape in the box is the box's, not the pause menu's")


func test_a_space_in_the_box_is_typed_not_the_clock() -> void:
	var r: GameRoot = await _court()
	var screen := await _open(r)
	var held := Game.clock_held
	var speed := Game.clock_speed
	await _type(screen, "a b")
	assert_eq(screen.search_box().text, "a b", "the space reached the box")
	assert_eq(Game.clock_speed, speed, "the clock did not toggle")
	assert_eq(Game.clock_held, held)
