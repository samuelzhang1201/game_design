extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## RelationshipGraph: loading, shocks, healing drift, display text,
## event op, save round-trip. Hand-computed expectations per convention.

var data: DataRepository
var state: GameState

func before_each() -> void:
	data = SuiteData.repo()
	state = SuiteData.campaign(data, 42)

func test_campaign_starts_with_csv_graph() -> void:
	assert_gt(state.relationships.size(), 0)
	var row: Dictionary = data.relationships.filter(func(r: Dictionary) -> bool:
		return String(r["from_id"]) == "you" and String(r["to_id"]) == "char_queen")[0]
	var e := RelationshipGraph.edge(state, "you", "char_queen")
	assert_eq(String(e["type"]), String(row["rel_type"]))
	assert_eq(float(e["sentiment"]), float(row["sentiment"]))
	assert_eq(float(e["baseline"]), float(row["sentiment"]))
	assert_eq(String(e["log"][0]["reason"]), String(row["reason"]), "the CSV's reason opens the log")

func test_adjust_shocks_clamp_and_log_reason() -> void:
	RelationshipGraph.adjust(state, "you", "char_queen", -25.0, "a forgotten anniversary", 7)
	var e := RelationshipGraph.edge(state, "you", "char_queen")
	# 55 - 25 = 30
	assert_eq(float(e["sentiment"]), 30.0)
	var last: Dictionary = e["log"][e["log"].size() - 1]
	assert_eq(String(last["reason"]), "a forgotten anniversary")
	assert_eq(int(last["tick"]), 7)
	RelationshipGraph.adjust(state, "you", "char_queen", 999.0, "impossible devotion", 8)
	assert_eq(float(RelationshipGraph.edge(state, "you", "char_queen")["sentiment"]), 100.0)

func test_adjust_creates_missing_edge_as_acquaintance() -> void:
	assert_true(RelationshipGraph.edge(state, "char_bard_corvin", "char_king_osric").is_empty())
	RelationshipGraph.adjust(state, "char_bard_corvin", "char_king_osric",
		-10.0, "a mocking ballad travels north", 3)
	var e := RelationshipGraph.edge(state, "char_bard_corvin", "char_king_osric")
	assert_eq(String(e["type"]), "acquaintance")
	assert_eq(float(e["sentiment"]), -10.0)
	assert_eq(float(e["baseline"]), 0.0)

func test_drift_heals_toward_baseline_without_overshoot() -> void:
	# relationship_drift_per_tick = 0.5 (council/balance.csv).
	RelationshipGraph.adjust(state, "you", "char_queen", -25.0, "quarrel", 1)
	var deltas := RelationshipGraph.drift(state, data)
	# 30 -> 30.5, exactly one reported move for this edge.
	assert_eq(float(RelationshipGraph.edge(state, "you", "char_queen")["sentiment"]), 30.5)
	var found := false
	for d in deltas:
		if d["from"] == "you" and d["to"] == "char_queen":
			assert_eq(float(d["delta"]), 0.5)
			found = true
	assert_true(found, "drift reports the move")
	# An edge 0.2 below baseline (35) heals only the remaining gap.
	var e := RelationshipGraph.edge(state, "you", "char_princess")
	e["sentiment"] = 34.8
	RelationshipGraph.drift(state, data)
	assert_almost_eq(float(e["sentiment"]), 35.0, 0.000001)

func test_edges_at_baseline_do_not_drift_or_report() -> void:
	assert_eq(RelationshipGraph.drift(state, data).size(), 0,
		"no edge moves at campaign start")

func test_tick_engine_reports_relationship_deltas() -> void:
	RelationshipGraph.adjust(state, "you", "char_queen", -25.0, "quarrel", 1)
	var r := TickEngine.new(data).advance(state)
	assert_gt(r.relationship_deltas.size(), 0)
	assert_true(r.to_dict().has("relationship_deltas"))

func test_describe_for_orders_by_strength_and_caps() -> void:
	var text := RelationshipGraph.describe_for(state, "you", 2)
	var lines := text.split("\n")
	assert_eq(lines.size(), 2)
	# King Aldric's strongest ties are both with Lord Malvern (+75 incoming
	# liege, +70 outgoing ally) — the story's most-trusted adviser.
	for line in lines:
		assert_string_contains(line, "Malvern")
	var full := RelationshipGraph.describe_for(state, "you")
	assert_string_contains(full, "Victoria")

func test_event_rel_op_applies_shock() -> void:
	var results := EventEffects.apply(
		"rel:char_duke_tomas:you:-15:the duke storms from the hall", state, data)
	assert_eq(results.size(), 1)
	assert_eq(String(results[0]["kind"]), "relationship")
	var e := RelationshipGraph.edge(state, "char_duke_tomas", "you")
	# -45 - 15 = -60
	assert_eq(float(e["sentiment"]), -60.0)
	assert_eq(String(e["log"][e["log"].size() - 1]["reason"]),
		"the duke storms from the hall")

func test_relationships_survive_save_round_trip() -> void:
	RelationshipGraph.adjust(state, "you", "char_queen", -25.0, "quarrel", 5)
	var restored := GameState.from_dict(state.to_dict())
	assert_eq(restored.relationships.size(), state.relationships.size())
	var e := RelationshipGraph.edge(restored, "you", "char_queen")
	# 55 - 25 = 30
	assert_eq(float(e["sentiment"]), 30.0)
	assert_eq(String(e["log"][e["log"].size() - 1]["reason"]), "quarrel")
	var c: Character = restored.characters["char_king_osric"]
	assert_eq(c.category, "foreign")
	assert_eq(c.kingdom, data.resolve_realm("raider_realm"))

func test_pre_roster_save_loads_with_empty_graph() -> void:
	var d := state.to_dict()
	d.erase("relationships")
	var restored := GameState.from_dict(d)
	assert_not_null(restored)
	assert_eq(restored.relationships.size(), 0)
