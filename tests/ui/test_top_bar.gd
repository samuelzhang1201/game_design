extends GutTest
## TopBar (UI_example chrome, supersedes the KingdomCard): date + the six
## metrics with this tick's deltas + a pending-event chip. Ports the old
## kingdom-card coverage (values mode, changes mode) onto the strip.

func _bar() -> TopBar:
	var t: TopBar = load("res://scenes/top_bar.tscn").instantiate()
	add_child_autofree(t)
	return t

## The crown's generated arms (owner 2026-09-15) mark the lord's purse and
## fly beside the date, where the family-flag glyph was.
func test_the_crowns_arms_mark_the_lords_purse_and_the_date() -> void:
	Game.start_campaign(42)
	var bar := _bar()
	await wait_process_frames(2)
	var arms := HouseArms.texture_of_house(Game.data, Game.state, MapManors.crown(Game.state))
	assert_not_null(arms, "the crown has arms")
	assert_same(bar.lord_crest().texture, arms)
	assert_same(bar.date_arms().texture, arms)
	# THE WAR TABLE (2026-10-01): the brass dial takes the date's place and the
	# arms stay on the tally board's house row alone (twice was noise).
	assert_eq(bar.date_arms().visible, not UiPalette.war_table())

func test_shows_date_and_metric_values() -> void:
	Game.start_campaign(42)
	var t := _bar()
	await wait_process_frames(1)
	assert_string_contains(t.find_child("DateLabel", true, false).text, "Year 1")
	assert_eq(t.metric_text("treasury"), UiPalette.format_int(int(Game.state.metrics["treasury"])))
	assert_eq(t.metric_text("grain"), UiPalette.format_int(int(Game.state.metrics["grain"])))

func test_shows_tick_deltas_from_current_report() -> void:
	Game.start_campaign(42)
	Game.next_tick()
	var t := _bar()
	await wait_process_frames(1)
	assert_ne(t.delta_text("treasury"), "",
		"income always moves treasury, so its delta column is filled")
	assert_true(t.delta_text("treasury").begins_with("+")
		or t.delta_text("treasury").begins_with("-"))

func test_event_chip_tracks_pending_event() -> void:
	Game.start_campaign(42)
	Game.next_tick()
	if not Game.state.pending_event.is_empty():
		Game.apply_event_choice(String(Game.state.pending_event["choices"][0]["choice_id"]))
	var t := _bar()
	await wait_process_frames(1)
	assert_false(t.find_child("EventChip", true, false).visible)
	Game.engine.events._fire("ev_01", Game.state)
	t.refresh()
	assert_true(t.find_child("EventChip", true, false).visible,
		"a pending event shows the chip")
	Game.apply_event_choice(String(Game.state.pending_event["choices"][0]["choice_id"]))
	await wait_process_frames(1)
	assert_false(t.find_child("EventChip", true, false).visible,
		"resolving the event (state_changed) hides the chip again")

## Icons instead of words (user request 2026-09-09), each with a floating
## tooltip; the values keep their seams.
func test_metrics_show_as_icons_with_tooltips() -> void:
	Game.start_campaign(42)
	var t := _bar()
	await wait_process_frames(1)
	for m in TopBar.ORDER + TopBar.LORD:
		var icon := t.icon_for(m)
		assert_not_null(icon, "%s has an icon" % m)
		assert_ne(icon.tooltip_text, "", "%s explains itself on hover" % m)
	assert_eq(t.icon_for("treasury").glyph(), "coin")

