# scripts/engine/ledger.gd
class_name Ledger
extends RefCounted
## The LEDGER — the realm's ontology (spec 2026-09-30-ledger-ontology-design).
## Rows of data/ledger_*.csv checked as a schema, and (Task 4) turned with
## the live state into the picture the LEDGER screen draws. It reads, never
## writes; it draws no RNG and reads no clock.

const LAYERS := ["things", "people", "know"]   # bottom to top
const STATUSES := ["live", "planned"]


static func type_row(repo: DataRepository, type_id: String) -> Dictionary:
	for r: Dictionary in repo.ledger_types:
		if String(r["type_id"]) == type_id:
			return r
	return {}


static func link_row(repo: DataRepository, link_id: String) -> Dictionary:
	for r: Dictionary in repo.ledger_links:
		if String(r["link_id"]) == link_id:
			return r
	return {}


static func type_of(node_id: String) -> String:
	if node_id.contains("|"):
		return ""
	if node_id.begins_with("type:"):
		return node_id.substr(5)
	return node_id.get_slice(":", 0)


static func in_lens(row: Dictionary, lens: String) -> bool:
	return lens in String(row["lenses"]).split("|", false)


static func validate(repo: DataRepository) -> Array[String]:
	var errors: Array[String] = []
	var lenses := {}
	for l: Dictionary in repo.ledger_lenses:
		lenses[String(l["lens"])] = l
	var types := {}
	for r: Dictionary in repo.ledger_types:
		var id := String(r["type_id"])
		types[id] = r
		if not String(r["layer"]) in LAYERS:
			errors.append("%s: unknown layer %s" % [id, r["layer"]])
		_check_status(errors, id, r)
		_check_lenses(errors, id, r, lenses)
		if String(r["instances"]) != "" and not LedgerResolvers.has_instances(String(r["instances"])):
			errors.append("%s: unknown instance list %s" % [id, r["instances"]])
	for lens: String in lenses:
		var it := String(lenses[lens]["instance_type"])
		if it != "" and not types.has(it):
			errors.append("lens %s: unknown instance type %s" % [lens, it])
	var links := {}
	for r: Dictionary in repo.ledger_links:
		var id := String(r["link_id"])
		links[id] = r
		_check_status(errors, id, r)
		_check_lenses(errors, id, r, lenses)
		for end in ["from_type", "to_type"]:
			if not types.has(String(r[end])):
				errors.append("%s: unknown type %s" % [id, r[end]])
		if String(r["status"]) == "live":
			if not LedgerResolvers.has(String(r["resolver"])):
				errors.append("%s: live without a reader" % id)
			for end in ["from_type", "to_type"]:
				if String((types.get(String(r[end]), {}) as Dictionary).get("status", "")) == "planned":
					errors.append("%s: live on a planned type" % id)
		var seat := String(r["governor_seat"])
		if seat != "" and not repo.seats.has(seat):
			errors.append("%s: unknown seat %s" % [id, seat])
		if not String(r["governor_kind"]) in ["", "seat", "faction"]:
			errors.append("%s: unknown governor kind %s" % [id, r["governor_kind"]])
	for a: Dictionary in repo.ledger_actions:
		var code := String(a["action_code"])
		if not types.has(String(a["target"])) and not links.has(String(a["target"])):
			errors.append("%s: unknown target %s" % [code, a["target"]])
		if not repo.actions.has(code):
			errors.append("%s: unknown action" % code)
		elif not repo.order_costs.has(code):
			errors.append("%s: no order_costs row (invariant 8)" % code)
	for lp: Dictionary in repo.ledger_loops:
		for l: String in String(lp["links"]).split("|", false):
			if not links.has(l):
				errors.append("loop %s: unknown link %s" % [lp["loop_id"], l])
		if not String(lp["kind"]) in ["virtuous", "vicious"]:
			errors.append("loop %s: unknown kind %s" % [lp["loop_id"], lp["kind"]])
	return errors


static func _check_status(errors: Array[String], id: String, r: Dictionary) -> void:
	if not String(r["status"]) in STATUSES:
		errors.append("%s: unknown status %s" % [id, r["status"]])
	if String(r["status"]) == "planned" and String(r["milestone"]) == "":
		errors.append("%s: planned without a milestone" % id)


static func _check_lenses(errors: Array[String], id: String, r: Dictionary, lenses: Dictionary) -> void:
	for l: String in String(r["lenses"]).split("|", false):
		if not lenses.has(l):
			errors.append("%s: unknown lens %s" % [id, l])


# --- the picture -----------------------------------------------------------

