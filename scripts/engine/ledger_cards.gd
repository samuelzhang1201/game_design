# scripts/engine/ledger_cards.gd
class_name LedgerCards
extends RefCounted
## What the LEDGER puts in the left column (spec 2026-09-30 §6.1): a thing
## the map already has a card for opens that card; anything else is a card
## of its threads, every figure with its source and its age. No numeric
## credibility (the intelligence ruling).


static func entry(repo: DataRepository, state: GameState, node_id: String, snap: Dictionary) -> Dictionary:
	var kind := node_id.get_slice(":", 0)
	var rest := node_id.substr(kind.length() + 1)
	match kind:
		"manor":
			return {"obj": {"kind": "manor", "cell": int(rest)}}
		"town":
			return {"obj": {"kind": "burg", "code": rest}}
		"regiment":
			return {"obj": {"kind": "army", "code": rest}}
		"courier":
			return {"obj": {"kind": "courier", "id": int(rest)}}
	var lines: Array[String] = []
	var written := LedgerResolvers.static_node(repo, node_id)
	if not written.is_empty() and String(written["note"]) != "":
		lines.append(String(written["note"]))
	var t := Ledger.type_of(node_id)
	var row := Ledger.type_row(repo, t)
	if String(row.get("status", "")) == "planned":
		lines.append("Not yet built (%s). %s" % [row["milestone"], String(row.get("notes", ""))])
	var head := _head(repo, state, kind, rest)
	if head != "":
		lines.append(head)
	var folds := _folds_line(repo, node_id, snap)
	if folds != "":
		lines.append(folds)
	# A governor's ties to each workshop or supply line fold into ONE line
	# per flow, carrying his factors (final review M4).
	var governs := {}
	for l: Dictionary in snap.get("links", []):
		if String(l["from"]) != node_id and String(l["to"]) != node_id:
			continue
		var gflow := _governed_flow(repo, l) if String(l["from"]) == node_id else ""
		if gflow != "":
			if not governs.has(gflow):
				governs[gflow] = lines.size()
				lines.append("")
			continue
		lines.append(_line(repo, state, l, node_id, int(snap.get("day", 0))))
	for gflow: String in governs:
		var n := 0
		for l: Dictionary in snap.get("links", []):
			if String(l["from"]) == node_id and _governed_flow(repo, l) == gflow:
				n += 1
		lines[int(governs[gflow])] = "governs %s (%d) — %s" % [
			String(repo.ledger_governance[gflow]["label"]), n, _factors_text(repo, state, gflow)]
	if kind == "character":
		# his record (GameState.records): what the crown has caught him at
		for rec in state.records.get(rest, []):
			lines.append(String(rec))
	return {"title": LedgerResolvers.label_of(repo, state, node_id), "lines": lines}


## The first line of a supply chain card (final review): a supply line's
## road — "from Walbover, 250 km, 15% lost on the way — flowing" — and a war workshop's
## rate ("Runs at half"). The crown's own depots: exact, like their threads.
static func _head(repo: DataRepository, state: GameState, kind: String, rest: String) -> String:
	match kind:
		"supply_line":
			if not state.regiments.has(rest) \
					or String(ArmySystem.regiment(repo, rest).get("is_naval", "0")) == "1":
				return ""  # a fleet has no supply line
			var line := SupplySystem.line_of(repo, state, rest)
			if String(line["town"]) == "":
				return ""
			var from := String((repo.burgs.get(String(line["town"]), {}) as Dictionary).get("label", line["town"]))
			@warning_ignore("integer_division")  # whole percent from per-mille
			return "from %s, %d km, %d%% lost on the way — %s" % [from, int(line["length_km"]),
				int(line["loss_permille"]) / 10, String(line["state"])]
		"workshop":
			if not rest.is_valid_int():
				return ""
			return "Runs " + WorkshopSystem.rate_word(repo, WorkshopSystem.rate_of(state, int(rest)))
		"trade_route":
			# M6: the route's state and its trade; closing it touches no treaty
			# yet (diplomacy is not state — the spec's no-op hook).
			for r: Dictionary in MarketSystem.routes(repo, state):
				if String(r["kingdom"]) == rest:
					return "%s — %s gold of exports a month in %d deals" % [
						"Open" if bool(r["open"]) else "Closed", Intel.num(int(r["value"])), int(r["deals"])]
			return ""
		"artisans":
			# Uncontrolled: no master of works, no card (final fix wave,
			# Minor2) — matches work_speed_permille's own plain 1000‰ there
			# and LedgerResolvers.label_of's "" (the focus falls back).
			if not repo.provinces.has(rest) or not MapManors.controlled_provinces(repo, state).has(rest):
				return ""
			@warning_ignore("integer_division")  # whole percent from per-mille
			return "Works go %d%% faster" % ((MapManors.work_speed_permille(repo, state, rest) - 1000) / 10)
	return ""