## The clock (owner 2026-09-13): pause, play, 2x and 4x beside the date; the
## lit one is Game's speed, and the date reads to the day.
func test_the_clock_buttons_set_the_speed_and_the_date_reads_the_day() -> void:
	Game.start_campaign(42)
	Game.set_clock_speed(0)
	var t := _bar()
	await wait_process_frames(1)
	if UiPalette.war_table():
		# THE WAR TABLE: the day on the brass dial (its tooltip the full date),
		# the season and year written beside it
		var dial: BrassDial = t.find_child("DateDial", true, false)
		assert_not_null(dial, "the date is a brass dial")
		assert_eq(dial.day, Game.state.day)
		assert_eq(dial.tooltip_text, Calendar.date_string(Game.state.tick, Game.state.day))
		assert_string_contains(t.find_child("DateLabel", true, false).text,
			Calendar.season_name(Game.state.tick))
	else:
		assert_eq(t.find_child("DateLabel", true, false).text,
			Calendar.date_string(Game.state.tick, Game.state.day))
	assert_not_null(t.clock_button(0))
	assert_not_null(t.clock_button(1))
	assert_not_null(t.clock_button(2))
	assert_not_null(t.clock_button(4))
	assert_true(t.clock_button(0).button_pressed, "paused at the start")
	t.clock_button(2).pressed.emit()
	assert_eq(Game.clock_speed, 2)
	await wait_process_frames(1)
	assert_true(t.clock_button(2).button_pressed)
	assert_false(t.clock_button(0).button_pressed)
	# Another bar (another screen's) follows the same clock.
	var other := _bar()
	await wait_process_frames(1)
	assert_true(other.clock_button(2).button_pressed)
	Game.set_clock_speed(0)
	await wait_process_frames(1)
	assert_true(other.clock_button(0).button_pressed)
	assert_true(t.clock_button(0).button_pressed)

## Two purses (owner 2026-09-14): the crown's row — treasury, strategic and
## civil goods under a crown — and the lord's own purse under the house's
## arms, each with what the month brings (RealmEconomy.purses). Nothing
## else is in the bar: the realm's temper moved to the country card.
func test_the_bar_shows_the_crowns_pools_and_the_lords_purse() -> void:
	Game.start_campaign(42)
	var bar := _bar()
	await wait_process_frames(2)
	var p := RealmEconomy.purses(Game.data, Game.state)
	for m in ["treasury", "strategic", "grain", "lord_gold", "lord_strategic", "lord_civil"]:
		assert_eq(bar.metric_text(m), UiPalette.format_int(int(Game.state.metrics[m])), m)
	assert_eq(bar.monthly_text("treasury"), "+%d" % int(p["realm_share"]["tax"]))
	assert_eq(bar.monthly_text("strategic"), "+%d" % int(p["realm_share"]["strategic"]))
	assert_eq(bar.monthly_text("grain"), "+%d" % int(p["realm_share"]["civil"]))
	assert_eq(bar.monthly_text("lord_gold"), "+%d" % int(p["lord"]["tax"]))
	assert_eq(bar.monthly_text("lord_civil"), "+%d" % int(p["lord"]["civil"]))
	assert_gt(int(Game.state.metrics["lord_gold"]), 0, "the lord starts with what his towns hold")
	assert_not_null(bar.crown_mark(), "a crown marks the realm's pools")
	assert_not_null(bar.lord_crest(), "the house's arms mark the lord's purse")
	assert_ne(bar.crown_mark().tooltip_text, bar.lord_crest().tooltip_text, "and each says whose it is")
	for gone in ["unrest", "legitimacy", "army_quality", "church_opinion"]:
		assert_null(bar.icon_for(gone), "%s moved to the country card" % gone)
	# Tidied 2026-09-14 (owner, UIFIX.png): ONE change a pool, the two purses
	# in one grid so their columns line up, and the strip's content clear of
	# the frame's ornament.
	for m in TopBar.ORDER + TopBar.LORD:
		var labels := bar.cell_of(m).get_children().filter(func(c: Node) -> bool: return c is Label)
		assert_eq(labels.size(), 2, "%s: its stock and ONE change, not two" % m)
	bar.size = Vector2(1280, bar.bar_height())
	await wait_process_frames(3)
	var crown_cell := bar.cell_of("treasury").get_global_rect()
	var lord_cell := bar.cell_of("lord_gold").get_global_rect()
	assert_almost_eq(lord_cell.position.x, crown_cell.position.x, 0.5, "the lord's gold stands in the crown's column")
	assert_gt(lord_cell.position.y, crown_cell.position.y, "under it")
	var frame: Control = bar.get_node("%Bar")
	var style := frame.get_theme_stylebox("panel")
	var inner := frame.get_global_rect()
	var menu := (bar.get_node("%MenuButton") as Control).get_global_rect()
	assert_lte(menu.end.x, inner.end.x - style.content_margin_right + 0.5, "MENU stands inside the frame")
	assert_gte(menu.position.y, inner.position.y + style.content_margin_top - 0.5, "below its top rule")
