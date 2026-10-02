extends GutTest
## The left column's default content (user ruling 2026-09-09): the realm at a
## glance — icons with tooltips, and bars and a pie of engine truth.

func _dashboard() -> RealmDashboard:
	var col := VBoxContainer.new()
	add_child_autofree(col)
	return RealmDashboard.attach(col)

func test_shows_the_realm_and_its_resources() -> void:
	Game.start_campaign(42)
	var d := _dashboard()
	await wait_process_frames(1)
	var mine := Game.data.resolve_realm("player_realm")
	assert_eq(d.title_label().text, String(Game.data.kingdoms[mine]["label"]))
	assert_eq(d.resource_text("treasury"), UiPalette.format_int(int(Game.state.metrics["treasury"])))
	assert_eq(d.resource_text("grain"), UiPalette.format_int(int(Game.state.metrics["grain"])))
	assert_ne(d.resource_text("population"), "", "the people are counted")
	assert_ne(d.resource_text("army"), "", "so is the host")

func test_charts_carry_engine_truth() -> void:
	Game.start_campaign(42)
	var d := _dashboard()
	await wait_process_frames(1)
	assert_eq(d.temper_chart().rows.size(), RealmDashboard.TEMPER.size(), "four gauges")
	assert_eq(d.temper_chart().max_value, 100.0)
	# The people and the provinces are the crown's OWN (2026-09-13): the
	# provinces it controls, one at the start; the host is the realm's.
	var own := MapManors.controlled_provinces(Game.data, Game.state)
	var people := 0.0
	for code: String in own:
		for key in ["urban", "rural"]:
			people += float(WorldLedger.value_of(Game.data, Game.state,
				"economy.provinces.%s.%s_population" % [code, key]))
	var realm_rural := float(WorldLedger.value_of(Game.data, Game.state,
		"economy.kingdoms.player_realm.rural_population"))
	assert_eq(d.people_chart().slices.size(), 2, "towns and country")
	assert_almost_eq(d.people_chart().total(), people, 0.5)
	assert_lt(people, realm_rural, "the crown's people are fewer than the realm's")
	assert_eq(d.host_chart().rows.size(), Game.data.world_table("military", "unit_types").size(),
		"one bar per unit type")
	var provs := d.provinces_chart().rows
	assert_eq(provs.size(), mini(own.size(), int(Game.data.bal("dashboard_max_provinces"))))
	for i in provs.size() - 1:
		assert_gte(float(provs[i]["value"]), float(provs[i + 1]["value"]), "largest first")

func test_refreshes_on_state_change() -> void:
	Game.start_campaign(42)
	var d := _dashboard()
	await wait_process_frames(1)
	Game.state.metrics["treasury"] = 999.0
	Game.state_changed.emit()
	assert_eq(d.resource_text("treasury"), "999")

func test_every_shown_resource_and_unit_has_an_icon_with_a_tooltip() -> void:
	Game.start_campaign(42)
	for key in RealmDashboard.RESOURCES + RealmDashboard.TEMPER + TopBar.ORDER \
			+ Game.data.world_table("military", "unit_types").keys():
		var row: Dictionary = Game.data.resource_icons.get(String(key), {})
		assert_false(row.is_empty(), "%s has a resource_icons.csv row" % key)
		assert_ne(String(row["tooltip"]), "", "%s explains itself" % key)
	var icon := ResourceIcon.create("treasury")
	add_child_autofree(icon)
	await wait_process_frames(1)
	assert_eq(icon.glyph(), "coin")
	assert_string_contains(icon.tooltip_text, "Gold")

func test_the_theme_styles_tooltips() -> void:
	var theme := UiPalette.build_theme()
	assert_true(theme.has_stylebox("panel", "TooltipPanel"), "tooltips wear the chip chrome")
	assert_true(theme.has_color("font_color", "TooltipLabel"))

func test_compact_numbers() -> void:
	assert_eq(RealmDashboard._compact(512.0), "512")
	assert_eq(RealmDashboard._compact(4567.0), "4.6k")
	assert_eq(RealmDashboard._compact(45678.0), "46k")
	assert_eq(RealmDashboard._compact(1234567.0), "1.2M")

## Icons, not words (owner 2026-09-13): every temper gauge, host bar and
## people slice carries its dimension key, the charts draw that key's art in
## place of the label, and the label comes back as the row's floating tooltip.
func test_the_cards_dimensions_are_icons_with_tooltips() -> void:
	Game.start_campaign(42)
	var d := _dashboard()
	await wait_process_frames(1)
	for row: Dictionary in d.temper_chart().rows:
		assert_true(RealmDashboard.TEMPER.has(String(row["dimension"])), "a temper key")
	for row: Dictionary in d.host_chart().rows:
		assert_true(Game.data.resource_icons.has(String(row["dimension"])), "a unit key with a row")
	var slices: Array = d.people_chart().slices
	assert_eq(String(slices[0]["dimension"]), "towns")
	assert_eq(String(slices[1]["dimension"]), "country")
	for row: Dictionary in d.provinces_chart().rows:
		assert_false(row.has("dimension"), "a province is a name, not a dimension")
	# The first temper row is unrest: hovering it names it.
	var tip := d.temper_chart()._get_tooltip(Vector2(10.0, BarChart.ROW_H * 0.5))
	assert_true(tip.begins_with("Unrest"), "the tooltip starts with the label: " + tip)
	assert_eq(d.temper_chart()._get_tooltip(Vector2(10.0, BarChart.ROW_H * 40.0)), "", "past the rows")
	var legend := d.people_chart()._get_tooltip(Vector2(PieChart.LEGEND_X + 4.0, 10.0))
	assert_true(legend.begins_with("Towns"), legend)
	assert_eq(d.people_chart()._get_tooltip(Vector2(2.0, 10.0)), "", "the disc has no tooltip")

## Every dimension the interface shows has its art installed, and the icon
## draws it (a missing file would silently fall back to the glyph).
func test_every_dimension_has_its_art() -> void:
	Game.start_campaign(42)
	for key: String in ResourceIconSet.shared().textures:
		assert_true(Game.data.resource_icons.has(key), "%s's art has a resource_icons.csv row" % key)
		assert_not_null(ResourceIcon.texture_of(key), key)
	for key: String in RealmDashboard.RESOURCES + RealmDashboard.TEMPER + ["towns", "country"]:
		assert_true(ResourceIconSet.has_art(key), key + " has its art (assets/2D/icons/resource_icons.tres)")

## Every good the manor card can list has its colour icon installed
## (goods_icons.tres, owner 2026-09-14: every icon on the card is game art).
func test_every_good_has_its_colour_icon() -> void:
	Game.start_campaign(42)
	var icons := GameArt.table(GameArt.GOODS_ICONS)
	assert_false(icons.art.is_empty())
	for good: String in Game.data.world_table("economy", "goods"):
		assert_true(icons.of(good) is Texture2D, "%s's colour icon is installed" % good)
