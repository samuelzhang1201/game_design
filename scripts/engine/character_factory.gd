class_name CharacterFactory
extends RefCounted

const ATTRS := ["ambition","loyalty","integrity","boldness","piety","compassion","vanity","temper"]
const SKILLS := ["sk_admin","sk_martial","sk_intrigue","sk_diplomacy","sk_steward"]
const AXES := ["centralism","militarism","orthodoxy","tax_incidence","expansionism"]
## Role-level 0-100 metrics (data/roles.csv columns; default 50 when a row
## predates them). Live in `attributes` beside the personality axes so they
## serialize and clamp identically.
const ROLE_METRICS := ["health","wealth","prestige","influence"]

static func build_founding(data: DataRepository) -> Dictionary:
	var out := {}
	for row in data.founding:
		out[row["id"]] = build(row, data)
	return out

## Founding council plus every extended role (data/roles.csv): player family,
## relatives, officers, nobles, enemies, foreign courts, celebrities.
static func build_roster(data: DataRepository) -> Dictionary:
	var out := build_founding(data)
	for row in data.roles:
		out[row["id"]] = build(row, data)
	return out

static func build(row: Dictionary, data: DataRepository) -> Character:
	var c := Character.new()
	c.id = row["id"]; c.display_name = row["display_name"]; c.seat = row["seat"]
	c.category = String(row.get("category", ""))
	c.family_name = String(row.get("family_name", ""))
	c.kingdom = String(row.get("kingdom", ""))
	for rm in ROLE_METRICS:
		c.attributes[rm] = int(row.get(rm, "50") if String(row.get(rm, "")) != "" else "50")
	# Personal data (game_story/chapter_0/game_start.md gives canonical ages).
	c.attributes["age"] = int(row.get("age", "40") if String(row.get("age", "")) != "" else "40")
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
		var trait_row: Dictionary = data.traits[t]
		for a in ATTRS:
			c.attributes[a] = clampi(c.attributes[a] + int(trait_row[a]), 0, 100)
		for sk in SKILLS:
			c.skills[sk] = clampi(c.skills[sk] + int(trait_row[sk]), 0, 20)
	return c
