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
	for tab: String in ["REALM", "FAMILIES", "RELATIONSHIP"]:
		assert_gt(names.find(String(tab.capitalize())), rule, "%s is a screen, right of it" % tab)
	assert_not_null(bar.button("WAR ROOM"), "the placeholder stays while ui_show_placeholder_tabs is 1")
	assert_gte(BottomBar.BAR_HEIGHT, bar.content_height(), "the grouped strip still fits its height")

func test_the_council_handle_is_a_level_button() -> void:
	Game.data.balance["ui_council_button"] = 1.0
	var b := ScreenLayout.make_handle("ENTER THE COUNCIL")
	add_child_autofree(b)
	ScreenLayout.place_handle(b, 60.0)
	assert_eq(b.rotation, 0.0, "not turned on its side")
	assert_eq(b.anchor_left, 1.0, "held to the map's right edge")
	assert_gt(b.offset_top, 60.0, "below the top bar")
