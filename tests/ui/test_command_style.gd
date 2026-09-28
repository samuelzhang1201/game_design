extends GutTest
## A command is small capitals in title case whatever case it was written in
## (owner 2026-09-28, second critique: "Start Game", "ASK THE COUNCIL" and
## "Wave them on" were three rules on one screen).

func test_command_text_is_title_case_from_any_case() -> void:
	assert_eq(UiPalette.command_text("ASK THE COUNCIL"), "Ask the Council")
	assert_eq(UiPalette.command_text("Wave them on"), "Wave Them On")
	assert_eq(UiPalette.command_text("Send a spy"), "Send a Spy")
	assert_eq(UiPalette.command_text("CLOSE"), "Close")

func test_figures_are_grouped_and_units_left_alone() -> void:
	assert_eq(UiPalette.command_text("BUY — 3508 gold"), "Buy — 3,508 Gold")
	assert_eq(UiPalette.command_text("WORK GRAIN FIELDS — 20g"), "Work Grain Fields — 20g")

func test_a_command_button_wears_the_tab_face() -> void:
	var b := Button.new()
	add_child_autofree(b)
	b.text = "LEAVE THE COUNCIL"
	UiPalette.command_button(b, 14)
	assert_eq(b.text, "Leave the Council")
	assert_eq(b.get_theme_font("font"), UiPalette.tab_font())
	assert_eq(b.get_theme_font_size("font_size"), 14)
