extends GutTest
## The persistent bottom news strip (user request 2026-08-31): transparent,
## pinned above the bottom tab bar on every gameplay screen, fed by the
## Royal Chronicle via Game.news_published, crawling at the balance-driven
## speed.

func _root() -> GameRoot:
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	return r

func test_ticker_hidden_on_menu_pinned_bottom_and_transparent_in_game() -> void:
	Game.start_campaign(42)
	Game.next_tick()
	var r := _root()
	await wait_process_frames(2)
	assert_false(r.news_ticker().visible, "no ticker on the title screen")
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_process_frames(2)
	var ticker := r.news_ticker()
	assert_true(ticker.visible, "the strip shows on every gameplay screen")
	var rect := ticker.get_global_rect()
	var bg: Panel = ticker.find_child("TickerBg", true, false)
	if UiPalette.war_table():
		# THE WAR TABLE: a paper slip lying in the bookmarks' band, between the groups
		assert_gt(rect.position.y, r.size.y - BottomBar.BAR_HEIGHT - 1.0, "the slip lies in the bookmarks' band")
		assert_lt(rect.end.y, r.size.y + 1.0, "and on the screen")
		# between the lenses and the screens (owner 2026-10-01: log界面挪到measurement和
		# realm tab中间; 2026-10-02: 拉长log tab, both tabs gone), clear of every bookmark
		assert_eq(r.size.x, 1280.0, "measured at the design width (the gap is a width; an earlier test may leave the window taller)")
		assert_gt(rect.position.x, r.bottom_bar().button("MANORS").get_global_rect().end.x - 0.5,
			"right of MANORS")
		assert_lt(rect.end.x, r.bottom_bar().button("FAMILIES").get_global_rect().position.x + 0.5, "left of FAMILIES")
		assert_gt(rect.size.x, 300.0, "long (owner 2026-10-02: 拉长log tab)")
		assert_true(ticker.find_child("LogButton", true, false).is_visible_in_tree(), "its LOG kept")
		for tab: String in BottomBar.TABS:
			var b := r.bottom_bar().button(tab)
			if b != null and b.visible:
				assert_false(rect.intersects(b.get_global_rect()), "clear of the " + tab + " bookmark")
		assert_true(bg.get_theme_stylebox("panel") is PaperStyle, "the slip is paper")
	else:
		assert_almost_eq(rect.position.y + rect.size.y,
			r.size.y - BottomBar.BAR_HEIGHT, 1.0,
			"the strip rests directly above the bottom tab bar")
		assert_lt((bg.get_theme_stylebox("panel") as StyleBoxFlat).bg_color.a, 0.7, "the bar is translucent glass")
	assert_almost_eq(ticker.speed(), Game.data.bal("news_ticker_speed"), 0.001,
		"crawl speed is balance data, not a hardcoded constant")

func test_published_news_joins_the_crawl_and_moves_leftward() -> void:
	Game.start_campaign(42)
	Game.next_tick()
	# an unheard event holds the clock and speaks on the news (owner 2026-10-02)
	if not Game.state.pending_event.is_empty():
		Game.apply_event_choice(String(Game.state.pending_event["choices"][0]["choice_id"]))
	var r := _root()
	await wait_process_frames(2)
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_process_frames(1)
	Game.publish_news("Wolves were heard close to the north villages.")
	await wait_process_frames(1)
	var ticker := r.news_ticker()
	assert_has(ticker.items(), "Wolves were heard close to the north villages.")
	assert_string_contains(ticker.crawl_label().text, "Wolves")
	# It crawls only while time runs (owner 2026-09-14).
	Game.set_clock_speed(0)
	var x0: float = ticker.crawl_label().position.x
	await wait_process_frames(10)
	assert_eq(ticker.crawl_label().position.x, x0, "paused: the line holds still")
	Game.set_clock_speed(1)
	await wait_process_frames(10)
	Game.set_clock_speed(0)
	assert_lt(ticker.crawl_label().position.x, x0, "time runs: the line crawls leftward")
	# Every headline is kept, dated, and the LOG opens the history.
	assert_eq(String(ticker.history()[0]["text"]), "Wolves were heard close to the north villages.")
	assert_eq(String(ticker.history()[0]["date"]), Calendar.date_string(Game.state.tick, Game.state.day))
	# What a day's END brings is dated the day that ended, not the day begun
	# (owner 2026-10-06: 顶栏日期滞后一天); GameRoot dates it so as it tells it.
	Game.news_dated_to(Game.state.absolute_day() + 2)   # any day other than today's
	Game.publish_news("The column reached the ford.")
	Game.news_dated_to(-1)
	assert_eq(String(ticker.history()[0]["date"]), Calendar.date_of_day(Game.state.absolute_day() + 2))
	Game.publish_news("A rider was seen on the road.")
	assert_eq(String(ticker.history()[0]["date"]), Calendar.date_string(Game.state.tick, Game.state.day),
		"anything else is dated the day now running")
	ticker.show_history(true)
	await wait_process_frames(2)
	assert_true(ticker.history_panel().visible)
	var entries := ticker.history_panel().find_child("Entries", true, false)
	assert_gt(entries.get_child_count(), 0, "the history lists what was heard")
	ticker.show_history(false)

