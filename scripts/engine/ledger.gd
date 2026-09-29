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
