extends GutTest
## THE WAR TABLE (owner 2026-10-01, B3 + C1's bookmarks; spec
## docs/superpowers/specs/2026-10-01-war-table-ui-design.md): the main screens
## laid out as objects on an oak table. These hold the pieces that carry
## meaning — the switch, the paper ink, the bookmark colours as data, the
## report that no longer runs under the bottom bar, the seal as the one
## primary action — not the look, which the snapshots judge.

func _root() -> GameRoot:
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	return r

func _court(r: GameRoot) -> CourtScreen:
	Game.start_campaign(42)
	Game.next_tick()
	if not Game.state.pending_event.is_empty():
		Game.apply_event_choice(String(Game.state.pending_event["choices"][0]["choice_id"]))
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	return r.current_screen as CourtScreen

func test_the_table_is_on_by_default_and_its_tables_load() -> void:
	assert_true(UiPalette.war_table(), "balance ui_war_table 1")
	for key in ["ink", "ink_muted", "rubric", "paper", "sheet", "brass_mid", "wax_mid", "board", "light"]:
		assert_true(Game.data.ui_table_palette.has(key), "ui_table_palette.csv has " + key)

func test_paper_takes_dark_ink_that_reads_on_it() -> void:
	var ink := UiPalette.ink("soft")
	assert_eq(ink, UiPalette.table_color("ink"))
	var paper := UiPalette.table_color("paper")
	assert_gt(paper.get_luminance() - ink.get_luminance(), 0.45, "dark ink on pale paper")
	assert_eq(UiPalette.ink("rubric"), UiPalette.table_color("rubric"))

func test_every_tab_has_a_bookmark_colour_in_the_data() -> void:
	for tab: String in BottomBar.TABS:
		assert_true(Game.data.ui_bookmarks.has(tab), "ui_bookmarks.csv colours " + tab)
	# the lenses share one colour, and it is not a screen's
	var lens := UiPalette.bookmark_color("HEIGHTS")
	for tab: String in BottomBar.MAP_TABS:
		assert_eq(UiPalette.bookmark_color(tab), lens)
	assert_ne(UiPalette.bookmark_color("REALM"), lens)

func test_the_report_ends_above_the_bookmarks_and_scrolls() -> void:
	var r := _root()
	var court := _court(r)
	await wait_frames(3)
	var column: Control = court.get_node("%LogPanel")
	var bar_top := r.size.y - BottomBar.BAR_HEIGHT
	assert_lt(column.get_global_rect().end.y, bar_top + 1.0,
		"the left column never runs under the bottom bar (it did, 2026-10-01)")
	var scroll: ScrollContainer = court.dashboard().find_child("Scroll", true, false)
	assert_not_null(scroll, "the realm's card scrolls inside the column")

func test_the_map_is_a_sheet_and_the_column_a_report() -> void:
	var r := _root()
	var court := _court(r)
	await wait_frames(2)
	assert_true(court.map_panel().get_theme_stylebox("panel") is PaperStyle, "the map lies on a vellum sheet")
	var report := court.get_node("%LogPanel").get_theme_stylebox("panel") as PaperStyle
	assert_not_null(report, "the left column is paper")
	assert_true(report.pin, "pinned at its head")
	assert_not_null(court.find_child("WarTable", false, false), "the oak table lies under the panels")

func test_the_council_is_a_wax_seal_and_still_the_order() -> void:
	var r := _root()
	var court := _court(r)
	await wait_frames(2)
	var seal := court.council_handle()
	assert_true(seal is WaxSeal, "ENTER THE COUNCIL is the council's seal")
	assert_eq(seal.text, "ENTER THE COUNCIL", "its text stays the order")

func test_tally_marks_count_whole_tens() -> void:
	var chart := BarChart.new()
	add_child_autofree(chart)
	chart.named = true
	chart.tally = true
	chart.size = Vector2(220, 60)
	chart.set_rows([{"label": "Legitimacy", "value": 49.0, "text": "49"},
		{"label": "Church", "value": 50.0, "text": "50"}], 100.0)
	await wait_frames(1)
	assert_eq(BarChart.tally_marks(49.0, 10.0), 4, "49 is four strokes")
	assert_eq(BarChart.tally_marks(50.0, 10.0), 5, "50 is a gate")
	assert_eq(BarChart.tally_marks(0.0, 10.0), 0)

