extends GutTest

var data: DataRepository
var engine: TickEngine
var s: GameState

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	engine = TickEngine.new(data)
	s = GameState.new_campaign(data, 42)
	engine.advance(s)

func _promise(code: String, due: int) -> void:
	s.promises.append({"character_id": "char_marshal", "promise_code": code,
		"made_tick": s.tick, "tick_due": due, "status": "open"})

func test_kept_when_action_executes_before_due() -> void:
	_promise("LEVY_RAISE", s.tick + 4)
	var before: int = s.characters["char_marshal"].opinion
	engine.actions.execute(ActionRequest.make("LEVY_RAISE"), s)
	assert_eq(s.promises[0]["status"], "kept")
	# +15 kept, minus whatever ideology drift the levy itself causes — assert the log entry
	var found := false
	for e in s.characters["char_marshal"].opinion_log:
		if "promise kept" in String(e["reason"]) and int(e["delta"]) == 15:
			found = true
	assert_true(found)
	assert_gt(s.characters["char_marshal"].opinion, before)

## Kept promises apply +15 opinion but, before this fix, never narrated: the
## kept-check only called change_opinion, leaving nothing in the outcome's
## `effects` array for the promise-kept suffix helpers (conversation_scene.gd/
## court_screen.gd) to pick up.
func test_kept_promise_outcome_carries_narratable_effect() -> void:
	_promise("LEVY_RAISE", s.tick + 4)
	var outcome := engine.actions.execute(ActionRequest.make("LEVY_RAISE"), s)
	var found := false
	for e in outcome["effects"]:
		if String(e.get("metric", "")) == "promise" and int(e["delta"]) == 15 \
				and "a promise kept:" in String(e["reason"]):
			found = true
	assert_true(found, "kept-promise outcome should carry a narratable 'promise' effect")

func test_targeted_promise_needs_matching_target() -> void:
	_promise("CHARACTER_REWARD", s.tick + 4)
	engine.actions.execute(ActionRequest.make("CHARACTER_REWARD", {"mode": "gold"}, "char_steward"), s)
	assert_eq(s.promises[0]["status"], "open")  # rewarded the wrong person
	engine.advance(s)  # advance tick to clear cooldown
	engine.advance(s)  # clear cooldown (set to tick+2 at tick 1, so clear at tick 3)
	engine.actions.execute(ActionRequest.make("CHARACTER_REWARD", {"mode": "gold"}, "char_marshal"), s)
	assert_eq(s.promises[0]["status"], "kept")

func test_broken_when_due_passes() -> void:
	_promise("LEVY_RAISE", s.tick + 1)
	var before: int = s.characters["char_marshal"].opinion
	var r1 := engine.advance(s)   # tick == due: still open
	assert_eq(s.promises[0]["status"], "open")
	var r2 := engine.advance(s)   # past due -> broken
	assert_eq(s.promises[0]["status"], "broken")
	assert_eq(s.characters["char_marshal"].opinion, before + int(data.bal("promise_broken_opinion")))
	assert_true("grudge" in s.characters["char_marshal"].flags)
	assert_eq(r2.promise_events.size(), 1)
	assert_eq(r2.promise_events[0]["status"], "broken")

func test_flags_survive_round_trip() -> void:
	s.characters["char_marshal"].flags.append("grudge")
	var s2 := GameState.from_dict(s.to_dict())
	assert_true("grudge" in s2.characters["char_marshal"].flags)
	assert_eq(SaveLoad.state_hash(s2), SaveLoad.state_hash(s))
