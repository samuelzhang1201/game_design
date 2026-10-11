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
	var clusters := {}
	for c: Dictionary in repo.ledger_clusters:
		var cid := String(c["cluster"])
		clusters[cid] = true
		if not repo.ledger_palette.has(String(c["colour"])):
			errors.append("cluster %s: unknown colour %s" % [cid, c["colour"]])
		if not lenses.has(String(c["lens"])):
			errors.append("cluster %s: unknown lens %s" % [cid, c["lens"]])
	var governed := {}
	for flow: String in repo.ledger_governance:
		governed[String(repo.ledger_governance[flow]["ledger_type"])] = true
	for r: Dictionary in repo.ledger_types:
		var id := String(r["type_id"])
		if not clusters.has(String(r.get("cluster", ""))):
			errors.append("%s: unknown cluster %s" % [id, r.get("cluster", "")])
		# folding is open only as far as _province_code can place a star
		# (final review I3, option b)
		var fold := String(r.get("fold_to", ""))
		if fold != "" and not types.has(fold):
			errors.append("%s: folds into unknown type %s" % [id, fold])
		elif fold != "" and fold != FOLD_INTO:
			errors.append("%s: folds into %s; only a %s can be folded into" % [id, fold, FOLD_INTO])
		elif fold != "" and not PLACED.has(id):
			errors.append("%s: folds into a %s, but nothing places a %s in one" % [id, FOLD_INTO, id])
		if fold != "" and governed.has(id):
			errors.append("%s: a governed flow (ledger_governance.csv) must not fold" % id)
		if not String(r.get("star", "")) in ["pool", "instance"]:
			errors.append("%s: unknown star %s" % [id, r.get("star", "")])
	for r: Dictionary in repo.ledger_links:
		if not String(r.get("look", "")) in ["flow", "tie", "kin", "structure"]:
			errors.append("%s: unknown look %s" % [r["link_id"], r.get("look", "")])
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
	for n: Dictionary in repo.ledger_static_nodes:
		var tid := String(n["type_id"])
		if not types.has(tid):
			errors.append("static node %s: unknown type %s" % [n["node_id"], tid])
		elif String(types[tid]["instances"]) != "static":
			errors.append("static node %s: type %s does not list static instances" % [n["node_id"], tid])
		elif type_of(String(n["node_id"])) != tid:
			errors.append("static node %s: its id must begin %s:" % [n["node_id"], tid])
	for l: Dictionary in repo.ledger_static_links:
		var lid := String(l["link_id"])
		if not links.has(lid):
			errors.append("static link %s: unknown link type" % lid)
			continue
		if String(links[lid]["resolver"]) != "static":
			errors.append("static link %s: its link type is not read from the table" % lid)
		for end: String in ["from", "to"]:
			var want := String(links[lid]["from_type" if end == "from" else "to_type"])
			if type_of(String(l[end])) != want:
				errors.append("static link %s: %s %s is not a %s" % [lid, end, l[end], want])
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


