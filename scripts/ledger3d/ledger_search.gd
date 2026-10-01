# scripts/ledger3d/ledger_search.gd
class_name LedgerSearch
extends RefCounted
## The LEDGER's search (owner 2026-10-01: 在ledger界面新增一个搜索栏，可以搜索
## node): every star of a galaxy snapshot AND every instance folded into a
## province's star (a manor, town or building outside an opened province)
## is found by its label, case-insensitively. Pure: the screen builds the
## index once a snapshot and asks it on every keystroke.

## One entry per findable node, in the snapshot's own order: {id, label,
## low (the label lower-cased), kind (what it is, in words), fold (the
## province star a folded instance must be opened from, else "")}.
static func index(repo: DataRepository, state: GameState, snap: Dictionary) -> Array:
	var out: Array = []
	for n: Dictionary in snap.get("nodes", []):
		var id := String(n["id"])
		var label := String(n.get("label", ""))
		if label == "" or id.begins_with("more:"):
			continue
		out.append({"id": id, "label": label, "low": label.to_lower(), "kind": kind_of(repo, id), "fold": ""})
	var folded: Dictionary = snap.get("folded", {})
	var ids: Array = folded.keys()
	ids.sort()
	for id: String in ids:
		var label := LedgerResolvers.label_of(repo, state, id)
		if label == "":
			continue
		out.append({"id": id, "label": label, "low": label.to_lower(), "kind": kind_of(repo, id),
			"fold": String(folded[id])})
	return out


## What a node is, in words: its type's one-of-it name (`label_one`, else
## its label) in lower case; a type's own star is a "pool", a ghost type
## "planned".
static func kind_of(repo: DataRepository, id: String) -> String:
	var row := Ledger.type_row(repo, Ledger.type_of(id))
	if id.begins_with("type:"):
		if String(row.get("status", "live")) == "planned":
			return "planned"
		return "pool" if String(row.get("star", "")) == "pool" else "type"
	var one := String(row.get("label_one", ""))
	return (one if one != "" else String(row.get("label", Ledger.type_of(id)))).to_lower()


## The entries of `idx` whose label holds `text` (case-insensitive), at most
## `limit`: a label that BEGINS with it first, then one with a word that
## does, then any other; a drawn star before a folded one; then by label
## and id. Blank text finds nothing.
static func matches(idx: Array, text: String, limit: int) -> Array:
	var q := text.strip_edges().to_lower()
	if q == "" or limit <= 0:
		return []
	var found: Array = []
	for e: Dictionary in idx:
		var low := String(e["low"])
		var at := low.find(q)
		if at < 0:
			continue
		var rank := 2
		if at == 0:
			rank = 0
		elif low.find(" " + q) >= 0 or low.find("-" + q) >= 0:
			rank = 1
		found.append([rank, 0 if String(e["fold"]) == "" else 1, low, String(e["id"]), e])
	found.sort_custom(func(a: Array, b: Array) -> bool:
		for k in 4:
			if a[k] != b[k]:
				return a[k] < b[k]
		return false)
	var out: Array = []
	for f: Array in found.slice(0, limit):
		out.append(f[4])
	return out
