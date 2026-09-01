class_name CharacterTools
extends RefCounted
## The "tools" a courtier can be called on to use, for the dossier's SKILLS
## tab (user request 2026-08-31). Two kinds, both read from the data CSVs:
## - kingdom tools: the seated minister's kingdom operations — their seat's
##   advises_on codes (council_seats.csv), shown only when the action is
##   actually implemented (present in the actions tables) so every listed
##   tool is a real call the game can make.
## - personal tools: person-to-person interactions available with any
##   courtier — court actions flagged personal=yes in
##   policy_actions_court_additions.csv.
## Labels are the CSVs' human-readable `label` column, never raw codes.

static func kingdom_tools(data: DataRepository, c: Character) -> Array:
	var out: Array = []
	if c == null or not data.seats.has(c.seat):
		return out
	for code in String(data.seats[c.seat]["advises_on"]).split("|", false):
		if data.actions.has(code):
			out.append({"code": String(code),
				"label": String(data.actions[code]["label"])})
	return out

## Same for every courtier; a code already listed among the character's
## kingdom tools is not repeated here.
static func personal_tools(data: DataRepository, c: Character) -> Array:
	var out: Array = []
	if c == null:
		return out
	var taken := {}
	for t in kingdom_tools(data, c):
		taken[t["code"]] = true
	for code in data.actions:
		var row: Dictionary = data.actions[code]
		if String(row.get("personal", "")) == "yes" and not taken.has(code):
			out.append({"code": String(code), "label": String(row["label"])})
	return out
