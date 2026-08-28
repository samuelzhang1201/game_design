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
	# Normalize numeric dictionaries to float for canonical JSON serialization
	# (JSON round-trips ints as floats, so we cast consistently)
	var normalized_attributes := {}
	for k in attributes:
		normalized_attributes[k] = float(attributes[k])
	var normalized_skills := {}
	for k in skills:
		normalized_skills[k] = float(skills[k])
	var normalized_ideology := {}
	for k in ideology:
		normalized_ideology[k] = float(ideology[k])
	var normalized_log := []
	for entry in opinion_log:
		normalized_log.append({
			"tick": float(entry["tick"]),
			"delta": float(entry["delta"]),
			"reason": entry["reason"],
		})
	return {
		"id": id, "display_name": display_name, "seat": seat,
		"attributes": normalized_attributes, "skills": normalized_skills,
		"ideology": normalized_ideology, "traits": traits.duplicate(),
		"opinion": float(opinion), "opinion_log": normalized_log,
		"flags": flags.duplicate(),
	}

static func from_dict(d: Dictionary) -> Character:
	var c := Character.new()
	c.id = d["id"]; c.display_name = d["display_name"]; c.seat = d["seat"]
	c.attributes = d["attributes"].duplicate(); c.skills = d["skills"].duplicate()
	c.ideology = d["ideology"].duplicate(); c.traits = d["traits"].duplicate()
	c.opinion = int(d["opinion"]); c.opinion_log = d["opinion_log"].duplicate(true)
	c.flags = d.get("flags", []).duplicate()
	return c
