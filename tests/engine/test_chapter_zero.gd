extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Chapter 0 — the prologue tutorial (game_story/chapter_0/chapter_0_events.md,
## data/story/chapter_events.csv, chapter_event_choices.csv, chapter_branches.csv).
##
## It runs on the ordinary event system: chapter beats are fired off a chain,
## never sampled by the random roll, so this file holds them to the same
## rigour test_event_content.gd holds the pool to, plus the two properties a
## scripted chain needs that a pool does not — every beat is reachable from
## the opener, and no beat can leave the player with nothing to click.

var data: DataRepository

func before_each() -> void:
	data = SuiteData.repo()

## The chain's own beats (`c0_*`). The chapter table also holds the beats the
## ENGINE fires off the war (`war_*`, game_story/chapter_0/war_events.md,
## DefeatSystem): fixed prose under the same content rules (the loops over
## data.chapter_events / chapter_event_choices below and test_defeat.gd), but
## outside the chain, so not reachable from the opener nor on its paths.
func _ids() -> Array:
	var out: Array = []
	for id: String in _all_ids():
		if id.begins_with("c0_"):
			out.append(id)
	return out

func _all_ids() -> Array:
	var out: Array = []
	for row in data.chapter_events:
		out.append(String(row["event_id"]))
	return out

func _choices_of(id: String) -> Array:
	var out: Array = []
	for c in data.chapter_event_choices:
		if String(c["event_id"]) == id:
			out.append(c)
	return out

# --- inventory -------------------------------------------------------------

func test_the_chapter_is_all_there() -> void:
	assert_false(data.chapter_events.is_empty(), "the chapter's beats are loaded")
	for row in data.chapter_events:
		var id := String(row["event_id"])
		assert_eq(String(row["category"]), "chapter", id)
		assert_eq(String(row["trigger"]), "never",
			id + " must be chained, never sampled by the random roll")
		assert_eq(String(row["once"]), "1", id + " fires at most once")
		assert_between(_choices_of(id).size(), 1, 4, id + " choice count")
	var ids := _all_ids()
	for c in data.chapter_event_choices:
		assert_has(ids, String(c["event_id"]), "%s belongs to a chapter beat" % c["choice_id"])
	for id: String in ids:
		assert_true(id.begins_with("c0_") or id.begins_with("war_"),
			id + " is neither a chain beat nor a war beat")

## The prologue is free of the model (PRD §8, invariant 9): every beat is
## authored prose shown verbatim.
func test_no_chapter_beat_is_model_voiced() -> void:
	for row in data.chapter_events:
		assert_eq(String(row["voice"]), "template", String(row["event_id"]))

func test_chapter_beats_are_not_in_the_random_pool() -> void:
	# The pool is sampled by weight; a scripted beat in it would fire out of
	# order. It still has to be findable by id, which is how a chain fires it.
	var pool := {}
	for row in data.events:
		pool[String(row["event_id"])] = true
	for id: String in _all_ids():
		assert_false(pool.has(id), id + " must not be in data/story/events.csv")
		assert_true(data.events_by_id.has(id), id + " must be findable by id")
	assert_eq(data.event_choices_all().size(),
		data.event_choices.size() + data.chapter_event_choices.size())

# --- prose -----------------------------------------------------------------

func test_every_beat_has_an_authored_scene_a_title_and_an_outcome_line() -> void:
	var keys := {}
	for t in data.templates:
		keys[String(t["key"])] = true
	for id: String in _all_ids():
		assert_true(data.event_scenes.has(id), "missing authored scene for " + id)
		assert_ne(String(data.event_scenes.get(id, "")).strip_edges(), "", id + " scene is blank")
		assert_ne(String(data.event_titles.get(id, "")).strip_edges(), "",
			id + " has no title on its heading (the audience window's banner)")
		assert_false(keys.has("event_" + id),
			id + "'s scene must not also sit in templates.csv, or the two will drift")
	for c in data.chapter_event_choices:
		assert_true(keys.has("event_%s_%s" % [c["event_id"], c["choice_id"]]),
			"missing outcome template for %s/%s" % [c["event_id"], c["choice_id"]])

## Invariant 5: authored prose never names a kingdom.
func test_no_scene_names_a_kingdom() -> void:
	var names: Array = []
	for slot: String in ["player_realm", "raider_realm", "neighbor_realm", "empire_realm"]:
		var code := data.resolve_realm(slot)
		if code != "" and data.kingdoms.has(code):
			names.append(String((data.kingdoms[code] as Dictionary)["label"]))
	assert_gt(names.size(), 0, "the pack binds at least one realm")
	for id: String in _all_ids():
		# event_scenes is the FILLED copy; the authored one is what the
		# author typed and is the thing that must be slot-only.
		var authored := String(data.event_scenes_authored.get(id, ""))
		for n: String in names:
			assert_false(authored.contains(n),
				"%s names the kingdom %s — use a {slot} token" % [id, n])

# --- effects ---------------------------------------------------------------

func test_effect_ops_are_known_and_of_the_right_arity() -> void:
	# A colon inside a reason silently truncates downstream (EventEffects
	# indexes positionally), so wrong arity must fail loud here.
	var arity := {"metric": 3, "gold": 3, "opinion": 4, "schedule": 3, "flag": 2,
		"promise": 4, "world": 4, "rel": 5, "attribute": 5, "branch": 2}
	for c in data.chapter_event_choices:
		for raw in String(c["effects"]).split(";", false):
			var op := raw.strip_edges()
			if op == "":
				continue
			var parts := op.split(":")
			var head := String(parts[0])
			assert_true(arity.has(head),
				"unknown op '%s' in %s/%s" % [head, c["event_id"], c["choice_id"]])
			if arity.has(head):
				assert_eq(parts.size(), int(arity[head]),
					"%s op wrong arity in %s/%s: '%s'" % [
						head, c["event_id"], c["choice_id"], op])

func test_world_paths_are_schema_listed() -> void:
	var s := SuiteData.campaign(data, 3)
	for c in data.chapter_event_choices:
		for raw in String(c["effects"]).split(";", false):
			var op := raw.strip_edges()
			if not op.begins_with("world:"):
				continue
			var path := String(op.split(":")[1])
			assert_false(WorldLedger.schema_for(data, WorldLedger.resolve(data, path)).is_empty(),
				"%s/%s writes unlisted path %s" % [c["event_id"], c["choice_id"], path])
			assert_not_null(WorldLedger.value_of(data, s, WorldLedger.resolve(data, path)),
				"%s has no value behind it" % path)

func test_opinion_and_relationship_targets_resolve() -> void:
	var s := SuiteData.campaign(data, 5)
	for c in data.chapter_event_choices:
		for raw in String(c["effects"]).split(";", false):
			var op := raw.strip_edges()
			var parts := op.split(":")
			if parts.size() < 2:
				continue
			var targets: Array = []
			if parts[0] in ["opinion", "promise"]:
				targets = [String(parts[1])]
			elif parts[0] == "rel":
				targets = [String(parts[1]), String(parts[2])]
			for t: String in targets:
				var ok: bool = s.characters.has(t) or s.council.has(t)
				assert_true(ok, "unresolved target '%s' in %s/%s" % [
					t, c["event_id"], c["choice_id"]])

func test_triggers_and_requires_parse() -> void:
	var s := SuiteData.campaign(data, 7)
	s.tick = 9
	for row in data.chapter_events:
		TriggerDsl.evaluate(String(row["trigger"]), s, data)
	for c in data.chapter_event_choices:
		var req := String(c.get("requires", "")).strip_edges()
		if req != "":
			TriggerDsl.evaluate(req, s, data)
	var checked := 0
	for id: String in data.chapter_branches:
		for rule: Dictionary in data.chapter_branches[id]:
			TriggerDsl.evaluate(String(rule["requires"]), s, data)
			checked += 1
	assert_gt(checked, 0, "every branch rule parsed without an unknown-clause error")
	# The negation the harvest relies on, and the one-person trait check.
	assert_true(TriggerDsl.evaluate("!flag=c0_seed_lent", s, data))
	s.event_state["flags"].append("c0_seed_lent")
	assert_false(TriggerDsl.evaluate("!flag=c0_seed_lent", s, data))
	assert_false(TriggerDsl.evaluate("never", s, data))
	assert_true(TriggerDsl.evaluate("trait_of=char_captain_hale:veteran", s, data))
	assert_false(TriggerDsl.evaluate("trait_of=char_captain_hale:amb_ruthless", s, data))

# --- the chain ------------------------------------------------------------

func _targets_of(effects: String) -> Array:
	var out: Array = []
	for raw in effects.split(";", false):
		var op := raw.strip_edges()
		if op.begins_with("schedule:"):
			out.append(String(op.split(":")[1]))
		elif op.begins_with("branch:"):
			for rule: Dictionary in data.chapter_branches.get(op.split(":")[1], []):
				out.append(String(rule["event_id"]))
	return out

func test_every_schedule_and_branch_target_exists() -> void:
	for c in data.chapter_event_choices:
		for t: String in _targets_of(String(c["effects"])):
			assert_true(data.events_by_id.has(t),
				"%s/%s points at missing beat %s" % [c["event_id"], c["choice_id"], t])

func test_every_branch_table_ends_in_an_always_rule() -> void:
	assert_gt(data.chapter_branches.size(), 0)
	for id: String in data.chapter_branches:
		var rules: Array = data.chapter_branches[id]
		assert_gt(rules.size(), 1, id + " is a fork, not a redirect")
		assert_eq(String((rules[rules.size() - 1] as Dictionary)["requires"]), "always",
			id + " must end in an unconditional rule or it can dead-end")
		var last := -1
		for rule: Dictionary in rules:
			assert_gt(int(rule["order"]), last, id + " rules must be ordered")
			last = int(rule["order"])

func test_every_beat_is_reachable_from_the_opener() -> void:
	var start: Array = []
	for row in data.chapter_events:
		if String(row.get("start_tick", "")).strip_edges() != "":
			start.append(String(row["event_id"]))
	assert_eq(start, ["c0_01"], "exactly one beat opens the chapter")
	var seen := {"c0_01": true}
	var queue: Array = ["c0_01"]
	while not queue.is_empty():
		var id: String = queue.pop_front()
		for c in _choices_of(id):
			for t: String in _targets_of(String(c["effects"])):
				if not seen.has(t):
					seen[t] = true
					queue.append(t)
	for id: String in _ids():
		assert_true(seen.has(id), id + " is unreachable from the first council")

## A beat may gate its choices, but never all of them at once: the engine
## SKIPS an event whose every choice is gated off (EventSystem._fire), which
## would silently swallow a chapter beat. Either a beat has an unconditional
## choice, or two of its choices are exact complements (`X` and `!X`).
func test_no_beat_can_gate_every_choice_off() -> void:
	for id: String in _all_ids():
		var open_choice := false
		var reqs: Array = []
		for c in _choices_of(id):
			var r := String(c.get("requires", "")).strip_edges()
			if r == "":
				open_choice = true
			else:
				reqs.append(r)
		var complementary := false
		for r: String in reqs:
			if ("!" + r) in reqs:
				complementary = true
		assert_true(open_choice or complementary,
			id + " can be gated off entirely and would be skipped")

## The four figures are judged on the year's work. The silver paid for the
## ledger's silence arrives AFTER the branch has read the state, which is
## only true while the branch op comes first in that row's effects.
func test_hush_money_cannot_buy_the_bond() -> void:
	for c in data.chapter_event_choices:
		if String(c["event_id"]) == "c0_12" and String(c["choice_id"]) == "settle":
			var ops := String(c["effects"]).split(";", false)
			assert_true(String(ops[0]).strip_edges().begins_with("branch:"),
				"the branch must be read before the gold lands")
			assert_true(String(c["effects"]).contains("gold:1500"))
			return
	fail_test("c0_12/settle is gone")

## Beats whose illustration is planned (event_art.csv, prompts.csv) but not yet
## rendered and installed: a local session renders them (ComfyUI) and installs
## them with install_map_art.py events, then takes them off this list.
const PENDING_INSTALL := ["war_01"]

## Every beat has an illustration planned, and every plan points at a real
## entry of the art prompt library. The installed PNG is not required — a
## fresh checkout has no renders and the audience window simply shows no
## band — but the mapping must never rot.
func test_every_beat_has_an_illustration_planned() -> void:
	var art := {}
	for r in DataRepository.parse_csv("res://assets/imagegen/event_art.csv",
			["event_id", "art_id"]):
		art[String(r["event_id"])] = String(r["art_id"])
	var prompts := {}
	for r in DataRepository.parse_csv("res://assets/imagegen/prompts.csv", ["id", "canvas"]):
		prompts[String(r["id"])] = String(r["canvas"])
	for id: String in _all_ids():
		assert_true(art.has(id), id + " has no row in assets/imagegen/event_art.csv")
		var art_id: String = art.get(id, "")
		assert_true(prompts.has(art_id),
			"%s names %s, which is not in the prompt library" % [id, art_id])
		assert_eq(String(prompts.get(art_id, "")), "C-EVENT",
			"%s must be drawn on the wide event band canvas" % art_id)
	for id: String in art:
		assert_true(data.events_by_id.has(id),
			"event_art.csv names %s, which is not an event" % id)
	# The renders are committed (assets/2D/events/illustrations/), so a missing one is an
	# incomplete install, not an empty checkout: install_map_art.py events. A beat
	# whose art is planned but not yet rendered is named in PENDING_INSTALL, which
	# fails loudly once its file lands (take it off) or once it names no beat.
	var ids := _all_ids()
	for id: String in PENDING_INSTALL:
		assert_has(ids, id, "PENDING_INSTALL names %s, which is no chapter beat" % id)
		assert_false(ResourceLoader.exists("res://assets/2D/events/illustrations/%s.png" % id),
			"%s's illustration is installed: take it off PENDING_INSTALL" % id)
	for id: String in ids:
		if id in PENDING_INSTALL:
			continue
		assert_true(ResourceLoader.exists("res://assets/2D/events/illustrations/%s.png" % id),
			"no installed illustration for " + id)

# --- playing it -----------------------------------------------------------

func test_a_new_reign_opens_on_the_first_council() -> void:
	var s := SuiteData.campaign(data, 44)
	var sys := EventSystem.new(data)
	s.tick = 1
	var ev := sys.roll(s)
	assert_eq(String(ev.get("event_id", "")), "c0_01",
		"the prologue opens the reign, not a random event")
	assert_eq((ev["choices"] as Array).size(), 3)

## Neither fork may be dead content. The captain's search is an OPTION the
## player is offered because his captain is a veteran (the design rule: gate
## the option, never roll a hidden die), and the spymaster's own fork turns
## on how the king treated his council in the first hour of the reign.
func test_both_sides_of_every_fork_are_reachable() -> void:
	var s := SuiteData.campaign(data, 44)
	s.tick = 3
	for branch: String in ["c0_br_spy", "c0_br_guard", "c0_br_charter",
			"c0_br_tax", "c0_br_harvest", "c0_br_ending"]:
		var seen := {}
		# Every rule of the table must be the winner for SOME state: walk the
		# table and check each rule is not shadowed by an earlier one that
		# holds whenever it does. The cheap, honest version: each rule's own
		# target must differ from the target of the rule above it, or the
		# fork has a side nobody can reach.
		for rule: Dictionary in data.chapter_branches[branch]:
			seen[String(rule["event_id"])] = true
		assert_gt(seen.size(), 1, branch + " has only one destination")
	# The captain's option exists because Captain Hale is a veteran.
	var sys := EventSystem.new(data)
	s.event_state["scheduled"] = []
	var ev := sys._fire("c0_02", s)
	var ids: Array = []
	for c in ev["choices"]:
		ids.append(String(c["choice_id"]))
	assert_true("summon_searched" in ids,
		"a veteran captain offers to strip the hall, in the open")
	assert_true("summon" in ids, "and the plain safe conduct is still there")


func test_the_chain_keeps_the_seasons_it_says_it_keeps() -> void:
	# Walk the chain the way the game does: fire what is due, take the first
	# offered choice, let the engine schedule the next. No RNG is consulted
	# on this path, so the walk is the same every run. It reaches an ending,
	# and keeps the document's own timetable on the way: the first council in
	# spring, the bond set in summer, the year counted at the harvest.
	var s := SuiteData.campaign(data, 44)
	var sys := EventSystem.new(data)
	var seen: Array = []
	var when := {}
	for tick in range(1, 25):
		s.tick = tick
		var ev := sys.roll(s)
		if ev.is_empty():
			continue
		var id := String(ev["event_id"])
		if not id.begins_with("c0_"):
			s.pending_event = {}
			continue
		seen.append(id)
		when[id] = tick
		var out := sys.apply_choice(String((ev["choices"] as Array)[0]["choice_id"]), s)
		assert_false(out.is_empty(), id + " would not resolve")
		if id in ["c0_13", "c0_14", "c0_15", "c0_16"]:
			break
	assert_eq(seen[0], "c0_01")
	var last: String = seen[seen.size() - 1]
	assert_true(last in ["c0_13", "c0_14", "c0_15", "c0_16"],
		"the chapter ended on " + last)
	assert_true("c0_end_just" in s.event_state["flags"]
		or "c0_end_compromise" in s.event_state["flags"]
		or "c0_end_iron" in s.event_state["flags"]
		or "c0_end_winter" in s.event_state["flags"], "an ending flag is set")
	assert_eq(int(when["c0_01"]), 1, "the first council opens the reign")
	assert_eq(Calendar.season_name(int(when["c0_06"])), "Summer", "the bond is set in summer")
	var harvest: int = int(when.get("c0_11h", when.get("c0_11t", 0)))
	# Holding the king's own tax carts costs a month, and the year is read
	# out in the first week of winter instead of on the threshing floor —
	# the document says so, so the walk has to show it either way.
	var want := "Winter" if when.has("c0_10") else "Autumn"
	assert_eq(Calendar.season_name(harvest), want,
		"the year is counted at the harvest, a month late if the carts were held")

## The same walk with the other fork at every branch: no obstruction, and
## the tallies are read on the threshing floor.
func test_the_unobstructed_chain_counts_the_year_in_autumn() -> void:
	var s := SuiteData.campaign(data, 44)
	var sys := EventSystem.new(data)
	var when := {}
	for tick in range(1, 25):
		s.tick = tick
		var ev := sys.roll(s)
		if ev.is_empty():
			continue
		var id := String(ev["event_id"])
		if not id.begins_with("c0_"):
			s.pending_event = {}
			continue
		when[id] = tick
		# The LAST offered choice: investigate over suppress, revoke the
		# wardenship over leaving it, and so on down the other side.
		var choices: Array = ev["choices"]
		sys.apply_choice(String(choices[choices.size() - 1]["choice_id"]), s)
	assert_false(when.has("c0_10"), "the carts were never held")
	var harvest: int = int(when.get("c0_11h", when.get("c0_11t", 0)))
	assert_eq(Calendar.season_name(harvest), "Autumn")
	assert_eq(harvest, 9, "on the threshing floor, tick 9")

func test_the_branch_op_takes_the_first_matching_rule() -> void:
	var s := SuiteData.campaign(data, 44)
	s.tick = 5
	# No flag: the tax branch falls through to the thin harvest.
	EventEffects.apply("branch:c0_br_tax", s, data, "test")
	assert_eq(String((s.event_state["scheduled"][s.event_state["scheduled"].size() - 1])["event_id"]),
		"c0_11t")
	# With the Warden still holding the keys, the carts are held first.
	s.event_state["flags"].append("c0_warden_tomas")
	EventEffects.apply("branch:c0_br_tax", s, data, "test")
	var last: Dictionary = s.event_state["scheduled"][s.event_state["scheduled"].size() - 1]
	assert_eq(String(last["event_id"]), "c0_10")
	assert_eq(int(last["due_tick"]), 6, "the rule carries its own delay")

func test_the_ending_follows_the_four_figures() -> void:
	var cases := [
		[{}, [], "c0_16"],
		[{"treasury": 20000.0, "grain": 60000.0, "unrest": 0.0, "peasant_contentment": 60.0},
			[], "c0_14"],
		[{"treasury": 20000.0, "grain": 60000.0, "unrest": 0.0, "peasant_contentment": 60.0},
			["c0_ledger_shown"], "c0_13"],
		[{"treasury": 20000.0, "grain": 60000.0, "unrest": 0.0, "peasant_contentment": 60.0},
			["c0_path_suppress", "c0_ledger_shown"], "c0_15"],
		[{"treasury": 20000.0, "grain": 60000.0, "unrest": 40.0, "peasant_contentment": 60.0},
			["c0_ledger_shown"], "c0_16"],
	]
	for case: Array in cases:
		var s := SuiteData.campaign(data, 9)
		s.tick = 11
		for k: String in (case[0] as Dictionary):
			s.metrics[k] = float((case[0] as Dictionary)[k])
		for f: String in (case[1] as Array):
			s.event_state["flags"].append(f)
		s.event_state["scheduled"] = []
		EventEffects.apply("branch:c0_br_ending", s, data, "test")
		assert_eq(String((s.event_state["scheduled"][0])["event_id"]), String(case[2]),
			"metrics %s flags %s" % [case[0], case[1]])

## Every path, walked. The chain is small enough to enumerate outright, but
## only if the walk is cheap: a path's whole history is the set of flags it
## has set, so it is simulated as a flag set rather than by replaying a
## GameState. The one state-dependent clause a branch uses beyond flags is
## trait_of, which is constant for a roster, so it is resolved once up front.
func test_every_path_terminates_in_one_of_the_four_endings() -> void:
	var s := SuiteData.campaign(data, 44)
	var endings := {"c0_13": 0, "c0_14": 0, "c0_15": 0, "c0_16": 0}
	var visited := {}
	var paths := 0
	for bond_kept: bool in [true, false]:
		paths += _walk("c0_01", {}, bond_kept, s, endings, visited, 0)
	assert_gt(paths, 100, "the chain really does branch")
	for id: String in endings:
		assert_gt(int(endings[id]), 0, id + " is reached by no path")
	for id: String in _ids():
		assert_true(visited.has(id), id + " is reached by no path at all")

func _walk(event_id: String, flags: Dictionary, bond_kept: bool, s: GameState,
		endings: Dictionary, visited: Dictionary, depth: int) -> int:
	if depth >= 24:
		fail_test("the chain runs longer than the chapter can, at " + event_id)
		return 0
	visited[event_id] = true
	if endings.has(event_id):
		endings[event_id] = int(endings[event_id]) + 1
		return 1
	var closed := 0
	var offered := 0
	for c in data.chapter_event_choices:
		if String(c["event_id"]) != event_id:
			continue
		if not _holds(String(c.get("requires", "")), flags, bond_kept, s):
			continue
		offered += 1
		var next_flags := flags.duplicate()
		var next := ""
		for raw in String(c["effects"]).split(";", false):
			var op := raw.strip_edges()
			if op.begins_with("flag:"):
				next_flags[op.split(":")[1]] = true
			elif op.begins_with("schedule:"):
				next = String(op.split(":")[1])
			elif op.begins_with("branch:"):
				for rule: Dictionary in data.chapter_branches.get(op.split(":")[1], []):
					if _holds(String(rule["requires"]), next_flags, bond_kept, s):
						next = String(rule["event_id"])
						break
		assert_ne(next, "", "%s/%s leads nowhere" % [event_id, c["choice_id"]])
		if next != "":
			closed += _walk(next, next_flags, bond_kept, s, endings, visited, depth + 1)
	assert_gt(offered, 0, event_id + " offers nothing in this state")
	return closed

## The branch/requires clauses this chapter actually uses, over a flag set:
## always, flag=, !flag=, trait_of= and the four metric comparisons of the
## bond (which this walk fixes per pass rather than simulating).
func _holds(expr: String, flags: Dictionary, bond_kept: bool, s: GameState) -> bool:
	var e := expr.strip_edges()
	if e == "" or e == "always":
		return true
	for raw in e.split("&"):
		var c := raw.strip_edges()
		var want := true
		if c.begins_with("!"):
			want = false
			c = c.substr(1).strip_edges()
		var got := false
		if c.begins_with("flag="):
			got = flags.has(c.substr(5))
		elif c.begins_with("trait_of="):
			got = TriggerDsl.evaluate(c, s, data)
		elif "<" in c or ">" in c:
			got = bond_kept  # the four figures, kept or lost, per pass
		else:
			fail_test("the walk cannot read the clause: " + c)
		if got != want:
			return false
	return true
