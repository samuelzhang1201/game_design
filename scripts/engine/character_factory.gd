class_name CharacterFactory
extends RefCounted

const ATTRS := ["ambition","loyalty","integrity","boldness","piety","compassion","vanity","temper"]
const SKILLS := ["sk_admin","sk_martial","sk_intrigue","sk_diplomacy","sk_steward"]
const AXES := ["centralism","militarism","orthodoxy","tax_incidence","expansionism"]

static func build_founding(data: DataRepository) -> Dictionary:
	var out := {}
	for row in data.founding:
		out[row["id"]] = build(row, data)
	return out

static func build(row: Dictionary, data: DataRepository) -> Character:
	var c := Character.new()
	c.id = row["id"]; c.display_name = row["display_name"]; c.seat = row["seat"]
	for a in ATTRS:
		c.attributes[a] = int(row[a])
	c.attributes["pragmatism"] = int(row["pragmatism"])
	for sk in SKILLS:
		c.skills[sk] = int(row[sk])
	for ax in AXES:
		c.ideology[ax] = int(row[ax])
	c.ideology["policy_sensitivity"] = int(row["policy_sensitivity"])
	c.opinion = int(row["opinion"])
	c.traits = Array(row["traits"].split("|"))
	for t in c.traits:
		assert(data.traits.has(t), "unknown trait: " + t)
		var tr: Dictionary = data.traits[t]
		for a in ATTRS:
			c.attributes[a] = clampi(c.attributes[a] + int(tr[a]), 0, 100)
		for sk in SKILLS:
			c.skills[sk] = clampi(c.skills[sk] + int(tr[sk]), 0, 20)
	return c
