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
	# The month's plans are read once per snapshot, never across two
	# (LedgerResolvers' memo, fix round 1 of M3 Task 4).
	LedgerResolvers.begin_memo()
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
	LedgerResolvers.end_memo()
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
			out["links"].append(_planned(repo, state, r))
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
					"instance": true, "props": []})
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
		"milestone": String(row.get("milestone", "")), "instance": not id.begins_with("type:"),
		"props": LedgerResolvers.props_of(repo, state, id)}


static func _planned(repo: DataRepository, state: GameState, r: Dictionary) -> Dictionary:
	var from := "type:" + String(r["from_type"])
	var to := "type:" + String(r["to_type"])
	return {"id": "%s|%s|%s" % [r["link_id"], from, to], "type": String(r["link_id"]), "verb": String(r["verb"]),
		"from": from, "to": to, "status": "planned", "flow": null, "accounts": [],
		"governor": _governor(repo, state, r), "planned_note": String(r["planned_note"]), "sentiment": 0}


## A live link as the crown believes it. A governed flow's reader hands its
## `claims` (spec 2026-09-30-ledger-governors-design §4): the accounts are
## built from them, and the thread's flow is the first account's (the
## governor's word).
static func _believed(repo: DataRepository, state: GameState, r: Dictionary, t: Dictionary) -> Dictionary:
	var accs: Array = _claimed(repo, state, t) if t.has("claims") else [_account(repo, state, t)]
	return {"id": "%s|%s|%s" % [r["link_id"], t["from"], t["to"]], "type": String(r["link_id"]),
		"verb": String(r["verb"]), "from": String(t["from"]), "to": String(t["to"]), "status": "live",
		"flow": (accs[0] as Dictionary)["value"], "accounts": accs, "governor": _governor(repo, state, r),
		"planned_note": "", "sentiment": int(t.get("sentiment", 0))}


## The accounts of a governed flow (spec 2026-09-30-ledger-governors-design
## §4): each claim, then this month's audit's figure for this node (an audit
## is a snapshot of ITS month — a controller ruling of fix round 1; instance
## threads only: the type level keeps to the governor's word and the
## receiving count — a ruling of the plan); equal figures merge into one
## account naming every source. The crown's own books: every account is
## `full`.
static func _claimed(repo: DataRepository, state: GameState, t: Dictionary) -> Array:
	var today := state.absolute_day()
	var raw: Array = []
	for c: Dictionary in t["claims"]:
		raw.append({"value": int(c["value"]), "source": String(c["source"]), "day": today})
	var node := String(t["to"]) if String(t["from"]).begins_with("type:") else String(t["from"])
	var audit := _audit_figure(state, node)
	if not audit.is_empty():
		raw.append(audit)
	var out: Array = []
	for a: Dictionary in raw:
		var merged := false
		for o: Dictionary in out:
			if int(o["value"]) == int(a["value"]):
				o["source"] = String(o["source"]) + "; " + String(a["source"])
				merged = true
				break
		if not merged:
			out.append({"value": int(a["value"]), "text": Intel.num(int(a["value"])),
				"source": String(a["source"]), "day": int(a["day"]), "level": "full"})
	return out


## The newest audit letter's figure for `node` (an AuditWriter fact is keyed
## by the LEDGER node id) filed THIS month (the letter's `tick`), or {}.
static func _audit_figure(state: GameState, node: String) -> Dictionary:
	for i in range(state.missives.size() - 1, -1, -1):
		var m: Dictionary = state.missives[i]
		if String(m.get("kind", "")) != "audit" or int(m.get("tick", -1)) != state.tick:
			continue
		for f: Dictionary in m["facts"]:
			if String(f["key"]) == node and f.has("exact"):
				return {"value": int(f["exact"]), "source": "the audit of " + _date_words(int(m["day"])),
					"day": int(m["day"])}
	return {}


## "Spring 5, Year 1" for an absolute day (Calendar.date_string's words).
static func _date_words(abs_day: int) -> String:
	var d := maxi(abs_day, 1) - 1
	@warning_ignore("integer_division")  # whole months
	return Calendar.date_string(d / Calendar.DAYS_PER_TICK + 1, d % Calendar.DAYS_PER_TICK + 1)


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


## Who governs a link: for a link touching a governed flow (a type of
## data/ledger_governance.csv — the workshops, the supply lines) the man who
## governs it NOW, given or not (Governance.governor_of); otherwise its
## seat's holder.
static func _governor(repo: DataRepository, state: GameState, r: Dictionary) -> String:
	for end: String in ["from_type", "to_type"]:
		if repo.ledger_governance.has(String(r[end])):
			return Governance.governor_of(repo, state, String(r[end]))
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
## A row whose params name `character=@council` is generated from the
## council as it sits (spec 2026-09-30-ledger-governors-design §4): one row
## per councillor by seat, "<label> <name>", the flow's own governor left
## out; without a state there is no council to read, and no such row.
static func actions_for(repo: DataRepository, node_id: String, state: GameState = null) -> Array:
	var target := node_id.get_slice("|", 0) if node_id.contains("|") else type_of(node_id)
	var on_type := node_id.begins_with("type:")
	var has_list := String(type_row(repo, target).get("instances", "")) != ""
	var out: Array = []
	for a: Dictionary in repo.ledger_actions:
		if String(a["target"]) != target:
			continue
		if not node_id.contains("|") and on_type == has_list:
			continue  # an instance order on a type sphere, or a pool order on an instance
		var row := {"code": String(a["action_code"]), "label": String(a["label"]),
			"params": String(a["params"]), "needs_map": String(a["needs_map"]) == "1"}
		if String(row["params"]).contains("=@council"):
			if state != null:
				out.append_array(_per_councillor(repo, state, row))
			continue
		out.append(row)
	return out


static func _per_councillor(repo: DataRepository, state: GameState, row: Dictionary) -> Array:
	var flow := ""
	for pair: String in String(row["params"]).split("|", false):
		if pair.get_slice("=", 0) == "flow":
			flow = pair.get_slice("=", 1)
	var skip := Governance.governor_of(repo, state, flow) if flow != "" else ""
	var seats: Array = state.council.keys()
	seats.sort()
	var seen := {}
	var out: Array = []
	for seat: String in seats:
		var cid := String(state.council[seat])
		if cid == "" or cid == skip or seen.has(cid) or not state.characters.has(cid):
			continue
		seen[cid] = true
		var r := row.duplicate()
		r["label"] = "%s %s" % [row["label"], (state.characters[cid] as Character).display_name]
		r["params"] = String(row["params"]).replace("=@council", "=" + cid)
		out.append(r)
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