## The whole realm as ONE picture (spec 2026-09-30-ledger-galaxy-design
## §3): every listed instance, every pool, every planned type as a ghost,
## and the links that are the union of their egos — read by a worklist that
## expands every node it finds EXCEPT a foldable one (a manor, building or
## town) outside a controlled or opened province. Then the fold: each
## foldable node not in an opened province becomes its province's, its links
## re-pointed there and merged (counted; flows summed within one Intel
## level). `opened` is a set of province codes. Nodes and links by id;
## `folded` maps each folded instance's id to its province's star id.
static func galaxy(repo: DataRepository, state: GameState, opened: Dictionary) -> Dictionary:
	var out := {"lens": "galaxy", "focus_id": "", "focus_lost": false, "day": state.absolute_day(),
		"nodes": [], "links": [], "loops": [], "folded": {}}
	LedgerResolvers.begin_memo()
	var controlled := {}
	for code: String in MapManors.controlled_provinces(repo, state):
		controlled[code] = true
	var nodes := {}
	var raw := {}
	var queue: Array = []
	# _fold_target / _province_code once per node id (fix round 1, IMPORTANT
	# 1b): the skip below and the fold loop each asked a busy id's province
	# afresh every time it turned up as an edge's end.
	var fold_cache := {}
	var fold_of := func(id: String) -> String:
		if not fold_cache.has(id):
			fold_cache[id] = _fold_target(repo, state, id, opened)
		return fold_cache[id]
	var prov_cache := {}
	var prov_of := func(id: String) -> String:
		if not prov_cache.has(id):
			prov_cache[id] = _province_code(repo, state, id)
		return prov_cache[id]
	for r: Dictionary in repo.ledger_types:
		var tid := String(r["type_id"])
		if String(r["status"]) == "planned":
			nodes["type:" + tid] = _galaxy_node(repo, state, "type:" + tid)
			continue
		var list := String(r["instances"])
		if list == "":
			if String(r["fold_to"]) == "":
				nodes["type:" + tid] = _galaxy_node(repo, state, "type:" + tid)
			continue
		for row: Dictionary in LedgerResolvers.instances(list, repo, state, tid):
			var id := String(row["id"])
			if not nodes.has(id):
				nodes[id] = _galaxy_node(repo, state, id)
				queue.append(id)
	# each type's live rows, once a read rather than a scan of every row per
	# node (Task 11 fix round 1, F7)
	var rows_of := {}
	for r: Dictionary in repo.ledger_links:
		if String(r["status"]) != "live":
			continue
		for end: String in [String(r["from_type"]), String(r["to_type"])]:
			var rows: Array = rows_of.get(end, [])
			if not rows.has(r):
				rows.append(r)
			rows_of[end] = rows
	var i := 0
	while i < queue.size():
		var id: String = queue[i]
		i += 1
		for r: Dictionary in rows_of.get(type_of(id), []):
			for l: Dictionary in LedgerResolvers.run(r, repo, state, {"id": id}):
				var a := String(l["from"])
				var b := String(l["to"])
				if a != id and b != id:
					continue
				var gone := false
				for e: String in [a, b]:
					if not nodes.has(e) and not e.begins_with("type:") \
							and LedgerResolvers.label_of(repo, state, e) == "":
						gone = true
				if gone:
					continue
				# a link both of whose ends fold to the same province is
				# dropped at the merge below (`a == b`) however it is
				# believed — skip believing it now (province -> its own
				# manors is most of the worklist's edges, and its belief is
				# never read).
				var fa: String = fold_of.call(a)
				var fb: String = fold_of.call(b)
				if (fa if fa != "" else a) != (fb if fb != "" else b):
					var bl := _believed(repo, state, r, l)
					raw[String(bl["id"])] = bl
				for e: String in [a, b]:
					if nodes.has(e):
						continue
					nodes[e] = _galaxy_node(repo, state, e)
					if _expands(repo, state, e, controlled, opened):
						queue.append(e)
	# a row between two types that have no instances (pool to pool) once
	for r: Dictionary in repo.ledger_links:
		if String(r["status"]) != "live":
			continue
		if not nodes.has("type:" + String(r["from_type"])) or not nodes.has("type:" + String(r["to_type"])):
			continue
		for l: Dictionary in LedgerResolvers.run(r, repo, state, {}):
			var bl := _believed(repo, state, r, l)
			raw[String(bl["id"])] = bl
	# the fold
	var fold := {}
	for id: String in nodes:
		var p: String = fold_of.call(id)
		if p != "":
			fold[id] = p
	for id: String in fold:
		var pid := String(fold[id])
		if not nodes.has(pid):
			nodes[pid] = _galaxy_node(repo, state, pid)
		var f: Dictionary = nodes[pid].get("folded", {})
		f[type_of(id)] = int(f.get(type_of(id), 0)) + 1
		nodes[pid]["folded"] = f
	for id: String in nodes:
		var fold_to := String(type_row(repo, type_of(id)).get("fold_to", ""))
		if fold_to != "" and not fold.has(id):
			nodes[id]["home_id"] = "province:" + String(prov_of.call(id))
	var merged := {}
	var keys: Array = raw.keys()
	keys.sort()
	for k: String in keys:
		var l: Dictionary = raw[k]
		var a := String(fold.get(String(l["from"]), String(l["from"])))
		var b := String(fold.get(String(l["to"]), String(l["to"])))
		if a == b:
			continue
		var mid := "%s|%s|%s" % [l["type"], a, b]
		if merged.has(mid):
			_merge_into(merged[mid], l)
		else:
			var m: Dictionary = l.duplicate(true)
			m["id"] = mid
			m["from"] = a
			m["to"] = b
			m["count"] = 1
			merged[mid] = m
	for id: String in fold:
		nodes.erase(id)
	# what each folded instance folded into (its province's star), for the
	# LEDGER's search: a folded manor is found by opening its province
	out["folded"] = fold
	# a planned row touching at least one ghost (planned) type (owner
	# ruling, fix round 1, IMPORTANT 2): its ghost end is its type sphere;
	# its other end is that type's pool sphere if one stands, else the
	# instance of that type with the most links in the galaxy (ties: lowest
	# id); the row is left out if neither end can be found. `commands` and
	# `contradicts` touch no ghost type and are never drawn.
	var link_counts := {}
	for lid: String in merged:
		var m: Dictionary = merged[lid]
		link_counts[String(m["from"])] = int(link_counts.get(String(m["from"]), 0)) + 1
		link_counts[String(m["to"])] = int(link_counts.get(String(m["to"]), 0)) + 1
	for r: Dictionary in repo.ledger_links:
		if String(r["status"]) != "planned":
			continue
		var from_ghost := String(type_row(repo, String(r["from_type"])).get("status", "live")) == "planned"
		var to_ghost := String(type_row(repo, String(r["to_type"])).get("status", "live")) == "planned"
		if not from_ghost and not to_ghost:
			continue
		var from_id := _planned_end(repo, nodes, link_counts, String(r["from_type"]))
		var to_id := _planned_end(repo, nodes, link_counts, String(r["to_type"]))
		if from_id == "" or to_id == "":
			continue
		var pl := _planned(repo, state, r)
		pl["id"] = "%s|%s|%s" % [r["link_id"], from_id, to_id]
		pl["from"] = from_id
		pl["to"] = to_id
		merged[String(pl["id"])] = pl
	var ids: Array = nodes.keys()
	ids.sort()
	for id: String in ids:
		out["nodes"].append(nodes[id])
	var lids: Array = merged.keys()
	lids.sort()
	for lid: String in lids:
		out["links"].append(merged[lid])
	_loops(repo, state, out)
	LedgerResolvers.end_memo()
	return out


