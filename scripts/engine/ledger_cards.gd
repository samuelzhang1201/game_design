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
	var t := Ledger.type_of(node_id)
	var row := Ledger.type_row(repo, t)
	if String(row.get("status", "")) == "planned":
		lines.append("Not yet built (%s). %s" % [row["milestone"], String(row.get("notes", ""))])
	for l: Dictionary in snap.get("links", []):
		if String(l["from"]) != node_id and String(l["to"]) != node_id:
			continue
		lines.append(_line(repo, state, l, node_id, int(snap.get("day", 0))))
	return {"title": LedgerResolvers.label_of(repo, state, node_id), "lines": lines}


static func thread_entry(repo: DataRepository, state: GameState, link: Dictionary) -> Dictionary:
	var title := "%s %s %s" % [LedgerResolvers.label_of(repo, state, String(link["from"])), link["verb"],
		LedgerResolvers.label_of(repo, state, String(link["to"]))]
	var lines: Array[String] = []
	if String(link["status"]) == "planned":
		var milestone := String(Ledger.link_row(repo, String(link["type"])).get("milestone", ""))
		lines.append("Not yet built (%s): %s" % [milestone, link["planned_note"]])
	for acc: Dictionary in link["accounts"]:
		lines.append(_account(acc, state.absolute_day()))
	if String(link["governor"]) != "":
		var c: Character = state.characters.get(String(link["governor"]))
		if c != null:
			lines.append("Governed by " + c.display_name)
	return {"title": title, "lines": lines}


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
	var head := ("%s %s" % [l["verb"], other]) if outward else ("%s: %s" % [other, l["verb"]])
	if String(l["status"]) == "planned":
		return "%s — not yet built" % head
	var accs: Array = l["accounts"]
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
