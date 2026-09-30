extends GutTest
## Navigation (owner 2026-09-28, after the UI critique): the bottom bar is
## grouped — the map's lenses and the ruler left, the screens right, a gold
## rule between — and ENTER THE COUNCIL is a level primary button.

func test_the_bottom_bar_groups_lenses_left_and_screens_right() -> void:
	Game.data.balance["ui_nav_grouped"] = 1.0
	var bar := BottomBar.new()
	add_child_autofree(bar)
	await wait_frames(1)
	var row := bar.get_node("Bar/Row")
	var names: Array = []
	for c in row.get_children():
		names.append(String(c.name))
	var rule := names.find("Rule")
	assert_gt(rule, -1, "a rule divides the groups")
	for tab: String in BottomBar.MAP_TABS:
		assert_lt(names.find(String(tab.capitalize())), rule, "%s is a lens, left of the rule" % tab)
	for tab: String in ["REALM", "FAMILIES", "LEDGER"]:
		assert_gt(names.find(String(tab.capitalize())), rule, "%s is a screen, right of it" % tab)
	assert_not_null(bar.button("WAR ROOM"), "the placeholder stays while ui_show_placeholder_tabs is 1")
	assert_gte(BottomBar.BAR_HEIGHT, bar.content_height(), "the grouped strip still fits its height")

## MISSIVE (2026-09-28, rebased onto the grouped bar) is a SCREEN: it stands
## right of the rule, and its unread count still reads on the flat tab and
## keeps the row inside the design viewport.
func test_the_missive_tab_is_a_screen_and_its_badge_fits() -> void:
	Game.data.balance["ui_nav_grouped"] = 1.0
	var bar := BottomBar.new()
	bar.theme = UiPalette.build_theme()
	add_child_autofree(bar)
	await wait_frames(1)
	var row: Control = bar.get_node("Bar/Row")
	var names: Array = []
	for c in row.get_children():
		names.append(String(c.name))
	assert_gt(names.find("Missive"), names.find("Rule"), "MISSIVE is a screen, right of the rule")
	bar.set_badge("MISSIVE", 99)
	await wait_frames(1)
	assert_eq(bar.button("MISSIVE").text, "MISSIVE (99)")
	assert_lte(row.get_combined_minimum_size().x, 1280.0, "the strip with a two-figure badge fits 1280 px")
	bar.set_badge("MISSIVE", 0)
	assert_eq(bar.button("MISSIVE").text, "MISSIVE", "a read board drops the count")

func test_the_council_handle_is_a_level_button() -> void:
	Game.data.balance["ui_council_button"] = 1.0
	var b := ScreenLayout.make_handle("ENTER THE COUNCIL")
	add_child_autofree(b)
	ScreenLayout.place_handle(b, 60.0)
	assert_eq(b.rotation, 0.0, "not turned on its side")
	assert_eq(b.anchor_left, 1.0, "held to the map's right edge")
	assert_gt(b.offset_top, 60.0, "below the top bar")
