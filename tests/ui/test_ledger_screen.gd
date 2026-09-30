extends GutTest
## The LEDGER screen (spec 2026-09-30 §6): lenses, the left column's card
## and list, drilling into an instance, and an order run for real.

func _court() -> GameRoot:
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	await wait_frames(2)
	var menu: MainMenu = r.current_screen
	menu.menu_column().get_node("StartGame").pressed.emit()
	await wait_frames(1)
	menu.setup_panel().find_child("BeginReign", true, false).pressed.emit()
	await wait_frames(2)
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_frames(2)
	return r

func test_a_type_sphere_lists_its_instances_and_a_row_drills_in() -> void:
	var r: GameRoot = await _court()
	r.bottom_bar().button("LEDGER").pressed.emit()
	await wait_frames(2)
	var screen := r.ledger_screen()
	screen.set_lens("war")
	screen.view().sphere_selected.emit("type:regiment")
	await wait_frames(1)
	var detail: MapDetailPanel = r.current_screen.detail_panel()
	assert_true(detail.has_content(), "the left column holds the list")
	var first := detail.find_children("*", "Button", true, false).filter(
		func(b: Button) -> bool: return b.has_meta("ledger_id"))[0] as Button
	first.pressed.emit()
	await wait_frames(1)
	var focus := String(screen.snapshot()["focus_id"])
	assert_true(focus.begins_with("regiment:"))
	var card := MapObjects.army_card(Game.data, focus.substr(9), Game.state)
	assert_eq(detail.title_label().text, String(card["title"]), "the drilled regiment's own card replaced the list")
	assert_true(detail.find_children("*", "Button", true, false).filter(
		func(b: Button) -> bool: return b.has_meta("ledger_id")).is_empty(), "the list is gone")
	screen.back()
	assert_eq(String(screen.snapshot()["focus_id"]), "")
	assert_false(detail.has_content(), "back to the realm closes the focus's card")

func test_a_double_clicked_person_opens_their_card() -> void:
	var r: GameRoot = await _court()
	r.bottom_bar().button("LEDGER").pressed.emit()
	await wait_frames(2)
	var screen := r.ledger_screen()
	screen.set_lens("court")
	var id := String((screen.snapshot()["nodes"] as Array)[0]["id"])
	screen.view().drill_requested.emit(id)
	await wait_frames(1)
	var detail: MapDetailPanel = r.current_screen.detail_panel()
	assert_true(detail.has_content())
	assert_eq(detail.title_label().text, LedgerResolvers.label_of(Game.data, Game.state, id))

func test_the_court_lens_draws_every_character() -> void:
	var r: GameRoot = await _court()
	r.bottom_bar().button("LEDGER").pressed.emit()
	await wait_frames(2)
	r.ledger_screen().set_lens("court")
	assert_eq(r.ledger_screen().snapshot()["nodes"].size(), Game.state.characters.size())

func test_an_order_on_a_pool_runs_through_the_engine() -> void:
	var r: GameRoot = await _court()
	r.bottom_bar().button("LEDGER").pressed.emit()
	await wait_frames(2)
	var screen := r.ledger_screen()
	var before := float(Game.state.metrics["treasury"])
	var menu: LedgerOrderMenu = screen.find_child("Orders", true, false)
	screen.view().orders_requested.emit("type:civil_goods", Vector2(100, 100))
	await wait_frames(1)
	menu.hide()                      # PopupMenu hides BEFORE id_pressed, as for real
	menu.id_pressed.emit(0)          # the first row: Buy civil goods
	await wait_frames(1)
	assert_lt(float(Game.state.metrics["treasury"]), before, "the purchase was paid")

## Final fix I2: a state change marks the LEDGER dirty; however many come in
## one frame, it is drawn again once.
func test_refreshes_in_one_frame_rebuild_once() -> void:
	var r: GameRoot = await _court()
	r.bottom_bar().button("LEDGER").pressed.emit()
	await wait_frames(2)
	var screen := r.ledger_screen()
	var before := screen._rebuilds
	screen.refresh()
	screen.refresh()
	screen.refresh()
	assert_eq(screen._rebuilds, before, "nothing is drawn inside the calls")
	await wait_frames(2)
	assert_eq(screen._rebuilds, before + 1, "drawn once")

