extends GutTest
## Navigation (owner 2026-09-28, after the UI critique): the bottom bar is
## grouped — the map's lenses and the ruler left, the screens right, a gold
## rule between — and ENTER THE COUNCIL is a level primary button.

const KEYS := ["ui_nav_grouped", "ui_council_button"]
var _kept := {}


func before_each() -> void:
	_kept = {}
	for key: String in KEYS:
		_kept[key] = Game.data.balance.get(key)


## Every later file reads the balance as the data has it.
func after_each() -> void:
	for key: String in _kept:
		if _kept[key] == null:
			Game.data.balance.erase(key)
		else:
			Game.data.balance[key] = _kept[key]


func test_the_bottom_bar_groups_lenses_left_and_screens_right() -> void:
	Game.data.balance["ui_nav_grouped"] = 1.0
	var bar: BottomBar = load("res://scenes/hud/bottom_bar.tscn").instantiate()
	bar.theme = UiPalette.build_theme()
	add_child_autofree(bar)
	await wait_process_frames(1)
	var row := bar.get_node("Bar/Row")
	var names: Array = []
	for c in row.get_children():
		names.append(String(c.name))
	var rule := names.find("Rule")
	assert_gt(rule, -1, "a rule divides the groups")
	for tab: String in BottomBar.MAP_TABS:
		assert_lt(names.find(String(tab.capitalize())), rule, "%s is a lens, left of the rule" % tab)
	for tab: String in ["FAMILIES", "MISSIVE", "WAR ROOM", "LEDGER"]:
		assert_gt(names.find(String(tab.capitalize())), rule, "%s is a screen, right of it" % tab)
	assert_not_null(bar.button("WAR ROOM"), "the WAR ROOM tab is on the bar")
	# BAR_HEIGHT is a constant NewsTicker and ScreenLayout place themselves
	# off: it must cover the buttons (it broke once when the design viewport
	# doubled and the tabs fell off the bottom of the screen).
	assert_gt(bar.content_height(), 0.0, "the strip measured itself")
	assert_gte(BottomBar.BAR_HEIGHT, bar.content_height(), "the grouped strip still fits its height")

## MISSIVE (2026-09-28, rebased onto the grouped bar) is a SCREEN: it stands
## right of the rule, and its unread count still reads on the flat tab and
## keeps the row inside the design viewport.
func test_the_missive_tab_is_a_screen_and_its_badge_fits() -> void:
	Game.data.balance["ui_nav_grouped"] = 1.0
	var bar: BottomBar = load("res://scenes/hud/bottom_bar.tscn").instantiate()
	bar.theme = UiPalette.build_theme()
	add_child_autofree(bar)
	await wait_process_frames(1)
	var row: Control = bar.get_node("Bar/Row")
	var names: Array = []
	for c in row.get_children():
		names.append(String(c.name))
	assert_gt(names.find("Missive"), names.find("Rule"), "MISSIVE is a screen, right of the rule")
	bar.set_badge("MISSIVE", 99)
	await wait_process_frames(1)
	assert_eq(bar.button("MISSIVE").text, "MISSIVE (99)")
	assert_lte(row.get_combined_minimum_size().x, 1280.0, "the strip with a two-figure badge fits 1280 px")
	bar.set_badge("MISSIVE", 0)
	assert_eq(bar.button("MISSIVE").text, "MISSIVE", "a read board drops the count")

func test_the_council_handle_is_a_level_button() -> void:
	Game.data.balance["ui_council_button"] = 1.0
	var b := ScreenLayout.make_handle("ENTER THE COUNCIL")
	add_child_autofree(b)
	ScreenLayout.place_handle(b, 60.0)
	assert_gt(b.offset_top, 60.0, "below the top bar")