## The picture of one lens (spec §6-§7). focus is {} (the type level, or the
## lens's own instances for a lens with an instance_type: the court) or
## {"id": node id} (that instance's ego network). A focus that no longer
## exists falls back to the type level with focus_lost set.
static func snapshot(repo: DataRepository, state: GameState, lens: String, focus: Dictionary) -> Dictionary:
	var out := {"lens": lens, "focus_id": "", "focus_lost": false, "day": state.absolute_day(),
		"nodes": [], "links": [], "loops": []}
	var focus_id := String(focus.get("id", ""))
	if focus_id != "" and not exists(repo, state, focus_id):
		out["focus_lost"] = true
		focus_id = ""
	var inst_type := ""
	for l: Dictionary in repo.ledger_lenses:
		if String(l["lens"]) == lens:
			inst_type = String(l["instance_type"])
	if focus_id != "":
		out["focus_id"] = focus_id
		_ego(repo, state, lens, focus_id, out)
	elif inst_type != "":
		_all_instances(repo, state, lens, inst_type, out)
	else:
		_type_level(repo, state, lens, out)
	_loops(repo, state, out)
	return out


static func exists(repo: DataRepository, state: GameState, node_id: String) -> bool:
	if node_id.begins_with("type:"):
		return not type_row(repo, node_id.substr(5)).is_empty()
	return LedgerResolvers.label_of(repo, state, node_id) != ""


static func _type_level(repo: DataRepository, state: GameState, lens: String, out: Dictionary) -> void:
	var shown := {}
	for r: Dictionary in repo.ledger_types:
		if not in_lens(r, lens):
			continue
		shown[String(r["type_id"])] = true
		var node := _node(repo, state, "type:" + String(r["type_id"]))
		node["x"] = float(r["x"])
		node["z"] = float(r["z"])
		out["nodes"].append(node)
	for r: Dictionary in repo.ledger_links:
		if not in_lens(r, lens) or not shown.has(String(r["from_type"])) or not shown.has(String(r["to_type"])):
			continue
		if String(r["from_type"]) == String(r["to_type"]):
			continue  # a tie between two of one type is drawn between instances only
		if String(r["status"]) == "planned":
			out["links"].append(_planned(state, r))
			continue
		for t: Dictionary in LedgerResolvers.run(r, repo, state, {}):
			out["links"].append(_believed(repo, state, r, t))


static func _all_instances(repo: DataRepository, state: GameState, lens: String, inst_type: String,
		out: Dictionary) -> void:
	var list := String(type_row(repo, inst_type).get("instances", ""))
	for row: Dictionary in LedgerResolvers.instances(list, repo, state):
		out["nodes"].append(_node(repo, state, String(row["id"])))
	for r: Dictionary in repo.ledger_links:
		if String(r["status"]) != "live" or not in_lens(r, lens):
			continue
		if String(r["from_type"]) != inst_type or String(r["to_type"]) != inst_type:
			continue
		for t: Dictionary in LedgerResolvers.run(r, repo, state, {"all": true}):
			out["links"].append(_believed(repo, state, r, t))


static func _ego(repo: DataRepository, state: GameState, lens: String, focus_id: String, out: Dictionary) -> void:
	var ftype := type_of(focus_id)
	var seen := {focus_id: true}
	out["nodes"].append(_node(repo, state, focus_id))
	var cap := int(repo.bal("ledger_instance_cap"))
	for r: Dictionary in repo.ledger_links:
		if String(r["status"]) != "live" or not in_lens(r, lens):
			continue
		if String(r["from_type"]) != ftype and String(r["to_type"]) != ftype:
			continue
		var found: Array = LedgerResolvers.run(r, repo, state, {"id": focus_id}).filter(
			func(t: Dictionary) -> bool: return String(t["from"]) == focus_id or String(t["to"]) == focus_id)
		for i in found.size():
			var t: Dictionary = found[i]
			var outward := String(t["from"]) == focus_id
			if i == cap:
				var more := "more:%s:%d" % [r["link_id"], found.size() - cap]
				var other_type := String(r["to_type"]) if outward else String(r["from_type"])
				out["nodes"].append({"id": more, "type": "more", "label": LedgerResolvers.label_of(repo, state, more),
					"layer": String(type_row(repo, other_type)["layer"]), "status": "live", "milestone": "",
					"instance": true})
				var folded := {"from": focus_id if outward else more, "to": more if outward else focus_id,
					"flow": -1, "subj": {}, "key": "count"}
				out["links"].append(_believed(repo, state, r, folded))
				break
			var other := String(t["to"]) if outward else String(t["from"])
			if not seen.has(other):
				seen[other] = true
				out["nodes"].append(_node(repo, state, other))
			out["links"].append(_believed(repo, state, r, t))


static func _node(repo: DataRepository, state: GameState, id: String) -> Dictionary:
	var t := type_of(id)
	var row := type_row(repo, t)
	return {"id": id, "type": t, "label": LedgerResolvers.label_of(repo, state, id),
		"layer": String(row.get("layer", "things")), "status": String(row.get("status", "live")),
		"milestone": String(row.get("milestone", "")), "instance": not id.begins_with("type:")}


