extends GutTest
## The faces are resources (owner 2026-10-02): one FontVariation per role in
## assets/fonts/roles/, edited in the editor; data/screens/ui/ui_fonts.csv keeps each
## role's size_scale and title_case.

const ROLES := ["title", "header", "body", "body_bold", "body_italic", "tab", "display", "figures"]

func test_every_role_has_its_face_and_its_row() -> void:
	for role: String in ROLES:
		var path := UiPalette.ROLE_FONT_DIR + role + ".tres"
		assert_true(ResourceLoader.exists(path), "%s's face ships: %s" % [role, path])
		assert_true(load(path) is FontVariation, role + " is a FontVariation")
		assert_false(Game.data.ui_fonts.get(role, {}).is_empty(), role + " has a ui_fonts.csv row")
		assert_not_null(UiPalette.role_font(role), "%s resolves to a font" % role)

## The theme the game and the editor share names the body face as its default.
func test_the_theme_is_the_saved_one() -> void:
	var theme := UiPalette.build_theme()
	assert_eq(theme.resource_path, UiPalette.THEME_PATH)
	assert_eq(theme.default_font, UiPalette.role_font("body"))
	assert_eq(ProjectSettings.get_setting("gui/theme/custom", ""), UiPalette.THEME_PATH,
		"the project theme, so the editor draws scenes in it")
	for kind: String in ["HeaderLabel", "TitleLabel", "SectionLabel"]:
		assert_true(theme.is_type_variation(kind, "Label"), kind)

## Blackletter reads a size small and its capitals in a row cannot be read, so
## a title set in it is scaled up and set in title case.
func test_the_title_is_scaled_and_title_cased() -> void:
	var label := Label.new()
	label.text = "COUNCIL IN RECESS"
	UiPalette.style_title(label, 20)
	assert_eq(label.text, "Council in Recess")
	assert_gt(label.get_theme_font_size("font_size"), 20, "scaled up from the size asked")
	label.free()
