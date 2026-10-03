class_name ManorBars
extends RefCounted
## What the MANORS bars show (owner 2026-10-04: 玩家自己省内的每个manor以柱状图显示
## 人口和财富。除非玩家探查清楚非自己掌控的地区，否则不显示): each manor's people
## and its wealth — its worth a month, tax and goods in gold — exact for every
## manor of a province the crown controls; for any other manor only once a
## CREDIBLE spy's report on that very manor has come in, as that report's
## estimate (its range and middle), never the truth. Pure: the 3D map's HUD
## draws the rows (Map3DHudManorBars).


## A manor's wealth a month, whole gold: what its line (ManorEconomy.line_of)
## pays in tax and makes in goods' worth, strategic and civil.
static func worth_of(line: Dictionary) -> int:
	return int(line.get("tax", 0)) + int(line.get("strategic", 0)) + int(line.get("civil", 0))


## Every manor the bars may show, in cell order:
## {cell, people, worth, estimate (bool), people_lo/hi, worth_lo/hi}; a scouted
## manor's worth is -1 when its report predates the worth fact.
static func rows(repo: DataRepository, state: GameState) -> Array:
	var out: Array = []
	if state == null:
		return out
	var seen: Dictionary = {}
	var everything := Intel.dev_all
	var provinces: Array = MapManors.controlled_provinces(repo, state)
	if everything:
		provinces = repo.world_table("political", "provinces").keys()
	for prov in provinces:
		for cell: int in MapManors.manors_of_province(repo, String(prov), state):
			if seen.has(cell):
				continue
			seen[cell] = true
			var line := RealmEconomy.line_of(repo, state, cell)
			var people := int(line.get("people", 0))
			var worth := worth_of(line)
			out.append({"cell": cell, "people": people, "worth": worth, "estimate": false,
				"people_lo": people, "people_hi": people, "worth_lo": worth, "worth_hi": worth})
	# the newest credible report on each other manor
	var reports: Dictionary = {}
	for m: Dictionary in state.missives:
		var subj: Dictionary = m.get("subject", {})
		if String(subj.get("kind", "")) != "manor" or String(m.get("column", "")) != "credible":
			continue
		var cell := int(subj.get("cell", -1))
		if cell < 0 or seen.has(cell):
			continue
		if not reports.has(cell) or int(m["id"]) > int(reports[cell]["id"]):
			reports[cell] = m
	var cells := reports.keys()
	cells.sort()
	for cell: int in cells:
		var f := {}
		for x: Dictionary in reports[cell]["facts"]:
			f[String(x["key"])] = x
		if not f.has("people"):
			continue
		var p: Dictionary = f["people"]
		var row := {"cell": cell, "estimate": true,
			"people_lo": int(p["lo"]), "people_hi": int(p["hi"]),
			"people": (int(p["lo"]) + int(p["hi"])) >> 1,
			"worth": -1, "worth_lo": -1, "worth_hi": -1}
		if f.has("worth"):
			var w: Dictionary = f["worth"]
			row["worth_lo"] = int(w["lo"])
			row["worth_hi"] = int(w["hi"])
			row["worth"] = (int(w["lo"]) + int(w["hi"])) >> 1
		out.append(row)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["cell"]) < int(b["cell"]))
	return out


## The tallest bar's figures among `rows` (the hi end of an estimate counts),
## so every bar is drawn against the same scale: {people, worth}, at least 1.
static func scale_of(rows_: Array) -> Dictionary:
	var p := 1
	var w := 1
	for r: Dictionary in rows_:
		p = maxi(p, int(r["people_hi"]))
		w = maxi(w, int(r["worth_hi"]))
	return {"people": p, "worth": w}


## The row for one manor, {} when the bars do not show it.
static func row_of(repo: DataRepository, state: GameState, cell: int) -> Dictionary:
	for r: Dictionary in rows(repo, state):
		if int(r["cell"]) == cell:
			return r
	return {}


## The bars' figures in words, for the manor's hover: exact for the crown's
## own land, "≈ lo–hi … (a spy's estimate)" for a scouted manor; "" for none.
static func words_of(r: Dictionary) -> String:
	if r.is_empty():
		return ""
	if not bool(r["estimate"]):
		return "%s people · %s gold a month" % [Intel.num(int(r["people"])),
			Intel.num(int(r["worth"]))]
	var text := "≈ %s–%s people" % [Intel.num(int(r["people_lo"])),
		Intel.num(int(r["people_hi"]))]
	if int(r["worth"]) >= 0:
		text += " · ≈ %s–%s gold a month" % [Intel.num(int(r["worth_lo"])),
			Intel.num(int(r["worth_hi"]))]
	return text + " (a spy's estimate)"
