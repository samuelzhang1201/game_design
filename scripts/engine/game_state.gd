class_name GameState
extends RefCounted

var tick: int = 0
var rng: Rng
var metrics: Dictionary = {}
var characters: Dictionary = {}
var council: Dictionary = {}
## Role-to-role edges; shape and mutation API in RelationshipGraph.
var relationships: Array = []
## Facts and who knows them; shape and API in KnowledgeBase.
var knowledge: Dictionary = {}
## Character creation (main menu): {"first_name", "family_name", "flag"}.
## Applied by apply_player_setup; kept so saves restore the chosen identity.
var player_setup: Dictionary = {}
## Where the player stands (data/locations.csv). Moving within a region is
## free (LocationSystem); saved with everything else.
var current_location: String = LocationSystem.DEFAULT_LOCATION
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
	s.characters = CharacterFactory.build_roster(data)
	for id in s.characters:
		if s.characters[id].seat != "":
			s.council[s.characters[id].seat] = id
	s.relationships = RelationshipGraph.init_from_data(data)
	s.knowledge = KnowledgeBase.init_from_data(data, s)
	return s

## Applies the player's chosen identity: the player's display name becomes
## "King <first> <family>", and the royal family name is inherited by every
## role of the player's house (family_name match), in both their family_name
## and display_name. Deterministic string work only — no RNG.
func apply_player_setup(setup: Dictionary) -> void:
	player_setup = setup.duplicate(true)
	var first := String(setup.get("first_name", "")).strip_edges()
	var family := String(setup.get("family_name", "")).strip_edges()
	if first == "" and family == "":
		return
	var you: Character = characters.get("you")
	if you == null:
		return
	var old_family := you.family_name
	if first == "":
		first = you.display_name.get_slice(" ", 1)
	if family == "":
		family = old_family
	for id in characters:
		var c: Character = characters[id]
		if c.family_name == old_family and old_family != "":
			c.family_name = family
			c.display_name = c.display_name.replace(old_family, family)
	you.family_name = family
	you.display_name = "King %s %s" % [first, family]

func season() -> String:
	# Delegates to Calendar so tick 1..24 is year 1 with 6 ticks per season
	# (fixes the old 0-based off-by-one where tick 24 read as spring, year 2).
	return Calendar.season_name(tick).to_lower()

func year() -> int:
	return Calendar.year_of(tick)

## Godot 4.7.1 has a verified engine bug: JSON.parse_string(JSON.stringify(x,
## "", true, true)) mis-decodes a meaningful fraction of float64 values by
## exactly 1 ULP (independently confirmed: ~30% of a 10k-sample random-double
## corpus round-tripped to a different bit pattern). JSON's own float
## formatting/parsing cannot be trusted for save determinism, so every
## numeric leaf is instead round-tripped as a hex-encoded byte string
## (mirrors how Rng.to_dict already string-encodes its state "to preserve
## precision"), which IS bit-exact (0/10000 mismatches on the same corpus).
const _ENCODED_FLOAT_LEN := 17 # "f" + 16 hex nibbles of a float64

static func _float_to_hex(v: float) -> String:
	return PackedFloat64Array([v]).to_byte_array().hex_encode()

static func _hex_to_float(s: String) -> float:
	return s.hex_decode().decode_double(0)

## True iff s is exactly "f" followed by 16 lowercase hex digits — the shape
## produced by _encode_values below. Strict on purpose: game content strings
## (event ids, reasons, trait names) never accidentally match this 17-char
## shape, but the decoder checks anyway rather than assuming.
static func _is_encoded_float(s: String) -> bool:
	if s.length() != _ENCODED_FLOAT_LEN or s.unicode_at(0) != 102: # 'f'
		return false
	for i in range(1, _ENCODED_FLOAT_LEN):
		var c := s.unicode_at(i)
		var is_digit := c >= 48 and c <= 57 # '0'-'9'
		var is_lower_hex := c >= 97 and c <= 102 # 'a'-'f'
		if not (is_digit or is_lower_hex):
			return false
	return true

