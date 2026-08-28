class_name GameState
extends RefCounted

var tick: int = 0
var rng: Rng
var metrics: Dictionary = {}
var characters: Dictionary = {}
var council: Dictionary = {}
var cooldowns: Dictionary = {}
var recent_outcomes: Array = []
var promises: Array = []
var event_state: Dictionary = {
	"cooldowns": {}, "once": [], "pity": 0, "scheduled": [],
	"flags": [], "last_action_tick": {},
}
var pending_event: Dictionary = {}

const SEASONS := ["spring", "summer", "autumn", "winter"]

static func new_campaign(data: DataRepository, seed_value: int) -> GameState:
	var s := GameState.new()
	s.rng = Rng.new(seed_value)
	s.metrics = {
		"treasury": data.bal("start_treasury"),
		"tax_rate": data.bal("start_tax_rate"),
		"tariff_rate": data.bal("start_tariff_rate"),
		"tax_income": 0.0,
		"admin_capacity": data.bal("admin_base"),
		"legitimacy": data.bal("start_metric_default"),
		"unrest": 0.0,
		"grain": data.bal("start_grain"),
		"army_quality": data.bal("start_metric_default"),
		"church_opinion": data.bal("start_metric_default"),
		"peasant_contentment": data.bal("start_metric_default"),
		"grain_capacity_bonus": 0.0,
		"road_income_bonus": 0.0,
		"grain_ration": 0.0,
	}
	s.characters = CharacterFactory.build_founding(data)
	for id in s.characters:
		s.council[s.characters[id].seat] = id
	return s

func season() -> String:
	# Delegates to Calendar so tick 1..24 is year 1 with 6 ticks per season
	# (fixes the old 0-based off-by-one where tick 24 read as spring, year 2).
	return Calendar.season_name(tick).to_lower()

func year() -> int:
	return Calendar.year_of(tick)

func to_dict() -> Dictionary:
	var chars := {}
	for id in characters:
		chars[id] = characters[id].to_dict()
	# Normalize int fields to float for canonical JSON serialization
	# (JSON round-trips ints as floats, so we cast consistently)
	var normalized_cooldowns := {}
	for k in cooldowns:
		normalized_cooldowns[k] = float(cooldowns[k])
	return {
		"tick": float(tick), "rng": rng.to_dict(), "metrics": metrics.duplicate(),
		"characters": chars, "council": council.duplicate(),
		"cooldowns": normalized_cooldowns,
		"recent_outcomes": _normalize_ints(recent_outcomes),
		"promises": _normalize_ints(promises),
		"event_state": _normalize_ints(event_state.duplicate(true)),
		"pending_event": _normalize_ints(pending_event.duplicate(true)),
	}

## Recursively casts int values to float throughout an arbitrarily-nested
## Dictionary/Array structure, for canonical JSON serialization (JSON
## round-trips ints as floats, so to_dict() must cast consistently). Unlike
## metrics/attributes/skills (flat dicts of known numeric keys), recent_outcomes
## and promises hold engine-created ints at unpredictable depths (e.g.
## outcome.params.delta, promise.made_tick/tick_due) — same normalization
## philosophy as Character.to_dict(), generalized to handle that shape.
static func _normalize_ints(value):
	if value is Dictionary:
		var out := {}
		for k in value:
			out[k] = _normalize_ints(value[k])
		return out
	elif value is Array:
		var out := []
		for v in value:
			out.append(_normalize_ints(v))
		return out
	elif typeof(value) == TYPE_INT:
		return float(value)
	return value

static func from_dict(d: Dictionary) -> GameState:
	var s := GameState.new()
	s.tick = int(d["tick"])
	s.rng = Rng.from_dict(d["rng"])
	s.metrics = d["metrics"].duplicate()
	for id in d["characters"]:
		s.characters[id] = Character.from_dict(d["characters"][id])
	s.council = d["council"].duplicate()
	for k in d["cooldowns"]:
		s.cooldowns[k] = int(d["cooldowns"][k])
	s.recent_outcomes = d["recent_outcomes"].duplicate(true)
	s.promises = d["promises"].duplicate(true)
	s.event_state = d.get("event_state", {
		"cooldowns": {}, "once": [], "pity": 0, "scheduled": [],
		"flags": [], "last_action_tick": {},
	}).duplicate(true)
	s.pending_event = d.get("pending_event", {}).duplicate(true)
	return s
