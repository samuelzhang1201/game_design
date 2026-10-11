# scripts/ledger3d/ledger_lineage.gd
class_name LedgerLineage
extends RefCounted
## A selected star's LINEAGE (owner 2026-10-01: 我需要点击一个node的时候，
## highlight整个lineage — the hybrid): what the LEDGER lights when a star is
## clicked, not only its neighbours. Pure: a snapshot in, levels out.
##
## a. every link of the selected star itself (any look) — FULL;
## b. the FLOW chain: from the selected star itself, the links whose look is
##    `flow` followed in one direction to the end — downstream from → to,
##    upstream to → from, never turning back mid-walk — FULL. Its whole
##    upstream and downstream, never its SIBLINGS (owner 2026-10-11: 点击node
##    后还是应该完全显示所有上下游，但是如果上游node连接了其他同类node
##    （siblings），则不应该显示siblings): an upstream star's other outflows, a
##    downstream star's other inflows are not walked;
## b'. from a neighbour joined by a STRUCTURE link only (a regiment's town or
##    province, a manor's province), its flow chain UPSTREAM to the end — what
##    feeds the place the star stands in (owner 2026-10-11: 点击军队，再往上的
##    lineage没出现) — FULL; never its downstream, whose other ends are the
##    star's siblings;
## c. people's ties: links whose look is `tie` or `kin` walked `tie_hops` from
##    the selected star, the hops past the first FAR (drawn dimmer);
## d. structure is never followed past the first hop; everything else is not
##    in the lineage.

const FULL := 1
const FAR := 2


## {"stars": {id: FULL|FAR}, "links": {link id: FULL|FAR}} for `id` in
## `snap` (Ledger.galaxy's nodes and links); `look_of` maps a link to its
## look (flow / tie / kin / structure). A planned link counts at the first
## hop only when `with_planned` (the camera's frame leaves it out); it is
## never walked further. Empty when `id` is not a star of the snapshot.
static func of(snap: Dictionary, id: String, look_of: Callable, tie_hops: int = 2,
		with_planned: bool = true) -> Dictionary:
	var stars := {}
	var links := {}
	var known := false
	for n: Dictionary in snap.get("nodes", []):
		if String(n["id"]) == id:
			known = true
			break
	if not known:
		return {"stars": stars, "links": links}
	var out_flow := {}   # star -> [link] whose look is flow, leaving it
	var in_flow := {}    # star -> [link] whose look is flow, entering it
	var ties := {}       # star -> [link] whose look is tie or kin
	var touching: Array = []
	for l: Dictionary in snap.get("links", []):
		var a := String(l["from"])
		var b := String(l["to"])
		var planned := String(l.get("status", "live")) == "planned"
		if a == id or b == id:
			if with_planned or not planned:
				touching.append(l)
		if planned:
			continue
		var look := String(look_of.call(l))
		if look == "flow":
			_push(out_flow, a, l)
			_push(in_flow, b, l)
		elif look == "tie" or look == "kin":
			_push(ties, a, l)
			_push(ties, b, l)
	stars[id] = FULL
	# a. every link of the star itself
	var flow_nb := {}     # neighbours joined by a live flow link
	var struct_nb := {}   # neighbours joined by a live structure link
	for l: Dictionary in touching:
		links[String(l["id"])] = FULL
		var other := String(l["to"]) if String(l["from"]) == id else String(l["from"])
		stars[other] = FULL
		if String(l.get("status", "live")) == "planned":
			continue
		match String(look_of.call(l)):
			"flow":
				flow_nb[other] = true
			"structure":
				struct_nb[other] = true
	# b. the flow chain, down and up, from the star alone
	var starts: Array[String] = [id]
	_walk(starts, out_flow, "to", stars, links)
	_walk(starts, in_flow, "from", stars, links)
	# b'. upstream from each structure-only neighbour
	var places: Array[String] = []
	for nb: String in struct_nb:
		if not flow_nb.has(nb):
			places.append(nb)
	_walk(places, in_flow, "from", stars, links)
	# c. the ties, hop by hop; the hops past the first FAR
	var ring: Array[String] = [id]
	var seen := {id: true}
	for hop in range(1, tie_hops + 1):
		var level := FULL if hop == 1 else FAR
		var next: Array[String] = []
		for s: String in ring:
			for l: Dictionary in ties.get(s, []):
				var lid := String(l["id"])
				if not links.has(lid):
					links[lid] = level
				var other := String(l["to"]) if String(l["from"]) == s else String(l["from"])
				if not stars.has(other):
					stars[other] = level
				if not seen.has(other):
					seen[other] = true
					next.append(other)
		ring = next
	return {"stars": stars, "links": links}


## Every star `starts` reach through `edges` (star -> [link]), each link
## crossed to its `toward` end only: one direction, to the end.
static func _walk(starts: Array[String], edges: Dictionary, toward: String, stars: Dictionary,
		links: Dictionary) -> void:
	var queue: Array[String] = starts.duplicate()
	var seen := {}
	for s: String in starts:
		seen[s] = true
	var i := 0
	while i < queue.size():
		var s: String = queue[i]
		i += 1
		for l: Dictionary in edges.get(s, []):
			links[String(l["id"])] = FULL
			var nxt := String(l[toward])
			stars[nxt] = FULL
			if not seen.has(nxt):
				seen[nxt] = true
				queue.append(nxt)


static func _push(m: Dictionary, k: String, l: Dictionary) -> void:
	var arr: Array = m.get(k, [])
	arr.append(l)
	m[k] = arr
