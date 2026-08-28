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

func change_opinion(delta: int, reason: String, tick: int) -> void:
	opinion = clampi(opinion + delta, -100, 100)
	opinion_log.append({"tick": tick, "delta": delta, "reason": reason})

func to_dict() -> Dictionary:
	return {
		"id": id, "display_name": display_name, "seat": seat,
		"attributes": attributes.duplicate(), "skills": skills.duplicate(),
		"ideology": ideology.duplicate(), "traits": traits.duplicate(),
		"opinion": opinion, "opinion_log": opinion_log.duplicate(true),
	}

static func from_dict(d: Dictionary) -> Character:
	var c := Character.new()
	c.id = d["id"]; c.display_name = d["display_name"]; c.seat = d["seat"]
	c.attributes = d["attributes"].duplicate(); c.skills = d["skills"].duplicate()
	c.ideology = d["ideology"].duplicate(); c.traits = d["traits"].duplicate()
	c.opinion = int(d["opinion"]); c.opinion_log = d["opinion_log"].duplicate(true)
	return c
