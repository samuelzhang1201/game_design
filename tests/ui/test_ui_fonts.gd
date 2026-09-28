extends GutTest
## The faces are data (data/ui_fonts.csv, picked by balance ui_font_scheme;
## owner 2026-09-28, after the UI critique): every scheme names every role,
## every file it names ships, and the chosen scheme resolves to real fonts.

const ROLES := ["title", "header", "body", "body_bold", "body_italic", "tab", "display"]

func test_every_scheme_names_every_role_and_its_file_ships() -> void:
	var schemes := {}
	for key: String in Game.data.ui_fonts:
		schemes[key.split(":")[0]] = true
	assert_true(schemes.has("0"), "scheme 0 restates the fallback set")
	for scheme: String in schemes:
		for role: String in ROLES:
			var row: Dictionary = Game.data.ui_fonts.get("%s:%s" % [scheme, role], {})
			assert_false(row.is_empty(), "scheme %s names a %s face" % [scheme, role])
			if not row.is_empty():
				assert_true(FileAccess.file_exists(UiPalette.FONT_DIR + String(row["path"])),
					"scheme %s %s: %s ships" % [scheme, role, row["path"]])

func test_the_chosen_scheme_resolves_every_role() -> void:
	assert_true(Game.data.balance.has("ui_font_scheme"))
	for role: String in ROLES:
		assert_not_null(UiPalette.role_font(role), "%s resolves to a font" % role)

## Blackletter reads a size small and its capitals in a row cannot be read, so
## a title set in it is scaled up and set in title case.
func test_the_title_is_scaled_and_title_cased() -> void:
	var label := Label.new()
	label.text = "COUNCIL IN RECESS"
	UiPalette.style_title(label, 20)
	assert_eq(label.text, "Council in Recess")
	assert_eq(label.get_theme_font_size("font_size"), 24)
	label.free()