## Recursively encodes every int/float leaf in an arbitrarily-nested
## Dictionary/Array/scalar as a bit-exact hex string, replacing the old
## _normalize_ints (which only cast int->float and left the float encoding
## to JSON, exactly the code path the ULP bug lives in). Strings pass
## through unchanged.
static func _encode_values(value):
	if value is Dictionary:
		var out := {}
		for k in value:
			out[k] = _encode_values(value[k])
		return out
	elif value is Array:
		var out := []
		for v in value:
			out.append(_encode_values(v))
		return out
	elif typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return "f" + _float_to_hex(float(value))
	return value

## Inverse of _encode_values: recursively decodes hex-encoded float strings
## back to float, leaves everything else (plain strings, bools, already-
## nested structures) untouched.
static func _decode_values(value):
	if value is Dictionary:
		var out := {}
		for k in value:
			out[k] = _decode_values(value[k])
		return out
	elif value is Array:
		var out := []
		for v in value:
			out.append(_decode_values(v))
		return out
	elif value is String and _is_encoded_float(value):
		return _hex_to_float(value.substr(1))
	return value

## Bump when the save shape changes incompatibly; from_dict refuses saves
## newer than it knows (write the matching migration when bumping).
const SAVE_VERSION := 1

func to_dict() -> Dictionary:
	var chars := {}
	for id in characters:
		chars[id] = characters[id].to_dict()
	return {
		"version": SAVE_VERSION,
		"tick": _encode_values(tick), "rng": rng.to_dict(),
		"metrics": _encode_values(metrics.duplicate()),
		"characters": chars, "council": council.duplicate(),
		"relationships": _encode_values(relationships.duplicate(true)),
		"knowledge": _encode_values(knowledge.duplicate(true)),
		"player_setup": player_setup.duplicate(true),
		"current_location": current_location,
		"cooldowns": _encode_values(cooldowns.duplicate()),
		"recent_outcomes": _encode_values(recent_outcomes.duplicate(true)),
		"promises": _encode_values(promises.duplicate(true)),
		"event_state": _encode_values(event_state.duplicate(true)),
		"pending_event": _encode_values(pending_event.duplicate(true)),
	}

static func from_dict(d: Dictionary) -> GameState:
	# Pre-versioning saves carry no field and count as version 1. A newer
	# save fails closed (null) rather than half-loading; push_warning (not
	# push_error) so the refusal path stays testable under run_tests.sh's
	# exact engine-error count.
	if int(d.get("version", 1)) > SAVE_VERSION:
		push_warning("GameState: save version %d is newer than this build's %d"
			% [int(d.get("version", 1)), SAVE_VERSION])
		return null
	var s := GameState.new()
	s.tick = int(_decode_values(d["tick"]))
	s.rng = Rng.from_dict(d["rng"])
	s.metrics = _decode_values(d["metrics"])
	for id in d["characters"]:
		s.characters[id] = Character.from_dict(d["characters"][id])
	s.council = d["council"].duplicate()
	s.relationships = _decode_values(d.get("relationships", []))
	s.knowledge = _decode_values(d.get("knowledge", {}))
	s.player_setup = d.get("player_setup", {}).duplicate(true)
	s.current_location = String(d.get("current_location", LocationSystem.DEFAULT_LOCATION))
	var decoded_cooldowns = _decode_values(d["cooldowns"])
	for k in decoded_cooldowns:
		s.cooldowns[k] = int(decoded_cooldowns[k])
	s.recent_outcomes = _decode_values(d["recent_outcomes"])
	s.promises = _decode_values(d["promises"])
	s.event_state = _decode_values(d.get("event_state", {
		"cooldowns": {}, "once": [], "pity": 0, "scheduled": [],
		"flags": [], "last_action_tick": {},
	}))
	s.pending_event = _decode_values(d.get("pending_event", {}))
	return s