## What a province's star folds (spec 2026-09-30-ledger-galaxy-design §3:
## "for its size and its card"), named by the types' own labels in their
## table's order — "Folds 37 manors, 2 towns, 1 building" (a type's
## `label_one` for one of it) — or "" when it folds nothing.
static func _folds_line(repo: DataRepository, node_id: String, snap: Dictionary) -> String:
	var folded := {}
	for n: Dictionary in snap.get("nodes", []):
		if String(n["id"]) == node_id:
			folded = n.get("folded", {})
			break
	var parts: Array[String] = []
	for r: Dictionary in repo.ledger_types:
		var n := int(folded.get(String(r["type_id"]), 0))
		if n > 0:
			parts.append("%d %s" % [n, _type_words(r, n)])
	return "" if parts.is_empty() else "Folds " + ", ".join(parts)


## A type named for `n` of it: its label, or its `label_one` for one, in
## lower case ("manors", "1 town").
static func _type_words(row: Dictionary, n: int) -> String:
	var one := String(row.get("label_one", ""))
	return (one if n == 1 and one != "" else String(row["label"])).to_lower()


## "37 manors: " for a link the galaxy merged from 37 (its folded end's
## type named), "" for a link that stands for one.
static func _count_prefix(repo: DataRepository, l: Dictionary) -> String:
	var n := int(l.get("count", 1))
	if n <= 1:
		return ""
	var row := Ledger.link_row(repo, String(l["type"]))
	for end: String in ["from_type", "to_type"]:
		var t := Ledger.type_row(repo, String(row.get(end, "")))
		if String(t.get("fold_to", "")) != "":
			return "%d %s: " % [n, _type_words(t, n)]
	return "%d × " % n


static func thread_entry(repo: DataRepository, state: GameState, link: Dictionary) -> Dictionary:
	var title := "%s%s %s %s" % [_count_prefix(repo, link), LedgerResolvers.label_of(repo, state, String(link["from"])),
		link["verb"], LedgerResolvers.label_of(repo, state, String(link["to"]))]
	var lines: Array[String] = []
	if String(link["status"]) == "planned":
		var milestone := String(Ledger.link_row(repo, String(link["type"])).get("milestone", ""))
		lines.append("Not yet built (%s): %s" % [milestone, link["planned_note"]])
	if (link["accounts"] as Array).size() > 1:
		lines.append("Accounts differ:")
	for acc: Dictionary in link["accounts"]:
		lines.append(_account(acc, state.absolute_day()))
	if String(link["governor"]) != "":
		var c: Character = state.characters.get(String(link["governor"]))
		if c != null:
			lines.append("Governed by " + c.display_name)
	var flow := _governed_flow(repo, link)
	if flow != "":
		lines.append(_factors_line(repo, state, flow))
	return {"title": title, "lines": lines}