## Final fix I2: a focus that vanished takes its card with it and the
## camera frames the realm again.
func test_a_lost_focus_closes_its_card_and_reframes() -> void:
	var r: GameRoot = await _court()
	MissiveLog.add(Game.data, Game.state, MissiveWriter.monthly(Game.data, Game.state, Game.state.tick))
	var rid := int((Game.state.missives[Game.state.missives.size() - 1] as Dictionary)["id"])
	r.bottom_bar().button("LEDGER").pressed.emit()
	await wait_frames(2)
	var screen := r.ledger_screen()
	screen.set_lens("intelligence")
	screen.drill("report:%d" % rid)
	var detail: MapDetailPanel = r.current_screen.detail_panel()
	assert_true(detail.has_content(), "the report's card")
	screen.view().orbit().zoom(2.0)
	screen.view()._framed = false
	Game.state.missives = Game.state.missives.filter(func(m: Dictionary) -> bool: return int(m["id"]) != rid)
	screen.refresh()
	await wait_frames(2)
	assert_eq(String(screen.snapshot()["focus_id"]), "")
	assert_false(detail.has_content(), "the vanished focus's card went with it")
	assert_true(screen.view()._framed, "the camera framed the realm again")

## Final fix M3: the LEDGER closes only a card it put in the left column.
func test_closing_keeps_a_card_the_ledger_did_not_put_there() -> void:
	var r: GameRoot = await _court()
	var detail: MapDetailPanel = r.current_screen.detail_panel()
	detail.show_province(MapManors.home_province(Game.data, Game.state))
	assert_true(detail.has_content())
	r.bottom_bar().button("LEDGER").pressed.emit()
	await wait_frames(2)
	var screen := r.ledger_screen()
	screen.close()
	assert_true(detail.has_content(), "the player's own card stays")
	r.bottom_bar().button("LEDGER").pressed.emit()
	await wait_frames(2)
	screen.set_lens("court")
	var id := String((screen.snapshot()["nodes"] as Array)[0]["id"])
	screen.drill(id)
	assert_true(detail.has_content())
	screen.set_lens("economy")
	assert_false(detail.has_content(), "a new lens takes the old focus's card away")
	screen.drill(id)
	screen.close()
	assert_false(detail.has_content(), "closing takes the LEDGER's own card")

## LEDGER M3: a strand ("<link id>#<i>") is its link's — its card lists every
## account, and its orders give the flow to another councillor for real.
func test_a_strand_opens_its_links_card_and_gives_its_flow_away() -> void:
	var r: GameRoot = await _court()
	var m: Character = Game.state.characters[String(Game.state.council["marshal"])]
	m.traits = ["venal"]
	m.skills["sk_admin"] = 16
	m.opinion = 50
	Game.state.metrics["strategic"] = 1000000.0
	for c in Game.state.regiments.keys():
		Game.state.regiments[c]["supplies"] = 0
	r.bottom_bar().button("LEDGER").pressed.emit()
	await wait_frames(2)
	var screen := r.ledger_screen()
	screen.set_lens("war")
	var code := String(SupplySystem.plan(Game.data, Game.state)[0]["code"])
	screen.drill("regiment:" + code)
	var link: Dictionary = (screen.snapshot()["links"] as Array).filter(
		func(l: Dictionary) -> bool: return String(l["type"]) == "supplies_out")[0]
	assert_eq((link["accounts"] as Array).size(), 2, "two strands")
	var strand := String(link["id"]) + "#1"
	screen.view().thread_selected.emit(strand)
	await wait_frames(1)
	var detail: MapDetailPanel = r.current_screen.detail_panel()
	assert_eq(detail.title_label().text, LedgerCards.thread_entry(Game.data, Game.state, link)["title"])
	var menu: LedgerOrderMenu = screen.find_child("Orders", true, false)
	screen.view().orders_requested.emit(strand, Vector2(100, 100))
	await wait_frames(1)
	var gives: Array = []
	for i in menu.item_count:
		if menu.get_item_text(i).begins_with("Give it to "):
			gives.append(i)
	assert_eq(gives.size(), Game.state.council.size() - 1, "every councillor but the marshal")
	menu.hide()
	menu.id_pressed.emit(menu.get_item_id(int(gives[0])))
	await wait_frames(1)
	assert_ne(Governance.governor_of(Game.data, Game.state, "supply_line"), m.id, "the supply lines changed hands")
