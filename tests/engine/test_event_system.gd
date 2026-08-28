extends GutTest

var data: DataRepository
var s: GameState
var es: EventSystem

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	# Synthetic pool: deterministic, independent of the real content task.
	data.events = [
		{"event_id": "ev_a", "category": "folk", "trigger": "always", "weight": "1",
			"cooldown_ticks": "4", "once": "0", "voice": "template", "title_key": "event_ev_a"},
		{"event_id": "ev_once", "category": "folk", "trigger": "always", "weight": "1",
			"cooldown_ticks": "0", "once": "1", "voice": "template", "title_key": "event_ev_once"},
		{"event_id": "ev_gated", "category": "realm", "trigger": "grain<5", "weight": "99",
			"cooldown_ticks": "0", "once": "0", "voice": "template", "title_key": "event_ev_gated"},
	]
	data.events_by_id = {}
	for row in data.events:
		data.events_by_id[row["event_id"]] = row
	data.event_choices = [
		{"event_id": "ev_a", "choice_id": "accept", "label": "Accept the geese",
			"centralism": "0", "militarism": "0", "orthodoxy": "0",
			"tax_incidence": "20", "expansionism": "0",
			"effects": "metric:peasant_contentment:2", "requires": ""},
		{"event_id": "ev_a", "choice_id": "refuse", "label": "Refuse",
			"centralism": "0", "militarism": "0", "orthodoxy": "0",
			"tax_incidence": "0", "expansionism": "0",
			"effects": "metric:peasant_contentment:-2", "requires": ""},
		{"event_id": "ev_once", "choice_id": "ok", "label": "So be it",
			"centralism": "0", "militarism": "0", "orthodoxy": "0",
			"tax_incidence": "0", "expansionism": "0", "effects": "flag:seen_once",
			"requires": ""},
		{"event_id": "ev_gated", "choice_id": "ok", "label": "Endure",
			"centralism": "0", "militarism": "0", "orthodoxy": "0",
			"tax_incidence": "0", "expansionism": "0", "effects": "", "requires": ""},
	]
	s = GameState.new_campaign(data, 42)
	s.tick = 1
	es = EventSystem.new(data)

func test_pity_forces_event_within_window() -> void:
	var fired := 0
	for i in 30:
		s.tick += 1
		var ev := es.roll(s)
		if not ev.is_empty():
			fired += 1
			es.apply_choice(String(ev["choices"][0]["choice_id"]), s)
	assert_gt(fired, 3)  # 35% + pity 6 over 30 ticks fires several times

func test_trigger_gates_eligibility() -> void:
	# grain healthy: ev_gated (weight 99) must never fire
	for i in 40:
		s.tick += 1
		var ev := es.roll(s)
		if not ev.is_empty():
			assert_ne(String(ev["event_id"]), "ev_gated")
			es.apply_choice(String(ev["choices"][0]["choice_id"]), s)

func test_once_fires_at_most_once() -> void:
	var seen := 0
	for i in 60:
		s.tick += 1
		var ev := es.roll(s)
		if not ev.is_empty():
			if String(ev["event_id"]) == "ev_once":
				seen += 1
			es.apply_choice(String(ev["choices"][0]["choice_id"]), s)
	assert_lte(seen, 1)

func test_apply_choice_runs_effects_and_signature_drift() -> void:
	s.pending_event = {}
	var ev := es._fire("ev_a", s)
	var pc0: float = s.metrics["peasant_contentment"]
	var out := es.apply_choice("accept", s)
	assert_eq(s.metrics["peasant_contentment"], pc0 + 2.0)
	assert_eq(String(out["choice_id"]), "accept")
	assert_true(s.pending_event.is_empty())
	# tax_incidence +20 signature drifts seated ministers (e.g. Mirella -40 axis)
	assert_gt(out["drift"].size(), 0)

