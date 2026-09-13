extends GutTest
## The world ledger (spec 2026-09-09 §2): one addressable schema over the
## player's metrics, the court's opinions and attributes, and the pack's
## domain tables; every write clamped, reasoned, and logged.

var data: DataRepository
var state: GameState

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	state = GameState.new_campaign(data, 42)

func _player() -> String:
	return data.resolve_realm("player_realm")

func _other_kingdom() -> String:
	for code: String in data.kingdoms:
		if code != _player():
			return code
	return ""

func test_slots_resolve_to_the_bound_kingdom() -> void:
	assert_eq(WorldLedger.resolve(data, "economy.kingdoms.player_realm.treasury"),
		"economy.kingdoms.%s.treasury" % _player())
	assert_eq(WorldLedger.resolve(data, "metrics.grain"), "metrics.grain", "no slot, no change")

func test_the_most_specific_schema_row_wins() -> void:
	var mine := WorldLedger.schema_for(data, "economy.kingdoms.player_realm.treasury")
	assert_eq(String(mine["alias_to"]), "metrics.treasury", "the player's row aliases the metric")
	var theirs := WorldLedger.schema_for(data, "economy.kingdoms.%s.treasury" % _other_kingdom())
	assert_eq(String(theirs["alias_to"]), "", "a foreign treasury is its own field")
	assert_true(WorldLedger.schema_for(data, "no.such.path.here").is_empty())

func test_reads_fall_through_from_override_to_pack() -> void:
	var row: Dictionary = data.world_row("military", "kingdoms", _player())
	var path := "military.kingdoms.player_realm.infantry"
	assert_eq(int(WorldLedger.value_of(data, state, path)), int(row["infantry"]), "pack value")
	var out := WorldLedger.apply(data, state, path, -100.0, "a skirmish", "test")
	assert_false(out.has("error"), str(out))
	assert_eq(int(WorldLedger.value_of(data, state, path)), int(row["infantry"]) - 100, "override")
	assert_eq(state.world.size(), 1, "only the moved field is stored")
	assert_eq(String(state.world_log[0]["reason"]), "a skirmish")
	assert_eq(String(state.world_log[0]["source"]), "test")

func test_alias_reads_and_writes_the_metric() -> void:
	state.metrics["treasury"] = 300.0
	assert_eq(float(WorldLedger.value_of(data, state, "economy.kingdoms.player_realm.treasury")), 300.0)
	var out := WorldLedger.apply(data, state, "economy.kingdoms.player_realm.treasury", -40.0,
		"surveyors", "test")
	assert_eq(float(out["delta"]), -40.0)
	assert_eq(state.metrics["treasury"], 260.0, "the metric moved")
	assert_false(state.world.has("economy.kingdoms.%s.treasury" % _player()), "no shadow copy")
	# Scaled alias: poll_tax is the tax rate divided by the balance factor.
	state.metrics["tax_rate"] = 6.0
	assert_almost_eq(float(WorldLedger.value_of(data, state, "economy.kingdoms.player_realm.poll_tax")),
		6.0 / data.bal("tax_rate_per_poll_tax"), 0.0001)

func test_writes_clamp_to_the_schema_range() -> void:
	state.metrics["unrest"] = 98.0
	var out := WorldLedger.apply(data, state, "metrics.unrest", 10.0, "riots", "test")
	assert_eq(float(out["delta"]), 2.0, "clamped to the max")
	assert_eq(state.metrics["unrest"], 100.0)

func test_unlisted_path_and_empty_reason_are_refused() -> void:
	assert_true(WorldLedger.apply(data, state, "metrics.no_such", 1.0, "why", "test").has("error"))
	assert_true(WorldLedger.apply(data, state, "metrics.grain", 1.0, "  ", "test").has("error"))
	assert_true(WorldLedger.apply(data, state, "political.diplomacy.a>b.stance", 1.0, "why",
		"test").has("error"), "an enum is not numeric")
	assert_true(state.world_log.is_empty(), "nothing refused is logged")

