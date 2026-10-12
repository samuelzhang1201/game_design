extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The threshold events of the development axes (spec 2026-10-12-development-axes
## §7): ev_21..ev_30 fire off the crossing flags DevelopmentSystem.move raises.

const IDS: Array = ["ev_21", "ev_22", "ev_23", "ev_24", "ev_25", "ev_26", "ev_27",
	"ev_28", "ev_29", "ev_30"]

var repo: DataRepository
var s: GameState
var es: EventSystem
var player: String
var neighbor: String


func before_each() -> void:
	repo = SuiteData.repo()
	s = SuiteData.campaign(repo, 42)
	player = repo.resolve_realm("player_realm")
	neighbor = repo.resolve_realm("neighbor_realm")
	# Only the development pool, and a roll that always fires, so a test sees
	# exactly which of these events the flags make eligible.
	repo.events = repo.events.filter(func(r: Dictionary) -> bool: return IDS.has(String(r["event_id"])))
	repo.balance["event_base_chance"] = 1.0
	s.pending_event = {}
	s.event_state["scheduled"] = []
	s.event_state["flags"] = []
	es = EventSystem.new(repo)


func _flags() -> Array:
	return s.event_state.get("flags", [])


func _roll() -> String:
	s.pending_event = {}
	s.event_state["pity"] = 99
	var e := es.roll(s)
	return String(e.get("event_id", ""))


func _row(id: String) -> Dictionary:
	return repo.events_by_id[id]


func _flag_of(id: String) -> String:
	return String(_row(id)["trigger"]).trim_prefix("flag=")


func test_ten_events_with_the_agreed_shape() -> void:
	assert_eq(repo.events.size(), 10)
	for id: String in IDS:
		var row := _row(id)
		assert_eq(String(row["once"]), "1", id)
		assert_eq(String(row["category"]), "realm", id)
		assert_true(String(row["trigger"]).begins_with("flag=dev_"), id)
		assert_gte(float(row["weight"]), 50.0, id)
		var n := 0
		for c in repo.event_choices:
			if String(c["event_id"]) == id:
				n += 1
				assert_ne(String(c["effects"]).strip_edges(), "", "%s/%s has a consequence" % [id, c["choice_id"]])
				for col: String in ["centralism", "militarism", "orthodoxy", "tax_incidence", "expansionism"]:
					assert_true(String(c[col]).is_valid_int(), "%s/%s %s" % [id, c["choice_id"], col])
		assert_between(n, 2, 3, id + " choices")


func test_every_dev_event_resolves_in_random_events_md() -> void:
	var titles := StorySource.load_all_titles()
	for id: String in IDS:
		assert_true(repo.event_scenes.has(id), id + " scene")
		assert_ne(String(repo.event_scenes[id]).strip_edges(), "", id + " scene text")
		assert_ne(String(titles.get(id, "")).strip_edges(), "", id + " title")


func test_each_event_has_a_reachable_trigger_flag() -> void:
	# Drive a realm up through every tier and back down, and collect the flags.
	var made := {}
	for realm: String in [player, neighbor, repo.resolve_realm("raider_realm")]:
		for axis: String in DevelopmentSystem.AXES:
			s.event_state["flags"] = []
			DevelopmentSystem.move(repo, s, realm, axis, 1000, "up")
			DevelopmentSystem.move(repo, s, realm, axis, -1000, "down")
			for f: String in _flags():
				made[f] = true
	for id: String in IDS:
		assert_true(made.has(_flag_of(id)), "%s trigger %s is raised by move" % [id, _flag_of(id)])


func test_crossing_makes_the_event_eligible_once() -> void:
	assert_eq(_roll(), "", "no crossing, nothing fires")
	s.development[player]["renaissance"] = 240
	DevelopmentSystem.move(repo, s, player, "renaissance", 20, "a school")
	assert_eq(_roll(), "ev_21")
	assert_true("ev_21" in s.event_state["once"])
	assert_eq(_roll(), "", "spent")


func test_each_tier_up_event_follows_its_own_flag() -> void:
	var want := {"renaissance": ["ev_21", "ev_22", "ev_23"], "chivalry": ["ev_25", "ev_26", "ev_27"]}
	for axis: String in want:
		s.event_state["flags"] = []
		s.event_state["once"] = []
		DevelopmentSystem.move(repo, s, player, axis, 1000, "to the top")
		var fired: Array = []
		for i in 3:
			fired.append(_roll())
		fired.sort()
		assert_eq(fired, want[axis], axis + ": one event per tier crossed")
		assert_eq(_roll(), "")
		s.development[player][axis] = 100
		s.development[player]["tier_" + axis] = 0


func test_oscillation_inside_hysteresis_does_not_refire() -> void:
	s.development[player]["renaissance"] = 240
	DevelopmentSystem.move(repo, s, player, "renaissance", 20, "up")
	DevelopmentSystem.move(repo, s, player, "renaissance", -20, "back")
	DevelopmentSystem.move(repo, s, player, "renaissance", 20, "up again")
	assert_eq(DevelopmentSystem.tier(s, player, "renaissance"), 1)
	assert_eq(_flags().count("dev_renaissance_up_1"), 1)
	assert_false(_flags().has("dev_renaissance_down_1"))
	assert_eq(_roll(), "ev_21")
	assert_eq(_roll(), "")
	assert_eq(s.event_state["once"].count("ev_21"), 1)


func test_decline_event_fires_on_fall() -> void:
	s.development[player]["chivalry"] = 260
	s.development[player]["tier_chivalry"] = 1
	DevelopmentSystem.move(repo, s, player, "chivalry", -40, "the horse sold")
	assert_true(_flags().has("dev_chivalry_down_1"))
	assert_eq(_roll(), "ev_28")
	s.development[player]["renaissance"] = 260
	s.development[player]["tier_renaissance"] = 1
	DevelopmentSystem.move(repo, s, player, "renaissance", -40, "the founders left")
	assert_eq(_roll(), "ev_24")


func test_monthly_foreign_step_raises_the_flag_and_the_event() -> void:
	var ruler := DevelopmentSystem.ruler_of(repo, s, neighbor)
	assert_not_null(ruler)
	repo.traits["t_lean"] = {"trait_code": "t_lean", "dev_renaissance": 80, "dev_chivalry": 80}
	ruler.traits = ["crowned_head", "t_lean"]
	var raider := repo.resolve_realm("raider_realm")
	var warchief := DevelopmentSystem.ruler_of(repo, s, raider)
	assert_not_null(warchief)
	warchief.traits = ["crowned_head", "t_lean"]
	s.development[neighbor]["renaissance"] = 248
	s.development[raider]["chivalry"] = 248
	DevelopmentSystem.settle_month(repo, s)
	assert_eq(DevelopmentSystem.score(s, neighbor, "renaissance"), 263, "one step of dev_ai_step (15)")
	assert_eq(DevelopmentSystem.tier(s, neighbor, "renaissance"), 1)
	assert_true(_flags().has("dev_foreign_neighbor_realm_renaissance_up_1"))
	assert_true(_flags().has("dev_foreign_raider_realm_chivalry_up_1"))
	var fired := [_roll(), _roll()]
	fired.sort()
	assert_eq(fired, ["ev_29", "ev_30"])
	assert_eq(_roll(), "")


func test_no_prose_names_a_kingdom() -> void:
	var names: Array = []
	for slot: String in repo.realm_bindings:
		names.append(repo.resolve_realm(slot).to_lower())
		names.append(repo.realm_label(slot).to_lower())
	var titles := StorySource.load_all_titles()
	for id: String in IDS:
		var texts: Array = [String(repo.event_scenes_authored[id]), String(titles[id])]
		for c in repo.event_choices:
			if String(c["event_id"]) == id:
				texts.append(String(c["label"]))
				texts.append(String(c["_authored"].get("label", "")) if c.has("_authored") else "")
		for t: Array in [texts]:
			for text: String in t:
				for n: String in names:
					if n != "":
						assert_eq(text.to_lower().find(n), -1, "%s names %s" % [id, n])
	for t in repo.templates:
		if String(t["key"]).begins_with("event_ev_2") or String(t["key"]).begins_with("event_ev_30"):
			var authored := String(t.get("_authored", {}).get("text", t["text"]))
			for n: String in names:
				if n != "":
					assert_eq(authored.to_lower().find(n), -1, "%s names %s" % [t["key"], n])


## The shipped roster, no injected traits: twelve real months lift the
## neighbour's Renaissance and the raider's Chivalry to tier 1. Hand values:
## start 100, step dev_ai_step a month, so min(100 + 12 x step, target).
func test_shipped_roster_reaches_tier_one_in_a_year() -> void:
	var raider := repo.resolve_realm("raider_realm")
	var step := int(repo.bal("dev_ai_step"))
	var per := int(repo.bal("dev_ai_target_per_pref"))
	var eng := TickEngine.new(repo)
	for i in 12:
		eng.advance(s)
	var n_pref := DevelopmentSystem.preference(repo, DevelopmentSystem.ruler_of(repo, s, neighbor), "renaissance")
	var r_pref := DevelopmentSystem.preference(repo, DevelopmentSystem.ruler_of(repo, s, raider), "chivalry")
	assert_eq(DevelopmentSystem.score(s, neighbor, "renaissance"), mini(100 + 12 * step, 100 + n_pref * per))
	assert_eq(DevelopmentSystem.score(s, raider, "chivalry"), mini(100 + 12 * step, 100 + r_pref * per))
	assert_gte(DevelopmentSystem.score(s, neighbor, "renaissance"), 250)
	assert_gte(DevelopmentSystem.score(s, raider, "chivalry"), 250)
	assert_true(_flags().has("dev_foreign_neighbor_realm_renaissance_up_1"))
	assert_true(_flags().has("dev_foreign_raider_realm_chivalry_up_1"))

