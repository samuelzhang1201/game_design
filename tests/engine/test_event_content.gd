extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")

var data: DataRepository

func before_each() -> void:
	data = SuiteData.repo()

func test_pool_inventory() -> void:
	assert_eq(data.events.size(), 20)
	for row in data.events:
		var id := String(row["event_id"])
		var n := 0
		for c in data.event_choices:
			if String(c["event_id"]) == id:
				n += 1
		assert_between(n, 2, 4, id + " choice count")
		assert_gt(float(row["weight"]), 0.0, id)

## No event may be model-voiced (user ruling 2026-08-31): event stories are
## fixed authored prose. This asserts the data agrees with the code, which
## has no branch to a model at all.
func test_no_event_is_model_voiced() -> void:
	for row in data.events:
		assert_eq(String(row["voice"]), "template",
			String(row["event_id"]) + " must not be model-voiced")

## Scene prose now lives in RANDOM_EVENTS.md, not templates.csv — the CSV
## keeps only the per-choice outcome lines. Both halves still have to exist.
func test_every_event_has_authored_scene_and_outcome_lines() -> void:
	var keys := {}
	for t in data.templates:
		keys[String(t["key"])] = true
	for row in data.events:
		var id := String(row["event_id"])
		assert_true(data.event_scenes.has(id), "missing authored scene for " + id)
		assert_false(keys.has("event_" + id),
			id + "'s scene must not also sit in templates.csv, or the two will drift")
	for c in data.event_choices:
		assert_true(keys.has("event_%s_%s" % [c["event_id"], c["choice_id"]]),
			"missing outcome template for %s/%s" % [c["event_id"], c["choice_id"]])

func test_effects_and_triggers_parse() -> void:
	var s := SuiteData.campaign(data, 7)
	s.tick = 30  # year>=2 triggers evaluable either way
	for row in data.events:
		TriggerDsl.evaluate(String(row["trigger"]), s, data)  # must not push unknown-clause errors
	for c in data.event_choices:
		for raw in String(c["effects"]).split(";", false):
			var op := raw.strip_edges()
			if op == "":
				continue
			var head := op.split(":")[0]
			assert_true(head in ["metric", "gold", "opinion", "schedule", "flag", "promise", "law"],
				"unknown op '%s' in %s/%s" % [head, c["event_id"], c["choice_id"]])

func test_schedule_targets_exist() -> void:
	for c in data.event_choices:
		for raw in String(c["effects"]).split(";", false):
			var op := raw.strip_edges()
			if op.begins_with("schedule:"):
				var target := op.split(":")[1]
				assert_true(data.events_by_id.has(target),
					"schedule target %s missing (from %s)" % [target, c["event_id"]])

func test_every_event_reachable_or_chained() -> void:
	# every event is either trigger-reachable or the target of a schedule op
	var chained := {}
	for c in data.event_choices:
		for raw in String(c["effects"]).split(";", false):
			if raw.strip_edges().begins_with("schedule:"):
				chained[raw.strip_edges().split(":")[1]] = true
	for row in data.events:
		var trig := String(row["trigger"])
		var ok: bool = trig != "never" or chained.has(String(row["event_id"]))
		assert_true(ok, String(row["event_id"]) + " unreachable")

## --- Mandatory additions (controller rulings) ---

## Ruling 1: colon safety. Each effect op must split(":") into EXACTLY the
## declared arity for its kind — a colon inside a reason/arg silently
## truncates downstream (EventEffects indexes p[1]/p[2]/p[3] positionally),
## so wrong arity must fail loud here instead of misbehaving at runtime.
## Also assert no ";" survives inside a single op's own args (a raw op is
## already the result of splitting the whole effects string on ";", so this
## catches nothing new by itself — it documents the invariant explicitly,
## as the ruling requires).
func test_effect_op_arity_and_colon_safety() -> void:
	var arity := {"metric": 3, "gold": 2, "opinion": 4, "schedule": 3, "flag": 2, "promise": 4, "law": 3}
	for c in data.event_choices:
		for raw in String(c["effects"]).split(";", false):
			var op := raw.strip_edges()
			if op == "":
				continue
			assert_false(";" in op,
				"stray ';' inside op '%s' in %s/%s" % [op, c["event_id"], c["choice_id"]])
			var parts := op.split(":")
			var head := parts[0]
			if not arity.has(head):
				continue  # unknown-op case is already covered by test_effects_and_triggers_parse
			assert_eq(parts.size(), arity[head],
				"%s op wrong arity (got %d parts, want %d) in %s/%s: '%s'" % [
					head, parts.size(), arity[head], c["event_id"], c["choice_id"], op])

## Ruling 2: target resolution. Every opinion:/promise: op's target (part 1)
## must resolve the same way EventEffects._resolve resolves it at runtime:
## a founding seat code (state.council key) or an existing character id
## (state.characters key): founding_council.csv's seat/id columns, or a
## roles.csv id (the cast outside the council — Cassian, Ysolde, the Duke),
## so we validate against those files directly rather than duplicating
## engine internals.
func test_opinion_and_promise_targets_resolve() -> void:
	var founding_ids := {}
	var founding_seats := {}
	for f in data.founding:
		founding_ids[String(f["id"])] = true
		founding_seats[String(f["seat"])] = true
	for r in data.roles:
		founding_ids[String(r["id"])] = true
	for c in data.event_choices:
		for raw in String(c["effects"]).split(";", false):
			var op := raw.strip_edges()
			if op == "":
				continue
			var parts := op.split(":")
			if parts[0] in ["opinion", "promise"] and parts.size() > 1:
				var target := parts[1]
				var ok: bool = founding_seats.has(target) or founding_ids.has(target)
				assert_true(ok,
					"unresolved %s target '%s' in %s/%s" % [parts[0], target, c["event_id"], c["choice_id"]])

## Ruling 3: every event must have at least one choice with empty requires,
## or the engine can gate every choice off and silently skip the event
## every time it is rolled (EventSystem._fire drops it when choices.is_empty()).
func test_every_event_has_unconditional_choice() -> void:
	for row in data.events:
		var id := String(row["event_id"])
		var has_open := false
		for c in data.event_choices:
			if String(c["event_id"]) == id and String(c.get("requires", "")).strip_edges() == "":
				has_open = true
		assert_true(has_open, id + " has no choice with empty requires (all choices gate-able off)")

## Ruling 4: requires clauses must parse through TriggerDsl without an
## unknown-clause error. TriggerDsl.push_error on an unrecognized clause is
## caught by GUT itself (gut.gd _fail_for_error, treat_error_as_failure is
## on by default) which fails whichever test is running when the error
## fires — same mechanism the brief's own test_effects_and_triggers_parse
## relies on for event `trigger` strings. This extends that coverage to
## every choice's `requires` clause, evaluated against a fresh GameState.
func test_requires_clauses_parse_without_unknown_clause_errors() -> void:
	var s := SuiteData.campaign(data, 11)
	s.tick = 30
	var checked := 0
	for c in data.event_choices:
		var req := String(c.get("requires", "")).strip_edges()
		if req != "":
			TriggerDsl.evaluate(req, s, data)
			checked += 1
	assert_gt(checked, 0, "expected at least one gated (non-empty requires) choice to exercise this test")