## FIX 2(a): a resolved choice's metric effects must carry a human reason
## (the choice's own label) so council_screen can narrate them — see
## council_screen._finish_event / _narrate_effects.
func test_apply_choice_metric_effect_carries_choice_label_as_reason() -> void:
	s.pending_event = {}
	es._fire("ev_a", s)
	var out := es.apply_choice("accept", s)
	var found := false
	for e in out["effects"]:
		if String(e.get("kind", "")) == "metric":
			found = true
			assert_eq(String(e.get("reason", "")), "Accept the geese")
	assert_true(found, "ev_a accept has a metric effect to check")

func test_scheduled_event_fires_regardless_of_roll() -> void:
	EventEffects.apply("schedule:ev_once:2", s, data)
	s.tick += 1
	assert_true(es.roll(s).is_empty() or true)  # may or may not fire random event
	s.pending_event = {}
	s.tick += 2
	var ev := es.roll(s)
	assert_eq(String(ev.get("event_id", "")), "ev_once")

func test_pending_event_round_trip() -> void:
	es._fire("ev_a", s)
	var s2 := GameState.from_dict(s.to_dict())
	assert_eq(SaveLoad.state_hash(s2), SaveLoad.state_hash(s))
	assert_eq(String(s2.pending_event.get("event_id", "")), "ev_a")

func test_reload_with_pending_event_is_bit_identical() -> void:
	# Force an event, save/load, then resolve on both independently: both should diverge identically
	es._fire("ev_a", s)
	var s_hash_before_save := SaveLoad.state_hash(s)
	SaveLoad.save_game(s, "user://ev_test.json")
	var loaded := SaveLoad.load_game("user://ev_test.json")

	# (i) Hash is preserved through save/load
	assert_eq(SaveLoad.state_hash(loaded), s_hash_before_save)

	# (ii) pending_event matches exactly
	assert_eq(loaded.pending_event, s.pending_event)

	# (iii) Resolve independently on both; hashes diverge by the same effects
	var s_es := EventSystem.new(data)
	var loaded_es := EventSystem.new(data)
	var outcome_s := s_es.apply_choice("accept", s)
	var outcome_loaded := loaded_es.apply_choice("accept", loaded)
	assert_eq(SaveLoad.state_hash(s), SaveLoad.state_hash(loaded))

	# (iv) One subsequent roll on each (same tick) yields same result
	s.tick += 1
	loaded.tick += 1
	var roll_s := s_es.roll(s)
	var roll_loaded := loaded_es.roll(loaded)
	# Both should be empty or both should have the same event_id (deterministic via pity/weights)
	if roll_s.is_empty() and roll_loaded.is_empty():
		pass  # both empty: OK
	else:
		assert_eq(String(roll_s.get("event_id", "")), String(roll_loaded.get("event_id", "")))

func test_no_eligible_choices_returns_empty() -> void:
	# Add an event with no eligible choices (requires unfilled seat)
	var ev_no_choice := {
		"event_id": "ev_no_choice", "category": "folk", "trigger": "always", "weight": "1",
		"cooldown_ticks": "0", "once": "0", "voice": "template", "title_key": "event_none"
	}
	data.events.append(ev_no_choice)
	data.events_by_id["ev_no_choice"] = ev_no_choice
	data.event_choices.append({
		"event_id": "ev_no_choice", "choice_id": "gated_choice", "label": "Gated",
		"centralism": "0", "militarism": "0", "orthodoxy": "0",
		"tax_incidence": "0", "expansionism": "0", "effects": "", "requires": "seat_filled=admiral"
	})

	# Try to fire this event; should return {} and leave state unchanged
	var pity_before := int(s.event_state["pity"])
	var cooldowns_before: Dictionary = s.event_state["cooldowns"].duplicate(true)
	var once_before: Array = s.event_state["once"].duplicate(true)
	var pending_before: Dictionary = s.pending_event.duplicate(true)

	var result := es._fire("ev_no_choice", s)

	# Should return empty dict
	assert_true(result.is_empty())
	# State should be unchanged
	assert_eq(int(s.event_state["pity"]), pity_before)
	assert_eq(s.event_state["cooldowns"], cooldowns_before)
	assert_eq(s.event_state["once"], once_before)
	assert_eq(s.pending_event, pending_before)