## The node a planned row's `type_id` end draws as: its own ghost sphere if
## the type itself is planned, else that type's pool sphere if one stands
## in `nodes`, else the instance of that type with the most links (ties:
## the lowest id) — "" when nothing of that type stands at all.
static func _planned_end(repo: DataRepository, nodes: Dictionary, link_counts: Dictionary, type_id: String) -> String:
	if String(type_row(repo, type_id).get("status", "live")) == "planned":
		return "type:" + type_id
	if nodes.has("type:" + type_id):
		return "type:" + type_id
	var best := ""
	var best_n := -1
	var ids: Array = nodes.keys()
	ids.sort()
	for id: String in ids:
		if id.begins_with("type:") or type_of(id) != type_id:
			continue
		var n := int(link_counts.get(id, 0))
		if n > best_n:
			best_n = n
			best = id
	return best


static func _galaxy_node(repo: DataRepository, state: GameState, id: String) -> Dictionary:
	var n := _node(repo, state, id)
	n["cluster"] = String(type_row(repo, type_of(id)).get("cluster", "economy"))
	return n


## Whether the worklist reads a node's own ego: a foldable node only inside a
## controlled or opened province (elsewhere it only folds); a pool never
## (its links come from the other end).
static func _expands(repo: DataRepository, state: GameState, id: String, controlled: Dictionary,
		opened: Dictionary) -> bool:
	if id.begins_with("type:") or id.begins_with("more:"):
		return false
	if String(type_row(repo, type_of(id)).get("fold_to", "")) == "":
		return true
	var code := _province_code(repo, state, id)
	return controlled.has(code) or opened.has(code)


## The one type a node folds into (`fold_to`): its province's star.
const FOLD_INTO := "province"
## The types _province_code can place in a province — all that may fold
## (validate names any other foldable row).
const PLACED := ["manor", "building", "town"]


