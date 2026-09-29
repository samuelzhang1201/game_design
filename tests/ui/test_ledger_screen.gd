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
	assert_true(String(screen.snapshot()["focus_id"]).begins_with("regiment:"))
	screen.back()
	assert_eq(String(screen.snapshot()["focus_id"]), "")

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
