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
	await wait_frames(2)
	assert_false(r.news_ticker().visible, "no ticker on the title screen")
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_frames(2)
	var ticker := r.news_ticker()
	assert_true(ticker.visible, "the strip shows on every gameplay screen")
	var rect := ticker.get_global_rect()
	assert_almost_eq(rect.position.y + rect.size.y,
		r.size.y - BottomBar.BAR_HEIGHT, 1.0,
		"the strip rests directly above the bottom tab bar")
	var bg: ColorRect = ticker.find_child("TickerBg", true, false)
	assert_lt(bg.color.a, 0.7, "the strip is transparent glass")
	assert_almost_eq(ticker.speed(), Game.data.bal("news_ticker_speed"), 0.001,
		"crawl speed is balance data, not a hardcoded constant")

func test_published_news_joins_the_crawl_and_moves_leftward() -> void:
	Game.start_campaign(42)
	Game.next_tick()
	var r := _root()
	await wait_frames(2)
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_frames(1)
	Game.publish_news("Wolves were heard close to the north villages.")
	await wait_frames(1)
	var ticker := r.news_ticker()
	assert_has(ticker.items(), "Wolves were heard close to the north villages.")
	assert_string_contains(ticker.crawl_label().text, "Wolves")
	var x0: float = ticker.crawl_label().position.x
	await wait_frames(10)
	assert_lt(ticker.crawl_label().position.x, x0, "the line crawls leftward")

func test_chronicle_entries_publish_dated_headlines() -> void:
	Game.start_campaign(42)
	var got: Array = []
	var handler := func(text: String) -> void: got.append(text)
	Game.news_published.connect(handler)
	var overlay := CalendarOverlay.new()
	add_child_autofree(overlay)
	await wait_frames(1)
	overlay._tick = 2
	overlay._day = 4
	overlay._add_news("A pedlar swears he saw lights over the barrow hills.")
	Game.news_published.disconnect(handler)
	assert_eq(got.size(), 1, "each chronicle entry reaches the ticker feed")
	assert_string_contains(String(got[0]),
		"A pedlar swears he saw lights over the barrow hills.")
	assert_string_contains(String(got[0]), Calendar.date_string(2, 4),
		"the headline carries its chronicle date")
