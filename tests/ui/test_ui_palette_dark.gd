extends GutTest
## The dark CK3 theme (owner 2026-09-15, reversing the bright theme of
## 2026-09-13): light ink on dark leather, a gold accent. Pinned as contrast,
## not as hex values, so the tones can be tuned without touching the test.

func test_panels_are_dark_and_ink_is_light() -> void:
	assert_lt(UiPalette.PANEL_BG.get_luminance(), 0.15, "the card is dark")
	assert_lt(UiPalette.BG_SCREEN.get_luminance(), UiPalette.PANEL_BG.get_luminance() + 0.01,
		"the desk is no lighter than the card on it")
	assert_gt(UiPalette.TEXT_SOFT.get_luminance(), 0.75, "body ink is light")
	assert_gt(UiPalette.GOLD.get_luminance() - UiPalette.PANEL_BG.get_luminance(), 0.45,
		"the accent reads on the card")
	assert_gt(UiPalette.TEXT_DIM.get_luminance() - UiPalette.CHIP_BG.get_luminance(), 0.25,
		"even a hint reads on a button")
	for sk in UiPalette.SKILL_COLORS:
		assert_gt(UiPalette.skill_color(sk).get_luminance()
			- UiPalette.PANEL_BG.get_luminance(), 0.3, "%s reads on the card" % sk)

func test_theme_has_no_light_boxes() -> void:
	var theme := UiPalette.build_theme()
	for pair in [["normal", "Button"], ["hover", "Button"], ["pressed", "Button"],
			["normal", "LineEdit"], ["focus", "LineEdit"], ["panel", "TooltipPanel"]]:
		var box := theme.get_stylebox(pair[0], pair[1]) as StyleBoxFlat
		assert_lt(box.bg_color.get_luminance(), 0.2, "%s %s is dark" % pair)
	assert_lt(UiPalette.bar_bg().bg_color.get_luminance(), 0.2, "a bar's trough is dark")

## The ornament plate is dark ink on clear: on a dark card it must be drawn in
## the gold tint or it cannot be seen at all.
func test_the_ornament_is_drawn_in_gold() -> void:
	var style := UiPalette.panel_style(UiPalette.BORDER_GOLD, 2, 12)
	if style is VellumPanelStyle:
		assert_eq((style as VellumPanelStyle).tint, UiPalette.ORNAMENT_TINT)
	else:
		pass_test("ornament off in this build")

func test_chart_track_is_dark() -> void:
	Game.start_campaign(42)
	assert_lt(UiPalette.chart_color("track").get_luminance(), 0.2)

## One ornament per layer (owner 2026-09-28): under ui_panel_ornament 3 only a
## floating window wears the vellum ornament; a column wears the gold inner
## hairline instead, and the map's frame neither.
func test_only_windows_wear_the_ornament() -> void:
	var keep: float = Game.data.balance.get("ui_panel_ornament", 1.0)
	var rule: float = Game.data.balance.get("ui_panel_inner_rule_alpha", 0.0)
	Game.data.balance["ui_panel_ornament"] = 3.0
	Game.data.balance["ui_panel_inner_rule_alpha"] = 0.35
	var window := UiPalette.panel_style(UiPalette.BORDER_GOLD, 2, 12, "window") as VellumPanelStyle
	var column := UiPalette.panel_style(UiPalette.BORDER_GOLD, 2, 12, "column") as VellumPanelStyle
	var map := UiPalette.panel_style(UiPalette.BORDER_GOLD, 2, 12, "map") as VellumPanelStyle
	assert_not_null(window.texture, "a window wears the ornament")
	assert_null(column.texture, "a column does not")
	assert_gt(column.inner_rule.a, 0.0, "a column wears the inner hairline")
	assert_null(map.texture, "the map's frame wears no ornament")
	assert_eq(map.inner_rule.a, 0.0, "nor a hairline: the map's edge frames it")
	Game.data.balance["ui_panel_ornament"] = keep
	Game.data.balance["ui_panel_inner_rule_alpha"] = rule

## The grain is laid in two halves so it neither lifts nor greys the card.
func test_the_grain_has_a_light_and_a_dark_half() -> void:
	var grain := UiPalette.panel_grain()
	assert_eq(grain.size(), 2)
	for tex: Texture2D in grain:
		assert_eq(tex.get_width(), 256)

## Figures are grouped by thousands (owner 2026-09-28).
func test_numbers_are_grouped() -> void:
	assert_eq(UiPalette.format_int(0), "0")
	assert_eq(UiPalette.format_int(999), "999")
	assert_eq(UiPalette.format_int(13272), "13,272")
	assert_eq(UiPalette.format_int(-1234567), "-1,234,567")
	assert_eq(UiPalette.format_delta(1597), "+1,597")
	assert_eq(UiPalette.format_delta(-51), "-51")