func test_the_seal_shows_who_waits_until_the_council_is_entered() -> void:
	var r := _root()
	var court := _court(r)
	await wait_frames(2)
	var seal := court.council_handle() as WaxSeal
	WaxSeal.heard_tick = -1
	# the opening months are calm: give two ministers a matter — the church
	# and the army below their concern marks — and turn the month
	Game.state.metrics["church_opinion"] = Game.data.bal("concern_church_low") - 5.0
	Game.state.metrics["army_quality"] = Game.data.bal("concern_army_low") - 5.0
	Game.next_tick()
	if not Game.state.pending_event.is_empty():
		Game.apply_event_choice(String(Game.state.pending_event["choices"][0]["choice_id"]))
	var waiting := ConversationBeats.waiting(Game.current_report, Game.state, Game.data)
	gut.p("waiting at tick %d: %s" % [Game.state.tick, waiting])
	assert_false(waiting.is_empty(), "some month brings a minister with a matter")
	seal.refresh()
	assert_eq(seal.waiting_ids(), waiting, "the seal's miniatures are this month's speakers")
	for id in waiting:
		assert_true(Game.state.characters.has(id), "each a living minister")
	seal.pressed.emit()
	seal.refresh()
	assert_eq(seal.waiting_ids().size(), 0, "entering the council hears them")

## Owner 2026-10-01: 指南针被盖住了，往下挪，露出来 — the compass lies in the
## free band below the report's DRAWN foot, as big as that band allows up to
## ui_table_compass_px, wholly on the screen and clear of the paper, the news
## slip and every bookmark — at 1280x720 and at a 16:10 window (1280x800).
func test_the_compass_lies_on_the_table_below_the_report() -> void:
	var was := get_tree().root.size
	for shape: Vector2i in [Vector2i(1280, 720), Vector2i(2560, 1600)]:
		get_tree().root.size = shape
		var r := _root()
		var court := _court(r)
		await wait_frames(4)
		var compass: TableCompass = court.find_child("TableCompass", false, false)
		assert_not_null(compass, "the compass lies on the table")
		var rect := compass.wheel_global_rect()
		var tag := " at %s (design %s)" % [shape, r.size]
		assert_true(Rect2(Vector2.ZERO, r.size).encloses(rect), "wholly on the screen" + tag)
		var col := court.get_node("%LogPanel") as Control
		var paper := Rect2(col.global_position, Vector2(col.size.x, compass.paper_bottom() - col.global_position.y))
		assert_false(rect.intersects(paper), "clear of the report's drawn paper" + tag)
		assert_false(rect.intersects(r.news_ticker().get_global_rect()), "clear of the news slip" + tag)
		for tab: String in BottomBar.TABS:
			var b := r.bottom_bar().button(tab)
			if b != null and b.visible:
				assert_false(rect.intersects(b.get_global_rect()), "clear of the " + tab + " bookmark" + tag)
		if r.size.y >= 799.0:
			assert_gte(rect.size.x, 90.0, "near its full size where the band allows" + tag)
		gut.p("compass %s: %s, paper foot %.0f" % [tag, rect, compass.paper_bottom()])
		r.free()
	get_tree().root.size = was


## The fit itself: as big as the band allows, up to ui_table_compass_px.
func test_the_compass_fits_the_band_below_the_report() -> void:
	var full := Game.data.bal("ui_table_compass_px")
	var clear := Game.data.bal("ui_table_compass_clear_px")
	var wide := TableCompass.fit(640.0, 796.0, ScreenLayout.LEFT_WIDTH)
	assert_eq(wide.size.x, full, "a 16:10 band (~150 px) takes the whole compass")
	assert_gte(wide.position.y, 640.0 + clear)
	var tight := TableCompass.fit(664.0, 716.0, ScreenLayout.LEFT_WIDTH)
	assert_eq(tight.size.x, 716.0 - 664.0 - clear, "a tight band, as large as it allows")
	assert_lte(tight.end.y, 716.0)
	assert_eq(TableCompass.fit(716.0, 716.0, 240.0).size.x, 0.0, "no band, no wheel")


func test_a_tooltip_over_the_paper_keeps_the_chip_light_ink() -> void:
	# Godot resolves a tooltip's label through the HOVERED control's theme,
	# and TooltipLabel falls back to Label — the paper's dark ink drew the
	# town card's icon tooltips dark on their dark chip (owner 2026-10-01).
	var holder := Control.new()
	holder.theme = WarTable.paper_theme()
	var tip := Label.new()
	tip.theme_type_variation = &"TooltipLabel"
	var on_paper := Label.new()
	holder.add_child(tip)
	holder.add_child(on_paper)
	add_child_autofree(holder)
	assert_eq(tip.get_theme_color("font_color", "TooltipLabel"), UiPalette.TEXT_SOFT,
		"a tooltip over the paper reads light on its dark chip")
	assert_ne(on_paper.get_theme_color("font_color"), UiPalette.TEXT_SOFT,
		"the paper's own labels keep their dark ink")
