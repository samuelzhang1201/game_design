class_name OrderCosts
extends RefCounted
## Every order carries a cost (spec 2026-09-09 §3). A cost is a metric moved
## against its good direction, an opinion / relationship / attribute loss, or
## a world field moved against its good direction. Tone deltas and the kept
## promise pseudo-effect do not count. When an order carried none of its own,
## the action's row in data/order_costs.csv is charged. Engine-pure.

const EXEMPT := "none"

static func snapshot_opinions(state: GameState) -> Dictionary:
	var out: Dictionary = {}
	for id: String in state.characters:
		out[id] = (state.characters[id] as Character).opinion
	return out

## True when anything in the order was a loss for the crown. `effects` may
## mix ActionSystem's {metric, delta, reason} entries (no kind) with
## EventEffects results (kind: metric|opinion|relationship|attribute|world).
static func has_cost(data: DataRepository, state: GameState, effects: Array, drift: Array,
		opinions_before: Dictionary) -> bool:
	for e in effects:
		var delta := float(e.get("delta", 0.0))
		match String(e.get("kind", "metric")):
			"metric":
				if int(data.metric_polarity.get(String(e.get("metric", "")), 0)) * delta < 0.0:
					return true
			"opinion", "relationship", "attribute":
				if delta < 0.0:
					return true
			"world":
				if WorldLedger.polarity_of(data, String(e.get("path", ""))) * delta < 0.0:
					return true
	for d in drift:
		if int(d.get("delta", 0)) < 0:
			return true
	for id in opinions_before:
		if state.characters.has(id) \
				and (state.characters[id] as Character).opinion < int(opinions_before[id]):
			return true
	return false

## Gold an action's cost row would take, as a positive number (affordability).
static func gold_of(data: DataRepository, action_code: String) -> float:
	var gold := 0.0
	for raw in _ops(data, action_code).split(";", false):
		var p := raw.strip_edges().split(":")
		if p[0] == "gold" and p.size() > 1:
			gold += maxf(-float(p[1]), 0.0)
	return gold

## What an action's cost row takes OUT of one metric, as a positive number
## (affordability, gold_of's sibling). A pool the row draws on — the
## strategic stock, the civil stores — cannot be spent below empty, so
## ActionSystem.validate refuses the order rather than settling a negative.
static func metric_cost_of(data: DataRepository, action_code: String, metric: String) -> float:
	var cost := 0.0
	for raw in _ops(data, action_code).split(";", false):
		var p := raw.strip_edges().split(":")
		if p[0] == "metric" and p.size() > 2 and p[1] == metric:
			cost += maxf(-float(p[2]), 0.0)
	return cost

static func _ops(data: DataRepository, action_code: String) -> String:
	var row: Dictionary = data.order_costs.get(action_code, {})
	var ops := String(row.get("cost", EXEMPT)).strip_edges()
	return "" if ops == EXEMPT or ops == "" else ops

## Rows marked always=1 are charged every time, beside the action's own costs.
static func always(data: DataRepository, action_code: String) -> bool:
	return String((data.order_costs.get(action_code, {}) as Dictionary).get("always", "0")) == "1"

## Apply the action's cost row; `target` replaces the literal "target" in an
## op so CHARACTER_PUNISH can charge the punished. [] for exempt actions.
static func charge(data: DataRepository, state: GameState, action_code: String,
		target: String) -> Array:
	var ops := _ops(data, action_code)
	if ops == "":
		return []
	if target != "":
		ops = ops.replace(":target:", ":%s:" % target)
	return EventEffects.apply(ops, state, data, "")

## The guarantee: charge the row when the order carried no cost of its own
## (always rows are charged by ActionSystem regardless). Charged results are
## appended to `effects` so narration prints them like any other effect.
static func ensure(data: DataRepository, state: GameState, effects: Array, drift: Array,
		opinions_before: Dictionary, action_code: String, target: String) -> Array:
	if has_cost(data, state, effects, drift, opinions_before):
		return []
	var charged := charge(data, state, action_code, target)
	effects.append_array(charged)
	return charged
