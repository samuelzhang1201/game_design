extends GutTest
## Directed speaker->listener trust (spec §4.3). Derived from relationships at
## campaign start, then moved only by the reckoning, so it stays auditable.

var data: DataRepository
var state: GameState

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	state = GameState.new_campaign(data, 42)

func test_trust_is_derived_from_how_the_listener_feels_about_the_speaker() -> void:
	# Malvern feels +75 toward the king (liege), so he trusts the king's word:
	# 50 + 75/2 = 87.5
	assert_almost_eq(SourceTrust.get_trust(data, state, "you", "char_lord_malvern"),
		87.5, 0.001)
	# Duke Tomas feels -45 toward the king: 50 + (-45)/2 = 27.5
	assert_almost_eq(SourceTrust.get_trust(data, state, "you", "char_duke_tomas"),
		27.5, 0.001)

func test_trust_is_directional() -> void:
	# The king's own feeling toward Tomas (-35) governs the other direction:
	# 50 + (-35)/2 = 32.5
	assert_almost_eq(SourceTrust.get_trust(data, state, "char_duke_tomas", "you"),
		32.5, 0.001)

func test_pair_with_no_edge_uses_the_default() -> void:
	assert_almost_eq(SourceTrust.get_trust(data, state, "you", "char_bard_corvin"),
		50.0, 0.001)

func test_adjust_clamps_and_logs_a_reason() -> void:
	SourceTrust.adjust(data, state, "you", "char_lord_malvern", -25.0, "caught in a lie", 7)
	assert_almost_eq(SourceTrust.get_trust(data, state, "you", "char_lord_malvern"),
		62.5, 0.001)
	var entry: Dictionary = state.source_trust[SourceTrust.key("you", "char_lord_malvern")]
	var last: Dictionary = entry["log"][entry["log"].size() - 1]
	assert_eq(String(last["reason"]), "caught in a lie")
	assert_eq(int(last["tick"]), 7)
	SourceTrust.adjust(data, state, "you", "char_lord_malvern", -999.0, "utter ruin", 8)
	assert_almost_eq(SourceTrust.get_trust(data, state, "you", "char_lord_malvern"),
		0.0, 0.001)

func test_adjust_on_an_underived_pair_starts_from_default() -> void:
	SourceTrust.adjust(data, state, "you", "char_bard_corvin", 10.0, "a kindness", 3)
	assert_almost_eq(SourceTrust.get_trust(data, state, "you", "char_bard_corvin"),
		60.0, 0.001)

func test_trust_survives_save_round_trip() -> void:
	SourceTrust.adjust(data, state, "you", "char_lord_malvern", -25.0, "caught in a lie", 7)
	var restored := GameState.from_dict(state.to_dict())
	assert_almost_eq(SourceTrust.get_trust(data, restored, "you", "char_lord_malvern"),
		62.5, 0.001)

func test_pre_feature_save_falls_back_to_derivation() -> void:
	var d := state.to_dict()
	d.erase("source_trust")
	var restored := GameState.from_dict(d)
	assert_not_null(restored)
	assert_almost_eq(SourceTrust.get_trust(data, restored, "you", "char_lord_malvern"),
		87.5, 0.001, "derivation still works from relationships alone")