## The province a foldable node stands in (live state), or "".
static func _province_code(repo: DataRepository, state: GameState, id: String) -> String:
	var rest := id.substr(id.get_slice(":", 0).length() + 1)
	match type_of(id):
		"manor":
			return MapManors.province_of(repo, int(rest), state)
		"building":
			return MapManors.province_of(repo, int(rest.get_slice(":", 0)), state)
		"town":
			return LedgerResolvers.burg_province(repo, state, rest)
	return ""


## The province node a node folds into, or "" (not foldable, no province,
## its province is opened, or a type sphere — a `type:` id is never
## foldable, however its type_id happens to parse; fix round 1, M6).
static func _fold_target(repo: DataRepository, state: GameState, id: String, opened: Dictionary) -> String:
	if id.begins_with("type:"):
		return ""
	if String(type_row(repo, type_of(id)).get("fold_to", "")) == "":
		return ""
	var code := _province_code(repo, state, id)
	if code == "" or opened.has(code):
		return ""
	return "province:" + code


const _LEVELS := ["full", "general", "basic"]


## Adds a folded link into the one it merges with: one more counted; the
## flow sums only while both are figures at one Intel level — else the
## merged figure is words at the worse level (never words added to numbers).
## When the incoming link is the strictly worse one, its SOURCE travels with
## its words (fix round 1, M5: provenance follows the words) — a tie keeps
## the accumulator's own source, as it always has.
static func _merge_into(m: Dictionary, l: Dictionary) -> void:
	m["count"] = int(m["count"]) + 1
	var ma: Dictionary = (m["accounts"] as Array)[0]
	var la: Dictionary = (l["accounts"] as Array)[0] if not (l["accounts"] as Array).is_empty() else ma
	var from_la := _LEVELS.find(String(la["level"])) > _LEVELS.find(String(ma["level"]))
	var worse := String(la["level"]) if from_la else String(ma["level"])
	var f: Variant = null
	if m["flow"] != null and l["flow"] != null and String(ma["level"]) == String(la["level"]):
		var a := int(m["flow"])
		var b := int(l["flow"])
		f = -1 if a < 0 and b < 0 else maxi(a, 0) + maxi(b, 0)
	m["flow"] = f
	var text := String(ma["text"])
	var source := String(ma["source"])
	if f == null and from_la:
		text = String(la["text"])
		source = String(la["source"])
	elif f != null:
		text = Intel.num(int(f)) if int(f) >= 0 else ""
	m["accounts"] = [{"value": f, "text": text, "source": source,
		"day": mini(int(ma["day"]), int(la["day"])), "level": worse}]


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
	for row: Dictionary in LedgerResolvers.instances(list, repo, state, inst_type):
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
	var accs: Array = _claimed(repo, state, r, t) if t.has("claims") else [_account(repo, state, t)]
	if bool(t.get("vacant", false)):
		accs = [{"value": -1, "text": "", "source": "no one governs it", "day": state.absolute_day(),
			"level": "full"}]
	return {"id": "%s|%s|%s" % [r["link_id"], t["from"], t["to"]], "type": String(r["link_id"]),
		"verb": String(r["verb"]), "from": String(t["from"]), "to": String(t["to"]), "status": "live",
		"flow": (accs[0] as Dictionary)["value"], "accounts": accs, "governor": _governor(repo, state, r),
		"planned_note": "", "sentiment": int(t.get("sentiment", 0)), "vacant": bool(t.get("vacant", false))}


## The accounts of a governed flow (spec 2026-09-30-ledger-governors-design
## §4): each claim, then this month's audit's figure for this thread — an
## instance thread its node's fact, the type level the audit's total (final
## review M5) — equal figures merged into one account naming every source.
## The crown's own books: every account is `full`.
static func _claimed(repo: DataRepository, state: GameState, r: Dictionary, t: Dictionary) -> Array:
	var today := state.absolute_day()
	var raw: Array = []
	for c: Dictionary in t["claims"]:
		raw.append({"value": int(c["value"]), "source": String(c["source"]), "day": today})
	var flow := governed_flow(repo, r)
	var from := String(t["from"])
	var to := String(t["to"])
	var node := "total" if from.begins_with("type:") and to.begins_with("type:") \
		else (from if from.begins_with(Governance.type_of_flow(repo, flow) + ":") else to)
	var audit := _audit_figure(state, flow, node, int((t["claims"][0] as Dictionary)["value"]))
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