## A `governs` tie's factors (spec §4): how well he runs the flow, as a
## percentage, his skill, and his opinion when it holds him back — never
## whether he skims. "Runs it at 85% of what it could — skill 8".
static func _factors_line(repo: DataRepository, state: GameState, flow: String) -> String:
	var text := _factors_text(repo, state, flow)
	return text.substr(0, 1).to_upper() + text.substr(1)


## "runs it at 85% of what it could — skill 8"; an empty seat's flow "no one
## governs it: it runs at 60% of what it could" (final review M8).
static func _factors_text(repo: DataRepository, state: GameState, flow: String) -> String:
	var f := Governance.factors(repo, state, flow)
	@warning_ignore("integer_division")  # whole percent from per-mille
	var pct := int(f["efficiency"]) / 10
	if String(f["governor"]) == "":
		return "no one governs it: it runs at %d%% of what it could" % pct
	var why := "skill %d" % int(f["skill"])
	if bool(f["held_back"]):
		why += ", held back by his opinion of you (%d)" % int(f["opinion"])
	return "runs it at %d%% of what it could — %s" % [pct, why]


## The flow a `governs` link ties its governor to ("workshop",
## "supply_line", "trade_route"; "works" for a tie to the artisans), or ""
## for any other link.
static func _governed_flow(repo: DataRepository, link: Dictionary) -> String:
	var row := Ledger.link_row(repo, String(link["type"]))
	if String(row.get("resolver", "")) != "governs" or String(link["status"]) != "live":
		return ""
	return Governance.flow_of_type(repo, String(row["to_type"]))


static func subject_of(repo: DataRepository, state: GameState, node_id: String) -> Dictionary:
	var kind := node_id.get_slice(":", 0)
	var rest := node_id.substr(kind.length() + 1)
	match kind:
		"manor":
			var cell := int(rest)
			return MissiveLog.subject("manor", MapManors.code_of(repo, cell), cell,
				MapTerrain.cell_center(repo, repo.cells[cell]))
		"province", "peasants":
			var p: Dictionary = repo.provinces.get(rest, {})
			return {} if p.is_empty() else MissiveLog.subject("province", rest, -1,
				Vector2(float(p["center_x"]), float(p["center_y"])))
		"town":
			var b: Dictionary = repo.burgs.get(rest, {})
			return {} if b.is_empty() else MissiveLog.subject("burg", rest, -1, Vector2(float(b["x"]), float(b["y"])))
		"regiment":
			var reg := ArmySystem.regiment(repo, rest)
			return {} if reg.is_empty() else MissiveLog.subject("regiment", rest, -1,
				ArmySystem.position_of(repo, state, reg))
	return {}


static func _line(repo: DataRepository, state: GameState, l: Dictionary, node_id: String, today: int) -> String:
	var outward := String(l["from"]) == node_id
	var other := LedgerResolvers.label_of(repo, state, String(l["to"] if outward else l["from"]))
	var head := _count_prefix(repo, l) + (("%s %s" % [l["verb"], other]) if outward else ("%s: %s" % [other, l["verb"]]))
	if String(l["status"]) == "planned":
		return "%s — not yet built" % head
	var accs: Array = l["accounts"]
	if accs.size() > 1:  # L1: accounts that differ are all named
		var each: Array[String] = []
		for acc: Dictionary in accs:
			each.append(_account(acc, today))
		return "%s — accounts differ: %s" % [head, " / ".join(each)]
	return head if accs.is_empty() else "%s — %s" % [head, _account(accs[0], today)]


## "1,240 · own records" / "thousands · common knowledge, 3 days ago".
static func _account(acc: Dictionary, today: int) -> String:
	var text := String(acc["text"])
	var source := String(acc["source"])
	var age := today - int(acc["day"])
	var when := "" if age <= 0 else (", %d days ago" % age if age != 1 else ", yesterday")
	if text == "":
		return source + when
	return "%s · %s%s" % [text, source, when]
