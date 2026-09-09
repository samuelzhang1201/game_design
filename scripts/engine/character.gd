class_name Character
extends RefCounted

var id: String = ""
var display_name: String = ""
var seat: String = ""
## Role taxonomy (data/roles.csv): player|family|relative|council|officer|
## noble|enemy|foreign|celebrity. Empty for pre-roster saves.
var category: String = ""
var family_name: String = ""
var kingdom: String = ""
var attributes: Dictionary = {}
var skills: Dictionary = {}
var ideology: Dictionary = {}
var traits: Array = []
var opinion: int = 0
var opinion_log: Array = []
## Every move of a role-level metric (health, wealth, prestige, influence),
## with its reason — the same rule as opinion_log.
var attribute_log: Array = []
var flags: Array = []

func change_opinion(delta: int, reason: String, tick: int) -> void:
	opinion = clampi(opinion + delta, -100, 100)
	opinion_log.append({"tick": tick, "delta": delta, "reason": reason})

## Role-level metrics move with a reason, like opinion: an attribute that
## changed without one is a number nobody can explain later.
func change_attribute(name: String, delta: int, reason: String, tick: int) -> void:
	attributes[name] = clampi(int(attributes.get(name, 50)) + delta, 0, 100)
	attribute_log.append({"tick": tick, "attribute": name, "delta": delta, "reason": reason})

func to_dict() -> Dictionary:
	# Route every numeric field through GameState's hex-encoding walkers so
	# floats survive JSON serialization bit-exactly (Godot 4.7.1 JSON
	# float round-trip has a verified ~1-ULP bug; see GameState._encode_values).
	return {
		"id": id, "display_name": display_name, "seat": seat,
		"category": category, "family_name": family_name, "kingdom": kingdom,
		"attributes": GameState._encode_values(attributes.duplicate()),
		"skills": GameState._encode_values(skills.duplicate()),
		"ideology": GameState._encode_values(ideology.duplicate()),
		"traits": traits.duplicate(),
		"opinion": GameState._encode_values(opinion),
		"opinion_log": GameState._encode_values(opinion_log.duplicate(true)),
		"attribute_log": GameState._encode_values(attribute_log.duplicate(true)),
		"flags": flags.duplicate(),
	}

static func from_dict(d: Dictionary) -> Character:
	var c := Character.new()
	c.id = d["id"]; c.display_name = d["display_name"]; c.seat = d["seat"]
	c.category = String(d.get("category", ""))
	c.family_name = String(d.get("family_name", ""))
	c.kingdom = String(d.get("kingdom", ""))
	c.attributes = GameState._decode_values(d["attributes"])
	c.skills = GameState._decode_values(d["skills"])
	c.ideology = GameState._decode_values(d["ideology"])
	c.traits = d["traits"].duplicate()
	c.opinion = int(GameState._decode_values(d["opinion"]))
	c.opinion_log = GameState._decode_values(d["opinion_log"])
	c.attribute_log = GameState._decode_values(d.get("attribute_log", []))
	c.flags = d.get("flags", []).duplicate()
	return c
