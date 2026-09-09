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
	await wait_frames(1)
	var mine := Game.data.resolve_realm("player_realm")
	assert_eq(d.title_label().text, String(Game.data.kingdoms[mine]["label"]))
	assert_eq(d.resource_text("treasury"), str(int(Game.state.metrics["treasury"])))
	assert_eq(d.resource_text("grain"), str(int(Game.state.metrics["grain"])))
	assert_ne(d.resource_text("population"), "", "the people are counted")
	assert_ne(d.resource_text("army"), "", "so is the host")

func test_charts_carry_engine_truth() -> void:
	Game.start_campaign(42)
	var d := _dashboard()
	await wait_frames(1)
	assert_eq(d.temper_chart().rows.size(), RealmDashboard.TEMPER.size(), "four gauges")
	assert_eq(d.temper_chart().max_value, 100.0)
	var urban := float(WorldLedger.value_of(Game.data, Game.state,
		"economy.kingdoms.player_realm.urban_population"))
	var rural := float(WorldLedger.value_of(Game.data, Game.state,
		"economy.kingdoms.player_realm.rural_population"))
	assert_eq(d.people_chart().slices.size(), 2, "towns and country")
	assert_almost_eq(d.people_chart().total(), urban + rural, 0.5)
	assert_eq(d.host_chart().rows.size(), Game.data.world_table("military", "unit_types").size(),
		"one bar per unit type")
	var provs := d.provinces_chart().rows
	assert_eq(provs.size(), int(Game.data.bal("dashboard_max_provinces")))
	for i in provs.size() - 1:
		assert_gte(float(provs[i]["value"]), float(provs[i + 1]["value"]), "largest first")

func test_refreshes_on_state_change() -> void:
	Game.start_campaign(42)
	var d := _dashboard()
	await wait_frames(1)
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
	await wait_frames(1)
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
