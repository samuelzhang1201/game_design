extends GutTest
## The LEDGER screen (spec 2026-09-30 §6): lenses, the left column's card
## and list, drilling into an instance, and an order run for real.

## The court on a fresh reign; no test here needs the opening narration.
func _court() -> GameRoot:
	Game.start_campaign(44)   # the seed Start Game begins
	Game.next_tick()
	# the opening event waits on the table and holds the clock (owner
	# 2026-10-02): answer it, so these tests measure the LEDGER's own hold
	if not Game.state.pending_event.is_empty():
		Game.apply_event_choice(String(Game.state.pending_event["choices"][0]["choice_id"]))
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	await wait_process_frames(2)
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_process_frames(2)
	return r

func _open(r: GameRoot) -> LedgerScreen:
	r.bottom_bar().button("LEDGER").pressed.emit()
	await wait_process_frames(2)
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


## A double-clicked province opens: its manors stand, its card fills the
## column, and the camera frames it and every star it unfolded (Task 11 fix
## round 1, F8); a second double click closes it and frames nothing new,
## and Back closes it too.
func test_a_double_clicked_province_opens_frames_and_closes() -> void:
	var r: GameRoot = await _court()
	var screen := await _open(r)
	var home := MapManors.home_province(Game.data, Game.state)
	screen.view().drill_requested.emit("province:" + home)
	await wait_process_frames(1)
	var manors := (screen.snapshot()["nodes"] as Array).filter(func(n: Dictionary) -> bool:
		return String(n["type"]) == "manor")
	assert_eq(manors.size(), MapManors.manors_of_province(Game.data, home, Game.state).size(), "its manors stand")
	assert_true(screen.opened().has(home))
	var detail: MapDetailPanel = r.current_screen.detail_panel()
	assert_true(detail.has_content(), "the province's card")
	var framed: Array = screen.view()._frame_ids
	assert_true(framed.has("province:" + home), "the province itself is framed")
	assert_eq(framed.size(), 1 + (screen.snapshot()["nodes"] as Array).filter(func(n: Dictionary) -> bool:
		return String(n.get("home_id", "")) == "province:" + home).size(), "and every star whose home it is")
	assert_gt(framed.size(), manors.size(), "its manors among them")
	screen.view().drill_requested.emit("province:" + home)
	await wait_process_frames(1)
	assert_false(screen.opened().has(home), "a second double click closes it")
	assert_eq(screen.view()._frame_ids, framed, "closing frames nothing new")
	screen.drill("province:" + home)
	assert_true(screen.opened().has(home))
	screen.back()
	assert_false(screen.opened().has(home), "back closes it")
	assert_true((screen.snapshot()["nodes"] as Array).all(func(n: Dictionary) -> bool:
		return String(n["type"]) != "manor"))


func test_a_double_clicked_person_opens_their_card_and_is_selected() -> void:
	var r: GameRoot = await _court()
	var screen := await _open(r)
	screen.view().drill_requested.emit("character:you")
	await wait_process_frames(1)
	var detail: MapDetailPanel = r.current_screen.detail_panel()
	assert_eq(detail.title_label().text, LedgerResolvers.label_of(Game.data, Game.state, "character:you"))
	assert_eq(screen.view().selected(), "character:you")


## The flat 2D view was removed (owner 2026-10-01: 删掉2D按钮和2d view吧).
func test_there_is_no_2d_mode() -> void:
	var r: GameRoot = await _court()
	var screen := await _open(r)
	assert_null(screen.find_child("Mode", true, false), "no Mode button")
	assert_false(screen.has_method("toggle_flat"))
	assert_false(screen.view().has_method("set_flat"))
	assert_false(screen.view().has_method("is_flat"))


func test_an_order_on_a_pool_runs_through_the_engine() -> void:
	var r: GameRoot = await _court()
	var screen := await _open(r)
	var before := float(Game.state.metrics["treasury"])
	var menu: LedgerOrderMenu = screen.find_child("Orders", true, false)
	screen.view().orders_requested.emit("type:civil_goods", Vector2(100, 100))
	await wait_process_frames(1)
	menu.hide()                      # PopupMenu hides BEFORE id_pressed, as for real
	menu.id_pressed.emit(0)          # the first row: Buy civil goods
	await wait_process_frames(1)
	assert_lt(float(Game.state.metrics["treasury"]), before, "the purchase was paid")


## Refreshes, an order's state change among them, are drained once in
## _process: nothing is drawn inside the calls, and the chart shows the state
## as it is now on the next frame, drawn once.
func test_refreshes_and_an_order_are_drawn_once_on_the_next_frame() -> void:
	var r: GameRoot = await _court()
	var screen := await _open(r)
	await wait_process_frames(2)
	var before := screen._rebuilds
	screen.refresh()
	screen.refresh()
	Game.state_changed.emit()
	assert_eq(screen._rebuilds, before, "nothing is drawn inside the calls")
	# drained in _process: wait for a process frame, not a count of physics
	# frames (several can run inside one slow process frame)
	await wait_until(func() -> bool: return screen._rebuilds > before, 1.0)
	await wait_process_frames(2)
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
	var before := screen._rebuilds
	screen.refresh()
	# drained in _process: wait for a process frame, not a count of physics
	# frames (several can run inside one slow process frame)
	await wait_until(func() -> bool: return screen._rebuilds > before, 1.0)
	await wait_process_frames(2)
	assert_eq(screen.view().selected(), "")
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
	# the supply lines are the regiments' own now: the first land regiment
	# runs one (spec 2026-10-07-army-supply-lines)
	var codes: Array = Game.state.regiments.keys()
	codes.sort()
	for c in codes:
		if String(ArmySystem.regiment(Game.data, String(c)).get("is_naval", "0")) != "1":
			Game.state.supply_lines[c] = SupplyLines._new_record(
				TownStores.realm_towns(Game.data, Game.state)[0], 1000, 1)
			Game.state.supply_lines[c]["state"] = SupplyLines.FLOWING
			break
	var screen := await _open(r)
	var link: Dictionary = (screen.snapshot()["links"] as Array).filter(func(l: Dictionary) -> bool:
		return String(l["type"]) == "supplies_out" and (l["accounts"] as Array).size() == 2)[0]
	screen.view().thread_selected.emit(String(link["id"]) + "#1")
	await wait_process_frames(1)
	var detail: MapDetailPanel = r.current_screen.detail_panel()
	assert_eq(detail.title_label().text, LedgerCards.thread_entry(Game.data, Game.state, link)["title"])


