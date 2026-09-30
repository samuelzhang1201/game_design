extends GutTest
## The LEDGER screen (spec 2026-09-30 §6): lenses, the left column's card
## and list, drilling into an instance, and an order run for real.

func _court() -> GameRoot:
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	await wait_frames(2)
	var menu: MainMenu = r.current_screen
	# Start Game begins the reign at once (owner 2026-09-30: no character creation).
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


func test_the_ledger_opens_on_the_whole_galaxy() -> void:
	var r: GameRoot = await _court()
	var screen := await _open(r)
	assert_eq(String(screen.snapshot()["lens"]), "galaxy")
	assert_eq(screen.lens(), "all")
	assert_eq(screen.view().cluster(), "all")
	assert_eq((screen.snapshot()["nodes"] as Array).size(),
		(Ledger.galaxy(Game.data, Game.state, {})["nodes"] as Array).size())


func test_a_tab_chooses_its_cluster_without_redrawing() -> void:
	var r: GameRoot = await _court()
	var screen := await _open(r)
	var before := screen._rebuilds
	screen.set_lens("court")
	assert_eq(screen.view().cluster(), "court")
	assert_eq(screen._rebuilds, before, "a tab flies the camera; it does not read the realm again")
	screen.set_lens("all")
	assert_eq(screen.view().cluster(), "all")


func test_a_double_clicked_province_opens_and_closes() -> void:
	var r: GameRoot = await _court()
	var screen := await _open(r)
	var home := MapManors.home_province(Game.data, Game.state)
	screen.view().drill_requested.emit("province:" + home)
	await wait_frames(1)
	var manors := (screen.snapshot()["nodes"] as Array).filter(func(n: Dictionary) -> bool:
		return String(n["type"]) == "manor")
	assert_eq(manors.size(), MapManors.manors_of_province(Game.data, home, Game.state).size(), "its manors stand")
	assert_true(screen.opened().has(home))
	var detail: MapDetailPanel = r.current_screen.detail_panel()
	assert_true(detail.has_content(), "the province's card")
	screen.back()
	assert_false(screen.opened().has(home), "back closes it")
	assert_true((screen.snapshot()["nodes"] as Array).all(func(n: Dictionary) -> bool:
		return String(n["type"]) != "manor"))


func test_a_double_clicked_person_opens_their_card_and_is_selected() -> void:
	var r: GameRoot = await _court()
	var screen := await _open(r)
	screen.view().drill_requested.emit("character:you")
	await wait_frames(1)
	var detail: MapDetailPanel = r.current_screen.detail_panel()
	assert_eq(detail.title_label().text, LedgerResolvers.label_of(Game.data, Game.state, "character:you"))
	assert_eq(screen.view()._selected, "character:you")


func test_the_mode_button_lays_the_chart_flat() -> void:
	var r: GameRoot = await _court()
	var screen := await _open(r)
	(screen.find_child("Mode", true, false) as Button).pressed.emit()
	assert_true(screen.view().is_flat())
	(screen.find_child("Mode", true, false) as Button).pressed.emit()
	assert_false(screen.view().is_flat())


func test_an_order_on_a_pool_runs_through_the_engine() -> void:
	var r: GameRoot = await _court()
	var screen := await _open(r)
	var before := float(Game.state.metrics["treasury"])
	var menu: LedgerOrderMenu = screen.find_child("Orders", true, false)
	screen.view().orders_requested.emit("type:civil_goods", Vector2(100, 100))
	await wait_frames(1)
	menu.hide()                      # PopupMenu hides BEFORE id_pressed, as for real
	menu.id_pressed.emit(0)          # the first row: Buy civil goods
	await wait_frames(1)
	assert_lt(float(Game.state.metrics["treasury"]), before, "the purchase was paid")


func test_refreshes_in_one_frame_rebuild_once() -> void:
	var r: GameRoot = await _court()
	var screen := await _open(r)
	var before := screen._rebuilds
	screen.refresh()
	screen.refresh()
	screen.refresh()
	assert_eq(screen._rebuilds, before, "nothing is drawn inside the calls")
	await wait_frames(2)
	assert_eq(screen._rebuilds, before + 1, "drawn once")


func test_a_vanished_selection_takes_its_card() -> void:
	var r: GameRoot = await _court()
	MissiveLog.add(Game.data, Game.state, MissiveWriter.monthly(Game.data, Game.state, Game.state.tick))
	var rid := int((Game.state.missives[Game.state.missives.size() - 1] as Dictionary)["id"])
	var screen := await _open(r)
	screen.drill("report:%d" % rid)
	var detail: MapDetailPanel = r.current_screen.detail_panel()
	assert_true(detail.has_content(), "the report's card")
	Game.state.missives = Game.state.missives.filter(func(m: Dictionary) -> bool: return int(m["id"]) != rid)
	screen.refresh()
	await wait_frames(2)
	assert_eq(screen.view()._selected, "")
	assert_false(detail.has_content(), "the vanished star's card went with it")


func test_closing_keeps_a_card_the_ledger_did_not_put_there() -> void:
	var r: GameRoot = await _court()
	var detail: MapDetailPanel = r.current_screen.detail_panel()
	detail.show_province(MapManors.home_province(Game.data, Game.state))
	var screen := await _open(r)
	screen.close()
	assert_true(detail.has_content(), "the player's own card stays")
	screen = await _open(r)
	screen.drill("character:you")
	assert_true(detail.has_content())
	screen.set_lens("economy")
	assert_false(detail.has_content(), "a new tab takes the old star's card away")
	screen.drill("character:you")
	screen.close()
	assert_false(detail.has_content(), "closing takes the LEDGER's own card")


func test_a_strand_opens_its_links_card() -> void:
	var r: GameRoot = await _court()
	var m: Character = Game.state.characters[String(Game.state.council["marshal"])]
	m.traits = ["venal"]
	m.skills["sk_admin"] = 16
	m.opinion = 50
	Game.state.metrics["strategic"] = 1000000.0
	for c in Game.state.regiments.keys():
		Game.state.regiments[c]["supplies"] = 0
	var screen := await _open(r)
	var link: Dictionary = (screen.snapshot()["links"] as Array).filter(func(l: Dictionary) -> bool:
		return String(l["type"]) == "supplies_out" and (l["accounts"] as Array).size() == 2)[0]
	screen.view().thread_selected.emit(String(link["id"]) + "#1")
	await wait_frames(1)
	var detail: MapDetailPanel = r.current_screen.detail_panel()
	assert_eq(detail.title_label().text, LedgerCards.thread_entry(Game.data, Game.state, link)["title"])
