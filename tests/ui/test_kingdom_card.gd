extends GutTest

func _card() -> KingdomCard:
	var c: KingdomCard = load("res://scenes/kingdom_card.tscn").instantiate()
	add_child_autofree(c)
	return c

func test_values_mode_lists_metrics_and_date() -> void:
	Game.start_campaign(42)
	var c := _card()
	c.show_values(Game.state)
	await wait_frames(1)
	var texts := _all_label_text(c)
	assert_string_contains(texts, "Gold")
	assert_string_contains(texts, "Grain")
	assert_string_contains(texts, "Year 1")

func test_changes_mode_shows_arrows_for_changed_metrics() -> void:
	Game.start_campaign(42)
	var c := _card()
	var deltas := [{"metric": "treasury", "delta": 19.0, "reason": "taxes collected"}]
	Game.state.metrics["treasury"] = 538.0
	c.show_changes(Game.state, deltas)
	await wait_frames(1)
	var texts := _all_label_text(c)
	assert_string_contains(texts, "→ 538")
	assert_string_contains(texts, "(+19)")

func _all_label_text(root: Node) -> String:
	var out := ""
	for child in root.find_children("*", "Label", true, false):
		out += child.text + "\n"
	return out