## Owner 2026-10-01 (replacing final review I1a): entering the LEDGER stops
## the clock, even a running one; nothing starts it while the LEDGER is open
## — not Space, not the top bar's play buttons; closing leaves it paused, and
## the player starts it again.
func _space() -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.physical_keycode = KEY_SPACE
	key.pressed = true
	get_viewport().push_input(key)
	var up := key.duplicate() as InputEventKey
	up.pressed = false
	get_viewport().push_input(up)


func test_opening_the_ledger_stops_the_clock_until_the_player_starts_it() -> void:
	var r: GameRoot = await _court()
	var fast := int(Game.data.bal("time_speed_fast"))
	Game.set_clock_speed(fast)
	assert_eq(Game.clock_speed, fast)
	var screen := await _open(r)
	assert_eq(Game.clock_speed, 0, "the LEDGER stops the clock")
	_space()
	await wait_process_frames(1)
	assert_eq(Game.clock_speed, 0, "Space does not start it while the LEDGER is open")
	var bar: TopBar = r.current_screen.top_bar()
	for speed: int in [1, fast, int(Game.data.bal("time_speed_faster"))]:
		var b := bar.clock_button(speed)
		assert_true(b.disabled, "the %d button is greyed" % speed)
		b.pressed.emit()
		assert_eq(Game.clock_speed, 0, "the %d button does not start it" % speed)
	Game.set_clock_speed(1)
	assert_eq(Game.clock_speed, 0, "nor does anyone else")
	screen.close()
	assert_eq(Game.clock_speed, 0, "closing leaves it paused")
	assert_false(Game.clock_held)
	assert_false(bar.clock_button(1).disabled, "the play buttons are back")
	if Game.has_method("toggle_clock"):  # Space pauses and resumes play (main, 2026-09-30)
		_space()
		await wait_process_frames(1)
		assert_gt(Game.clock_speed, 0, "after closing, Space starts it again")
	else:
		bar.clock_button(1).pressed.emit()
		assert_eq(Game.clock_speed, 1, "after closing, play starts it again")
	Game.set_clock_speed(0)


## Final review minors: the crumb names the realm, the chosen cluster and
## each opened province in order, and Back shows only while one is open;
## closing the LEDGER forgets what this viewing opened.
func test_the_crumb_and_back_follow_the_opened_provinces() -> void:
	var r: GameRoot = await _court()
	var screen := await _open(r)
	var crumb := screen.find_child("Crumb", true, false) as Label
	var back := screen.find_child("Back", true, false) as Button
	assert_eq(crumb.text, "Realm")
	assert_false(back.visible, "nothing opened: no Back")
	screen.set_lens("economy")
	var cluster_label := ""
	for c: Dictionary in Game.data.ledger_clusters:
		if String(c["lens"]) == "economy":
			cluster_label = String(c["label"])
	assert_eq(crumb.text, "Realm › " + cluster_label)
	var home := MapManors.home_province(Game.data, Game.state)
	screen.drill("province:" + home)
	assert_eq(crumb.text, "Realm › %s › %s" % [cluster_label,
		LedgerResolvers.label_of(Game.data, Game.state, "province:" + home)])
	assert_true(back.visible, "a province open: Back")
	back.pressed.emit()
	assert_eq(crumb.text, "Realm › " + cluster_label)
	assert_false(back.visible)
	screen.drill("province:" + home)
	screen.close()
	assert_true(screen.opened().is_empty(), "closing forgets this viewing's opened provinces")
	screen = await _open(r)
	assert_false((screen.find_child("Back", true, false) as Button).visible)


## Final review minors: the selected star's card follows a redraw (its
## figures are the day's it was redrawn on).
func test_the_selected_stars_card_follows_a_redraw() -> void:
	var r: GameRoot = await _court()
	var screen := await _open(r)
	screen.drill("character:you")
	var detail: MapDetailPanel = r.current_screen.detail_panel()
	var title := detail.title_label().text
	detail.title_label().text = "stale"
	var before := screen._rebuilds
	screen.refresh()
	# drained in _process: wait for a process frame, not a count of physics
	# frames (several can run inside one slow process frame)
	await wait_until(func() -> bool: return screen._rebuilds > before, 1.0)
	await wait_process_frames(2)
	assert_eq(detail.title_label().text, title, "the card was drawn again with the chart")
	assert_eq(screen.view().selected(), "character:you")
