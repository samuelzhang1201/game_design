class_name Character
extends RefCounted

var id: String = ""
var display_name: String = ""
var seat: String = ""
var attributes: Dictionary = {}
var skills: Dictionary = {}
var ideology: Dictionary = {}
var traits: Array = []
var opinion: int = 0
var opinion_log: Array = []
var flags: Array = []

func change_opinion(delta: int, reason: String, tick: int) -> void:
	opinion = clampi(opinion + delta, -100, 100)
	opinion_log.append({"tick": tick, "delta": delta, "reason": reason})

func to_dict() -> Dictionary:
	# Route every numeric field through GameState's hex-encoding walkers so
	# floats survive JSON serialization bit-exactly (Godot 4.7.1 JSON
	# float round-trip has a verified ~1-ULP bug; see GameState._encode_values).
	return {
		"id": id, "display_name": display_name, "seat": seat,
		"attributes": GameState._encode_values(attributes.duplicate()),
		"skills": GameState._encode_values(skills.duplicate()),
		"ideology": GameState._encode_values(ideology.duplicate()),
		"traits": traits.duplicate(),
		"opinion": GameState._encode_values(opinion),
		"opinion_log": GameState._encode_values(opinion_log.duplicate(true)),
		"flags": flags.duplicate(),
	}

static func from_dict(d: Dictionary) -> Character:
	var c := Character.new()
	c.id = d["id"]; c.display_name = d["display_name"]; c.seat = d["seat"]
	c.attributes = GameState._decode_values(d["attributes"])
	c.skills = GameState._decode_values(d["skills"])
	c.ideology = GameState._decode_values(d["ideology"])
	c.traits = d["traits"].duplicate()
	c.opinion = int(GameState._decode_values(d["opinion"]))
	c.opinion_log = GameState._decode_values(d["opinion_log"])
	c.flags = d.get("flags", []).duplicate()
	return c