## The news bar carries a work's progress (owner 2026-09-14): 30%, 70% and
## complete, as the clock runs.
func test_works_are_announced_at_their_milestones() -> void:
	var r := _root()
	await wait_process_frames(2)
	r.current_screen.start_requested.emit()
	await wait_process_frames(2)
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_process_frames(1)
	Game.state.pending_event = {}
	var cell := -1
	for c: int in MapManors.manors_of_house(Game.data, Game.state, MapManors.crown(Game.state),
			Game.data.resolve_realm("player_realm")):
		cell = c
		break
	assert_true(MapManors.start_work(Game.data, Game.state, cell, "chapel", "test"))
	(Game.state.manor_works[str(cell)] as Array)[0]["days"] = 10
	var got: Array = []
	var handler := func(text: String) -> void: got.append(text)
	Game.news_published.connect(handler)
	Game.data.balance["time_day_seconds"] = 0.001
	Game.set_clock_speed(1)
	for i in 30:
		await wait_process_frames(1)
		Game.state.pending_event = {}
		if not MapManors.is_building(Game.state, cell, "chapel"):
			break
	Game.set_clock_speed(0)
	Game.data.balance["time_day_seconds"] = 1.0
	Game.news_published.disconnect(handler)
	var joined := "\n".join(got)
	assert_string_contains(joined, "is 30% done")
	assert_string_contains(joined, "is 70% done")
	assert_string_contains(joined, "is complete")

## A building that first stands idle for want of inputs (LEDGER M5) is news,
## once, at the month's close.
func test_a_newly_idle_building_is_announced() -> void:
	var r := _root()
	await wait_process_frames(2)
	r.current_screen.start_requested.emit()
	await wait_process_frames(2)
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_process_frames(1)
	Game.state.pending_event = {}
	var cell := -1
	for c: int in MapManors.manors_of_house(Game.data, Game.state, MapManors.crown(Game.state),
			Game.data.resolve_realm("player_realm")):
		if not (ManorEconomy.line_of(Game.data, Game.state, c, Game.state.tick)["units"] as Dictionary).has("iron"):
			cell = c
			break
	assert_true(MapManors.build(Game.data, Game.state, cell, "smithy", "test: a forge"))
	# its iron needed past any purse, so it idles whatever the lord's pools
	# hold (a negative pool no longer lasts the month: the day's supply step
	# settles the pools into the towns every day)
	var need: Array = []
	for inp: Dictionary in Game.data.building_inputs["smithy"]:
		need.append(int(inp["units"]))
		inp["units"] = 1000000000
	RealmEconomy.forget()
	Game.state.day = Calendar.DAYS_PER_TICK
	var tick := Game.state.tick
	var got: Array = []
	var handler := func(text: String) -> void: got.append(text)
	Game.news_published.connect(handler)
	Game.data.balance["time_day_seconds"] = 0.001
	Game.set_clock_speed(1)
	for i in 30:
		await wait_process_frames(1)
		Game.state.pending_event = {}
		if Game.state.tick > tick:
			break
	Game.set_clock_speed(0)
	Game.data.balance["time_day_seconds"] = 1.0
	Game.news_published.disconnect(handler)
	for i in need.size():
		(Game.data.building_inputs["smithy"][i] as Dictionary)["units"] = int(need[i])
	RealmEconomy.forget()
	var joined := "\n".join(got)
	assert_string_contains(joined, "The smithy at %s stands idle: no iron." % MapManors.label_of(Game.data, cell))
