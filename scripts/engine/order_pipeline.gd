class_name OrderPipeline
extends RefCounted
## One order end to end (spec 2026-09-09 §4.3): execute the actions through
## ActionSystem, apply the validated world impacts through the ledger, apply
## the court reaction, charge the generic cost when a pure-impact order cost
## nothing, and write the ledger lines the screens print beneath the
## narrative — so what the court SAID and what the record SHOWS sit together.
## Engine-pure; the caller emits state_changed.

static func apply_order(data: DataRepository, state: GameState, engine: TickEngine,
		actions: Array, world: Array, court_reaction: Dictionary, source: String) -> Dictionary:
	var executed: Array = []
	var rejected: Array = []
	for req: ActionRequest in actions:
		if req.action_code == "EVENT_CHOICE":
			var ev_out := engine.events.apply_choice(String(req.params.get("choice_id", "")), state)
			if ev_out.is_empty():
				rejected.append({"request": req, "error": "no such choice awaits"})
			else:
				executed.append({"action_code": "EVENT_CHOICE", "ok": true,
					"effects": ev_out["effects"], "notes": String(ev_out["label"]),
					"drift": ev_out["drift"], "event_id": String(ev_out["event_id"]),
					"choice_id": String(ev_out["choice_id"])})
			continue
		var err := engine.actions.validate(req, state)
		if err != "":
			rejected.append({"request": req, "error": err})
		else:
			executed.append(engine.actions.execute(req, state))
	var world_effects: Array = []
	var world_rejected: Array = []
	for imp in world:
		var out := WorldLedger.apply(data, state, String(imp["path"]), float(imp["delta"]),
			String(imp["reason"]), source)
		if out.has("error"):
			world_rejected.append({"path": String(imp["path"]), "error": String(out["error"])})
		else:
			out["kind"] = "world"
			world_effects.append(out)
	engine.actions.apply_court_reaction(court_reaction, state)
	# Every order carries a cost (§3): an order that executed no action is
	# charged the generic row when its impacts were all gains.
	var cost_effects: Array = []
	if executed.is_empty() and not world_effects.is_empty() \
			and not OrderCosts.has_cost(data, state, world_effects, [], {}):
		cost_effects = OrderCosts.charge(data, state, "generic_order", "")
	var ledger: Array[String] = []
	for o in executed:
		var line := describe_effects(o["effects"], state)
		if line != "":
			ledger.append("%s — %s" % [String(o["notes"]), line])
	if not world_effects.is_empty():
		ledger.append(describe_effects(world_effects, state))
	if not cost_effects.is_empty():
		ledger.append(describe_effects(cost_effects, state))
	# Rejected ACTIONS are already spoken by the screens ("The council cannot:
	# ..."); struck impacts have no other voice, so they are named here.
	for r in world_rejected:
		ledger.append("the clerk struck %s (%s)" % [String(r["path"]), String(r["error"])])
	return {"executed": executed, "rejected": rejected, "world_effects": world_effects,
		"world_rejected": world_rejected, "cost_effects": cost_effects, "ledger": ledger}

## "treasury -40: surveyors hired, grain +5: a gift" — every effect with its
## reason, whatever its kind, so the numbers and their causes read together.
## A law moved by an event reads "Tariff rate 3 → 4: <reason>"; a decree's
## own line (ActionSystem's "law" pseudo-metric) is its reason alone, which
## already names the law and its value.
static func describe_effects(effects: Array, state: GameState) -> String:
	var parts: Array[String] = []
	for e in effects:
		var delta := float(e.get("delta", 0.0))
		var what := ""
		match String(e.get("kind", "metric")):
			"metric":
				var m := String(e.get("metric", ""))
				if m == "promise":
					continue
				if m == "law":
					parts.append(String(e.get("reason", "")))
					continue
				what = m.replace("_", " ")
			"law":
				var reason_l := String(e.get("reason", ""))
				parts.append("%s %s → %s%s" % [String(e.get("label", e.get("law", ""))),
					String(e.get("was", "")), String(e.get("value", "")),
					(": " + reason_l) if reason_l != "" else ""])
				continue
			"opinion":
				what = _name(state, String(e.get("character_id", ""))) + " opinion"
			"attribute":
				what = "%s %s" % [_name(state, String(e.get("character_id", ""))),
					String(e.get("attribute", ""))]
			"relationship":
				what = "%s toward %s" % [_name(state, String(e.get("from", ""))),
					_name(state, String(e.get("to", "")))]
			"world":
				what = _field_label(String(e.get("path", "")))
			_:
				continue
		var num := ("%+d" % roundi(delta)) if delta == floorf(delta) else ("%+.1f" % delta)
		var reason := String(e.get("reason", ""))
		parts.append("%s %s%s" % [what, num, (": " + reason) if reason != "" else ""])
	return ", ".join(parts)

## "grain" for metrics.grain, "kingdoms rural population" for
## economy.kingdoms.<code>.rural_population, "you prestige" for attribute paths.
static func _field_label(path: String) -> String:
	var p := path.split(".")
	match p.size():
		2:
			return p[1].replace("_", " ")
		3:
			return "%s %s" % [p[1], p[2].replace("_", " ")]
		4:
			return "%s %s" % [p[1], p[3].replace("_", " ")]
	return path

static func _name(state: GameState, id: String) -> String:
	return (state.characters[id] as Character).display_name if state.characters.has(id) else id