## The governed flow a link row touches ("workshop", "supply_line",
## "trade_route"; "works" for a link touching the artisans), or "".
static func governed_flow(repo: DataRepository, r: Dictionary) -> String:
	for end: String in ["from_type", "to_type"]:
		var flow := Governance.flow_of_type(repo, String(r[end]))
		if flow != "":
			return flow
	return ""


## The newest audit of `flow` filed THIS month (the letter's `tick`): its
## figure for `node` (an AuditWriter fact is keyed by the LEDGER node id, or
## "total"), or {}. An audit is a snapshot of ITS month and of HIS WORD
## (final review I2): it stands only while the governor's live claim is
## the one the audit found beside the truth. When his claim has moved — the
## civil goods rose, a regiment marched — the audit no longer speaks to it
## and is dropped, so an honest governor's thread never splits against a
## stale audit.
static func _audit_figure(state: GameState, flow: String, node: String, claim: int) -> Dictionary:
	for i in range(state.missives.size() - 1, -1, -1):
		var m: Dictionary = state.missives[i]
		if String(m.get("kind", "")) != "audit" or int(m.get("tick", -1)) != state.tick:
			continue
		if String((m.get("subject", {}) as Dictionary).get("code", "")) != flow:
			continue
		for f: Dictionary in m["facts"]:
			if String(f["key"]) == node and f.has("exact"):
				if int(f.get("claimed", -1)) != claim:
					return {}
				return {"value": int(f["exact"]), "source": "the audit of " + _date_words(int(m["day"])),
					"day": int(m["day"])}
		return {}
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
	var lvl := "full" if subj.is_empty() else LedgerResolvers.intel_level(repo, state, subj)
	if flow < 0:
		return {"value": -1, "text": "", "source": "own records" if lvl == "full" else "common knowledge",
			"day": state.absolute_day(), "level": lvl}
	if subj.is_empty():
		return {"value": flow, "text": Intel.num(flow), "source": "own records",
			"day": state.absolute_day(), "level": "full"}
	var f := _fact(repo, state, subj, String(t["key"]), flow)
	return {"value": (flow as Variant) if lvl == "full" else null, "text": String(f["text"]),
		"source": String(f["source"]), "day": int(f["day"]), "level": lvl}


## Who governs a link: for a link touching a governed flow (a type of
## data/ledger_governance.csv — the workshops, the supply lines) the man who
## governs it NOW, given or not (Governance.governor_of); otherwise its
## seat's holder.
static func _governor(repo: DataRepository, state: GameState, r: Dictionary) -> String:
	# once per link row within one read (Task 11 fix round 1, F7: asked
	# ~1,800 times opening three provinces, ~40 rows)
	if LedgerResolvers.memo_active():
		var cache := LedgerResolvers.memo_bucket("governor")
		var k := String(r["link_id"])
		if not cache.has(k):
			cache[k] = _governor_now(repo, state, r)
		return cache[k]
	return _governor_now(repo, state, r)


## Intel.fact, remembered within one read per subject, key and figure (F7).
static func _fact(repo: DataRepository, state: GameState, subj: Dictionary, key: String, flow: int) -> Dictionary:
	if not LedgerResolvers.memo_active():
		return Intel.fact(repo, state, subj, key, flow)
	var probe := {"s": subj, "k": key, "f": flow}
	var got := LedgerResolvers.memo_subject("fact", probe)
	if bool(got[0]):
		return got[1]
	var f := Intel.fact(repo, state, subj, key, flow)
	LedgerResolvers.memo_subject_put("fact", probe, f)
	return f


static func _governor_now(repo: DataRepository, state: GameState, r: Dictionary) -> String:
	var flow := governed_flow(repo, r)
	if flow != "":
		return Governance.governor_of(repo, state, flow)
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
			"params": String(a["params"]), "needs_map": String(a["needs_map"]) == "1",
			"hint": String(a.get("hint", ""))}
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
			out[k] = (int(own) as Variant) if own.is_valid_int() else own  # a manor's cell is a number
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