static func _planned(state: GameState, r: Dictionary) -> Dictionary:
	var from := "type:" + String(r["from_type"])
	var to := "type:" + String(r["to_type"])
	return {"id": "%s|%s|%s" % [r["link_id"], from, to], "type": String(r["link_id"]), "verb": String(r["verb"]),
		"from": from, "to": to, "status": "planned", "flow": null, "accounts": [],
		"governor": _governor(state, r), "planned_note": String(r["planned_note"]), "sentiment": 0}


static func _believed(repo: DataRepository, state: GameState, r: Dictionary, t: Dictionary) -> Dictionary:
	var acc := _account(repo, state, t)
	return {"id": "%s|%s|%s" % [r["link_id"], t["from"], t["to"]], "type": String(r["link_id"]),
		"verb": String(r["verb"]), "from": String(t["from"]), "to": String(t["to"]), "status": "live",
		"flow": acc["value"], "accounts": [acc], "governor": _governor(state, r), "planned_note": "",
		"sentiment": int(t.get("sentiment", 0))}


## The truth turned into what the crown has been told (Intel is the one
## gate). A figure the crown only has in words has no value: the view draws
## its thread at a fixed vague width and fainter ink. A TIE (flow < 0) is
## structural, never a figure — it never asks Intel for a magnitude word
## (fix round 1: `Intel.fact` on -1 fell through to `magnitude()`'s "a
## handful", a bogus quantity on a yes/no tie); its value stays -1 (not
## null) so the view keeps drawing it at base width.
static func _account(repo: DataRepository, state: GameState, t: Dictionary) -> Dictionary:
	var subj: Dictionary = t["subj"]
	var flow := int(t["flow"])
	var lvl := "full" if subj.is_empty() else Intel.level(repo, state, subj)
	if flow < 0:
		return {"value": -1, "text": "", "source": "own records" if lvl == "full" else "common knowledge",
			"day": state.absolute_day(), "level": lvl}
	if subj.is_empty():
		return {"value": flow, "text": Intel.num(flow), "source": "own records",
			"day": state.absolute_day(), "level": "full"}
	var f := Intel.fact(repo, state, subj, String(t["key"]), flow)
	return {"value": flow if lvl == "full" else null, "text": String(f["text"]),
		"source": String(f["source"]), "day": int(f["day"]), "level": lvl}


static func _governor(state: GameState, r: Dictionary) -> String:
	var seat := String(r["governor_seat"])
	return "" if seat == "" else String(state.council.get(seat, ""))


static func _loops(repo: DataRepository, state: GameState, out: Dictionary) -> void:
	for lp: Dictionary in repo.ledger_loops:
		var members: Array[String] = []
		var built := true
		for l: String in String(lp["links"]).split("|", false):
			members.append(l)
			if String(link_row(repo, l).get("status", "planned")) != "live":
				built = false
		out["loops"].append({"id": String(lp["loop_id"]), "kind": String(lp["kind"]), "links": members,
			"running": built and TriggerDsl.evaluate(String(lp["running"]), state, repo)})


# --- orders ------------------------------------------------------------------

## The orders a sphere or a thread offers (data/ledger_actions.csv). A type
## with an instance list takes its orders per instance; a type without one
## (a pool) takes them on its type sphere; a thread takes its link's rows.
static func actions_for(repo: DataRepository, node_id: String) -> Array:
	var target := node_id.get_slice("|", 0) if node_id.contains("|") else type_of(node_id)
	var on_type := node_id.begins_with("type:")
	var has_list := String(type_row(repo, target).get("instances", "")) != ""
	var out: Array = []
	for a: Dictionary in repo.ledger_actions:
		if String(a["target"]) != target:
			continue
		if not node_id.contains("|") and on_type == has_list:
			continue  # an instance order on a type sphere, or a pool order on an instance
		out.append({"code": String(a["action_code"]), "label": String(a["label"]),
			"params": String(a["params"]), "needs_map": String(a["needs_map"]) == "1"})
	return out


static func params_of(row: Dictionary, node_id: String) -> Dictionary:
	var out := {}
	var own := node_id.substr(node_id.get_slice(":", 0).length() + 1)
	for pair: String in String(row["params"]).split("|", false):
		var k := pair.get_slice("=", 0)
		var v := pair.get_slice("=", 1)
		if v == "@id":
			out[k] = int(own) if own.is_valid_int() else own  # a manor's cell is a number
		elif v.is_valid_int():
			out[k] = int(v)
		else:
			out[k] = v
	return out


## An order's line in the menu: its label with the params filled in
## ("Buy {gold} gold of civil goods" -> "Buy 50 gold of civil goods"), then
## what order_costs.csv charges. An order that spends a sum of its own names
## that sum in its label, so the charge is written as the fee beside it;
## any other order writes its charge as its cost.
static func order_text(repo: DataRepository, row: Dictionary, node_id: String) -> String:
	var params := params_of(row, node_id)
	var text := String(row["label"]).format(params)
	var fee := absi(int(OrderCosts.gold_of(repo, String(row["code"]))))
	if fee == 0:
		return text
	return text + ("  (+%d fee)" % fee if params.has("gold") else "  (%d gold)" % fee)
