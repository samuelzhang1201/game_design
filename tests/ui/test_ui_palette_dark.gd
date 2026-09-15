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
		assert_gt(Color(UiPalette.SKILL_COLORS[sk]).get_luminance()
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
