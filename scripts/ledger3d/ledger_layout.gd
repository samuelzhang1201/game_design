# scripts/ledger3d/ledger_layout.gd
class_name LedgerLayout
extends RefCounted
## Where each sphere stands (spec 2026-09-30 §6.2). Type spheres stand at
## their hand-set places, so the type level is the same every time; the
## spheres of an ego network or of the court are laid out per layer by a
## force layout with a fixed number of passes from places set by sorted ids,
## so one snapshot always lays out the same way. The layer sets the height.


static func layer_y(repo: DataRepository, layer: String) -> float:
	return float(maxi(Ledger.LAYERS.find(layer), 0)) * repo.bal("ledger_layer_gap_m")


static func positions(repo: DataRepository, snap: Dictionary) -> Dictionary:
	var out := {}
	var by_layer := {}
	for n: Dictionary in snap["nodes"]:
		var y := layer_y(repo, String(n["layer"]))
		if n.has("x"):
			out[String(n["id"])] = Vector3(float(n["x"]), y, float(n["z"]))
		else:
			if not by_layer.has(String(n["layer"])):
				by_layer[String(n["layer"])] = []
			by_layer[String(n["layer"])].append(String(n["id"]))
	if by_layer.is_empty():
		return out
	var focus := String(snap.get("focus_id", ""))
	var side := {}   # -1 upstream of the focus (left), +1 downstream (right)
	for l: Dictionary in snap["links"]:
		if String(l["to"]) == focus:
			side[String(l["from"])] = -1.0
		elif String(l["from"]) == focus:
			side[String(l["to"])] = 1.0
	var ring := repo.bal("ledger_ego_ring_m")
	for layer: String in by_layer:
		var ids: Array = by_layer[layer]
		ids.sort()
		var y := layer_y(repo, layer)
		for i in ids.size():
			var id := String(ids[i])
			if id == focus:
				out[id] = Vector3(0.0, y, 0.0)
				continue
			var a := PI * (float(i) + 0.5) / float(ids.size())
			var x := sin(a) * ring
			if side.has(id):
				x = absf(x) * float(side[id]) + float(side[id]) * ring * 0.5
			out[id] = Vector3(x, y, cos(a) * ring)
	var repel := repo.bal("ledger_layout_repel")
	var spring := repo.bal("ledger_layout_spring")
	for _pass in int(repo.bal("ledger_layout_iterations")):
		for layer: String in by_layer:
			var ids: Array = by_layer[layer]
			for id: String in ids:
				if id == focus:
					continue
				var p: Vector3 = out[id]
				var f := Vector2.ZERO
				for other: String in ids:
					if other == id:
						continue
					var q: Vector3 = out[other]
					var dv := Vector2(p.x - q.x, p.z - q.z)
					f += dv / maxf(dv.length_squared(), 0.01) * repel
				f -= Vector2(p.x, p.z) * spring
				if side.has(id):
					f.x += float(side[id]) * spring * ring
				var step := f * 0.1
				var nx := p.x + step.x
				if side.has(id) and signf(nx) != float(side[id]):
					nx = float(side[id]) * 0.1  # a side is kept: upstream stays left
				out[id] = Vector3(nx, p.y, p.z + step.y)
	_fit_to_disc(repo, out, by_layer, focus)
	return out


## The spheres stand ON their disc: a laid-out layer that the force pass
## spread wider than the disc (the court's 21, repelling one another, reached
## twice its radius) is drawn in about the disc's centre, its shape kept, to
## ledger_layout_margin_m inside the rim.
static func _fit_to_disc(repo: DataRepository, out: Dictionary, by_layer: Dictionary, focus: String) -> void:
	var limit := repo.bal("ledger_disc_radius_m") - repo.bal("ledger_layout_margin_m")
	if limit <= 0.0:
		return
	for layer: String in by_layer:
		var reach := 0.0
		for id: String in by_layer[layer]:
			var p: Vector3 = out[id]
			reach = maxf(reach, Vector2(p.x, p.z).length())
		if reach <= limit:
			continue
		var k := limit / reach
		for id: String in by_layer[layer]:
			if id == focus:
				continue
			var p: Vector3 = out[id]
			out[id] = Vector3(p.x * k, p.y, p.z * k)