func test_opinion_and_attribute_paths_go_through_the_character_logs() -> void:
	var before: int = state.characters["char_marshal"].opinion
	WorldLedger.apply(data, state, "opinion.char_marshal", 2.0, "a kind word", "test")
	var c: Character = state.characters["char_marshal"]
	assert_eq(c.opinion, before + 2)
	assert_eq(String(c.opinion_log[-1]["reason"]), "a kind word")
	var you: Character = state.characters["you"]
	var p: int = you.attributes["prestige"]
	WorldLedger.apply(data, state, "attribute.you.prestige", -1.0, "a slight", "test")
	assert_eq(int(you.attributes["prestige"]), p - 1)
	assert_eq(String(you.attribute_log[-1]["reason"]), "a slight")

func test_set_enum_accepts_only_listed_values() -> void:
	var path := "political.diplomacy.player_realm>%s.stance" % _other_kingdom()
	assert_true(WorldLedger.set_enum(data, state, path, "Dragon", "why", "test").has("error"))
	var out := WorldLedger.set_enum(data, state, path, "Enemy", "a border raid", "test")
	assert_false(out.has("error"), str(out))
	assert_eq(String(WorldLedger.value_of(data, state, path)), "Enemy")

func test_polarity_and_caps_read_from_the_schema() -> void:
	assert_eq(WorldLedger.polarity_of(data, "metrics.unrest"), -1)
	assert_eq(WorldLedger.polarity_of(data, "metrics.treasury"), 1)
	assert_eq(WorldLedger.polarity_of(data, "metrics.tax_rate"), 0)
	assert_eq(WorldLedger.llm_cap(data, "opinion.char_marshal"), data.bal("tone_delta_cap"))
	assert_eq(WorldLedger.llm_cap(data, "metrics.tax_rate"), 0.0, "engine-only")

## The crown's economy is the provinces it CONTROLS (owner 2026-09-13):
## the capital's at the start, not the kingdom's; the host stays the realm's.
func test_only_the_crowns_own_land_belongs_to_them() -> void:
	assert_true(WorldLedger.belongs_to_player(data, state, "metrics.grain"))
	assert_false(WorldLedger.belongs_to_player(data, state,
		"economy.kingdoms.player_realm.rural_population"), "the kingdom's people are not the crown's")
	assert_true(WorldLedger.belongs_to_player(data, state,
		"military.kingdoms.player_realm.infantry"), "the host is the realm's")
	var mine := MapManors.controlled_provinces(data, state)
	assert_eq(mine.size(), 1, "the capital's province alone at the start")
	assert_true(WorldLedger.belongs_to_player(data, state,
		"economy.provinces.%s.rural_population" % mine[0]))
	for code: String in MapOwnership.provinces_of(data, state, _player()):
		if code != mine[0]:
			assert_false(WorldLedger.belongs_to_player(data, state,
				"economy.provinces.%s.rural_population" % code), "another house's province")
			break
	var foreign := ""
	for code: String in data.provinces:
		if String(data.provinces[code]["kingdom_code"]) != _player():
			foreign = code
			break
	assert_false(WorldLedger.belongs_to_player(data, state,
		"economy.provinces.%s.rural_population" % foreign))
	assert_false(WorldLedger.belongs_to_player(data, state,
		"economy.kingdoms.raider_realm.rural_population"))

func test_overrides_survive_a_save_round_trip() -> void:
	WorldLedger.apply(data, state, "military.kingdoms.player_realm.cavalry", -50.0, "lost horses",
		"test")
	var back := GameState.from_dict(state.to_dict())
	assert_eq(int(WorldLedger.value_of(data, back, "military.kingdoms.player_realm.cavalry")),
		int(WorldLedger.value_of(data, state, "military.kingdoms.player_realm.cavalry")))
	assert_eq(back.world_log.size(), 1)

func test_prompt_catalog_lists_writable_fields_with_caps() -> void:
	var cat := WorldLedger.prompt_catalog(data, state)
	assert_string_contains(cat, "metrics.grain")
	assert_string_contains(cat, "economy.kingdoms.player_realm.rural_population")
	assert_string_contains(cat, "cap")
	assert_false(cat.contains("metrics.tax_rate"), "engine-only fields are not offered")
	assert_string_contains(cat, "Your provinces:")
